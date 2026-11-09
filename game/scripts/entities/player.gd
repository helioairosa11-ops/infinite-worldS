class_name VoxelPlayer
extends Node3D
## Complete voxel player controller: first/third-person camera, exact AABB physics,
## sneaking edge-guard, swimming/ladders, survival stats (health, hunger, oxygen, fall/lava damage),
## 36-slot inventory + 4 armor slots, DDA voxel raycast, progressive mining, building, combat & tools.

signal stats_changed
signal inventory_changed
signal died
signal open_station(kind: String, pos: Vector3i)
signal message_shown(text: String)

const EYE_H := 1.62
const SNEAK_EYE_H := 1.42
const HALF_W := 0.30
const HEIGHT := 1.78

var world: Node
var peer_id: int = 1
var is_local: bool = true
var game_mode: int = 0 # 0 = survival, 1 = creative

# Survival stats
var hp: float = 20.0
var max_hp: float = 20.0
var hunger: float = 20.0
var max_hunger: float = 20.0
var saturation: float = 8.0
var oxygen: float = 10.0
var max_oxygen: float = 10.0
var is_dead: bool = false

# Movement state
var velocity: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var pitch: float = 0.0
var on_ground: bool = false
var in_water: bool = false
var head_underwater: bool = false
var in_lava: bool = false
var on_ladder: bool = false
var fall_peak_y: float = -999.0
var step_accum: float = 0.0
var bob_phase: float = 0.0
var third_person: bool = false
var spawn_point: Vector3 = Vector3.ZERO
var has_custom_spawn: bool = false

# Inventory: 36 slots (0..8 hotbar, 9..35 backpack), 4 armor slots
var inv: Array = []
var armor: Array = []
var hotbar_idx: int = 0
var cursor_slot: Dictionary = {"id": 0, "count": 0, "dur": 0}

# Mining & interaction
var look_hit: Dictionary = {} # {hit:bool, block_pos:Vector3i, place_pos:Vector3i, normal:Vector3i, mob:VoxelMob}
var mine_pos: Vector3i = Vector3i(0, -999, 0)
var mine_progress: float = 0.0
var swing_anim: float = 0.0
var place_cooldown: float = 0.0
var attack_cooldown: float = 0.0
var regen_timer: float = 0.0
var active_bobber: VoxelProjectile = null

# Nodes
var head_pivot: Node3D
var cam: Camera3D
var hand_pivot: Node3D
var hand_sprite: Sprite3D
var hand_block_mesh: MeshInstance3D
var hand_block_mat: StandardMaterial3D
var hand_arm_mesh: MeshInstance3D
var body_mesh: Node3D
var select_box: MeshInstance3D
var crack_box: MeshInstance3D
var crack_mat: StandardMaterial3D

func _init() -> void:
	inv.resize(36)
	for i in 36:
		inv[i] = {"id": 0, "count": 0, "dur": 0}
	armor.resize(4)
	for i in 4:
		armor[i] = {"id": 0, "count": 0, "dur": 0}

func _ready() -> void:
	_build_nodes()
	Settings.changed.connect(_on_settings_changed)
	_on_settings_changed()

