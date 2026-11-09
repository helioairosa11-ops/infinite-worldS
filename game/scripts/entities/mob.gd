class_name VoxelMob
extends Node3D
## Complete articulated 3D voxel creature with custom multi-part model, animations,
## AI state machine, ecosystem behaviors (grazing, breeding, taming, hunting),
## voxel AABB physics/navigation, combat, sounds, and drops.

const DEFS := {
	"cow": {"hp": 12.0, "speed": 2.2, "hostile": false, "w": 0.85, "h": 1.35, "snd": "mob_cow", "food": "wheat", "drops": [["raw_steak", 1, 3], ["leather", 0, 2]]},
	"sheep": {"hp": 10.0, "speed": 2.3, "hostile": false, "w": 0.8, "h": 1.25, "snd": "mob_sheep", "food": "wheat", "drops": [["wool_white", 1, 1], ["raw_steak", 1, 2]]},
	"pig": {"hp": 10.0, "speed": 2.4, "hostile": false, "w": 0.75, "h": 0.95, "snd": "mob_pig", "food": "wheat", "drops": [["raw_pork", 1, 3]]},
	"chicken": {"hp": 5.0, "speed": 2.6, "hostile": false, "w": 0.45, "h": 0.65, "snd": "mob_chicken", "food": "seeds", "drops": [["raw_fowl", 1, 1], ["feather", 1, 2]]},
	"frost_hare": {"hp": 6.0, "speed": 3.8, "hostile": false, "w": 0.45, "h": 0.55, "snd": "mob_chicken", "food": "wheat", "drops": [["raw_hare", 1, 1], ["leather", 0, 1]]},
	"fish": {"hp": 4.0, "speed": 2.8, "hostile": false, "aquatic": true, "w": 0.4, "h": 0.35, "snd": "splash", "drops": [["raw_fish", 1, 1]]},
	"wolf": {"hp": 16.0, "speed": 3.8, "hostile": false, "neutral": true, "dmg": 3.5, "w": 0.65, "h": 0.85, "snd": "mob_wolf", "food": "raw_steak", "drops": [["leather", 1, 1]]},
	"zombie": {"hp": 20.0, "speed": 2.7, "hostile": true, "dmg": 3.5, "burns": true, "w": 0.65, "h": 1.8, "snd": "mob_zombie", "drops": [["hollow_flesh", 1, 2], ["iron_ingot", 0, 1]]},
	"skeleton": {"hp": 18.0, "speed": 2.8, "hostile": true, "ranged": true, "dmg": 3.0, "burns": true, "w": 0.6, "h": 1.8, "snd": "mob_skeleton", "drops": [["bone", 1, 2], ["arrow", 1, 3]]},
	"spider": {"hp": 16.0, "speed": 3.9, "hostile": true, "climbs": true, "dmg": 2.5, "w": 1.1, "h": 0.75, "snd": "mob_spider", "drops": [["string", 1, 2]]},
	"creeper": {"hp": 20.0, "speed": 2.6, "hostile": true, "explodes": true, "dmg": 14.0, "w": 0.65, "h": 1.65, "snd": "mob_creeper", "drops": [["ember_dust", 1, 2]]},
	"wraith": {"hp": 18.0, "speed": 4.2, "hostile": true, "flies": true, "dmg": 4.0, "burns": true, "w": 0.7, "h": 1.2, "snd": "mob_boss", "drops": [["luminite_shard", 1, 2]]},
	"crystal_colossus": {"hp": 120.0, "speed": 2.4, "hostile": true, "boss": true, "dmg": 7.0, "w": 1.4, "h": 2.8, "snd": "mob_boss", "drops": [["diamond", 3, 5], ["luminite_block", 2, 4], ["gold_ingot", 3, 6]]},
}

var world: Node
var mob_type: String = "cow"
var def: Dictionary
var hp: float = 10.0
var max_hp: float = 10.0
var velocity: Vector3 = Vector3.ZERO
var on_ground: bool = false
var in_water: bool = false

