class_name VoxelChunk
extends RefCounted
## Holds 16x128x16 voxel data, light map, and builds face-culled meshes with
## per-vertex ambient occlusion, directional shading, biome tinting, and UV2 layer indices.

const TOTAL := B.CHUNK * B.CHUNK * B.HEIGHT # 32768

# Face vertex positions (0..5: +X, -X, +Y, -Y, +Z, -Z), 4 vertices per face (f * 4 + 0..3)
# Ordered [Bottom-Left, Top-Left, Top-Right, Bottom-Right] when viewed from outside the block,
# ensuring uniform front-facing winding and upright textures on all 6 faces.
var FACE_VERTS := PackedVector3Array([
	Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(1, 0, 0), # +X
	Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1), # -X
	Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), # +Y
	Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), # -Y
	Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1), # +Z
	Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 0), # -Z
])
var FACE_NORMALS := PackedVector3Array([
	Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
	Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)
])
var FACE_DIRS_X := PackedInt32Array([1, -1, 0, 0, 0, 0])
var FACE_DIRS_Y := PackedInt32Array([0, 0, 1, -1, 0, 0])
var FACE_DIRS_Z := PackedInt32Array([0, 0, 0, 0, 1, -1])
var FACE_UVS := PackedVector2Array([
	Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)
])
var FACE_SHADE := PackedFloat32Array([0.76, 0.76, 1.0, 0.55, 0.86, 0.86])
var F_MAP := PackedInt32Array([4, 1, 5, 0])
var SIDE_FACES := PackedInt32Array([0, 1, 4, 5])

var cx: int
var cz: int
var dimension: int
var blocks: PackedByteArray
var meta: PackedByteArray
var light: PackedByteArray
var biomes: PackedByteArray
var hmap: PackedByteArray
var chests: Dictionary = {}
var furnaces: Dictionary = {}

var pending_s_verts: PackedVector3Array
var pending_s_norms: PackedVector3Array
var pending_s_cols: PackedColorArray
var pending_s_uvs: PackedVector2Array
var pending_s_uv2s: PackedVector2Array

var pending_l_verts: PackedVector3Array
var pending_l_norms: PackedVector3Array
var pending_l_cols: PackedColorArray
var pending_l_uvs: PackedVector2Array
var pending_l_uv2s: PackedVector2Array

var modified: bool = false
var dirty: bool = true
var meshing: bool = false

var solid_node: MeshInstance3D
var liquid_node: MeshInstance3D

func _init(p_cx: int, p_cz: int, p_dim: int = 0) -> void:
	cx = p_cx
	cz = p_cz
	dimension = p_dim
	blocks.resize(TOTAL)
	meta.resize(TOTAL)
	light.resize(TOTAL)
	biomes.resize(B.CHUNK * B.CHUNK)
	hmap.resize(B.CHUNK * B.CHUNK)

func compute_light() -> void:
	var b_op := Registry.b_opaque
	var b_at := Registry.b_atten
	var b_lt := Registry.b_light
	var l_queue: Array[int] = []

	# 1. Top-down skylight + seed light emitters
	for lx in B.CHUNK:
		for lz in B.CHUNK:
			var sky := 15 if dimension == 0 else 8
			for y in range(B.HEIGHT - 1, -1, -1):
				var idx := B.idx(lx, y, lz)
				var id := blocks[idx]
				if b_op[id] == 1:
					sky = 0
				elif b_at[id] > 0:
					sky = maxi(0, sky - b_at[id])
				var em := b_lt[id]
				light[idx] = (sky << 4) | em
				if em > 1:
					l_queue.append(idx)

	# 2. Local BFS propagation for torch/emissive block light
	var head := 0
	while head < l_queue.size():
		var idx := l_queue[head]
		head += 1
		var cur_bl := light[idx] & 15
		if cur_bl <= 1:
			continue
		var lx := idx & 15
		var lz := (idx >> 4) & 15
		var ly := idx >> 8
		var next_bl := cur_bl - 1
		if lx > 0: _spread_bl(idx - 1, next_bl, b_op, l_queue)
		if lx < 15: _spread_bl(idx + 1, next_bl, b_op, l_queue)
		if lz > 0: _spread_bl(idx - 16, next_bl, b_op, l_queue)
		if lz < 15: _spread_bl(idx + 16, next_bl, b_op, l_queue)
		if ly > 0: _spread_bl(idx - 256, next_bl, b_op, l_queue)
		if ly < B.HEIGHT - 1: _spread_bl(idx + 256, next_bl, b_op, l_queue)