func _build_nodes() -> void:
	head_pivot = Node3D.new()
	head_pivot.position = Vector3(0, EYE_H, 0)
	add_child(head_pivot)

	cam = Camera3D.new()
	cam.current = is_local
	cam.near = 0.05
	cam.far = 450.0
	head_pivot.add_child(cam)

	# First-person held item in bottom-right of view
	hand_pivot = Node3D.new()
	hand_pivot.position = Vector3(0.42, -0.34, -0.52)
	cam.add_child(hand_pivot)

	hand_sprite = Sprite3D.new()
	hand_sprite.pixel_size = 0.015
	hand_sprite.shaded = true
	hand_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	hand_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hand_sprite.rotation_degrees = Vector3(8, -32, 12)
	hand_pivot.add_child(hand_sprite)

	hand_block_mesh = MeshInstance3D.new()
	var hbm := BoxMesh.new()
	hbm.size = Vector3(0.28, 0.28, 0.28)
	hand_block_mat = StandardMaterial3D.new()
	hand_block_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hand_block_mat.roughness = 0.9
	hbm.material = hand_block_mat
	hand_block_mesh.mesh = hbm
	hand_block_mesh.rotation_degrees = Vector3(12, 38, -6)
	hand_pivot.add_child(hand_block_mesh)

	hand_arm_mesh = MeshInstance3D.new()
	var arm_bm := BoxMesh.new()
	arm_bm.size = Vector3(0.14, 0.14, 0.42)
	var arm_mat := StandardMaterial3D.new()
	arm_mat.albedo_color = Color("#dfb18b")
	arm_mat.roughness = 0.85
	arm_bm.material = arm_mat
	hand_arm_mesh.mesh = arm_bm
	hand_arm_mesh.position = Vector3(0.06, -0.06, 0.10)
	hand_arm_mesh.rotation_degrees = Vector3(18, -14, 0)
	hand_pivot.add_child(hand_arm_mesh)

	# Third-person / multiplayer character model
	body_mesh = _build_character_model()
	body_mesh.visible = not is_local
	add_child(body_mesh)

	# Block wireframe selection box & crack overlay
	select_box = _build_wire_box()
	select_box.top_level = true
	select_box.visible = false
	add_child(select_box)

	crack_box = MeshInstance3D.new()
	crack_box.top_level = true
	crack_box.visible = false
	var cbm := BoxMesh.new()
	cbm.size = Vector3(1.006, 1.006, 1.006)
	crack_mat = StandardMaterial3D.new()
	crack_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crack_mat.albedo_color = Color(1, 1, 1, 0.75)
	crack_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	cbm.material = crack_mat
	crack_box.mesh = cbm
	add_child(crack_box)

func _build_character_model() -> Node3D:
	var root := Node3D.new()
	var parts := [
		[Vector3(0.46, 0.68, 0.24), Vector3(0, 1.02, 0), Color("#34689a")],
		[Vector3(0.44, 0.44, 0.44), Vector3(0, 1.58, 0), Color("#dfb18b")],
		[Vector3(0.46, 0.14, 0.46), Vector3(0, 1.76, 0), Color("#4a321e")],
		[Vector3(0.20, 0.68, 0.20), Vector3(-0.12, 0.34, 0), Color("#2c3858")],
		[Vector3(0.20, 0.68, 0.20), Vector3(0.12, 0.34, 0), Color("#2c3858")],
		[Vector3(0.18, 0.66, 0.18), Vector3(-0.33, 1.02, 0), Color("#34689a")],
		[Vector3(0.18, 0.66, 0.18), Vector3(0.33, 1.02, 0), Color("#34689a")],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[0]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = p[2]
		mat.roughness = 0.85
		bm.material = mat
		mi.mesh = bm
		mi.position = p[1]
		root.add_child(mi)
	return root

func _build_wire_box() -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.08, 0.08, 0.10, 0.9)
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var m := -0.003
	var M := 1.003
	var corners := [
		Vector3(m, m, m), Vector3(M, m, m), Vector3(M, m, M), Vector3(m, m, M),
		Vector3(m, M, m), Vector3(M, M, m), Vector3(M, M, M), Vector3(m, M, M)
	]
	var edges := [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]
	for e in edges:
		im.surface_add_vertex(corners[e[0]])
		im.surface_add_vertex(corners[e[1]])
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	return mi

func _on_settings_changed() -> void:
	if cam != null:
		cam.fov = Settings.fov
	_refresh_hand_visual()

func give_starter_kit() -> void:
	add_item(Registry.id_of("wooden_pickaxe"), 1)
	add_item(Registry.id_of("wooden_axe"), 1)
	add_item(Registry.id_of("wooden_sword"), 1)
	add_item(Registry.id_of("torch"), 8)
	add_item(Registry.id_of("bread"), 5)
	_refresh_hand_visual()

func held_slot() -> Dictionary:
	return inv[hotbar_idx]

func held_item_id() -> int:
	return inv[hotbar_idx]["id"]

func select_hotbar(idx: int) -> void:
	hotbar_idx = posmod(idx, 9)
	mine_progress = 0.0
	_refresh_hand_visual()
	inventory_changed.emit()

func _refresh_hand_visual() -> void:
	if hand_sprite == null:
		return
	var id := held_item_id()
	if id <= 0:
		hand_sprite.visible = false
		hand_block_mesh.visible = false
		hand_arm_mesh.visible = true
	elif id < B.COUNT and Registry.b_render[id] in [B.R_CUBE, B.R_CUTOUT]:
		hand_sprite.visible = false
		hand_arm_mesh.visible = false
		hand_block_mesh.visible = true
		var front_l: int = Registry.b_front[id] if Registry.b_front[id] >= 0 else Registry.b_tex[id][4]
		hand_block_mat.albedo_texture = ImageTexture.create_from_image(Registry.layer_images[front_l])
	else:
		hand_arm_mesh.visible = false
		hand_block_mesh.visible = false
		hand_sprite.visible = true
		var flat_img: Image = Registry.icon_images.get(id)
		hand_sprite.texture = ImageTexture.create_from_image(flat_img) if flat_img != null else Registry.icon(id)

