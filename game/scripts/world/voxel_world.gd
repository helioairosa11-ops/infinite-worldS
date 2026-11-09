class_name VoxelWorld
extends Node3D
## Manages the infinite chunked voxel world, async generation/meshing, day/night sky,
## dynamic weather, block physics (gravity, fluids, crop/tree growth, furnaces),
## mob spawning, explosions, and dimension travel.

signal region_discovered(region_name: String)

var world_id: String = ""
var world_name: String = "World"
var world_seed: int = 1337
var game_mode: int = 0
var current_dimension: int = 0

var world_time: float = 0.28 # 0.0=midnight, 0.25=dawn, 0.5=noon, 0.75=dusk
var day_count: int = 1
var weather: String = "clear" # "clear", "rain", "storm", "blood_moon"
var weather_timer: float = 120.0
var discovered_biomes: Array = []

var gen: WorldGen
var chunks: Dictionary = {} # Vector2i(cx, cz) -> VoxelChunk
var _gen_tasks: Dictionary = {} # Vector2i -> task_id
var _mesh_tasks: Dictionary = {} # Vector2i -> {task_id, chunk}
var _falling_check_queue: Array[Vector3i] = []

var solid_material: ShaderMaterial
var liquid_material: ShaderMaterial

var chunks_root: Node3D
var drops_root: Node3D
var mobs_root: Node3D
var proj_root: Node3D
var clouds_root: Node3D
var sun_light: DirectionalLight3D
var world_env: WorldEnvironment
var sky_mat: ProceduralSkyMaterial
var rain_mesh: MultiMeshInstance3D

var local_player: VoxelPlayer
var remote_players: Dictionary = {} # peer_id -> Node3D
var main_ui: Node = null

var _rng := RandomNumberGenerator.new()
var _mob_spawn_timer: float = 3.0
var _tick_accum: float = 0.0
var _cloud_offset: float = 0.0

func _ready() -> void:
	_rng.randomize()
	_setup_materials()
	_setup_environment()
	chunks_root = Node3D.new(); chunks_root.name = "Chunks"; add_child(chunks_root)
	drops_root = Node3D.new(); drops_root.name = "Drops"; add_child(drops_root)
	mobs_root = Node3D.new(); mobs_root.name = "Mobs"; add_child(mobs_root)
	proj_root = Node3D.new(); proj_root.name = "Projectiles"; add_child(proj_root)
	_setup_clouds()
	_setup_rain()
	Settings.changed.connect(_apply_graphics_settings)
	_apply_graphics_settings()

func _setup_materials() -> void:
	solid_material = ShaderMaterial.new()
	solid_material.shader = load("res://shaders/voxel_opaque.gdshader")
	solid_material.set_shader_parameter("tex_array", Registry.texture_array)

	liquid_material = ShaderMaterial.new()
	liquid_material.shader = load("res://shaders/voxel_liquid.gdshader")
	liquid_material.set_shader_parameter("tex_array", Registry.texture_array)

func _setup_environment() -> void:
	sun_light = DirectionalLight3D.new()
	sun_light.shadow_enabled = Settings.shadows
	sun_light.directional_shadow_max_distance = 140.0
	sun_light.shadow_bias = 0.04
	add_child(sun_light)

	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.35

	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

func _setup_clouds() -> void:
	clouds_root = Node3D.new()
	clouds_root.position.y = 114.0
	add_child(clouds_root)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.96, 0.98, 1.0, 0.85)
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001
	for i in 28:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(rng.randi_range(12, 28), 3.0, rng.randi_range(10, 24))
		bm.material = cmat
		mi.mesh = bm
		mi.position = Vector3(rng.randf_range(-160, 160), rng.randf_range(-2, 4), rng.randf_range(-160, 160))
		clouds_root.add_child(mi)

func _setup_rain() -> void:
	rain_mesh = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.03, 0.75, 0.03)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.65, 0.80, 0.98, 0.55)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = rmat
	mm.mesh = bm
	mm.instance_count = 320
	for i in 320:
		var p := Vector3(_rng.randf_range(-14, 14), _rng.randf_range(-8, 12), _rng.randf_range(-14, 14))
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, p))
	rain_mesh.multimesh = mm
	rain_mesh.visible = false
	add_child(rain_mesh)

func _apply_graphics_settings() -> void:
	if sun_light != null:
		sun_light.shadow_enabled = Settings.shadows
	if clouds_root != null:
		clouds_root.visible = Settings.clouds and current_dimension == 0
	if world_env != null and world_env.environment != null:
		var rd := float(Settings.render_distance * B.CHUNK)
		world_env.environment.fog_density = clampf(0.032 / maxf(32.0, rd), 0.0015, 0.012)

func build_menu_panorama() -> void:
	clear_world()
	current_dimension = 0
	world_time = 0.34
	weather = "clear"
	gen = WorldGen.new(202611, 0)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			_ensure_chunk_sync(dx, dz)
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			_mesh_chunk_sync(chunks[Vector2i(dx, dz)])
	_update_day_night_and_weather(0.01)

func start_world(meta: Dictionary) -> void:
	clear_world()
	world_id = meta.get("id", "")
	world_name = meta.get("name", "World")
	world_seed = int(meta.get("seed", 1337))
	game_mode = int(meta.get("mode", 0))
	world_time = float(meta.get("time", 0.30))
	day_count = int(meta.get("days", 1))
	current_dimension = int(meta.get("dimension", 0))
	discovered_biomes = meta.get("discovered", []).duplicate()

	gen = WorldGen.new(world_seed, current_dimension)

	local_player = VoxelPlayer.new()
	local_player.world = self
	local_player.is_local = true
	local_player.game_mode = game_mode
	add_child(local_player)

	# Pre-generate a 3x3 chunk area around spawn synchronously so player lands on solid ground
	var sp := Vector3.ZERO
	if meta.has("player") and meta["player"].has("pos"):
		sp = meta["player"]["pos"]
	var scx := int(floor(sp.x / B.CHUNK))
	var scz := int(floor(sp.z / B.CHUNK))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			_ensure_chunk_sync(scx + dx, scz + dz)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			_mesh_chunk_sync(chunks[Vector2i(scx + dx, scz + dz)])

	if meta.has("player"):
		local_player.deserialize_state(meta["player"])
	else:
		local_player.global_position = find_safe_spawn()
		local_player.fall_peak_y = local_player.global_position.y
		local_player.give_starter_kit()

