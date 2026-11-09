class_name WorldGen
extends RefCounted
## Seed-based procedural world generator supporting Overworld (dim 0) and
## Umbra Crystal Realm (dim 1), with 12 biomes, rivers, vertical caves,
## deep crystal caverns, ore veins, trees, villages, desert temples and mineshafts.

const BIOME_PLAINS := 0
const BIOME_FOREST := 1
const BIOME_BIRCH := 2
const BIOME_TAIGA := 3
const BIOME_SNOWY := 4
const BIOME_DESERT := 5
const BIOME_BADLANDS := 6
const BIOME_SWAMP := 7
const BIOME_MOUNTAINS := 8
const BIOME_OCEAN := 9
const BIOME_BEACH := 10
const BIOME_CRYSTAL := 11
const BIOME_UMBRA := 12

const BIOME_KEYS := [
	"plains", "forest", "birch_forest", "taiga", "snowy", "desert",
	"badlands", "swamp", "mountains", "ocean", "beach", "crystal_caverns", "umbra"
]

var world_seed: int
var dimension: int = 0

var _n_cont: FastNoiseLite
var _n_erosion: FastNoiseLite
var _n_ridge: FastNoiseLite
var _n_detail: FastNoiseLite
var _n_temp: FastNoiseLite
var _n_hum: FastNoiseLite
var _n_river: FastNoiseLite
var _n_cave_a: FastNoiseLite
var _n_cave_b: FastNoiseLite

func _init(seed_val: int, dim: int = 0) -> void:
	world_seed = seed_val
	dimension = dim
	var s := seed_val + dim * 7919
	_n_cont = _mk_noise(s + 1, 0.0022, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 4)
	_n_erosion = _mk_noise(s + 2, 0.0045, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3)
	_n_ridge = _mk_noise(s + 3, 0.006, FastNoiseLite.TYPE_CELLULAR, 2)
	_n_detail = _mk_noise(s + 4, 0.022, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 3)
	_n_temp = _mk_noise(s + 5, 0.0018, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 2)
	_n_hum = _mk_noise(s + 6, 0.0020, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 2)
	_n_river = _mk_noise(s + 7, 0.0032, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 2)
	_n_cave_a = _mk_noise(s + 8, 0.028, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 2)
	_n_cave_b = _mk_noise(s + 9, 0.032, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 2)