func _spread_bl(nidx: int, nval: int, b_op: PackedByteArray, q: Array[int]) -> void:
	if b_op[blocks[nidx]] == 1:
		return
	var cur := light[nidx]
	if (cur & 15) < nval:
		light[nidx] = (cur & 0xf0) | nval
		q.append(nidx)

## Builds geometry arrays for solid/cutout/flora and liquids.
func build_mesh_data(nb_px: PackedByteArray, nb_nx: PackedByteArray, nb_pz: PackedByteArray, nb_nz: PackedByteArray, gen: WorldGen) -> void:
	compute_light()

	var s_verts := PackedVector3Array()
	var s_norms := PackedVector3Array()
	var s_cols := PackedColorArray()
	var s_uvs := PackedVector2Array()
	var s_uv2s := PackedVector2Array()

	var l_verts := PackedVector3Array()
	var l_norms := PackedVector3Array()
	var l_cols := PackedColorArray()
	var l_uvs := PackedVector2Array()
	var l_uv2s := PackedVector2Array()

	var b_ren := Registry.b_render
	var b_op := Registry.b_opaque
	var b_tx_flat := Registry.b_tex_flat
	var b_fr := Registry.b_front
	var b_tn := Registry.b_tint
	var b_sw := Registry.b_sway
	var b_em := Registry.b_emissive

	for y in range(0, B.HEIGHT):
		var y_off := y << 8
		for lz in B.CHUNK:
			var z_off := y_off + (lz << 4)
			for lx in B.CHUNK:
				var idx := z_off + lx
				var id := blocks[idx]
				if id == B.AIR:
					continue
				var rtype := b_ren[id]
				if rtype == B.R_NONE:
					continue

				var pos := Vector3(lx, y, lz)
				var col_idx := lx + (lz << 4)
				var btint := gen.biome_tint(biomes[col_idx]) if b_tn[id] == 1 else Color.WHITE
				var em := 1.0 if b_em[id] == 1 else 0.0
				var sway := 0.5 if b_sw[id] == 1 else (1.0 if b_sw[id] == 2 else 0.0)
				var tex_base := id * 6

				if rtype == B.R_CUBE or rtype == B.R_CUTOUT:
					var m := meta[idx]
					var front_layer: int = b_fr[id]
					var front_face := -1
					if front_layer >= 0:
						front_face = F_MAP[m & 3]

					for f in 6:
						var nx := lx + FACE_DIRS_X[f]
						var ny := y + FACE_DIRS_Y[f]
						var nz := lz + FACE_DIRS_Z[f]
						var nid := _sample_block(nx, ny, nz, nb_px, nb_nx, nb_pz, nb_nz)
						if b_op[nid] == 1:
							continue
						if rtype == B.R_CUTOUT and nid == id:
							continue

						var layer: int = front_layer if f == front_face else b_tx_flat[tex_base + f]
						var shade: float = FACE_SHADE[f]
						var f_tint := btint
						if id == B.GRASS and f != 2:
							f_tint = Color.WHITE # Only tint top of grass block for crisp dirt sides
						var nl := _sample_light_brightness(nx, ny, nz)
						var uv2 := Vector2(float(layer), em)
						var fb := f * 4
						var fv0: Vector3 = FACE_VERTS[fb]
						var fv1: Vector3 = FACE_VERTS[fb + 1]
						var fv2: Vector3 = FACE_VERTS[fb + 2]
						var fv3: Vector3 = FACE_VERTS[fb + 3]
						var fn: Vector3 = FACE_NORMALS[f]

						# Vertex ambient occlusion from side neighbors
						var c0 := _vert_color(lx, y, lz, fv0, fn, shade, nl, f_tint, sway, b_op, nb_px, nb_nx, nb_pz, nb_nz)
						var c1 := _vert_color(lx, y, lz, fv1, fn, shade, nl, f_tint, sway, b_op, nb_px, nb_nx, nb_pz, nb_nz)
						var c2 := _vert_color(lx, y, lz, fv2, fn, shade, nl, f_tint, sway, b_op, nb_px, nb_nx, nb_pz, nb_nz)
						var c3 := _vert_color(lx, y, lz, fv3, fn, shade, nl, f_tint, sway, b_op, nb_px, nb_nx, nb_pz, nb_nz)

						_add_quad(s_verts, s_norms, s_cols, s_uvs, s_uv2s,
							pos + fv0, pos + fv1, pos + fv2, pos + fv3,
							fn, c0, c1, c2, c3, uv2)

				elif rtype == B.R_LIQUID:
					var layer_l: int = b_tx_flat[tex_base + 2]
					var nl_l := _sample_light_brightness(lx, y + 1, lz)
					var lc := Color(nl_l, nl_l, nl_l, 1.0)
					var uv2_l := Vector2(float(layer_l), em)
					var top_id := _sample_block(lx, y + 1, lz, nb_px, nb_nx, nb_pz, nb_nz)
					if top_id != id:
						_add_quad(l_verts, l_norms, l_cols, l_uvs, l_uv2s,
							pos + FACE_VERTS[8], pos + FACE_VERTS[9], pos + FACE_VERTS[10], pos + FACE_VERTS[11],
							Vector3.UP, lc, lc, lc, lc, uv2_l)
					for si in 4:
						var sf: int = SIDE_FACES[si]
						var snid := _sample_block(lx + FACE_DIRS_X[sf], y, lz + FACE_DIRS_Z[sf], nb_px, nb_nx, nb_pz, nb_nz)
						if snid != id and b_op[snid] == 0:
							var sfb := sf * 4
							var fn_s: Vector3 = FACE_NORMALS[sf]
							_add_quad(l_verts, l_norms, l_cols, l_uvs, l_uv2s,
								pos + FACE_VERTS[sfb], pos + FACE_VERTS[sfb + 1], pos + FACE_VERTS[sfb + 2], pos + FACE_VERTS[sfb + 3],
								fn_s, lc, lc, lc, lc, uv2_l)

				elif rtype == B.R_CROSS:
					var layer_c: int = b_tx_flat[tex_base + 2]
					if id == B.WHEAT:
						layer_c = Registry.wheat_layer(meta[idx])
					var nl_c := _sample_light_brightness(lx, y, lz)
					var cc_bot := Color(btint.r * nl_c * 0.88, btint.g * nl_c * 0.88, btint.b * nl_c * 0.88, 0.0)
					var cc_top := Color(btint.r * nl_c, btint.g * nl_c, btint.b * nl_c, sway)
					var uv2_c := Vector2(float(layer_c), em)
					var n_up := Vector3.UP
					# Diagonal 1 (both sides)
					_add_quad(s_verts, s_norms, s_cols, s_uvs, s_uv2s,
						pos + Vector3(0.15, 0, 0.15), pos + Vector3(0.15, 1, 0.15),
						pos + Vector3(0.85, 1, 0.85), pos + Vector3(0.85, 0, 0.85),
						n_up, cc_bot, cc_top, cc_top, cc_bot, uv2_c)
					_add_quad(s_verts, s_norms, s_cols, s_uvs, s_uv2s,
						pos + Vector3(0.85, 0, 0.85), pos + Vector3(0.85, 1, 0.85),
						pos + Vector3(0.15, 1, 0.15), pos + Vector3(0.15, 0, 0.15),
						n_up, cc_bot, cc_top, cc_top, cc_bot, uv2_c)
					# Diagonal 2 (both sides)
					_add_quad(s_verts, s_norms, s_cols, s_uvs, s_uv2s,
						pos + Vector3(0.15, 0, 0.85), pos + Vector3(0.15, 1, 0.85),
						pos + Vector3(0.85, 1, 0.15), pos + Vector3(0.85, 0, 0.15),
						n_up, cc_bot, cc_top, cc_top, cc_bot, uv2_c)
					_add_quad(s_verts, s_norms, s_cols, s_uvs, s_uv2s,
						pos + Vector3(0.85, 0, 0.15), pos + Vector3(0.85, 1, 0.15),
						pos + Vector3(0.15, 1, 0.85), pos + Vector3(0.15, 0, 0.85),
						n_up, cc_bot, cc_top, cc_top, cc_bot, uv2_c)

				elif rtype == B.R_BOX:
					var box: AABB = Registry.render_box(id, meta[idx])
					var nl_b := _sample_light_brightness(lx, y, lz)
					var p0 := pos + box.position
					var sz := box.size
					for f in 6:
						var bfb := f * 4
						var fn_b: Vector3 = FACE_NORMALS[f]
						var sh_b: float = FACE_SHADE[f] * nl_b
						var cb := Color(sh_b, sh_b, sh_b, 0.0)
						var uv2_b := Vector2(float(b_tx_flat[tex_base + f]), em)
						var v0: Vector3 = p0 + FACE_VERTS[bfb] * sz
						var v1: Vector3 = p0 + FACE_VERTS[bfb + 1] * sz
						var v2: Vector3 = p0 + FACE_VERTS[bfb + 2] * sz
						var v3: Vector3 = p0 + FACE_VERTS[bfb + 3] * sz
						_add_quad(s_verts, s_norms, s_cols, s_uvs, s_uv2s, v0, v1, v2, v3, fn_b, cb, cb, cb, cb, uv2_b)

	pending_s_verts = s_verts
	pending_s_norms = s_norms
	pending_s_cols = s_cols
	pending_s_uvs = s_uvs
	pending_s_uv2s = s_uv2s

	pending_l_verts = l_verts
	pending_l_norms = l_norms
	pending_l_cols = l_cols
	pending_l_uvs = l_uvs
	pending_l_uv2s = l_uv2s