func add_item(id: int, count: int, dur: int = -1) -> int:
	if id <= 0 or count <= 0:
		return 0
	var max_s := Registry.max_stack(id)
	if dur < 0:
		dur = Registry.item(id).get("durability", 0)
	var rem := count
	# 1. Stack onto existing matching slots
	if max_s > 1:
		for i in 36:
			if inv[i]["id"] == id and inv[i]["count"] < max_s:
				var take := mini(rem, max_s - inv[i]["count"])
				inv[i]["count"] += take
				rem -= take
				if rem <= 0:
					_refresh_hand_visual()
					inventory_changed.emit()
					return 0
	# 2. Fill empty slots
	for i in 36:
		if inv[i]["id"] == 0 or inv[i]["count"] <= 0:
			var take2 := mini(rem, max_s)
			inv[i] = {"id": id, "count": take2, "dur": dur}
			rem -= take2
			if rem <= 0:
				_refresh_hand_visual()
				inventory_changed.emit()
				return 0
	_refresh_hand_visual()
	inventory_changed.emit()
	return rem

func consume_held_item(amount: int = 1) -> void:
	if game_mode == 1:
		return
	var s: Dictionary = inv[hotbar_idx]
	if s["id"] <= 0:
		return
	s["count"] -= amount
	if s["count"] <= 0:
		inv[hotbar_idx] = {"id": 0, "count": 0, "dur": 0}
	_refresh_hand_visual()
	inventory_changed.emit()

func damage_held_item(amount: int = 1) -> void:
	if game_mode == 1:
		return
	var s: Dictionary = inv[hotbar_idx]
	if s["id"] <= 0 or s["dur"] <= 0:
		return
	s["dur"] -= amount
	if s["dur"] <= 0:
		inv[hotbar_idx] = {"id": 0, "count": 0, "dur": 0}
		Sfx.play_ui("mat_wood", 0.7)
	_refresh_hand_visual()
	inventory_changed.emit()

func drop_held_item(all_stack: bool = false) -> void:
	var s: Dictionary = inv[hotbar_idx]
	if s["id"] <= 0 or s["count"] <= 0:
		return
	var qty: int = s["count"] if all_stack else 1
	var look_dir := -cam.global_transform.basis.z
	world.spawn_drop(global_position + Vector3(0, 1.35, 0) + look_dir * 0.4, s["id"], qty, s["dur"], look_dir * 5.5 + Vector3(0, 2.0, 0))
	s["count"] -= qty
	if s["count"] <= 0:
		inv[hotbar_idx] = {"id": 0, "count": 0, "dur": 0}
	_refresh_hand_visual()
	inventory_changed.emit()

func total_armor_points() -> int:
	var pts := 0
	for i in 4:
		if armor[i]["id"] > 0:
			pts += Registry.item(armor[i]["id"]).get("armor", 0)
	return pts

func rotate_look(dx: float, dy: float) -> void:
	var sens := Settings.mouse_sensitivity * 0.0045
	yaw -= dx * sens
	var y_sign := 1.0 if Settings.invert_y else -1.0
	pitch = clampf(pitch + dy * sens * y_sign, -1.52, 1.52)
	rotation.y = yaw
	head_pivot.rotation.x = pitch

func toggle_perspective() -> void:
	third_person = not third_person
	body_mesh.visible = third_person or not is_local
	hand_pivot.visible = not third_person
	cam.position = Vector3(0, 0.35, 3.4) if third_person else Vector3.ZERO

func _physics_process(delta: float) -> void:
	if not is_local or world == null or is_dead:
		return
	if not world.is_chunk_loaded_at(global_position):
		return

	_handle_movement(delta)
	_handle_survival(delta)
	_update_raycast()
	_handle_actions(delta)
	_update_hand_anim(delta)