func _exit_tree() -> void:
	for tid in _gen_tasks.values():
		WorkerThreadPool.wait_for_task_completion(tid)
	_gen_tasks.clear()
	for entry in _mesh_tasks.values():
		WorkerThreadPool.wait_for_task_completion(entry["task"])
	_mesh_tasks.clear()

func clear_world() -> void:
	for tid in _gen_tasks.values():
		WorkerThreadPool.wait_for_task_completion(tid)
	_gen_tasks.clear()
	for entry in _mesh_tasks.values():
		WorkerThreadPool.wait_for_task_completion(entry["task"])
	_mesh_tasks.clear()
	for c in chunks.values():
		if c.solid_node != null: c.solid_node.queue_free()
		if c.liquid_node != null: c.liquid_node.queue_free()
	chunks.clear()
	for n in drops_root.get_children(): n.queue_free()
	for n in mobs_root.get_children(): n.queue_free()
	for n in proj_root.get_children(): n.queue_free()
	for n in remote_players.values(): n.queue_free()
	remote_players.clear()
	if local_player != null:
		local_player.queue_free()
		local_player = null

func save_all() -> void:
	if world_id.is_empty() or local_player == null:
		return
	for c in chunks.values():
		WorldSave.save_chunk(world_id, c)
	var meta := WorldSave.load_meta(world_id)
	meta["name"] = world_name
	meta["seed"] = world_seed
	meta["mode"] = game_mode
	meta["time"] = world_time
	meta["days"] = day_count
	meta["dimension"] = current_dimension
	meta["discovered"] = discovered_biomes
	meta["player"] = local_player.serialize_state()
	WorldSave.save_meta(world_id, meta)

func travel_dimension(new_dim: int) -> void:
	save_all()
	for tid in _gen_tasks.values():
		WorkerThreadPool.wait_for_task_completion(tid)
	_gen_tasks.clear()
	for entry in _mesh_tasks.values():
		WorkerThreadPool.wait_for_task_completion(entry["task"])
	_mesh_tasks.clear()
	for c in chunks.values():
		WorldSave.save_chunk(world_id, c)
		if c.solid_node != null: c.solid_node.queue_free()
		if c.liquid_node != null: c.liquid_node.queue_free()
	chunks.clear()
	for n in drops_root.get_children(): n.queue_free()
	for n in mobs_root.get_children(): n.queue_free()
	for n in proj_root.get_children(): n.queue_free()

	current_dimension = new_dim
	gen = WorldGen.new(world_seed, current_dimension)
	var pcx := int(floor(local_player.global_position.x / B.CHUNK))
	var pcz := int(floor(local_player.global_position.z / B.CHUNK))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			_ensure_chunk_sync(pcx + dx, pcz + dz)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			_mesh_chunk_sync(chunks[Vector2i(pcx + dx, pcz + dz)])

	var sp := find_safe_spawn_near(int(local_player.global_position.x), int(local_player.global_position.z))
	local_player.global_position = sp
	local_player.fall_peak_y = sp.y
	# Place a return Luminite portal plinth so the player can always travel back
	var px := int(floor(sp.x)) + 2
	var py := int(floor(sp.y))
	var pz := int(floor(sp.z))
	set_block(px, py - 1, pz, B.OBSIDIAN)
	set_block(px + 1, py - 1, pz, B.OBSIDIAN)
	set_block(px - 1, py - 1, pz, B.OBSIDIAN)
	set_block(px, py, pz, B.LUMINITE_BLOCK)
	_apply_graphics_settings()
	Sfx.play_ui("portal")

func find_safe_spawn() -> Vector3:
	return find_safe_spawn_near(8, 8)

func find_safe_spawn_near(wx: int, wz: int) -> Vector3:
	for r in range(0, 48, 4):
		for dx in [-r, 0, r]:
			for dz in [-r, 0, r]:
				var tx: int = wx + int(dx)
				var tz: int = wz + int(dz)
				var h := gen.height_at(tx, tz)
				if current_dimension == 1 and h < 20:
					continue
				if current_dimension == 0 and h <= B.SEA:
					continue
				for y in range(B.HEIGHT - 4, 8, -1):
					var b := get_block(tx, y, tz)
					if b != B.AIR and b != B.WATER and Registry.is_solid(b):
						return Vector3(float(tx) + 0.5, float(y + 1) + 0.05, float(tz) + 0.5)
	var fh := maxi(B.SEA + 2, gen.height_at(wx, wz))
	set_block(wx, fh, wz, B.STONE)
	return Vector3(float(wx) + 0.5, float(fh + 1) + 0.05, float(wz) + 0.5)

func _ensure_chunk_sync(cx: int, cz: int) -> VoxelChunk:
	var key := Vector2i(cx, cz)
	if chunks.has(key):
		return chunks[key]
	var c := VoxelChunk.new(cx, cz, current_dimension)
	if not WorldSave.load_chunk(world_id, c):
		c.chests = gen.generate_chunk(cx, cz, c.blocks, c.meta, c.biomes, c.hmap)
	_attach_chunk_nodes(c)
	chunks[key] = c
	return c

func _attach_chunk_nodes(c: VoxelChunk) -> void:
	var base_pos := Vector3(c.cx * B.CHUNK, 0, c.cz * B.CHUNK)
	c.solid_node = MeshInstance3D.new()
	c.solid_node.position = base_pos
	chunks_root.add_child(c.solid_node)

	c.liquid_node = MeshInstance3D.new()
	c.liquid_node.position = base_pos
	chunks_root.add_child(c.liquid_node)

