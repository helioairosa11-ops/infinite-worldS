class_name WorldSave
extends RefCounted
## Handles world metadata, player state, chest/furnace tile entities, and ZSTD-compressed
## chunk persistence inside `user://worlds/<world_id>/`.

const ROOT := "res://saves/worlds"

static func ensure_root() -> void:
	var abs_p := ProjectSettings.globalize_path(ROOT)
	if not DirAccess.dir_exists_absolute(abs_p):
		DirAccess.make_dir_recursive_absolute(abs_p)

static func list_worlds() -> Array[Dictionary]:
	ensure_root()
	var out: Array[Dictionary] = []
	var d := DirAccess.open(ROOT)
	if d == null:
		return out
	d.list_dir_begin()
	var folder := d.get_next()
	while folder != "":
		if d.current_is_dir() and not folder.begins_with("."):
			var meta_path := "%s/%s/meta.dat" % [ROOT, folder]
			if FileAccess.file_exists(meta_path):
				var f := FileAccess.open(meta_path, FileAccess.READ)
				if f != null:
					var data: Variant = f.get_var()
					if data is Dictionary:
						data["id"] = folder
						out.append(data)
		folder = d.get_next()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("timestamp", 0)) > int(b.get("timestamp", 0))
	)
	return out

static func create_world(world_name: String, seed_val: int, mode: int = 0) -> Dictionary:
	ensure_root()
	var clean := world_name.strip_edges()
	if clean.is_empty():
		clean = "New World"
	var wid := "world_%d_%d" % [int(Time.get_unix_time_from_system()), abs(seed_val) % 10000]
	var dir_path := ProjectSettings.globalize_path("%s/%s" % [ROOT, wid])
	DirAccess.make_dir_recursive_absolute(dir_path)
	var meta := {
		"id": wid,
		"name": clean,
		"seed": seed_val,
		"mode": mode, # 0 = survival, 1 = creative
		"time": 0.30, # Morning
		"days": 1,
		"dimension": 0,
		"timestamp": int(Time.get_unix_time_from_system()),
		"discovered": [],
	}
	save_meta(wid, meta)
	return meta

static func delete_world(wid: String) -> void:
	var dir_path := ProjectSettings.globalize_path("%s/%s" % [ROOT, wid])
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var fn := d.get_next()
	while fn != "":
		if not d.current_is_dir():
			d.remove(fn)
		fn = d.get_next()
	DirAccess.remove_absolute(dir_path)

static func save_meta(wid: String, meta: Dictionary) -> void:
	ensure_root()
	var dir_path := ProjectSettings.globalize_path("%s/%s" % [ROOT, wid])
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	meta["timestamp"] = int(Time.get_unix_time_from_system())
	var f := FileAccess.open("%s/%s/meta.dat" % [ROOT, wid], FileAccess.WRITE)
	if f != null:
		f.store_var(meta)

static func load_meta(wid: String) -> Dictionary:
	var path := "%s/%s/meta.dat" % [ROOT, wid]
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var v: Variant = f.get_var()
	return v if v is Dictionary else {}

static func chunk_path(wid: String, dim: int, cx: int, cz: int) -> String:
	return "%s/%s/c_%d_%d_%d.chk" % [ROOT, wid, dim, cx, cz]

static func save_chunk(wid: String, chunk: VoxelChunk) -> void:
	if wid.is_empty() or not chunk.modified:
		return
	var f := FileAccess.open_compressed(chunk_path(wid, chunk.dimension, chunk.cx, chunk.cz), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	f.store_var({
		"blocks": chunk.blocks,
		"meta": chunk.meta,
		"biomes": chunk.biomes,
		"hmap": chunk.hmap,
		"chests": chunk.chests,
		"furnaces": chunk.furnaces,
	})

static func load_chunk(wid: String, chunk: VoxelChunk) -> bool:
	if wid.is_empty():
		return false
	var p := chunk_path(wid, chunk.dimension, chunk.cx, chunk.cz)
	if not FileAccess.file_exists(p):
		return false
	var f := FileAccess.open_compressed(p, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	var d: Variant = f.get_var()
	if not (d is Dictionary):
		return false
	chunk.blocks = d.get("blocks", chunk.blocks)
	chunk.meta = d.get("meta", chunk.meta)
	chunk.biomes = d.get("biomes", chunk.biomes)
	chunk.hmap = d.get("hmap", chunk.hmap)
	chunk.chests = d.get("chests", {})
	chunk.furnaces = d.get("furnaces", {})
	chunk.modified = true
	return true
