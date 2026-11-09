class_name DroppedItem
extends Node3D
## Physical dropped item stack in the world with gravity, voxel collision,
## bobbing/spinning animation, stack merging, and magnetic pickup.

var world: Node
var item_id: int = 0
var count: int = 1
var dur: int = 0
var velocity: Vector3 = Vector3.ZERO
var age: float = 0.0
var pickup_delay: float = 0.45
var visual: Node3D

func setup(p_world: Node, p_id: int, p_count: int, p_dur: int, p_vel: Vector3) -> void:
	world = p_world
	item_id = p_id
	count = p_count
	dur = p_dur
	velocity = p_vel
	_build_visual()

func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	var sp := Sprite3D.new()
	sp.texture = Registry.icon(item_id)
	sp.pixel_size = 0.014
	sp.shaded = true
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	visual.add_child(sp)

func _physics_process(delta: float) -> void:
	if world == null:
		queue_free()
		return
	age += delta
	if age > 300.0:
		queue_free()
		return
	if visual != null:
		visual.rotation.y += delta * 2.2
		visual.position.y = 0.18 + sin(age * 3.5) * 0.06

	# Physics & voxel collision
	velocity.y -= 18.0 * delta
	velocity.x = move_toward(velocity.x, 0.0, 4.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 4.0 * delta)
	var step := velocity * delta
	var npos := global_position + step
	var bx := int(floor(npos.x))
	var by := int(floor(npos.y))
	var bz := int(floor(npos.z))
	if world.is_solid_at(bx, by, bz):
		velocity.y = 0.0
		npos.y = float(by + 1) + 0.02
		velocity.x *= 0.7
		velocity.z *= 0.7
	global_position = npos

	if age < pickup_delay:
		return

	# Check player pickup
	var p: Node3D = world.local_player
	if p != null and not p.is_dead:
		var target := p.global_position + Vector3(0, 0.8, 0)
		var d := global_position.distance_to(target)
		if d < 2.2:
			global_position = global_position.move_toward(target, 9.5 * delta)
			if d < 0.85:
				var rem: int = p.add_item(item_id, count, dur)
				if rem < count:
					Sfx.play_ui("pickup", randf_range(0.95, 1.25), -3.0)
				if rem <= 0:
					queue_free()
				else:
					count = rem