func _mesh_chunk_sync(c: VoxelChunk) -> void:
	var empty := PackedByteArray()
	var c_px: VoxelChunk = chunks.get(Vector2i(c.cx + 1, c.cz))
	var c_nx: VoxelChunk = chunks.get(Vector2i(c.cx - 1, c.cz))
	var c_pz: VoxelChunk = chunks.get(Vector2i(c.cx, c.cz + 1))
	var c_nz: VoxelChunk = chunks.get(Vector2i(c.cx, c.cz - 1))
	c.build_mesh_data(
		c_px.blocks if c_px != null else empty,
		c_nx.blocks if c_nx != null else empty,
		c_pz.blocks if c_pz != null else empty,
		c_nz.blocks if c_nz != null else empty,
		gen
	)
	c.apply_mesh_data(solid_material, liquid_material)
	c.dirty = false

func _process(delta: float) -> void:
	if local_player == null:
		return
	_update_day_night_and_weather(delta)
	_stream_chunks()
	_process_falling_blocks()
	_tick_world_systems(delta)

func _update_day_night_and_weather(delta: float) -> void:
	# 10-minute full day/night cycle
	var prev_time := world_time
	world_time += delta / 600.0
	if world_time >= 1.0:
		world_time -= 1.0
		day_count += 1
		if (day_count % 5) == 0 and _rng.randf() < 0.45:
			weather = "blood_moon"
			weather_timer = 150.0
		elif weather == "blood_moon":
			weather = "clear"

	weather_timer -= delta
	if weather_timer <= 0.0:
		var r := _rng.randf()
		if r < 0.68:
			weather = "clear"
			weather_timer = _rng.randf_range(120.0, 240.0)
		elif r < 0.90:
			weather = "rain"
			weather_timer = _rng.randf_range(60.0, 140.0)
		else:
			weather = "storm"
			weather_timer = _rng.randf_range(45.0, 95.0)

	# Sun angle & sky colors
	var sun_angle := (world_time - 0.25) * TAU
	var sun_h := sin(sun_angle) # -1 midnight, 0 horizon, +1 noon
	sun_light.rotation = Vector3(-sun_angle if sun_h >= -0.05 else -(sun_angle + PI), -0.45, 0.0)

	var day_t := clampf((sun_h + 0.15) / 0.45, 0.0, 1.0)
	var sunset_t := clampf(1.0 - absf(sun_h) * 3.5, 0.0, 1.0)

	if current_dimension == 1:
		sky_mat.sky_top_color = Color(0.08, 0.04, 0.16)
		sky_mat.sky_horizon_color = Color(0.28, 0.12, 0.46)
		sky_mat.ground_horizon_color = Color(0.18, 0.08, 0.30)
		sky_mat.ground_bottom_color = Color(0.04, 0.02, 0.08)
		sun_light.light_color = Color(0.76, 0.62, 1.0)
		sun_light.light_energy = 0.65
		world_env.environment.fog_light_color = Color(0.22, 0.10, 0.36)
	else:
		var top_c := Color(0.03, 0.04, 0.11).lerp(Color(0.24, 0.52, 0.92), day_t)
		var hor_c := Color(0.06, 0.08, 0.18).lerp(Color(0.62, 0.80, 0.98), day_t).lerp(Color(0.95, 0.48, 0.24), sunset_t * 0.7)
		if weather == "blood_moon" and day_t < 0.4:
			top_c = Color(0.22, 0.03, 0.05)
			hor_c = Color(0.52, 0.08, 0.08)
		elif weather in ["rain", "storm"]:
			top_c = top_c.lerp(Color(0.28, 0.32, 0.38), 0.65)
			hor_c = hor_c.lerp(Color(0.42, 0.46, 0.52), 0.65)
		sky_mat.sky_top_color = top_c
		sky_mat.sky_horizon_color = hor_c
		sky_mat.ground_horizon_color = hor_c.darkened(0.25)
		sky_mat.ground_bottom_color = top_c.darkened(0.5)
		sun_light.light_color = Color(0.55, 0.65, 0.95).lerp(Color(1.0, 0.96, 0.88), day_t).lerp(Color(1.0, 0.58, 0.32), sunset_t * 0.6)
		sun_light.light_energy = lerpf(0.18, 1.15, day_t) * (0.55 if weather in ["rain", "storm"] else 1.0)
		world_env.environment.fog_light_color = hor_c

	# Clouds & Rain animation
	var ref_pos := local_player.global_position if local_player != null else Vector3.ZERO
	if clouds_root.visible:
		_cloud_offset = fmod(_cloud_offset + delta * 1.4, 320.0)
		clouds_root.position.x = ref_pos.x - 160.0 + _cloud_offset
		clouds_root.position.z = ref_pos.z

	var raining := (weather in ["rain", "storm"]) and current_dimension == 0
	rain_mesh.visible = raining
	Sfx.set_rain_intensity(1.0 if weather == "storm" else (0.6 if weather == "rain" else 0.0))
	solid_material.set_shader_parameter("wind_strength", 2.2 if weather == "storm" else (1.4 if weather == "rain" else 1.0))
	if raining:
		rain_mesh.global_position = ref_pos + Vector3(0, -Mathf_fmod(Time.get_ticks_msec() * 0.014, 4.0), 0)
		if weather == "storm" and _rng.randf() < delta * 0.08:
			sun_light.light_energy = 3.2
			Sfx.play_3d("explosion", ref_pos + Vector3(_rng.randf_range(-30, 30), 25, _rng.randf_range(-30, 30)), -2.0)

func Mathf_fmod(a: float, b: float) -> float:
	return a - floor(a / b) * b

func is_daytime() -> bool:
	return world_time > 0.23 and world_time < 0.77

func skip_to_morning() -> void:
	world_time = 0.26
	day_count += 1
	if weather in ["rain", "storm", "blood_moon"]:
		weather = "clear"