func _sample_block(lx: int, y: int, lz: int, nb_px: PackedByteArray, nb_nx: PackedByteArray, nb_pz: PackedByteArray, nb_nz: PackedByteArray) -> int:
	if y < 0:
		return B.BEDROCK
	if y >= B.HEIGHT:
		return B.AIR
	if lx >= 0 and lx < 16 and lz >= 0 and lz < 16:
		return blocks[B.idx(lx, y, lz)]
	if lx >= 16 and lz >= 0 and lz < 16 and not nb_px.is_empty():
		return nb_px[B.idx(lx - 16, y, lz)]
	if lx < 0 and lz >= 0 and lz < 16 and not nb_nx.is_empty():
		return nb_nx[B.idx(lx + 16, y, lz)]
	if lz >= 16 and lx >= 0 and lx < 16 and not nb_pz.is_empty():
		return nb_pz[B.idx(lx, y, lz - 16)]
	if lz < 0 and lx >= 0 and lx < 16 and not nb_nz.is_empty():
		return nb_nz[B.idx(lx, y, lz + 16)]
	return B.AIR

func _sample_light_brightness(lx: int, y: int, lz: int) -> float:
	var cy := clampi(y, 0, B.HEIGHT - 1)
	var clx := clampi(lx, 0, 15)
	var clz := clampi(lz, 0, 15)
	var raw := light[B.idx(clx, cy, clz)]
	var sky := (raw >> 4) & 15
	var blk := raw & 15
	var lv := maxi(sky, blk)
	return 0.16 + (float(lv) / 15.0) * 0.84