func _handle_movement(delta: float) -> void:
	var ui_open: bool = world.ui_blocking_input()
	var in_vec := Vector2.ZERO
	if not ui_open:
		in_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var sneak := not ui_open and Input.is_action_pressed("sneak")
	var sprint := not ui_open and Input.is_action_pressed("sprint") and in_vec.y < -0.1 and hunger > 6.0 and not sneak
	var jump := not ui_open and Input.is_action_pressed("jump")

	# Check fluid & ladder state
	var foot_b: int = world.get_block(int(floor(global_position.x)), int(floor(global_position.y + 0.2)), int(floor(global_position.z)))
	var mid_b: int = world.get_block(int(floor(global_position.x)), int(floor(global_position.y + 0.9)), int(floor(global_position.z)))
	var eye_b: int = world.get_block(int(floor(global_position.x)), int(floor(global_position.y + EYE_H)), int(floor(global_position.z)))
	in_water = (foot_b == B.WATER or mid_b == B.WATER)
	head_underwater = (eye_b == B.WATER)
	in_lava = (foot_b == B.LAVA or mid_b == B.LAVA)
	on_ladder = (foot_b == B.LADDER or mid_b == B.LADDER)

	var forward := -transform.basis.z
	var right := transform.basis.x
	var wish_dir := (forward * -in_vec.y + right * in_vec.x)
	if wish_dir.length_squared() > 1.0:
		wish_dir = wish_dir.normalized()

	var spd := 4.4
	if sprint:
		spd = 6.2
	elif sneak:
		spd = 2.1
	if in_water:
		spd *= 0.68

	var accel := 14.0 if on_ground else 6.0
	velocity.x = lerpf(velocity.x, wish_dir.x * spd, accel * delta)
	velocity.z = lerpf(velocity.z, wish_dir.z * spd, accel * delta)

	if on_ladder:
		velocity.y = 4.2 if jump else (-3.2 if sneak else (2.8 if in_vec.length() > 0.1 else 0.0))
		fall_peak_y = global_position.y
	elif in_water or in_lava:
		fall_peak_y = global_position.y
		if jump:
			velocity.y = lerpf(velocity.y, 3.8, 8.0 * delta)
		elif sneak:
			velocity.y = lerpf(velocity.y, -3.2, 8.0 * delta)
		else:
			velocity.y = lerpf(velocity.y, -1.4, 5.0 * delta)
	else:
		velocity.y = maxf(velocity.y - 26.0 * delta, -46.0)
		if on_ground and jump:
			velocity.y = 8.4
			on_ground = false
			if sprint:
				hunger = maxf(0.0, hunger - 0.08)

	# Swept axis-by-axis collision with sneak edge-guard
	var pos := global_position

	# X movement
	var nx := pos.x + velocity.x * delta
	if sneak and on_ground and not _has_ground_below(Vector3(nx, pos.y, pos.z)):
		velocity.x = 0.0
	elif _collides_player(Vector3(nx, pos.y, pos.z)):
		velocity.x = 0.0
	else:
		pos.x = nx

	# Z movement
	var nz := pos.z + velocity.z * delta
	if sneak and on_ground and not _has_ground_below(Vector3(pos.x, pos.y, nz)):
		velocity.z = 0.0
	elif _collides_player(Vector3(pos.x, pos.y, nz)):
		velocity.z = 0.0
	else:
		pos.z = nz

	# Y movement
	var ny := pos.y + velocity.y * delta
	if _collides_player(Vector3(pos.x, ny, pos.z)):
		if velocity.y < 0.0:
			# Landed on ground: check fall damage
			var fell := fall_peak_y - pos.y
			if fell > 3.6 and not in_water and game_mode == 0:
				var dmg := (fell - 3.3) * 1.15
				take_damage(dmg, "fall")
			on_ground = true
			fall_peak_y = pos.y
		velocity.y = 0.0
	else:
		if velocity.y < 0.0:
			fall_peak_y = maxf(fall_peak_y, pos.y)
		else:
			fall_peak_y = ny
		on_ground = false
		pos.y = ny

	var moved_dist := Vector2(pos.x - global_position.x, pos.z - global_position.z).length()
	global_position = pos

	# Camera eye height & view bobbing
	var target_eye := SNEAK_EYE_H if sneak else EYE_H
	if Settings.view_bobbing and on_ground and moved_dist > 0.001 and not third_person:
		bob_phase += moved_dist * 3.4
		target_eye += sin(bob_phase * 2.0) * 0.045
		head_pivot.position.x = cos(bob_phase) * 0.03
	else:
		head_pivot.position.x = lerpf(head_pivot.position.x, 0.0, 10.0 * delta)
	head_pivot.position.y = lerpf(head_pivot.position.y, target_eye, 12.0 * delta)
	cam.fov = lerpf(cam.fov, Settings.fov + (6.5 if sprint else 0.0), 8.0 * delta)

	# Footstep audio
	if on_ground and moved_dist > 0.001:
		step_accum += moved_dist
		if step_accum >= (1.65 if not sneak else 2.4):
			step_accum = 0.0
			var ground_id: int = world.get_block(int(floor(pos.x)), int(floor(pos.y - 0.15)), int(floor(pos.z)))
			if ground_id > 0:
				Sfx.play_block(ground_id, pos, "step")

	if sprint and moved_dist > 0.001 and game_mode == 0:
		_consume_energy(moved_dist * 0.018)