func _stream_chunks() -> void:
	# 1. Harvest finished generation tasks
	for key in _gen_tasks.keys():
		var tid: int = _gen_tasks[key]
		if WorkerThreadPool.is_task_completed(tid):
			WorkerThreadPool.wait_for_task_completion(tid)
			_gen_tasks.erase(key)

	# 2. Harvest finished mesh tasks (up to 3 per frame for butter-smooth frame times)
	var applied := 0
	for key in _mesh_tasks.keys():
		var entry: Dictionary = _mesh_tasks[key]
		var tid2: int = entry["task"]
		if WorkerThreadPool.is_task_completed(tid2):
			WorkerThreadPool.wait_for_task_completion(tid2)
			var c: VoxelChunk = entry["chunk"]
			c.meshing = false
			if chunks.has(key):
				c.apply_mesh_data(solid_material, liquid_material)
			_mesh_tasks.erase(key)
			applied += 1
			if applied >= 3:
				break

	var pcx := int(floor(local_player.global_position.x / B.CHUNK))
	var pcz := int(floor(local_player.global_position.z / B.CHUNK))
	var rd := clampi(Settings.render_distance, 4, 14)

	# 3. Unload chunks beyond render_distance + 2
	var unload_r := rd + 2
	for key in chunks.keys():
		if absi(key.x - pcx) > unload_r or absi(key.y - pcz) > unload_r:
			if _mesh_tasks.has(key) or _gen_tasks.has(key):
				continue
			var uc: VoxelChunk = chunks[key]
			WorldSave.save_chunk(world_id, uc)
			if uc.solid_node != null: uc.solid_node.queue_free()
			if uc.liquid_node != null: uc.liquid_node.queue_free()
			chunks.erase(key)

	# 4. Queue missing chunks & dirty chunk remeshing in radial order (1 task per category for lock-free thread safety)
	var max_gen_queue := 1
	var max_mesh_queue := 1
	for r in range(0, rd + 1):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				if dx * dx + dz * dz > rd * rd + 2:
					continue
				var cx := pcx + dx
				var cz := pcz + dz
				var key := Vector2i(cx, cz)
				if not chunks.has(key):
					if not _gen_tasks.has(key) and _gen_tasks.size() < max_gen_queue:
						var nc := VoxelChunk.new(cx, cz, current_dimension)
						_attach_chunk_nodes(nc)
						chunks[key] = nc
						var wid := world_id
						var g := gen
						_gen_tasks[key] = WorkerThreadPool.add_task(func() -> void:
							if not WorldSave.load_chunk(wid, nc):
								nc.chests = g.generate_chunk(cx, cz, nc.blocks, nc.meta, nc.biomes, nc.hmap)
							nc.dirty = true
						)
				else:
					var c: VoxelChunk = chunks[key]
					if c.dirty and not c.meshing and not _gen_tasks.has(key) and _mesh_tasks.size() < max_mesh_queue:
						c.dirty = false
						c.meshing = true
						var empty := PackedByteArray()
						var k_px := Vector2i(cx + 1, cz)
						var k_nx := Vector2i(cx - 1, cz)
						var k_pz := Vector2i(cx, cz + 1)
						var k_nz := Vector2i(cx, cz - 1)
						var c_px: VoxelChunk = chunks.get(k_px)
						var c_nx: VoxelChunk = chunks.get(k_nx)
						var c_pz: VoxelChunk = chunks.get(k_pz)
						var c_nz: VoxelChunk = chunks.get(k_nz)
						var nb_px := c_px.blocks.duplicate() if (c_px != null and not _gen_tasks.has(k_px)) else empty
						var nb_nx := c_nx.blocks.duplicate() if (c_nx != null and not _gen_tasks.has(k_nx)) else empty
						var nb_pz := c_pz.blocks.duplicate() if (c_pz != null and not _gen_tasks.has(k_pz)) else empty
						var nb_nz := c_nz.blocks.duplicate() if (c_nz != null and not _gen_tasks.has(k_nz)) else empty
						var g2 := gen
						var res_holder := {"chunk": c}
						res_holder["task"] = WorkerThreadPool.add_task(func() -> void:
							c.build_mesh_data(nb_px, nb_nx, nb_pz, nb_nz, g2)
						)
						_mesh_tasks[key] = res_holder

func is_chunk_loaded_at(pos: Vector3) -> bool:
	var key := Vector2i(int(floor(pos.x / B.CHUNK)), int(floor(pos.z / B.CHUNK)))
	return chunks.has(key) and not _gen_tasks.has(key)

func get_block(wx: int, wy: int, wz: int) -> int:
	if wy < 0: return B.BEDROCK
	if wy >= B.HEIGHT: return B.AIR
	var cx := wx >> 4
	var cz := wz >> 4
	var c: VoxelChunk = chunks.get(Vector2i(cx, cz))
	if c == null or _gen_tasks.has(Vector2i(cx, cz)):
		return B.AIR
	return c.blocks[B.idx(wx & 15, wy, wz & 15)]

func get_meta_val(wx: int, wy: int, wz: int) -> int:
	if wy < 0 or wy >= B.HEIGHT: return 0
	var cx := wx >> 4
	var cz := wz >> 4
	var c: VoxelChunk = chunks.get(Vector2i(cx, cz))
	if c == null: return 0
	return c.meta[B.idx(wx & 15, wy, wz & 15)]

func get_skylight(wx: int, wy: int, wz: int) -> int:
	if wy < 0 or wy >= B.HEIGHT: return 15
	var c: VoxelChunk = chunks.get(Vector2i(wx >> 4, wz >> 4))
	if c == null: return 15
	return (c.light[B.idx(wx & 15, wy, wz & 15)] >> 4) & 15

func is_solid_at(wx: int, wy: int, wz: int) -> bool:
	return not get_block_boxes(wx, wy, wz).is_empty()

func get_block_boxes(wx: int, wy: int, wz: int) -> Array:
	var id := get_block(wx, wy, wz)
	if id == B.AIR or Registry.b_solid[id] == 0:
		return []
	var m := get_meta_val(wx, wy, wz)
	var local_boxes := Registry.collision_boxes(id, m)
	var out := []
	var base := Vector3(wx, wy, wz)
	for b in local_boxes:
		out.append(AABB(base + b.position, b.size))
	return out