# AI & Ecosystem state
var state: String = "idle"
var state_timer: float = 2.0
var move_dir: Vector3 = Vector3.ZERO
var target: Node3D = null
var tamed: bool = false
var sheared: bool = false
var love_timer: float = 0.0
var breed_cooldown: float = 0.0
var egg_timer: float = 45.0
var attack_cd: float = 0.0
var fuse_time: float = 0.0
var hurt_flash: float = 0.0
var anim_phase: float = 0.0
var snd_timer: float = 5.0

# Articulated body parts
var rig: Node3D
var head_node: Node3D
var body_node: Node3D
var coat_node: Node3D
var limbs: Array[Node3D] = []
var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []

func setup(p_world: Node, p_type: String) -> void:
	world = p_world
	mob_type = p_type
	def = DEFS.get(p_type, DEFS["cow"])
	max_hp = def["hp"]
	hp = max_hp
	snd_timer = randf_range(4.0, 12.0)
	egg_timer = randf_range(35.0, 75.0)
	_build_model()

func _part(parent: Node3D, sz: Vector3, pos: Vector3, col: Color, pivot_offset: Vector3 = Vector3.ZERO, emissive: bool = false) -> Node3D:
	var piv := Node3D.new()
	piv.position = pos
	parent.add_child(piv)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.88
	if emissive:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 1.8
	bm.material = mat
	mi.mesh = bm
	mi.position = pivot_offset
	piv.add_child(mi)
	_materials.append(mat)
	_base_colors.append(col)
	return piv