func _has_ground_below(pos: Vector3) -> bool:
	var y_check := int(floor(pos.y - 0.15))
	for ox in [-HALF_W * 0.8, HALF_W * 0.8]:
		for oz in [-HALF_W * 0.8, HALF_W * 0.8]:
			if world.is_solid_at(int(floor(pos.x + ox)), y_check, int(floor(pos.z + oz))):
				return true
	return false

func _collides_player(pos: Vector3) -> bool:
	var p_aabb := AABB(pos - Vector3(HALF_W, 0.0, HALF_W), Vector3(HALF_W * 2.0, HEIGHT, HALF_W * 2.0))
	var x0 := int(floor(p_aabb.position.x))
	var x1 := int(floor(p_aabb.end.x))
	var y0 := int(floor(p_aabb.position.y + 0.01))
	var y1 := int(floor(p_aabb.end.y - 0.01))
	var z0 := int(floor(p_aabb.position.z))
	var z1 := int(floor(p_aabb.end.z))
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				for b_box in world.get_block_boxes(x, y, z):
					if p_aabb.intersects(b_box):
						return true
	return false

func _consume_energy(amount: float) -> void:
	if saturation > 0.0:
		saturation = maxf(0.0, saturation - amount)
	else:
		hunger = maxf(0.0, hunger - amount)
	stats_changed.emit()

func _handle_survival(delta: float) -> void:
	if game_mode == 1:
		hp = max_hp
		hunger = max_hunger
		oxygen = max_oxygen
		return

	# Oxygen & drowning
	if head_underwater:
		oxygen = maxf(0.0, oxygen - delta * 0.85)
		if oxygen <= 0.0:
			regen_timer += delta
			if regen_timer >= 1.0:
				regen_timer = 0.0
				take_damage(2.0, "drown")
	else:
		oxygen = minf(max_oxygen, oxygen + delta * 3.0)

	# Environmental hazards: lava, fire, cactus, void
	if in_lava:
		take_damage(4.0 * delta, "lava")
	var foot_id: int = world.get_block(int(floor(global_position.x)), int(floor(global_position.y + 0.1)), int(floor(global_position.z)))
	if foot_id == B.FIRE:
		take_damage(2.0 * delta, "fire")
	if global_position.y < -12.0:
		take_damage(10.0 * delta, "void")

	# Natural regeneration & starvation
	regen_timer += delta
	if regen_timer >= 2.2:
		regen_timer = 0.0
		if hunger >= 16.5 and hp < max_hp:
			hp = minf(max_hp, hp + 1.0)
			_consume_energy(0.6)
		elif hunger <= 0.0 and hp > 1.0:
			take_damage(1.0, "starve")
		stats_changed.emit()

func take_damage(amount: float, _source: String = "", knockback: Vector3 = Vector3.ZERO) -> void:
	if is_dead or game_mode == 1 or amount <= 0.0:
		return
	var reduction := float(total_armor_points()) * 0.04 # Up to 80% with 20 armor points
	var final_dmg := maxf(0.2, amount * (1.0 - reduction))
	hp = maxf(0.0, hp - final_dmg)
	velocity += knockback
	if amount >= 0.8:
		Sfx.play_ui("hurt", randf_range(0.92, 1.08), -2.0)
		# Damage armor durability
		for i in 4:
			if armor[i]["id"] > 0 and armor[i]["dur"] > 0:
				armor[i]["dur"] -= 1
				if armor[i]["dur"] <= 0:
					armor[i] = {"id": 0, "count": 0, "dur": 0}
	stats_changed.emit()
	if hp <= 0.0:
		is_dead = true
		select_box.visible = false
		crack_box.visible = false
		died.emit()

