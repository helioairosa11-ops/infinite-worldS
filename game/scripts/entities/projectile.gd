class_name VoxelProjectile
extends Node3D
## Handles both flying arrows (player or skeleton) and the fishing rod bobber.

var world: Node
var shooter: Node3D
var kind: String = "arrow" # "arrow" or "bobber"
var velocity: Vector3 = Vector3.ZERO
var damage: float = 6.0
var age: float = 0.0
var stuck: bool = false
var bite_timer: float = 0.0
var has_bite: bool = false

func setup(p_world: Node, p_shooter: Node3D, p_kind: String, p_vel: Vector3, p_dmg: float = 6.0) -> void:
	world = p_world
	shooter = p_shooter
	kind = p_kind
	velocity = p_vel
	damage = p_dmg
	_build_mesh()

func _build_mesh() -> void:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	var box := BoxMesh.new()
	if kind == "arrow":
		mat.albedo_color = Color("#c8b898")
		box.size = Vector3(0.08, 0.08, 0.45)
	else:
		mat.albedo_color = Color("#e03c28")
		box.size = Vector3(0.18, 0.18, 0.18)
		bite_timer = randf_range(3.0, 6.5)
	box.material = mat
	mi.mesh = box
	add_child(mi)

func _physics_process(delta: float) -> void:
	if world == null:
		queue_free()
		return
	age += delta
	if age > 25.0:
		queue_free()
		return
	if stuck:
		if age > 8.0:
			queue_free()
		return

	if kind == "bobber":
		var bx := int(floor(global_position.x))
		var by := int(floor(global_position.y))
		var bz := int(floor(global_position.z))
		var blk: int = world.get_block(bx, by, bz)
		if blk == B.WATER:
			velocity = velocity.lerp(Vector3.ZERO, 6.0 * delta)
			bite_timer -= delta
			if bite_timer <= 0.0 and not has_bite:
				has_bite = true
				bite_timer = 1.6
				Sfx.play_3d("splash", global_position, -2.0)
				VoxelFX.spawn_block_particles(world, global_position, B.WATER, 10)
			elif has_bite and bite_timer <= 0.0:
				has_bite = false
				bite_timer = randf_range(3.5, 7.0)
			global_position.y = float(by) + (0.65 if not has_bite else 0.42 + sin(age * 18.0) * 0.08)
			return
		velocity.y -= 18.0 * delta
		global_position += velocity * delta
		if world.is_solid_at(bx, by, bz):
			velocity = Vector3.ZERO
		return

	# Arrow flight & hit detection
	velocity.y -= 16.0 * delta
	var next_pos := global_position + velocity * delta
	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity, Vector3.UP)

	var bx2 := int(floor(next_pos.x))
	var by2 := int(floor(next_pos.y))
	var bz2 := int(floor(next_pos.z))
	if world.is_solid_at(bx2, by2, bz2):
		stuck = true
		Sfx.play_3d("hit", next_pos, -4.0)
		return

	# Check entity hits
	for m in world.mobs_root.get_children():
		if m != shooter and m.global_position.distance_to(next_pos) < 1.1:
			m.take_damage(damage, velocity.normalized() * 6.0, shooter)
			Sfx.play_3d("hit", next_pos)
			queue_free()
			return
	var p: Node3D = world.local_player
	if p != null and p != shooter and not p.is_dead and (p.global_position + Vector3(0, 0.9, 0)).distance_to(next_pos) < 0.95:
		p.take_damage(damage, "arrow", velocity.normalized() * 5.0)
		Sfx.play_3d("hit", next_pos)
		queue_free()
		return

	global_position = next_pos