func _build_model() -> void:
	rig = Node3D.new()
	add_child(rig)
	match mob_type:
		"cow", "sheep", "pig":
			var body_col := Color("#5c3c24") if mob_type == "cow" else (Color("#ececec") if mob_type == "sheep" else Color("#ebb0b6"))
			var head_col := Color("#4a301d") if mob_type == "cow" else (Color("#cabfa8") if mob_type == "sheep" else Color("#ebb0b6"))
			var leg_h := 0.42 if mob_type != "pig" else 0.28
			var body_sz := Vector3(0.68, 0.55, 0.98) if mob_type != "pig" else Vector3(0.62, 0.48, 0.86)
			body_node = _part(rig, body_sz, Vector3(0, leg_h + body_sz.y * 0.5, 0), body_col)
			if mob_type == "sheep":
				coat_node = _part(body_node, body_sz * 1.12, Vector3.ZERO, Color("#f4f6f6"))
			elif mob_type == "cow":
				_part(body_node, Vector3(0.70, 0.28, 0.35), Vector3(0, 0.08, 0.1), Color("#e8e4dc"))
			head_node = _part(rig, Vector3(0.44, 0.42, 0.44), Vector3(0, leg_h + body_sz.y * 0.78, -body_sz.z * 0.58), head_col)
			# Eyes & features
			_part(head_node, Vector3(0.08, 0.08, 0.05), Vector3(-0.14, 0.05, -0.22), Color("#18181c"))
			_part(head_node, Vector3(0.08, 0.08, 0.05), Vector3(0.14, 0.05, -0.22), Color("#18181c"))
			if mob_type == "cow":
				_part(head_node, Vector3(0.08, 0.18, 0.08), Vector3(-0.24, 0.2, -0.05), Color("#d8d0bc"))
				_part(head_node, Vector3(0.08, 0.18, 0.08), Vector3(0.24, 0.2, -0.05), Color("#d8d0bc"))
			elif mob_type == "pig":
				_part(head_node, Vector3(0.22, 0.14, 0.10), Vector3(0, -0.06, -0.24), Color("#d88a92"))
			for lx in [-0.22, 0.22]:
				for lz in [-0.32, 0.32]:
					limbs.append(_part(rig, Vector3(0.2, leg_h, 0.2), Vector3(lx, leg_h, lz), head_col, Vector3(0, -leg_h * 0.5, 0)))

		"chicken":
			body_node = _part(rig, Vector3(0.36, 0.32, 0.46), Vector3(0, 0.34, 0), Color("#f2f2f6"))
			head_node = _part(rig, Vector3(0.24, 0.28, 0.24), Vector3(0, 0.54, -0.22), Color("#f2f2f6"))
			_part(head_node, Vector3(0.12, 0.08, 0.14), Vector3(0, 0.0, -0.16), Color("#e6a825"))
			_part(head_node, Vector3(0.08, 0.10, 0.08), Vector3(0, -0.10, -0.12), Color("#d22b2b"))
			limbs.append(_part(rig, Vector3(0.08, 0.20, 0.08), Vector3(-0.1, 0.20, 0), Color("#e6a825"), Vector3(0, -0.10, 0)))
			limbs.append(_part(rig, Vector3(0.08, 0.20, 0.08), Vector3(0.1, 0.20, 0), Color("#e6a825"), Vector3(0, -0.10, 0)))

		"frost_hare":
			body_node = _part(rig, Vector3(0.34, 0.28, 0.44), Vector3(0, 0.26, 0), Color("#e6eef6"))
			head_node = _part(rig, Vector3(0.24, 0.22, 0.24), Vector3(0, 0.40, -0.22), Color("#f0f6fc"))
			_part(head_node, Vector3(0.06, 0.22, 0.06), Vector3(-0.07, 0.18, 0.02), Color("#d8e4f0"))
			_part(head_node, Vector3(0.06, 0.22, 0.06), Vector3(0.07, 0.18, 0.02), Color("#d8e4f0"))
			for lx in [-0.12, 0.12]:
				for lz in [-0.14, 0.14]:
					limbs.append(_part(rig, Vector3(0.1, 0.16, 0.12), Vector3(lx, 0.16, lz), Color("#dce6f0"), Vector3(0, -0.08, 0)))

		"fish":
			body_node = _part(rig, Vector3(0.18, 0.24, 0.46), Vector3(0, 0.22, 0), Color("#4a90c8"))
			head_node = _part(rig, Vector3(0.14, 0.18, 0.16), Vector3(0, 0.22, -0.26), Color("#6ab0e2"))
			limbs.append(_part(rig, Vector3(0.04, 0.22, 0.20), Vector3(0, 0.22, 0.28), Color("#8ac8f2")))

		"wolf":
			body_node = _part(rig, Vector3(0.46, 0.42, 0.78), Vector3(0, 0.52, 0), Color("#8c8e94"))
			coat_node = _part(body_node, Vector3(0.50, 0.44, 0.26), Vector3(0, 0.02, -0.24), Color("#a8aaae"))
			head_node = _part(rig, Vector3(0.36, 0.34, 0.36), Vector3(0, 0.62, -0.48), Color("#989aa0"))
			_part(head_node, Vector3(0.18, 0.14, 0.20), Vector3(0, -0.06, -0.22), Color("#b4b6bc"))
			_part(head_node, Vector3(0.08, 0.12, 0.06), Vector3(-0.12, 0.20, 0.0), Color("#6c6e74"))
			_part(head_node, Vector3(0.08, 0.12, 0.06), Vector3(0.12, 0.20, 0.0), Color("#6c6e74"))
			for lx in [-0.15, 0.15]:
				for lz in [-0.26, 0.26]:
					limbs.append(_part(rig, Vector3(0.14, 0.34, 0.14), Vector3(lx, 0.34, lz), Color("#7a7c82"), Vector3(0, -0.17, 0)))

		"zombie", "skeleton":
			var skin := Color("#4f7a44") if mob_type == "zombie" else Color("#dcd8cc")
			var shirt := Color("#355c7d") if mob_type == "zombie" else Color("#c8c2b4")
			var pants := Color("#2f3659") if mob_type == "zombie" else Color("#b8b2a4")
			var w := 0.22 if mob_type == "zombie" else 0.14
			body_node = _part(rig, Vector3(0.48, 0.68, 0.26), Vector3(0, 1.02, 0), shirt)
			head_node = _part(rig, Vector3(0.46, 0.46, 0.46), Vector3(0, 1.59, 0), skin)
			_part(head_node, Vector3(0.10, 0.08, 0.04), Vector3(-0.11, 0.02, -0.23), Color("#141416"))
			_part(head_node, Vector3(0.10, 0.08, 0.04), Vector3(0.11, 0.02, -0.23), Color("#141416"))
			limbs.append(_part(rig, Vector3(w, 0.68, w), Vector3(-0.13, 0.68, 0), pants, Vector3(0, -0.34, 0)))
			limbs.append(_part(rig, Vector3(w, 0.68, w), Vector3(0.13, 0.68, 0), pants, Vector3(0, -0.34, 0)))
			var arm_l := _part(rig, Vector3(w, 0.66, w), Vector3(-0.35, 1.32, 0), skin, Vector3(0, -0.30, 0))
			var arm_r := _part(rig, Vector3(w, 0.66, w), Vector3(0.35, 1.32, 0), skin, Vector3(0, -0.30, 0))
			arm_l.rotation.x = 1.35
			arm_r.rotation.x = 1.35
			limbs.append(arm_l); limbs.append(arm_r)

		"spider":
			body_node = _part(rig, Vector3(0.55, 0.40, 0.85), Vector3(0, 0.36, 0.15), Color("#262228"))
			head_node = _part(rig, Vector3(0.42, 0.34, 0.40), Vector3(0, 0.36, -0.38), Color("#322c35"))
			_part(head_node, Vector3(0.10, 0.08, 0.04), Vector3(-0.11, 0.04, -0.20), Color("#e62222"), Vector3.ZERO, true)
			_part(head_node, Vector3(0.10, 0.08, 0.04), Vector3(0.11, 0.04, -0.20), Color("#e62222"), Vector3.ZERO, true)
			for side in [-1.0, 1.0]:
				for z_i in [-0.25, -0.05, 0.15, 0.35]:
					var leg := _part(rig, Vector3(0.52 * side, 0.10, 0.10), Vector3(0.22 * side, 0.32, z_i), Color("#1e1a20"), Vector3(0.24 * side, -0.06, 0))
					limbs.append(leg)

		"creeper":
			body_node = _part(rig, Vector3(0.46, 0.76, 0.28), Vector3(0, 0.82, 0), Color("#4a8c3c"))
			head_node = _part(rig, Vector3(0.46, 0.46, 0.46), Vector3(0, 1.43, 0), Color("#58a046"))
			_part(head_node, Vector3(0.10, 0.10, 0.04), Vector3(-0.11, 0.06, -0.23), Color("#141812"))
			_part(head_node, Vector3(0.10, 0.10, 0.04), Vector3(0.11, 0.06, -0.23), Color("#141812"))
			_part(head_node, Vector3(0.18, 0.14, 0.04), Vector3(0, -0.10, -0.23), Color("#ff6a18"), Vector3.ZERO, true)
			for lx in [-0.15, 0.15]:
				for lz in [-0.18, 0.18]:
					limbs.append(_part(rig, Vector3(0.20, 0.44, 0.20), Vector3(lx, 0.44, lz), Color("#3d7631"), Vector3(0, -0.22, 0)))

		"wraith":
			body_node = _part(rig, Vector3(0.50, 0.85, 0.30), Vector3(0, 1.1, 0), Color("#261a3d"))
			head_node = _part(rig, Vector3(0.42, 0.42, 0.42), Vector3(0, 1.68, 0), Color("#38265a"))
			_part(head_node, Vector3(0.12, 0.08, 0.04), Vector3(-0.10, 0.02, -0.21), Color("#c396ff"), Vector3.ZERO, true)
			_part(head_node, Vector3(0.12, 0.08, 0.04), Vector3(0.10, 0.02, -0.21), Color("#c396ff"), Vector3.ZERO, true)
			limbs.append(_part(rig, Vector3(0.55, 0.12, 0.35), Vector3(-0.35, 1.35, 0), Color("#4a3275"), Vector3(-0.25, 0, 0)))
			limbs.append(_part(rig, Vector3(0.55, 0.12, 0.35), Vector3(0.35, 1.35, 0), Color("#4a3275"), Vector3(0.25, 0, 0)))

		"crystal_colossus":
			body_node = _part(rig, Vector3(1.25, 1.35, 0.72), Vector3(0, 1.65, 0), Color("#383a46"))
			_part(body_node, Vector3(0.52, 0.52, 0.78), Vector3(0, 0.10, 0), Color("#a57cf8"), Vector3.ZERO, true)
			head_node = _part(rig, Vector3(0.68, 0.68, 0.68), Vector3(0, 2.62, 0), Color("#474a58"))
			_part(head_node, Vector3(0.46, 0.14, 0.06), Vector3(0, 0.04, -0.34), Color("#d8c2ff"), Vector3.ZERO, true)
			limbs.append(_part(rig, Vector3(0.44, 0.98, 0.44), Vector3(-0.34, 0.98, 0), Color("#2e303a"), Vector3(0, -0.49, 0)))
			limbs.append(_part(rig, Vector3(0.44, 0.98, 0.44), Vector3(0.34, 0.98, 0), Color("#2e303a"), Vector3(0, -0.49, 0)))
			limbs.append(_part(rig, Vector3(0.42, 1.45, 0.42), Vector3(-0.86, 2.20, 0), Color("#474a58"), Vector3(0, -0.68, 0)))
			limbs.append(_part(rig, Vector3(0.42, 1.45, 0.42), Vector3(0.86, 2.20, 0), Color("#474a58"), Vector3(0, -0.68, 0)))