func respawn() -> void:
	is_dead = false
	hp = max_hp
	hunger = max_hunger
	saturation = 8.0
	oxygen = max_oxygen
	velocity = Vector3.ZERO
	if has_custom_spawn:
		global_position = spawn_point
	else:
		global_position = world.find_safe_spawn()
	fall_peak_y = global_position.y
	stats_changed.emit()

func _update_raycast() -> void:
	var origin := head_pivot.global_position
	var dir := -cam.global_transform.basis.z
	look_hit = world.raycast_voxel(origin, dir, 5.5)

	# Also check if a mob is closer than the block hit
	var best_mob: VoxelMob = null
	var best_t := float(look_hit.get("dist", 5.5))
	best_t = minf(best_t, 3.8)
	for m in world.mobs_root.get_children():
		if m is VoxelMob:
			var m_center: Vector3 = m.global_position + Vector3(0, float(m.def.get("h", 1.2)) * 0.5, 0)
			var to_m: Vector3 = m_center - origin
			var proj: float = to_m.dot(dir)
			if proj > 0.0 and proj < best_t:
				var perp: float = (to_m - dir * proj).length()
				if perp < float(m.def.get("w", 0.7)) * 0.75:
					best_t = proj
					best_mob = m
	look_hit["mob"] = best_mob

	if look_hit.get("hit", false) and best_mob == null:
		var bp: Vector3i = look_hit["block_pos"]
		select_box.position = Vector3(bp)
		select_box.visible = true
	else:
		select_box.visible = false
		crack_box.visible = false

func _handle_actions(delta: float) -> void:
	if place_cooldown > 0.0:
		place_cooldown -= delta
	if attack_cooldown > 0.0:
		attack_cooldown -= delta
	if world.ui_blocking_input():
		mine_progress = 0.0
		crack_box.visible = false
		return

	# Middle-click pick block
	if Input.is_action_just_pressed("pick_block") and look_hit.get("hit", false):
		var bp_pick: Vector3i = look_hit["block_pos"]
		var bid: int = world.get_block(bp_pick.x, bp_pick.y, bp_pick.z)
		var ikey: String = Registry.b_item[bid]
		var iid := Registry.id_of(ikey if ikey != "" else Registry.b_name[bid])
		if iid > 0:
			for i in 9:
				if inv[i]["id"] == iid:
					select_hotbar(i)
					break

	# Left click: attack mob OR mine block
	if Input.is_action_pressed("attack"):
		swing_anim = 1.0
		var mob: VoxelMob = look_hit.get("mob", null)
		if mob != null and is_instance_valid(mob):
			if attack_cooldown <= 0.0:
				attack_cooldown = 0.42
				var dmg: float = Registry.item(held_item_id()).get("damage", 1.0)
				if not on_ground and velocity.y < -0.2:
					dmg *= 1.5 # Critical jump hit!
				var dir := -cam.global_transform.basis.z
				mob.take_damage(dmg, Vector3(dir.x, 0.35, dir.z).normalized() * 6.5, self)
				damage_held_item(1)
				_consume_energy(0.1)
			mine_progress = 0.0
			crack_box.visible = false
		elif look_hit.get("hit", false):
			var bp: Vector3i = look_hit["block_pos"]
			var blk: int = world.get_block(bp.x, bp.y, bp.z)
			if bp != mine_pos:
				mine_pos = bp
				mine_progress = 0.0
			var btime := 0.08 if game_mode == 1 else Registry.break_time(blk, held_item_id())
			if btime < INF:
				mine_progress += delta / maxf(0.05, btime)
				if int(mine_progress * 10.0) != int((mine_progress - delta / maxf(0.05, btime)) * 10.0):
					Sfx.play_block(blk, Vector3(bp) + Vector3(0.5, 0.5, 0.5), "hit")
					VoxelFX.spawn_block_particles(world, Vector3(bp) + Vector3(0.5, 0.5, 0.5), blk, 3)
				var stage := clampi(int(mine_progress * 10.0), 0, 9)
				crack_mat.albedo_texture = ImageTexture.create_from_image(Registry.layer_images[Registry.destroy_layer0 + stage])
				crack_box.position = Vector3(bp) + Vector3(0.5, 0.5, 0.5)
				crack_box.visible = true
				if mine_progress >= 1.0:
					world.harvest_block(bp, held_item_id(), game_mode == 0)
					damage_held_item(1)
					_consume_energy(0.025)
					mine_progress = 0.0
					crack_box.visible = false
	else:
		mine_progress = 0.0
		crack_box.visible = false

	# Right click: interact with mob, block station, food, tool, or place block
	if Input.is_action_just_pressed("use") and place_cooldown <= 0.0:
		place_cooldown = 0.18
		_use_action()