func _vert_color(lx: int, y: int, lz: int, v: Vector3, fn: Vector3, shade: float, nl: float, tint: Color, sway: float, b_op: PackedByteArray, nb_px: PackedByteArray, nb_nx: PackedByteArray, nb_pz: PackedByteArray, nb_nz: PackedByteArray) -> Color:
	var sx := 1 if v.x > 0.5 else -1
	var sy := 1 if v.y > 0.5 else -1
	var sz := 1 if v.z > 0.5 else -1
	var occ := 0
	if absf(fn.y) > 0.5:
		var ny := y + int(fn.y)
		var s1 := b_op[_sample_block(lx + sx, ny, lz, nb_px, nb_nx, nb_pz, nb_nz)]
		var s2 := b_op[_sample_block(lx, ny, lz + sz, nb_px, nb_nx, nb_pz, nb_nz)]
		var cr := b_op[_sample_block(lx + sx, ny, lz + sz, nb_px, nb_nx, nb_pz, nb_nz)]
		occ = 3 if (s1 == 1 and s2 == 1) else (s1 + s2 + cr)
	elif absf(fn.x) > 0.5:
		var nx := lx + int(fn.x)
		var s1x := b_op[_sample_block(nx, y + sy, lz, nb_px, nb_nx, nb_pz, nb_nz)]
		var s2x := b_op[_sample_block(nx, y, lz + sz, nb_px, nb_nx, nb_pz, nb_nz)]
		var crx := b_op[_sample_block(nx, y + sy, lz + sz, nb_px, nb_nx, nb_pz, nb_nz)]
		occ = 3 if (s1x == 1 and s2x == 1) else (s1x + s2x + crx)
	else:
		var nz := lz + int(fn.z)
		var s1z := b_op[_sample_block(lx + sx, y, nz, nb_px, nb_nx, nb_pz, nb_nz)]
		var s2z := b_op[_sample_block(lx, y + sy, nz, nb_px, nb_nx, nb_pz, nb_nz)]
		var crz := b_op[_sample_block(lx + sx, y + sy, nz, nb_px, nb_nx, nb_pz, nb_nz)]
		occ = 3 if (s1z == 1 and s2z == 1) else (s1z + s2z + crz)

	var ao := 1.0 - float(occ) * 0.14
	var b := shade * nl * ao
	return Color(tint.r * b, tint.g * b, tint.b * b, sway)