func _physics_process(delta: float) -> void:
	if world == null or world.local_player == null:
		return
	var player: Node3D = world.local_player
	var dist_p := global_position.distance_to(player.global_position)
	if dist_p > float(Settings.render_distance * B.CHUNK + 24):
		if not tamed and not def.get("boss", false):
			queue_free()
			return

	# Timers & flash recovery
	if hurt_flash > 0.0:
		hurt_flash = maxf(0.0, hurt_flash - delta)
		if hurt_flash <= 0.0:
			_restore_colors()
	if breed_cooldown > 0.0:
		breed_cooldown -= delta
	if love_timer > 0.0:
		love_timer -= delta
	if attack_cd > 0.0:
		attack_cd -= delta
	snd_timer -= delta
	if snd_timer <= 0.0 and dist_p < 26.0:
		Sfx.play_3d(def.get("snd", "mob_cow"), global_position, -5.0)
		snd_timer = randf_range(6.0, 15.0)

	# Chicken egg laying
	if mob_type == "chicken":
		egg_timer -= delta
		if egg_timer <= 0.0:
			egg_timer = randf_range(45.0, 90.0)
			world.spawn_drop(global_position + Vector3(0, 0.3, 0), Registry.id_of("egg"), 1)
			Sfx.play_3d("mob_chicken", global_position, -3.0)

	# Daylight burning for undead
	if def.get("burns", false) and world.is_daytime() and not in_water:
		var bx := int(floor(global_position.x))
		var by := int(floor(global_position.y + 1.0))
		var bz := int(floor(global_position.z))
		if world.get_skylight(bx, by, bz) >= 13:
			take_damage(1.5 * delta, Vector3.ZERO, null)

	_update_ai(delta, player, dist_p)
	_move_and_collide(delta)
	_animate(delta)