func _use_action() -> void:
	var held_id := held_item_id()
	var it := Registry.item(held_id)

	# 1. Mob interaction (feed, breed, tame, shear)
	var mob: VoxelMob = look_hit.get("mob", null)
	if mob != null and is_instance_valid(mob):
		if mob.interact(self, held_id):
			swing_anim = 1.0
			return

	# 2. Block interaction (doors, stations, bedroll, portal crystal)
	if look_hit.get("hit", false):
		var bp: Vector3i = look_hit["block_pos"]
		var target_blk: int = world.get_block(bp.x, bp.y, bp.z)
		if not Input.is_action_pressed("sneak"):
			if target_blk in [B.WORKBENCH, B.FURNACE, B.FURNACE_LIT, B.CHEST]:
				var st_kind := "workbench" if target_blk == B.WORKBENCH else ("chest" if target_blk == B.CHEST else "furnace")
				open_station.emit(st_kind, bp)
				return
			elif target_blk in [B.DOOR_LOWER, B.DOOR_UPPER]:
				world.toggle_door(bp)
				swing_anim = 1.0
				return
			elif target_blk == B.LEVER:
				world.toggle_lever(bp)
				swing_anim = 1.0
				return
			elif target_blk == B.EXPLOSIVE_BARREL and it.get("kind", "") == "striker":
				world.set_block(bp.x, bp.y, bp.z, B.AIR)
				world.explode(Vector3(bp) + Vector3(0.5, 0.5, 0.5), 4.0, 18.0)
				damage_held_item(1)
				swing_anim = 1.0
				return
			elif target_blk == B.BEDROLL:
				spawn_point = Vector3(bp) + Vector3(0.5, 0.6, 0.5)
				has_custom_spawn = true
				message_shown.emit(Locale.t("ui.spawn_set"))
				if not world.is_daytime():
					world.skip_to_morning()
				return
			elif target_blk == B.LUMINITE_BLOCK and world.has_obsidian_frame(bp):
				world.travel_dimension(1 - world.current_dimension)
				return

	# 3. Consumable food
	if it.has("food") and (hunger < max_hunger or game_mode == 1):
		hunger = minf(max_hunger, hunger + float(it["food"]))
		saturation = minf(hunger, saturation + float(it.get("sat", 2.0)))
		Sfx.play_ui("eat", randf_range(0.95, 1.1))
		var ret: String = it.get("returns", "")
		consume_held_item(1)
		if ret != "":
			add_item(Registry.id_of(ret), 1)
		stats_changed.emit()
		swing_anim = 1.0
		return

	# 4. Special tools: Bow, Fishing Rod, Bucket, Hoe, Ember Striker
	var kind: String = it.get("kind", "")
	if kind == "bow":
		var arrow_id := Registry.id_of("arrow")
		if game_mode == 1 or _consume_item_id(arrow_id, 1):
			var dir := -cam.global_transform.basis.z
			world.spawn_projectile(self, "arrow", head_pivot.global_position + dir * 0.5, dir * 24.0, 7.0)
			Sfx.play_ui("bow")
			damage_held_item(1)
			swing_anim = 1.0
		return
	elif kind == "rod":
		if active_bobber != null and is_instance_valid(active_bobber):
			if active_bobber.has_bite:
				add_item(Registry.id_of("raw_fish"), 1)
				Sfx.play_ui("splash")
				damage_held_item(1)
			active_bobber.queue_free()
			active_bobber = null
		else:
			var dir2 := -cam.global_transform.basis.z
			active_bobber = world.spawn_projectile(self, "bobber", head_pivot.global_position + dir2 * 0.5, dir2 * 13.0 + Vector3(0, 3.0, 0), 0.0)
			Sfx.play_ui("swing")
		swing_anim = 1.0
		return

	# Bucket scooping liquid
	if Registry.key_of(held_id) == "bucket":
		var lhit: Dictionary = world.raycast_voxel(head_pivot.global_position, -cam.global_transform.basis.z, 5.0, true)
		if lhit.get("hit", false):
			var lpos: Vector3i = lhit["block_pos"]
			var lid: int = world.get_block(lpos.x, lpos.y, lpos.z)
			if lid == B.WATER or lid == B.LAVA:
				world.set_block(lpos.x, lpos.y, lpos.z, B.AIR)
				consume_held_item(1)
				add_item(Registry.id_of("water_bucket" if lid == B.WATER else "lava_bucket"), 1)
				Sfx.play_ui("splash")
				swing_anim = 1.0
				return

	if not look_hit.get("hit", false):
		return

	var bp2: Vector3i = look_hit["block_pos"]
	var pp: Vector3i = look_hit["place_pos"]
	var target_id: int = world.get_block(bp2.x, bp2.y, bp2.z)

	# Hoe tilling dirt/grass into farmland
	if it.get("tool", 0) == B.T_HOE and target_id in [B.DIRT, B.GRASS, B.SNOW_GRASS]:
		world.set_block(bp2.x, bp2.y, bp2.z, B.FARMLAND)
		Sfx.play_block(B.DIRT, Vector3(bp2) + Vector3(0.5, 0.5, 0.5), "place")
		damage_held_item(1)
		swing_anim = 1.0
		return

	# Ember Striker: light fire or activate Obsidian Portal to Umbra!
	if kind == "striker":
		if target_id == B.OBSIDIAN and world.has_obsidian_frame(bp2):
			Sfx.play_ui("portal")
			world.travel_dimension(1 - world.current_dimension)
			return
		if world.get_block(pp.x, pp.y, pp.z) == B.AIR:
			world.set_block(pp.x, pp.y, pp.z, B.FIRE)
			Sfx.play_block(B.FIRE, Vector3(pp), "place")
			damage_held_item(1)
			swing_anim = 1.0
		return

	# 5. Block placement
	if it.has("place"):
		var place_id: int = it["place"]
		if world.try_place_block(pp, bp2, look_hit["normal"], place_id, self):
			var ret_b: String = it.get("returns", "")
			consume_held_item(1)
			if ret_b != "":
				add_item(Registry.id_of(ret_b), 1)
			swing_anim = 1.0