func set_block(wx: int, wy: int, wz: int, id: int, meta_val: int = 0, from_net: bool = false) -> void:
	if wy <= 0 or wy >= B.HEIGHT:
		return
	var cx := wx >> 4
	var cz := wz >> 4
	var c: VoxelChunk = chunks.get(Vector2i(cx, cz))
	if c == null:
		return
	var lx := wx & 15
	var lz := wz & 15
	var idx := B.idx(lx, wy, lz)
	c.blocks[idx] = id
	c.meta[idx] = meta_val
	c.modified = true

	# Remesh immediately on main thread if not currently meshing so block edits have zero lag
	if not c.meshing:
		_mesh_chunk_sync(c)
	else:
		c.dirty = true

	# Mark adjacent chunk dirty if edited on border
	if lx == 0 and chunks.has(Vector2i(cx - 1, cz)): chunks[Vector2i(cx - 1, cz)].dirty = true
	if lx == 15 and chunks.has(Vector2i(cx + 1, cz)): chunks[Vector2i(cx + 1, cz)].dirty = true
	if lz == 0 and chunks.has(Vector2i(cx, cz - 1)): chunks[Vector2i(cx, cz - 1)].dirty = true
	if lz == 15 and chunks.has(Vector2i(cx, cz + 1)): chunks[Vector2i(cx, cz + 1)].dirty = true

	# Queue gravity check for sand/gravel at and above this block
	_falling_check_queue.append(Vector3i(wx, wy, wz))
	_falling_check_queue.append(Vector3i(wx, wy + 1, wz))

	# Fluid interaction: Water + Lava -> Obsidian / Cobblestone
	if id == B.WATER or id == B.LAVA:
		for n in Registry.FACE_NORMALS:
			var nb_id := get_block(wx + n.x, wy + n.y, wz + n.z)
			if (id == B.WATER and nb_id == B.LAVA) or (id == B.LAVA and nb_id == B.WATER):
				set_block(wx, wy, wz, B.OBSIDIAN)
				Sfx.play_block(B.STONE, Vector3(wx, wy, wz), "break")
				break

	if not from_net and Net.is_active():
		Net.broadcast_block_change(wx, wy, wz, id, meta_val)

func _process_falling_blocks() -> void:
	if _falling_check_queue.is_empty():
		return
	var batch := _falling_check_queue.duplicate()
	_falling_check_queue.clear()
	for p in batch:
		var id := get_block(p.x, p.y, p.z)
		if id > 0 and Registry.b_gravity[id] == 1:
			var below := get_block(p.x, p.y - 1, p.z)
			if below == B.AIR or below == B.WATER or below == B.FIRE:
				var ty: int = p.y - 1
				while ty > 1 and (get_block(p.x, ty - 1, p.z) in [B.AIR, B.WATER, B.FIRE]):
					ty -= 1
				set_block(p.x, p.y, p.z, B.AIR)
				set_block(p.x, ty, p.z, id)

func harvest_block(bp: Vector3i, held_id: int, drop_items: bool = true) -> void:
	var id := get_block(bp.x, bp.y, bp.z)
	if id <= 0 or id == B.BEDROCK:
		return
	var m := get_meta_val(bp.x, bp.y, bp.z)
	var center := Vector3(bp) + Vector3(0.5, 0.5, 0.5)
	Sfx.play_block(id, center, "break")
	VoxelFX.spawn_block_particles(self, center, id, 16)

	# Drop chest/furnace contents if broken
	var c: VoxelChunk = chunks.get(Vector2i(bp.x >> 4, bp.z >> 4))
	if c != null:
		if c.chests.has(bp):
			for s in c.chests[bp]:
				if s["id"] > 0 and s["count"] > 0:
					spawn_drop(center, s["id"], s["count"], s["dur"])
			c.chests.erase(bp)
		if c.furnaces.has(bp):
			var fd: Dictionary = c.furnaces[bp]
			for k in ["in", "fuel", "out"]:
				if fd.has(k) and fd[k]["id"] > 0 and fd[k]["count"] > 0:
					spawn_drop(center, fd[k]["id"], fd[k]["count"], fd[k]["dur"])
			c.furnaces.erase(bp)

	if drop_items:
		var list := Registry.drops(id, m, held_id, _rng)
		for entry in list:
			spawn_drop(center, entry[0], entry[1])

	set_block(bp.x, bp.y, bp.z, B.AIR)
	# Break paired door half or unsupported flora above
	if id == B.DOOR_LOWER and get_block(bp.x, bp.y + 1, bp.z) == B.DOOR_UPPER:
		set_block(bp.x, bp.y + 1, bp.z, B.AIR)
	elif id == B.DOOR_UPPER and get_block(bp.x, bp.y - 1, bp.z) == B.DOOR_LOWER:
		if drop_items:
			spawn_drop(center, Registry.id_of("oak_door"), 1)
		set_block(bp.x, bp.y - 1, bp.z, B.AIR)
	var above_id := get_block(bp.x, bp.y + 1, bp.z)
	if Registry.b_render[above_id] == B.R_CROSS:
		harvest_block(Vector3i(bp.x, bp.y + 1, bp.z), 0, drop_items)

