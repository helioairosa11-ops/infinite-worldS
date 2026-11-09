class_name VoxelFX
extends Node
## Lightweight pooled voxel particle bursts for mining, breaking and placing blocks,
## explosions, and water splashes.

static func spawn_block_particles(parent: Node, world_pos: Vector3, block_id: int, count: int = 14) -> void:
	if block_id <= 0 or block_id >= B.COUNT:
		return
	var tex_layer: int = Registry.b_tex[block_id][2]
	var img: Image = Registry.layer_images[tex_layer]
	var col := img.get_pixel(8, 8)
	var burst := _ParticleBurst.new()
	burst.position = world_pos
	burst.setup(col, count, 3.8)
	parent.add_child(burst)

static func spawn_explosion_particles(parent: Node, world_pos: Vector3) -> void:
	var burst := _ParticleBurst.new()
	burst.position = world_pos
	burst.setup(Color(1.0, 0.65, 0.25), 32, 9.0)
	parent.add_child(burst)

class _ParticleBurst extends Node3D:
	var _parts: Array[MeshInstance3D] = []
	var _vels: Array[Vector3] = []
	var _life: float = 0.65

	func setup(col: Color, count: int, speed: float) -> void:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.roughness = 0.9
		var box := BoxMesh.new()
		box.size = Vector3(0.12, 0.12, 0.12)
		box.material = mat
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		for i in count:
			var mi := MeshInstance3D.new()
			mi.mesh = box
			mi.position = Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3))
			add_child(mi)
			_parts.append(mi)
			_vels.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(0.3, 1.3), rng.randf_range(-1, 1)).normalized() * rng.randf_range(speed * 0.4, speed))

	func _process(delta: float) -> void:
		_life -= delta
		if _life <= 0.0:
			queue_free()
			return
		for i in _parts.size():
			_vels[i].y -= 16.0 * delta
			_parts[i].position += _vels[i] * delta
			_parts[i].scale = Vector3.ONE * clampf(_life * 1.6, 0.1, 1.0)