func _consume_item_id(target_id: int, count: int) -> bool:
	for i in 36:
		if inv[i]["id"] == target_id and inv[i]["count"] >= count:
			inv[i]["count"] -= count
			if inv[i]["count"] <= 0:
				inv[i] = {"id": 0, "count": 0, "dur": 0}
			inventory_changed.emit()
			return true
	return false

func _update_hand_anim(delta: float) -> void:
	if swing_anim > 0.0:
		swing_anim = maxf(0.0, swing_anim - delta * 4.5)
		var s := sin(swing_anim * PI)
		hand_pivot.position = Vector3(0.42 - s * 0.16, -0.34 + s * 0.08, -0.52 - s * 0.14)
		hand_pivot.rotation_degrees = Vector3(-s * 48.0, -s * 22.0, s * 18.0)
	else:
		hand_pivot.position = hand_pivot.position.lerp(Vector3(0.42, -0.34, -0.52), 12.0 * delta)
		hand_pivot.rotation_degrees = hand_pivot.rotation_degrees.lerp(Vector3.ZERO, 12.0 * delta)

func serialize_state() -> Dictionary:
	return {
		"pos": global_position,
		"yaw": yaw,
		"pitch": pitch,
		"hp": hp,
		"hunger": hunger,
		"sat": saturation,
		"inv": inv,
		"armor": armor,
		"hotbar": hotbar_idx,
		"spawn": spawn_point,
		"has_spawn": has_custom_spawn,
	}

func deserialize_state(d: Dictionary) -> void:
	if d.has("pos"): global_position = d["pos"]
	if d.has("yaw"): yaw = d["yaw"]; rotation.y = yaw
	if d.has("pitch"): pitch = d["pitch"]; head_pivot.rotation.x = pitch
	hp = d.get("hp", 20.0)
	hunger = d.get("hunger", 20.0)
	saturation = d.get("sat", 8.0)
	if d.has("inv") and d["inv"].size() == 36: inv = d["inv"]
	if d.has("armor") and d["armor"].size() == 4: armor = d["armor"]
	hotbar_idx = d.get("hotbar", 0)
	spawn_point = d.get("spawn", global_position)
	has_custom_spawn = d.get("has_spawn", false)
	fall_peak_y = global_position.y
	_refresh_hand_visual()
	stats_changed.emit()
	inventory_changed.emit()