func _update_ai(delta: float, player: Node3D, dist_p: float) -> void:
	var spd: float = def["speed"]

	# Hostile targeting
	if def.get("hostile", false) and not player.is_dead and player.game_mode == 0:
		var aggro_range := 28.0 if def.get("boss", false) else 18.0
		if dist_p < aggro_range:
			target = player
		elif dist_p > aggro_range * 1.4:
			target = null

	# Tamed wolf follows player & attacks threats
	if tamed:
		if target != null and not is_instance_valid(target):
			target = null
		if target == null and dist_p > 4.2:
			var d_p := (player.global_position - global_position)
			d_p.y = 0.0
			move_dir = d_p.normalized()
			if dist_p > 18.0:
				global_position = player.global_position + Vector3(1.5, 0.5, 1.5)
			return

	# Active combat target
	if target != null and is_instance_valid(target):
		var to_t := target.global_position - global_position
		var flat := Vector3(to_t.x, 0.0, to_t.z)
		var d := flat.length()
		var dir := flat.normalized() if d > 0.01 else Vector3.FORWARD

		if def.get("explodes", false):
			if d < 2.8:
				if fuse_time == 0.0:
					Sfx.play_3d("mob_creeper", global_position, 0.0)
				fuse_time += delta
				move_dir = Vector3.ZERO
				var flash := int(fuse_time * 10.0) % 2 == 0
				_tint_all(Color(1.0, 0.9, 0.7) if flash else _base_colors[0])
				rig.scale = Vector3.ONE * (1.0 + fuse_time * 0.16)
				if fuse_time >= 1.5:
					world.explode(global_position + Vector3(0, 0.8, 0), 3.4, def.get("dmg", 14.0))
					queue_free()
				return
			elif fuse_time > 0.0:
				fuse_time = maxf(0.0, fuse_time - delta * 1.5)
				rig.scale = Vector3.ONE
				_restore_colors()

		if def.get("ranged", false):
			move_dir = dir if d > 9.5 else (-dir * 0.5 if d < 5.0 else Vector3(-dir.z, 0, dir.x) * 0.6)
			if head_node != null:
				rig.rotation.y = atan2(-dir.x, -dir.z)
			if d < 16.0 and attack_cd <= 0.0:
				attack_cd = 2.1
				var aim := (target.global_position + Vector3(0, 1.1, 0) - (global_position + Vector3(0, 1.4, 0))).normalized() * 19.0
				aim.y += d * 0.15
				world.spawn_projectile(self, "arrow", global_position + Vector3(0, 1.4, 0) + dir * 0.6, aim, def.get("dmg", 3.0))
				Sfx.play_3d("bow", global_position, -2.0)
			return

		move_dir = dir
		if d < (2.3 if def.get("boss", false) else 1.45) and attack_cd <= 0.0:
			attack_cd = 1.15
			var kb := (dir + Vector3(0, 0.35, 0)).normalized() * (9.0 if def.get("boss", false) else 5.5)
			if target == player:
				player.take_damage(def.get("dmg", 3.0), mob_type, kb)
			elif target.has_method("take_damage"):
				target.take_damage(def.get("dmg", 3.0), kb, self)
			Sfx.play_3d("hit", global_position)
		return

	# Passive lure (player holding favorite food) or breeding pair search
	var food_key: String = def.get("food", "")
	if food_key != "" and dist_p < 10.0 and Registry.key_of(player.held_item_id()) == food_key:
		var flat_p := player.global_position - global_position
		flat_p.y = 0.0
		move_dir = flat_p.normalized() * 0.85 if flat_p.length() > 1.8 else Vector3.ZERO
		return

	if love_timer > 0.0:
		for other in world.mobs_root.get_children():
			if other != self and other is VoxelMob and other.mob_type == mob_type and other.love_timer > 0.0:
				var d_o: float = other.global_position.distance_to(global_position)
				var flat_o: Vector3 = other.global_position - global_position
				flat_o.y = 0.0
				move_dir = flat_o.normalized()
				if d_o < 1.5:
					love_timer = 0.0
					other.love_timer = 0.0
					breed_cooldown = 45.0
					other.breed_cooldown = 45.0
					world.spawn_mob(mob_type, global_position + Vector3(0.3, 0.2, 0.3))
					VoxelFX.spawn_block_particles(world, global_position + Vector3(0, 1, 0), B.FLOWER_RED, 12)
				return

	# Idle / Wander / Graze ecosystem state
	state_timer -= delta
	if state_timer <= 0.0:
		var r := randf()
		if r < 0.45:
			state = "idle"
			move_dir = Vector3.ZERO
			state_timer = randf_range(1.5, 4.0)
			# Sheep & cows graze grass to regrow wool / heal
			if mob_type in ["sheep", "cow"]:
				var bx := int(floor(global_position.x))
				var by := int(floor(global_position.y - 0.2))
				var bz := int(floor(global_position.z))
				if world.get_block(bx, by, bz) == B.GRASS:
					if mob_type == "sheep" and sheared:
						sheared = false
						if coat_node != null: coat_node.visible = true
					hp = minf(max_hp, hp + 2.0)
		else:
			state = "wander"
			var ang := randf() * TAU
			move_dir = Vector3(sin(ang), 0.0, cos(ang)) * 0.65
			state_timer = randf_range(2.0, 5.0)
	if state == "flee":
		move_dir = move_dir.normalized() * 1.35
		if state_timer <= 0.0:
			state = "idle"
	elif spd > 0.0:
		pass