func _mk_noise(s: int, freq: float, t: int, oct: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = t
	n.frequency = freq
	n.fractal_octaves = oct
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	return n

static func hash2(x: int, z: int, s: int) -> int:
	var h: int = (x * 374761393 + z * 668265263 + s * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h ^ (h >> 16)

static func hash3(x: int, y: int, z: int, s: int) -> int:
	var h: int = (x * 374761393 + y * 982451653 + z * 668265263 + s * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h ^ (h >> 16)

func biome_at(wx: int, wz: int) -> int:
	if dimension == 1:
		return BIOME_UMBRA
	var cont := _n_cont.get_noise_2d(wx, wz)
	var er := _n_erosion.get_noise_2d(wx, wz)
	var temp := _n_temp.get_noise_2d(wx, wz)
	var hum := _n_hum.get_noise_2d(wx, wz)
	if cont < -0.28:
		return BIOME_OCEAN
	if cont < -0.19:
		return BIOME_BEACH
	if cont > 0.35 and er > 0.12:
		return BIOME_MOUNTAINS
	if temp < -0.32:
		return BIOME_SNOWY if hum < 0.05 else BIOME_TAIGA
	if temp > 0.34:
		if hum < -0.1:
			return BIOME_DESERT
		elif hum < 0.22:
			return BIOME_BADLANDS
		else:
			return BIOME_SWAMP
	if hum > 0.32:
		return BIOME_SWAMP if temp > 0.05 else BIOME_FOREST
	if hum > 0.08:
		return BIOME_BIRCH if temp > 0.0 else BIOME_FOREST
	if temp < -0.12:
		return BIOME_TAIGA
	return BIOME_PLAINS

func biome_tint(biome: int) -> Color:
	match biome:
		BIOME_PLAINS: return Color(0.56, 0.86, 0.38)
		BIOME_FOREST: return Color(0.45, 0.78, 0.34)
		BIOME_BIRCH: return Color(0.58, 0.84, 0.42)
		BIOME_TAIGA: return Color(0.42, 0.68, 0.48)
		BIOME_SNOWY: return Color(0.52, 0.72, 0.58)
		BIOME_DESERT, BIOME_BADLANDS: return Color(0.76, 0.74, 0.38)
		BIOME_SWAMP: return Color(0.42, 0.62, 0.30)
		BIOME_MOUNTAINS: return Color(0.48, 0.74, 0.46)
		BIOME_UMBRA: return Color(0.62, 0.48, 0.92)
		_: return Color(0.52, 0.82, 0.40)

func height_at(wx: int, wz: int) -> int:
	if dimension == 1:
		var n := _n_cont.get_noise_2d(wx * 1.8, wz * 1.8) + _n_detail.get_noise_2d(wx, wz) * 0.35
		return clampi(int(60.0 + n * 28.0), 20, 108)
	var cont := _n_cont.get_noise_2d(wx, wz)
	var er := _n_erosion.get_noise_2d(wx, wz)
	var det := _n_detail.get_noise_2d(wx, wz)
	var riv := absf(_n_river.get_noise_2d(wx, wz))
	var base := float(B.SEA) + cont * 24.0 + det * 5.0
	if cont > 0.22:
		var m := (cont - 0.22) / 0.78
		var ridge := 1.0 - absf(_n_ridge.get_noise_2d(wx, wz))
		base += m * m * (38.0 + ridge * 26.0 + maxf(0.0, er) * 18.0)
	elif cont < -0.20:
		# Ocean floor with occasional islands
		var isl := maxf(0.0, _n_detail.get_noise_2d(wx * 0.6, wz * 0.6) - 0.38) * 36.0
		base = float(B.SEA) - 14.0 + cont * 22.0 + isl
	# Carve winding rivers near sea level in non-ocean biomes
	if cont > -0.18 and riv < 0.048:
		var rt := 1.0 - (riv / 0.048)
		base = lerpf(base, float(B.SEA - 4), rt * rt)
	return clampi(int(round(base)), 6, B.HEIGHT - 16)

## Populates chunk blocks, meta, biomes, heightmap, and returns chest loot dictionaries.
func generate_chunk(cx: int, cz: int, blocks: PackedByteArray, meta: PackedByteArray, biomes: PackedByteArray, hmap: PackedByteArray) -> Dictionary:
	var chests := {}
	if dimension == 1:
		_generate_umbra_chunk(cx, cz, blocks, meta, biomes, hmap, chests)
		return chests

	var wx0 := cx * B.CHUNK
	var wz0 := cz * B.CHUNK

	# 1. Base terrain, rivers, caves, strata
	for lx in B.CHUNK:
		var wx := wx0 + lx
		for lz in B.CHUNK:
			var wz := wz0 + lz
			var col_idx := lx + (lz << 4)
			var bio := biome_at(wx, wz)
			biomes[col_idx] = bio
			var h := height_at(wx, wz)
			hmap[col_idx] = h

			var top_block := B.GRASS
			var filler_block := B.DIRT
			match bio:
				BIOME_DESERT, BIOME_BEACH:
					top_block = B.SAND
					filler_block = B.SANDSTONE
				BIOME_BADLANDS:
					top_block = B.RED_SAND
					filler_block = B.TERRACOTTA
				BIOME_SNOWY:
					top_block = B.SNOW_GRASS
					filler_block = B.DIRT
				BIOME_TAIGA:
					top_block = B.SNOW_GRASS if h > B.SEA + 18 else B.GRASS
					filler_block = B.DIRT
				BIOME_SWAMP:
					top_block = B.MUD if (hash2(wx, wz, world_seed) & 3) == 0 else B.GRASS
					filler_block = B.MUD
				BIOME_MOUNTAINS:
					if h > 88:
						top_block = B.SNOW
						filler_block = B.STONE
					elif h > 76:
						top_block = B.STONE
						filler_block = B.STONE
				BIOME_OCEAN:
					top_block = B.SAND if (hash2(wx, wz, world_seed) & 1) == 0 else B.GRAVEL
					filler_block = B.SAND

			if h < B.SEA - 1:
				top_block = B.SAND if bio != BIOME_SWAMP else B.CLAY
				filler_block = B.SAND

			for y in range(0, max(h + 1, B.SEA + 1)):
				var idx := B.idx(lx, y, lz)
				if y == 0:
					blocks[idx] = B.BEDROCK
					continue
				if y > h:
					if y == B.SEA and bio == BIOME_SNOWY:
						blocks[idx] = B.ICE
					else:
						blocks[idx] = B.WATER
					continue

				# Cave carving (spaghetti + deep caverns)
				if y > 2 and y < h - 2:
					var ca := _n_cave_a.get_noise_3d(wx, y * 1.4, wz)
					var cb := _n_cave_b.get_noise_3d(wx, y * 1.4, wz)
					var is_cave := (absf(ca) < 0.085 and absf(cb) < 0.085) or (y < 26 and ca > 0.56)
					if is_cave:
						blocks[idx] = B.LAVA if y <= 10 else B.AIR
						continue

				if y == h:
					blocks[idx] = top_block
				elif y >= h - 3:
					if bio == BIOME_BADLANDS:
						blocks[idx] = _badlands_band(y)
					else:
						blocks[idx] = filler_block
				else:
					if bio == BIOME_BADLANDS and y > B.SEA - 4:
						blocks[idx] = _badlands_band(y)
					elif y < 22 + (hash2(wx, wz, y) & 3):
						blocks[idx] = B.SHALE
					else:
						blocks[idx] = B.STONE

	# 2. Ore veins & underground crystal/glow flora
	_generate_ores(cx, cz, blocks)
	_generate_cave_flora(cx, cz, blocks)

	# 3. Surface flora (trees, plants, reeds, cactus, snow cap)
	_generate_flora(cx, cz, blocks, meta, biomes, hmap)

	# 4. Structures (Villages, Desert Temples, Underground Mineshafts)
	_generate_structures(cx, cz, blocks, meta, biomes, hmap, chests)

	return chests

func _badlands_band(y: int) -> int:
	match posmod(y, 7):
		0, 1: return B.TERRACOTTA_ORANGE
		3, 4: return B.TERRACOTTA_BROWN
		_: return B.TERRACOTTA

func _generate_ores(cx: int, cz: int, blocks: PackedByteArray) -> void:
	# [ore_id, attempts, min_y, max_y, vein_size]
	const ORES := [
		[B.COAL_ORE, 16, 8, 108, 7],
		[B.IRON_ORE, 12, 6, 72, 6],
		[B.GOLD_ORE, 5, 5, 34, 5],
		[B.DIAMOND_ORE, 3, 4, 18, 4],
		[B.LUMINITE_ORE, 4, 4, 26, 4],
		[B.GRAVEL, 6, 12, 64, 8],
		[B.CLAY, 4, 48, 60, 6],
	]
	for spec in ORES:
		var ore: int = spec[0]
		var tries: int = spec[1]
		var min_y: int = spec[2]
		var max_y: int = spec[3]
		var vsize: int = spec[4]
		for t in tries:
			var h := hash3(cx, cz, t + ore * 31, world_seed)
			var ox := (h & 15)
			var oz := ((h >> 4) & 15)
			var oy := min_y + ((h >> 8) % maxi(1, max_y - min_y))
			for v in vsize:
				var vh := hash3(ox + v, oy, oz - v, h)
				var vx := clampi(ox + (vh % 3) - 1, 0, 15)
				var vy := clampi(oy + ((vh >> 2) % 3) - 1, 1, B.HEIGHT - 2)
				var vz := clampi(oz + ((vh >> 4) % 3) - 1, 0, 15)
				var idx := B.idx(vx, vy, vz)
				var cur := blocks[idx]
				if cur == B.STONE or cur == B.SHALE:
					blocks[idx] = ore

func _generate_cave_flora(cx: int, cz: int, blocks: PackedByteArray) -> void:
	for i in 28:
		var h := hash3(cx, cz, 900 + i, world_seed)
		var lx := h & 15
		var lz := (h >> 4) & 15
		var ly := 6 + ((h >> 8) % 36)
		var idx := B.idx(lx, ly, lz)
		if blocks[idx] == B.AIR and blocks[B.idx(lx, ly - 1, lz)] in [B.STONE, B.SHALE]:
			if ly < 24 and (h & 3) == 0:
				blocks[idx] = B.CRYSTAL_CLUSTER
			elif (h & 1) == 0:
				blocks[idx] = B.GLOWCAP
			else:
				blocks[B.idx(lx, ly - 1, lz)] = B.GLOWMOSS

func _generate_flora(cx: int, cz: int, blocks: PackedByteArray, _meta: PackedByteArray, biomes: PackedByteArray, hmap: PackedByteArray) -> void:
	var wx0 := cx * B.CHUNK
	var wz0 := cz * B.CHUNK
	for lx in B.CHUNK:
		for lz in B.CHUNK:
			var col := lx + (lz << 4)
			var bio := biomes[col]
			var h := hmap[col]
			if h <= B.SEA or h >= B.HEIGHT - 12:
				continue
			var ground := blocks[B.idx(lx, h, lz)]
			var above_idx := B.idx(lx, h + 1, lz)
			if blocks[above_idx] != B.AIR:
				continue
			var r := hash2(wx0 + lx, wz0 + lz, world_seed + 77) % 1000

			# Reeds on shore next to water
			if h == B.SEA and ground in [B.GRASS, B.SAND, B.DIRT, B.MUD] and r < 95:
				if (lx > 0 and blocks[B.idx(lx - 1, h, lz)] == B.WATER) or (lx < 15 and blocks[B.idx(lx + 1, h, lz)] == B.WATER):
					for ry in range(1, 3 + (r & 1)):
						if h + ry < B.HEIGHT:
							blocks[B.idx(lx, h + ry, lz)] = B.REEDS
					continue

			# Trees (kept away from chunk border so crowns don't clip)
			if lx >= 2 and lx <= 13 and lz >= 2 and lz <= 13:
				if ground in [B.GRASS, B.DIRT, B.SNOW_GRASS, B.MUD]:
					var tree_chance := 0
					var tree_kind := "oak"
					match bio:
						BIOME_FOREST: tree_chance = 28; tree_kind = "oak" if (r & 3) != 0 else "birch"
						BIOME_BIRCH: tree_chance = 26; tree_kind = "birch"
						BIOME_TAIGA: tree_chance = 26; tree_kind = "pine"
						BIOME_SNOWY: tree_chance = 6; tree_kind = "pine"
						BIOME_PLAINS: tree_chance = 3; tree_kind = "oak"
						BIOME_SWAMP: tree_chance = 16; tree_kind = "oak"
						BIOME_MOUNTAINS:
							if h < 82: tree_chance = 10; tree_kind = "pine"
					if r < tree_chance:
						_place_tree(blocks, lx, h + 1, lz, tree_kind, r)
						continue

			# Cactus & dead bush in deserts/badlands
			if bio in [BIOME_DESERT, BIOME_BADLANDS] and ground in [B.SAND, B.RED_SAND]:
				if r < 12:
					for cy in range(1, 3 + (r & 1)):
						blocks[B.idx(lx, h + cy, lz)] = B.CACTUS
				elif r < 30:
					blocks[above_idx] = B.DEAD_BUSH
				continue

			# Grass, flowers & mushrooms
			if ground in [B.GRASS, B.SNOW_GRASS, B.MUD]:
				if bio == BIOME_SWAMP and r < 35:
					blocks[above_idx] = B.GLOWCAP if (r & 1) == 0 else B.MUSHROOM
				elif bio in [BIOME_PLAINS, BIOME_FOREST, BIOME_BIRCH] and r < 160:
					if r < 125:
						blocks[above_idx] = B.TALL_GRASS
					elif r < 142:
						blocks[above_idx] = B.FLOWER_RED
					elif r < 155:
						blocks[above_idx] = B.FLOWER_YELLOW
					else:
						blocks[above_idx] = B.FLOWER_BLUE
				elif bio == BIOME_TAIGA and r < 60:
					blocks[above_idx] = B.TALL_GRASS if r < 45 else B.MUSHROOM

static func _place_tree(blocks: PackedByteArray, lx: int, y0: int, lz: int, kind: String, r: int) -> void:
	var log_id := B.OAK_LOG
	var leaf_id := B.OAK_LEAVES
	if kind == "birch":
		log_id = B.BIRCH_LOG; leaf_id = B.BIRCH_LEAVES
	elif kind == "pine":
		log_id = B.PINE_LOG; leaf_id = B.PINE_LEAVES

	var trunk_h := 4 + (r % 3)
	if kind == "pine":
		trunk_h = 6 + (r % 3)
	if y0 + trunk_h + 3 >= B.HEIGHT:
		return

	if kind == "pine":
		for dy in range(2, trunk_h + 2):
			var rad := 2 if (dy < trunk_h - 1 and dy % 2 == 0) else 1
			if dy >= trunk_h:
				rad = 1 if dy == trunk_h else 0
			for dx in range(-rad, rad + 1):
				for dz in range(-rad, rad + 1):
					if absi(dx) + absi(dz) <= rad + (1 if rad > 1 else 0):
						var bi := B.idx(lx + dx, y0 + dy, lz + dz)
						if blocks[bi] == B.AIR:
							blocks[bi] = leaf_id
	else:
		for dy in range(trunk_h - 2, trunk_h + 2):
			var rad := 2 if dy < trunk_h else 1
			for dx in range(-rad, rad + 1):
				for dz in range(-rad, rad + 1):
					if absi(dx) == rad and absi(dz) == rad and (dy == trunk_h + 1 or ((dx + dz + dy) & 1) == 0):
						continue
					var bi := B.idx(lx + dx, y0 + dy, lz + dz)
					if blocks[bi] == B.AIR:
						blocks[bi] = leaf_id

	for dy in trunk_h:
		blocks[B.idx(lx, y0 + dy, lz)] = log_id

func _generate_structures(cx: int, cz: int, blocks: PackedByteArray, meta: PackedByteArray, biomes: PackedByteArray, hmap: PackedByteArray, chests: Dictionary) -> void:
	var sh := hash2(cx, cz, world_seed + 404)
	var center_bio := biomes[8 + (8 << 4)]
	var center_h := hmap[8 + (8 << 4)]

	# 1. Village cabin + well in flat plains/forest chunks (~1 in 22 chunks)
	if center_bio in [BIOME_PLAINS, BIOME_FOREST, BIOME_TAIGA] and center_h > B.SEA + 1 and center_h < 78 and (sh % 22) == 0:
		_build_village_cabin(cx, cz, center_h, blocks, meta, chests, sh)

	# 2. Desert pyramid ruin (~1 in 26 desert chunks)
	elif center_bio in [BIOME_DESERT, BIOME_BADLANDS] and center_h > B.SEA and (sh % 26) == 0:
		_build_desert_ruin(cx, cz, center_h, blocks, meta, chests, sh)

	# 3. Underground mineshaft corridor (~1 in 9 chunks)
	if (sh % 9) == 0:
		_build_mineshaft(cx, cz, blocks, chests, sh)

func _build_village_cabin(cx: int, cz: int, y0: int, blocks: PackedByteArray, meta: PackedByteArray, chests: Dictionary, sh: int) -> void:
	# Foundation & floor (x: 4..11, z: 4..11)
	for x in range(4, 12):
		for z in range(4, 12):
			for fy in range(y0 - 4, y0 + 1):
				if fy > 1:
					blocks[B.idx(x, fy, z)] = B.COBBLE if fy < y0 else B.OAK_PLANKS
			for cy in range(y0 + 1, y0 + 7):
				blocks[B.idx(x, cy, z)] = B.AIR
	# Gravel front path
	for z in range(1, 4):
		var py := hmap_safe(blocks, 7, z, y0)
		blocks[B.idx(7, py, z)] = B.GRAVEL
		blocks[B.idx(8, py, z)] = B.GRAVEL
	# Walls & corner pillars
	for y in range(y0 + 1, y0 + 5):
		for x in range(4, 12):
			for z in range(4, 12):
				var edge_x := (x == 4 or x == 11)
				var edge_z := (z == 4 or z == 11)
				if edge_x and edge_z:
					blocks[B.idx(x, y, z)] = B.OAK_LOG
				elif edge_x or edge_z:
					if y == y0 + 2 and (x == 7 or z == 7) and not (z == 4 and x == 7):
						blocks[B.idx(x, y, z)] = B.GLASS
					else:
						blocks[B.idx(x, y, z)] = B.OAK_PLANKS
	# Roof
	for x in range(3, 13):
		for z in range(3, 13):
			var roof_y := y0 + 5 if (x >= 5 and x <= 10 and z >= 5 and z <= 10) else y0 + 4
			blocks[B.idx(x, roof_y, z)] = B.STONE_BRICKS if (x == 3 or x == 12 or z == 3 or z == 12) else B.OAK_PLANKS
	# Doorway at (7, y0+1, 4)
	blocks[B.idx(7, y0 + 1, 4)] = B.DOOR_LOWER
	blocks[B.idx(7, y0 + 2, 4)] = B.DOOR_UPPER
	meta[B.idx(7, y0 + 1, 4)] = 0
	meta[B.idx(7, y0 + 2, 4)] = 0
	# Interior furniture: workbench, furnace, bedroll, torch, loot chest
	blocks[B.idx(5, y0 + 1, 10)] = B.WORKBENCH
	blocks[B.idx(6, y0 + 1, 10)] = B.FURNACE
	blocks[B.idx(10, y0 + 1, 10)] = B.BEDROLL
	blocks[B.idx(5, y0 + 3, 5)] = B.TORCH; meta[B.idx(5, y0 + 3, 5)] = 4
	blocks[B.idx(9, y0 + 1, 10)] = B.CHEST
	var cpos := Vector3i(cx * B.CHUNK + 9, y0 + 1, cz * B.CHUNK + 10)
	chests[cpos] = _loot_table("village", sh)

func hmap_safe(blocks: PackedByteArray, lx: int, lz: int, fallback: int) -> int:
	for y in range(B.HEIGHT - 2, 1, -1):
		var id := blocks[B.idx(lx, y, lz)]
		if id != B.AIR and id != B.WATER and Registry.b_solid[id] == 1:
			return y
	return fallback

func _build_desert_ruin(cx: int, cz: int, y0: int, blocks: PackedByteArray, _meta: PackedByteArray, chests: Dictionary, sh: int) -> void:
	for x in range(3, 13):
		for z in range(3, 13):
			for fy in range(y0 - 3, y0 + 1):
				blocks[B.idx(x, fy, z)] = B.SANDSTONE
			var dist := maxi(absi(x - 8), absi(z - 8))
			var h := maxi(0, 6 - dist)
			for dy in range(1, h + 1):
				if dist >= 3 and dy <= 3 and dist > 1:
					blocks[B.idx(x, y0 + dy, z)] = B.AIR
				else:
					blocks[B.idx(x, y0 + dy, z)] = B.SMOOTH_SANDSTONE if dy % 2 == 0 else B.SANDSTONE
	blocks[B.idx(8, y0 + 1, 8)] = B.CHEST
	blocks[B.idx(8, y0 + 2, 8)] = B.AIR
	var cpos := Vector3i(cx * B.CHUNK + 8, y0 + 1, cz * B.CHUNK + 8)
	chests[cpos] = _loot_table("temple", sh)

func _build_mineshaft(cx: int, cz: int, blocks: PackedByteArray, chests: Dictionary, sh: int) -> void:
	var my := 18 + (sh % 20)
	for lx in B.CHUNK:
		for lz in range(6, 10):
			blocks[B.idx(lx, my - 1, lz)] = B.OAK_PLANKS if (lx + lz) % 3 == 0 else B.COBBLE
			for dy in range(0, 3):
				blocks[B.idx(lx, my + dy, lz)] = B.AIR
		if lx % 4 == 0:
			for dy in range(0, 3):
				blocks[B.idx(lx, my + dy, 6)] = B.OAK_LOG
				blocks[B.idx(lx, my + dy, 9)] = B.OAK_LOG
			for lz in range(6, 10):
				blocks[B.idx(lx, my + 2, lz)] = B.OAK_PLANKS
			blocks[B.idx(lx, my + 1, 7)] = B.TORCH
	if (sh & 3) == 0:
		blocks[B.idx(8, my, 7)] = B.CHEST
		var cpos := Vector3i(cx * B.CHUNK + 8, my, cz * B.CHUNK + 7)
		chests[cpos] = _loot_table("mineshaft", sh)

func _generate_umbra_chunk(cx: int, cz: int, blocks: PackedByteArray, _meta: PackedByteArray, biomes: PackedByteArray, hmap: PackedByteArray, chests: Dictionary) -> void:
	var wx0 := cx * B.CHUNK
	var wz0 := cz * B.CHUNK
	for lx in B.CHUNK:
		var wx := wx0 + lx
		for lz in B.CHUNK:
			var wz := wz0 + lz
			var col := lx + (lz << 4)
			biomes[col] = BIOME_UMBRA
			var isl := _n_cont.get_noise_2d(wx * 2.2, wz * 2.2) + _n_detail.get_noise_2d(wx, wz) * 0.35
			if isl < -0.18:
				hmap[col] = 0
				continue
			var top_y := clampi(int(62.0 + isl * 28.0), 28, 104)
			var bot_y := clampi(int(44.0 - isl * 24.0 + _n_erosion.get_noise_2d(wx * 2.0, wz * 2.0) * 10.0), 12, top_y - 4)
			hmap[col] = top_y
			for y in range(bot_y, top_y + 1):
				var idx := B.idx(lx, y, lz)
				if y == top_y:
					blocks[idx] = B.GLOWMOSS if (hash2(wx, wz, world_seed) & 3) != 0 else B.SHALE
				elif y > top_y - 3:
					blocks[idx] = B.SHALE
				else:
					var h := hash3(wx, y, wz, world_seed)
					if (h % 29) == 0:
						blocks[idx] = B.LUMINITE_ORE
					elif (h % 47) == 0:
						blocks[idx] = B.DIAMOND_ORE
					else:
						blocks[idx] = B.SHALE
			var r := hash2(wx, wz, world_seed + 99) % 100
			if r < 8 and top_y + 1 < B.HEIGHT:
				blocks[B.idx(lx, top_y + 1, lz)] = B.CRYSTAL_CLUSTER
			elif r < 16 and top_y + 1 < B.HEIGHT:
				blocks[B.idx(lx, top_y + 1, lz)] = B.GLOWCAP
			elif r == 99 and lx >= 4 and lx <= 11 and lz >= 4 and lz <= 11:
				# Crystal spire
				var sh := 6 + (r % 7)
				for sy in range(1, sh):
					if top_y + sy < B.HEIGHT:
						blocks[B.idx(lx, top_y + sy, lz)] = B.OBSIDIAN if sy < sh - 2 else B.LUMINITE_BLOCK

	var csh := hash2(cx, cz, world_seed + 888)
	if (csh % 14) == 0 and hmap[8 + (8 << 4)] > 40:
		var y0 := hmap[8 + (8 << 4)]
		for x in range(5, 11):
			for z in range(5, 11):
				blocks[B.idx(x, y0, z)] = B.SHALE_BRICKS
				if (x == 5 or x == 10) and (z == 5 or z == 10):
					for dy in range(1, 5):
						blocks[B.idx(x, y0 + dy, z)] = B.OBSIDIAN
					blocks[B.idx(x, y0 + 5, z)] = B.LUMINITE_BLOCK
		blocks[B.idx(8, y0 + 1, 8)] = B.CHEST
		chests[Vector3i(cx * B.CHUNK + 8, y0 + 1, cz * B.CHUNK + 8)] = _loot_table("umbra", csh)

func _loot_table(kind: String, seed_val: int) -> Array:
	var slots := []
	slots.resize(27)
	for i in 27:
		slots[i] = {"id": 0, "count": 0, "dur": 0}
	var pool: Array = []
	match kind:
		"village":
			pool = [["bread", 2, 5], ["apple", 1, 4], ["oak_log", 4, 12], ["iron_ingot", 1, 3], ["torch", 4, 12], ["seeds", 3, 8], ["iron_pickaxe", 1, 1]]
		"temple":
			pool = [["gold_ingot", 2, 6], ["diamond", 1, 3], ["iron_ingot", 3, 7], ["bone", 4, 10], ["luminite_shard", 2, 5], ["golden_sword", 1, 1]]
		"mineshaft":
			pool = [["coal", 4, 12], ["iron_ingot", 2, 5], ["torch", 6, 16], ["bread", 1, 3], ["luminite_shard", 1, 4], ["iron_pickaxe", 1, 1]]
		"umbra":
			pool = [["diamond", 2, 5], ["luminite_shard", 4, 10], ["gold_ingot", 3, 8], ["crystal_lamp", 2, 4], ["diamond_sword", 1, 1]]
	var count := 4 + (seed_val % 4)
	for i in count:
		var h := hash2(i, seed_val, 73)
		var entry: Array = pool[h % pool.size()]
		var iid := Registry.id_of(entry[0])
		var qty: int = entry[1] + (h % maxi(1, entry[2] - entry[1] + 1))
		var slot_idx := (h >> 4) % 27
		var d: int = Registry.item(iid).get("durability", 0)
		slots[slot_idx] = {"id": iid, "count": qty, "dur": d}
	return slots