func try_place_block(pp: Vector3i, clicked_pos: Vector3i, normal: Vector3i, id: int, player: VoxelPlayer) -> bool:
	var cur := get_block(pp.x, pp.y, pp.z)
	if not Registry.is_replaceable(cur):
		return false

	# Specific placement rules for crops & flora
	if id == B.WHEAT:
		if get_block(pp.x, pp.y - 1, pp.z) != B.FARMLAND:
			return false
	elif id in [B.OAK_SAPLING, B.BIRCH_SAPLING, B.PINE_SAPLING, B.FLOWER_RED, B.FLOWER_YELLOW, B.FLOWER_BLUE]:
		if not (get_block(pp.x, pp.y - 1, pp.z) in [B.GRASS, B.DIRT, B.FARMLAND, B.SNOW_GRASS]):
			return false
	elif id == B.DOOR_LOWER:
		if not Registry.is_replaceable(get_block(pp.x, pp.y + 1, pp.z)) or not is_solid_at(pp.x, pp.y - 1, pp.z):
			return false

	# Facing metadata for directional blocks
	var meta_val := 0
	var look_dir := -player.cam.global_transform.basis.z
	if absf(look_dir.x) > absf(look_dir.z):
		meta_val = 1 if look_dir.x > 0 else 3
	else:
		meta_val = 2 if look_dir.z > 0 else 0

	if id == B.TORCH:
		if normal.y > 0:
			meta_val = 4
		elif normal.z > 0: meta_val = 0
		elif normal.x < 0: meta_val = 1
		elif normal.z < 0: meta_val = 2
		elif normal.x > 0: meta_val = 3
	elif id == B.LADDER:
		if normal.y != 0:
			return false
		if normal.z > 0: meta_val = 0
		elif normal.x < 0: meta_val = 1
		elif normal.z < 0: meta_val = 2
		elif normal.x > 0: meta_val = 3

	# Prevent placing a solid block overlapping the player's own AABB
	if Registry.b_solid[id] == 1:
		var p_aabb := AABB(player.global_position - Vector3(VoxelPlayer.HALF_W, 0.0, VoxelPlayer.HALF_W), Vector3(VoxelPlayer.HALF_W * 2.0, VoxelPlayer.HEIGHT, VoxelPlayer.HALF_W * 2.0))
		for box in Registry.collision_boxes(id, meta_val):
			if p_aabb.intersects(AABB(Vector3(pp) + box.position, box.size)):
				return false

	set_block(pp.x, pp.y, pp.z, id, meta_val)
	if id == B.DOOR_LOWER:
		set_block(pp.x, pp.y + 1, pp.z, B.DOOR_UPPER, meta_val)
	elif id == B.POWER_CORE:
		propagate_energy(pp)

	Sfx.play_block(id, Vector3(pp) + Vector3(0.5, 0.5, 0.5), "place")
	return true

func toggle_door(bp: Vector3i) -> void:
	var id := get_block(bp.x, bp.y, bp.z)
	var m := get_meta_val(bp.x, bp.y, bp.z)
	var nm := m ^ 4
	set_block(bp.x, bp.y, bp.z, id, nm)
	if id == B.DOOR_LOWER and get_block(bp.x, bp.y + 1, bp.z) == B.DOOR_UPPER:
		set_block(bp.x, bp.y + 1, bp.z, B.DOOR_UPPER, nm)
	elif id == B.DOOR_UPPER and get_block(bp.x, bp.y - 1, bp.z) == B.DOOR_LOWER:
		set_block(bp.x, bp.y - 1, bp.z, B.DOOR_LOWER, nm)
	Sfx.play_block(B.OAK_PLANKS, Vector3(bp), "place")

func toggle_lever(bp: Vector3i) -> void:
	var m := get_meta_val(bp.x, bp.y, bp.z)
	var nm := m ^ 4
	set_block(bp.x, bp.y, bp.z, B.LEVER, nm)
	Sfx.play_ui("click", 1.2 if (nm & 4) != 0 else 0.85)
	if (nm & 4) != 0:
		propagate_energy(bp)

func propagate_energy(source: Vector3i) -> void:
	var visited := {source: true}
	var queue: Array[Vector3i] = [source]
	var head := 0
	while head < queue.size() and head < 32:
		var cur := queue[head]
		head += 1
		for n in Registry.FACE_NORMALS:
			var np: Vector3i = cur + n
			if visited.has(np):
				continue
			visited[np] = true
			var bid := get_block(np.x, np.y, np.z)
			if bid == B.ENERGY_CONDUIT or bid == B.POWER_CORE:
				queue.append(np)
			elif bid in [B.DOOR_LOWER, B.DOOR_UPPER]:
				toggle_door(np)
			elif bid == B.PISTON:
				_activate_piston(np)
			elif bid == B.EXPLOSIVE_BARREL:
				set_block(np.x, np.y, np.z, B.AIR)
				explode(Vector3(np) + Vector3(0.5, 0.5, 0.5), 4.0, 18.0)

func _activate_piston(ppos: Vector3i) -> void:
	var m := get_meta_val(ppos.x, ppos.y, ppos.z) & 3
	var dir: Vector3i = Registry.FACING_DIRS[m]
	var front := ppos + dir
	var target_pos := front + dir
	var fid := get_block(front.x, front.y, front.z)
	if fid != B.AIR and fid != B.BEDROCK and fid != B.OBSIDIAN and get_block(target_pos.x, target_pos.y, target_pos.z) == B.AIR:
		var fmeta := get_meta_val(front.x, front.y, front.z)
		set_block(front.x, front.y, front.z, B.AIR)
		set_block(target_pos.x, target_pos.y, target_pos.z, fid, fmeta)
		Sfx.play_block(B.STONE, Vector3(ppos), "place")

func has_obsidian_frame(bp: Vector3i) -> bool:
	var obs_count := 0
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			for dz in range(-2, 3):
				if get_block(bp.x + dx, bp.y + dy, bp.z + dz) == B.OBSIDIAN:
					obs_count += 1
	return obs_count >= 4

## Fast 3D DDA voxel raycast
func raycast_voxel(origin: Vector3, dir: Vector3, max_dist: float, hit_liquids: bool = false) -> Dictionary:
	var d := dir.normalized()
	if d.length_squared() < 0.0001:
		return {"hit": false}
	var x := int(floor(origin.x))
	var y := int(floor(origin.y))
	var z := int(floor(origin.z))
	var step_x := 1 if d.x >= 0.0 else -1
	var step_y := 1 if d.y >= 0.0 else -1
	var step_z := 1 if d.z >= 0.0 else -1
	var t_delta_x := absf(1.0 / d.x) if absf(d.x) > 1e-6 else 1e30
	var t_delta_y := absf(1.0 / d.y) if absf(d.y) > 1e-6 else 1e30
	var t_delta_z := absf(1.0 / d.z) if absf(d.z) > 1e-6 else 1e30
	var t_max_x := ((float(x + 1) - origin.x) if step_x > 0 else (origin.x - float(x))) * t_delta_x
	var t_max_y := ((float(y + 1) - origin.y) if step_y > 0 else (origin.y - float(y))) * t_delta_y
	var t_max_z := ((float(z + 1) - origin.z) if step_z > 0 else (origin.z - float(z))) * t_delta_z

	var prev := Vector3i(x, y, z)
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_dist:
		var id := get_block(x, y, z)
		if id != B.AIR and (hit_liquids or not Registry.is_liquid(id)):
			return {
				"hit": true,
				"block_pos": Vector3i(x, y, z),
				"place_pos": prev,
				"normal": normal,
				"dist": t,
			}
		prev = Vector3i(x, y, z)
		if t_max_x < t_max_y:
			if t_max_x < t_max_z:
				x += step_x; t = t_max_x; t_max_x += t_delta_x
				normal = Vector3i(-step_x, 0, 0)
			else:
				z += step_z; t = t_max_z; t_max_z += t_delta_z
				normal = Vector3i(0, 0, -step_z)
		else:
			if t_max_y < t_max_z:
				y += step_y; t = t_max_y; t_max_y += t_delta_y
				normal = Vector3i(0, -step_y, 0)
			else:
				z += step_z; t = t_max_z; t_max_z += t_delta_z
				normal = Vector3i(0, 0, -step_z)
	return {"hit": false}