func _move_and_collide(delta: float) -> void:
	var spd: float = def["speed"]
	var bx := int(floor(global_position.x))
	var by := int(floor(global_position.y + 0.2))
	var bz := int(floor(global_position.z))
	var blk: int = world.get_block(bx, by, bz)
	in_water = (blk == B.WATER)
	if blk == B.LAVA:
		take_damage(4.0 * delta, Vector3.UP * 3.0, null)

	if def.get("flies", false):
		var want_y := 0.0
		if target != null and is_instance_valid(target):
			want_y = clampf((target.global_position.y + 1.8) - global_position.y, -3.0, 3.0)
		else:
			want_y = sin(anim_phase * 2.0) * 1.2
		velocity = velocity.lerp(Vector3(move_dir.x * spd, want_y, move_dir.z * spd), 5.0 * delta)
	elif def.get("aquatic", false):
		if in_water:
			velocity = velocity.lerp(Vector3(move_dir.x * spd, sin(anim_phase * 2.5) * 0.4, move_dir.z * spd), 5.0 * delta)
		else:
			velocity.y -= 18.0 * delta
			if on_ground:
				velocity.y = 3.2
	else:
		velocity.x = lerpf(velocity.x, move_dir.x * spd, 8.0 * delta)
		velocity.z = lerpf(velocity.z, move_dir.z * spd, 8.0 * delta)
		if in_water:
			velocity.y = lerpf(velocity.y, 2.2, 5.0 * delta)
		else:
			var grav := 10.0 if mob_type == "chicken" else 24.0
			velocity.y = maxf(velocity.y - grav * delta, -38.0)

	# Axis-by-axis voxel collision with automatic step/jump over 1-block ledges
	var hw: float = def.get("w", 0.7) * 0.5
	var h: float = def.get("h", 1.3)
	var pos := global_position

	# Y movement
	pos.y += velocity.y * delta
	if _collides(pos, hw, h):
		if velocity.y < 0.0:
			pos.y = floor(pos.y) + 1.001
			on_ground = true
		else:
			pos.y = global_position.y
		velocity.y = 0.0
	else:
		on_ground = false

	# X movement
	var old_x := pos.x
	pos.x += velocity.x * delta
	if _collides(pos, hw, h):
		pos.x = old_x
		if on_ground:
			velocity.y = 7.6
		elif def.get("climbs", false):
			velocity.y = 4.2

	# Z movement
	var old_z := pos.z
	pos.z += velocity.z * delta
	if _collides(pos, hw, h):
		pos.z = old_z
		if on_ground:
			velocity.y = 7.6
		elif def.get("climbs", false):
			velocity.y = 4.2

	if mob_type == "frost_hare" and on_ground and move_dir.length_squared() > 0.05:
		velocity.y = 5.4

	global_position = pos
	if move_dir.length_squared() > 0.01:
		var want_yaw := atan2(-move_dir.x, -move_dir.z)
		rig.rotation.y = lerp_angle(rig.rotation.y, want_yaw, 10.0 * delta)