func _add_quad(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, uvs: PackedVector2Array, uv2s: PackedVector2Array,
		v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, n: Vector3, c0: Color, c1: Color, c2: Color, c3: Color, uv2: Vector2) -> void:
	# Triangle 1: 0, 1, 2
	verts.append(v0); verts.append(v1); verts.append(v2)
	norms.append(n); norms.append(n); norms.append(n)
	cols.append(c0); cols.append(c1); cols.append(c2)
	uvs.append(FACE_UVS[0]); uvs.append(FACE_UVS[1]); uvs.append(FACE_UVS[2])
	uv2s.append(uv2); uv2s.append(uv2); uv2s.append(uv2)
	# Triangle 2: 0, 2, 3
	verts.append(v0); verts.append(v2); verts.append(v3)
	norms.append(n); norms.append(n); norms.append(n)
	cols.append(c0); cols.append(c2); cols.append(c3)
	uvs.append(FACE_UVS[0]); uvs.append(FACE_UVS[2]); uvs.append(FACE_UVS[3])
	uv2s.append(uv2); uv2s.append(uv2); uv2s.append(uv2)

func apply_mesh_data(solid_mat: Material, liquid_mat: Material) -> void:
	if solid_node != null:
		solid_node.mesh = _build_array_mesh(pending_s_verts, pending_s_norms, pending_s_cols, pending_s_uvs, pending_s_uv2s, solid_mat)
	if liquid_node != null:
		liquid_node.mesh = _build_array_mesh(pending_l_verts, pending_l_norms, pending_l_cols, pending_l_uvs, pending_l_uv2s, liquid_mat)

func _build_array_mesh(verts: PackedVector3Array, norms: PackedVector3Array, cols: PackedColorArray, uvs: PackedVector2Array, uv2s: PackedVector2Array, mat: Material) -> ArrayMesh:
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	return mesh