func spawn_drop(pos: Vector3, item_id: int, count: int, dur: int = -1, vel: Vector3 = Vector3.ZERO) -> void:
	if item_id <= 0 or count <= 0:
		return
	if dur < 0:
		dur = Registry.item(item_id).get("durability", 0)
	# Merge with nearby identical drop if possible
	var max_s := Registry.max_stack(item_id)
	if max_s > 1:
		for d in drops_root.get_children():
			if d is DroppedItem and d.item_id == item_id and d.count + count <= max_s and d.global_position.distance_to(pos) < 1.3:
				d.count += count
				return
	var drop := DroppedItem.new()
	drop.position = pos
	if vel == Vector3.ZERO:
		vel = Vector3(_rng.randf_range(-1.8, 1.8), _rng.randf_range(2.2, 3.8), _rng.randf_range(-1.8, 1.8))
	drop.setup(self, item_id, count, dur, vel)
	drops_root.add_child(drop)

func spawn_mob(mob_type: String, pos: Vector3) -> VoxelMob:
	var m := VoxelMob.new()
	m.position = pos
	m.setup(self, mob_type)
	mobs_root.add_child(m)
	return m

func spawn_projectile(shooter: Node3D, kind: String, pos: Vector3, vel: Vector3, dmg: float) -> VoxelProjectile:
	var p := VoxelProjectile.new()
	p.position = pos
	p.setup(self, shooter, kind, vel, dmg)
	proj_root.add_child(p)
	return p

func explode(center: Vector3, radius: float, max_dmg: float) -> void:
	Sfx.play_3d("explosion", center, 2.0)
	VoxelFX.spawn_explosion_particles(self, center)
	var r := int(ceil(radius))
	var cx := int(floor(center.x))
	var cy := int(floor(center.y))
	var cz := int(floor(center.z))
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var p := Vector3(cx + dx + 0.5, cy + dy + 0.5, cz + dz + 0.5)
				if p.distance_to(center) <= radius:
					var bid := get_block(cx + dx, cy + dy, cz + dz)
					if bid != B.AIR and bid != B.BEDROCK and bid != B.OBSIDIAN:
						if _rng.randf() < 0.25:
							var dr := Registry.drops(bid, 0, 0, _rng)
							for e in dr:
								spawn_drop(p, e[0], e[1])
						set_block(cx + dx, cy + dy, cz + dz, B.AIR)
	for m in mobs_root.get_children():
		if m is VoxelMob:
			var d: float = m.global_position.distance_to(center)
			if d < radius * 2.0:
				var f: float = 1.0 - (d / (radius * 2.0))
				m.take_damage(max_dmg * f, (m.global_position - center).normalized() * 10.0 * f, null)
	if local_player != null and not local_player.is_dead:
		var dp := local_player.global_position.distance_to(center)
		if dp < radius * 2.0:
			var fp := 1.0 - (dp / (radius * 2.0))
			local_player.take_damage(max_dmg * fp, "explosion", (local_player.global_position - center).normalized() * 9.0 * fp)

func get_chest_slots(pos: Vector3i) -> Array:
	var c: VoxelChunk = chunks.get(Vector2i(pos.x >> 4, pos.z >> 4))
	if c == null:
		return []
	if not c.chests.has(pos):
		var arr := []
		arr.resize(27)
		for i in 27: arr[i] = {"id": 0, "count": 0, "dur": 0}
		c.chests[pos] = arr
	c.modified = true
	return c.chests[pos]

func get_furnace_data(pos: Vector3i) -> Dictionary:
	var c: VoxelChunk = chunks.get(Vector2i(pos.x >> 4, pos.z >> 4))
	if c == null:
		return {}
	if not c.furnaces.has(pos):
		c.furnaces[pos] = {
			"in": {"id": 0, "count": 0, "dur": 0},
			"fuel": {"id": 0, "count": 0, "dur": 0},
			"out": {"id": 0, "count": 0, "dur": 0},
			"burn": 0.0,
			"burn_max": 1.0,
			"prog": 0.0,
		}
	c.modified = true
	return c.furnaces[pos]