func _collides(pos: Vector3, hw: float, h: float) -> bool:
	var x0 := int(floor(pos.x - hw))
	var x1 := int(floor(pos.x + hw))
	var y0 := int(floor(pos.y + 0.02))
	var y1 := int(floor(pos.y + h - 0.05))
	var z0 := int(floor(pos.z - hw))
	var z1 := int(floor(pos.z + hw))
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			for z in range(z0, z1 + 1):
				if world.is_solid_at(x, y, z):
					return true
	return false

func _animate(delta: float) -> void:
	var hvel := Vector2(velocity.x, velocity.z).length()
	anim_phase += delta * (2.5 + hvel * 2.8)
	var swing := sin(anim_phase) * clampf(hvel * 0.35, 0.0, 0.85)
	for i in limbs.size():
		var l := limbs[i]
		if mob_type in ["zombie", "skeleton"] and i >= 2:
			l.rotation.x = 1.35 + sin(anim_phase * 0.7 + i) * 0.12
		elif mob_type == "spider":
			l.rotation.z = sin(anim_phase * 1.5 + i) * 0.25
		elif mob_type == "wraith":
			l.rotation.z = sin(anim_phase * 2.0) * (0.45 if i == 0 else -0.45)
		else:
			l.rotation.x = swing if (i % 2 == 0) else -swing
	if head_node != null:
		head_node.rotation.x = sin(anim_phase * 0.5) * 0.06

func interact(player: Node3D, held_id: int) -> bool:
	var held_key := Registry.key_of(held_id)
	# Shear sheep
	if mob_type == "sheep" and held_key == "shears" and not sheared:
		sheared = true
		if coat_node != null:
			coat_node.visible = false
		world.spawn_drop(global_position + Vector3(0, 0.6, 0), B.WOOL_WHITE, randi_range(1, 3))
		Sfx.play_3d("mob_sheep", global_position)
		player.damage_held_item(1)
		return true

	# Tame wolf with bone
	if mob_type == "wolf" and not tamed and held_key == "bone":
		player.consume_held_item(1)
		if randf() < 0.45:
			tamed = true
			target = null
			max_hp = 24.0
			hp = max_hp
			if coat_node != null:
				_materials[1].albedo_color = Color("#d23228") # Red collar!
			VoxelFX.spawn_block_particles(world, global_position + Vector3(0, 0.9, 0), B.FLOWER_RED, 14)
			Sfx.play_3d("mob_wolf", global_position)
		return true

	# Feed / breed passive animals
	if held_key != "" and held_key == def.get("food", "") and breed_cooldown <= 0.0 and love_timer <= 0.0:
		player.consume_held_item(1)
		love_timer = 18.0
		hp = minf(max_hp, hp + 4.0)
		VoxelFX.spawn_block_particles(world, global_position + Vector3(0, 1.0, 0), B.FLOWER_RED, 10)
		Sfx.play_3d(def.get("snd", "mob_cow"), global_position)
		return true
	return false

func take_damage(amount: float, knockback: Vector3, attacker: Node3D) -> void:
	if hp <= 0.0:
		return
	hp -= amount
	velocity += knockback
	hurt_flash = 0.22
	_tint_all(Color(1.0, 0.32, 0.32))
	Sfx.play_3d(def.get("snd", "hurt"), global_position, -1.0)

	if attacker != null:
		if def.get("hostile", false) or (def.get("neutral", false) and not tamed):
			target = attacker
		else:
			state = "flee"
			state_timer = 4.0
			var away := global_position - attacker.global_position
			away.y = 0.0
			move_dir = away.normalized()
		# Alert player's tamed wolves
		if attacker == world.local_player:
			for m in world.mobs_root.get_children():
				if m != self and m is VoxelMob and m.tamed:
					m.target = self

	if hp <= 0.0:
		_die()

func _die() -> void:
	VoxelFX.spawn_block_particles(world, global_position + Vector3(0, 0.6, 0), B.WOOL_WHITE, 16)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for d in def.get("drops", []):
		var key: String = d[0]
		var qty := rng.randi_range(d[1], d[2])
		if mob_type == "sheep" and key == "wool_white" and sheared:
			qty = 0
		if qty > 0:
			world.spawn_drop(global_position + Vector3(0, 0.5, 0), Registry.id_of(key), qty)
	queue_free()

func _tint_all(col: Color) -> void:
	for m in _materials:
		m.albedo_color = col

func _restore_colors() -> void:
	for i in _materials.size():
		_materials[i].albedo_color = _base_colors[i]