func _tick_world_systems(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum >= 0.25:
		var dt := _tick_accum
		_tick_accum = 0.0
		_tick_furnaces(dt)
		_random_block_ticks()
		_check_biome_discovery()

	_mob_spawn_timer -= delta
	if _mob_spawn_timer <= 0.0:
		_mob_spawn_timer = 3.5
		_try_spawn_mobs()

func _tick_furnaces(dt: float) -> void:
	for c in chunks.values():
		if c.furnaces.is_empty():
			continue
		for pos in c.furnaces.keys():
			var fd: Dictionary = c.furnaces[pos]
			var was_burning: bool = fd["burn"] > 0.0
			if fd["burn"] > 0.0:
				fd["burn"] = maxf(0.0, fd["burn"] - dt)

			var in_key := Registry.key_of(fd["in"]["id"])
			var can_smelt := false
			var out_id := 0
			var out_cnt := 1
			if in_key != "" and Registry.smelting.has(in_key):
				var spec: Array = Registry.smelting[in_key]
				out_id = Registry.id_of(spec[0])
				out_cnt = spec[1]
				if fd["out"]["id"] == 0 or (fd["out"]["id"] == out_id and fd["out"]["count"] + out_cnt <= Registry.max_stack(out_id)):
					can_smelt = true

			if can_smelt and fd["burn"] <= 0.0:
				var fkey := Registry.key_of(fd["fuel"]["id"])
				if fkey != "" and Registry.fuel.has(fkey):
					var fsec: float = Registry.fuel[fkey]
					fd["burn"] = fsec
					fd["burn_max"] = fsec
					var ret: String = Registry.item(fd["fuel"]["id"]).get("returns", "")
					fd["fuel"]["count"] -= 1
					if fd["fuel"]["count"] <= 0:
						fd["fuel"] = {"id": Registry.id_of(ret) if ret != "" else 0, "count": 1 if ret != "" else 0, "dur": 0}

			if can_smelt and fd["burn"] > 0.0:
				fd["prog"] += dt / 6.0 # 6 seconds per item
				if fd["prog"] >= 1.0:
					fd["prog"] = 0.0
					fd["in"]["count"] -= 1
					if fd["in"]["count"] <= 0:
						fd["in"] = {"id": 0, "count": 0, "dur": 0}
					if fd["out"]["id"] == 0:
						fd["out"] = {"id": out_id, "count": out_cnt, "dur": 0}
					else:
						fd["out"]["count"] += out_cnt
			else:
				fd["prog"] = maxf(0.0, fd["prog"] - dt * 0.5)

			var now_burning: bool = fd["burn"] > 0.0
			if was_burning != now_burning:
				var cur_b := get_block(pos.x, pos.y, pos.z)
				if cur_b in [B.FURNACE, B.FURNACE_LIT]:
					set_block(pos.x, pos.y, pos.z, B.FURNACE_LIT if now_burning else B.FURNACE, get_meta_val(pos.x, pos.y, pos.z))

func _random_block_ticks() -> void:
	# Random growth ticks for wheat crops, saplings, grass spread, and fire
	for c in chunks.values():
		if _gen_tasks.has(Vector2i(c.cx, c.cz)):
			continue
		for _i in 3:
			var lx := _rng.randi() & 15
			var lz := _rng.randi() & 15
			var h: int = c.hmap[lx + (lz << 4)]
			for dy in range(0, 3):
				var y := clampi(h + dy, 1, B.HEIGHT - 2)
				var idx := B.idx(lx, y, lz)
				var id: int = c.blocks[idx]
				var wx: int = c.cx * B.CHUNK + lx
				var wz: int = c.cz * B.CHUNK + lz
				if id == B.WHEAT:
					var st: int = c.meta[idx]
					if st < 7 and _rng.randf() < 0.35:
						set_block(wx, y, wz, B.WHEAT, st + 1)
				elif id in [B.OAK_SAPLING, B.BIRCH_SAPLING, B.PINE_SAPLING] and lx >= 2 and lx <= 13 and lz >= 2 and lz <= 13:
					if _rng.randf() < 0.15:
						var tkind := "oak" if id == B.OAK_SAPLING else ("birch" if id == B.BIRCH_SAPLING else "pine")
						WorldGen._place_tree(c.blocks, lx, y, lz, tkind, _rng.randi() % 10)
						c.modified = true
						c.dirty = true
				elif id == B.FIRE:
					if weather in ["rain", "storm"] or _rng.randf() < 0.25:
						set_block(wx, y, wz, B.AIR)

func _check_biome_discovery() -> void:
	if local_player == null:
		return
	var px := int(floor(local_player.global_position.x))
	var py := int(floor(local_player.global_position.y))
	var pz := int(floor(local_player.global_position.z))
	var b_idx := gen.biome_at(px, pz)
	if current_dimension == 0 and py < 24:
		b_idx = WorldGen.BIOME_CRYSTAL
	var b_key: String = WorldGen.BIOME_KEYS[b_idx]
	if not (b_key in discovered_biomes):
		discovered_biomes.append(b_key)
		region_discovered.emit(Locale.t("biome." + b_key))

func _try_spawn_mobs() -> void:
	if local_player == null or mobs_root.get_child_count() >= 24:
		return
	var ang := _rng.randf() * TAU
	var dist := _rng.randf_range(18.0, 42.0)
	var sx := int(local_player.global_position.x + sin(ang) * dist)
	var sz := int(local_player.global_position.z + cos(ang) * dist)
	if not is_chunk_loaded_at(Vector3(sx, 60, sz)):
		return
	var h := gen.height_at(sx, sz)
	var bio := gen.biome_at(sx, sz)

	if current_dimension == 1:
		if h > 25:
			var utype := "wraith" if _rng.randf() < 0.65 else ("crystal_colossus" if _rng.randf() < 0.18 else "spider")
			spawn_mob(utype, Vector3(sx + 0.5, h + 1.2, sz + 0.5))
		return

	# Aquatic fish in rivers/oceans
	if get_block(sx, B.SEA - 1, sz) == B.WATER and _rng.randf() < 0.35:
		spawn_mob("fish", Vector3(sx + 0.5, B.SEA - 1.5, sz + 0.5))
		return

	if h <= B.SEA:
		return

	if is_daytime() and weather != "blood_moon":
		var ptype := "cow"
		match bio:
			WorldGen.BIOME_SNOWY: ptype = "frost_hare"
			WorldGen.BIOME_TAIGA: ptype = "wolf" if _rng.randf() < 0.45 else "sheep"
			WorldGen.BIOME_FOREST, WorldGen.BIOME_BIRCH:
				var pool := ["pig", "chicken", "wolf", "sheep"]
				ptype = pool[_rng.randi() % pool.size()]
			_:
				var pool2 := ["cow", "sheep", "pig", "chicken"]
				ptype = pool2[_rng.randi() % pool2.size()]
		spawn_mob(ptype, Vector3(sx + 0.5, h + 1.1, sz + 0.5))
	else:
		var hpool := ["zombie", "skeleton", "spider", "creeper", "wraith"]
		var htype: String = hpool[_rng.randi() % hpool.size()]
		spawn_mob(htype, Vector3(sx + 0.5, h + 1.1, sz + 0.5))

func ui_blocking_input() -> bool:
	return main_ui != null and main_ui.is_blocking_gameplay()
