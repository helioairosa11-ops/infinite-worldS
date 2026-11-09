extends Node
## Central registry: blocks, items, textures, icons, recipes, smelting and fuel.
## Block property arrays are plain packed arrays so worker threads can read them.

const FACING_DIRS := [Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1), Vector3i(1, 0, 0)]
const FACE_NORMALS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

# ---- block property tables (index = block id)
var b_name: PackedStringArray
var b_render: PackedByteArray
var b_solid: PackedByteArray      # has collision
var b_opaque: PackedByteArray     # hides neighbours / blocks light
var b_light: PackedByteArray      # emitted light 0-15
var b_atten: PackedByteArray      # extra skylight attenuation when passing through
var b_tool: PackedByteArray
var b_tier: PackedByteArray       # required tool tier for drops (0 = none)
var b_hardness: PackedFloat32Array
var b_gravity: PackedByteArray
var b_replaceable: PackedByteArray
var b_flammable: PackedByteArray
var b_tint: PackedByteArray       # 1 = biome foliage tint
var b_sway: PackedByteArray       # 1 = leaves, 2 = plants
var b_emissive: PackedByteArray
var b_sound: PackedStringArray
var b_tex: Array = []             # Array[PackedInt32Array(6)] texture layer per face
var b_front: PackedInt32Array     # front texture layer for facing blocks (-1 none)
var b_item: PackedStringArray     # item key obtained when picked / default drop

# ---- textures
var layer_of: Dictionary = {}
var layer_images: Array[Image] = []
var texture_array: Texture2DArray
var destroy_layer0: int = 0

# ---- items
var items: Array = []             # id -> Dictionary
var item_ids: Dictionary = {}     # key -> id
var icons: Dictionary = {}        # id -> Texture2D
var icon_images: Dictionary = {}  # id -> Image (16x16 flat, for held items/drops)

var recipes: Array = []
var smelting: Dictionary = {}     # input key -> [out key, count]
var fuel: Dictionary = {}         # key -> seconds

const TOOL_TIERS := {"wood": 1, "stone": 2, "iron": 3, "gold": 1, "diamond": 4}
const TOOL_SPEED := {"wood": 2.0, "stone": 4.0, "iron": 6.0, "gold": 12.0, "diamond": 8.0}
const TOOL_DUR := {"wood": 60, "stone": 132, "iron": 251, "gold": 33, "diamond": 1562}
const TOOL_DMG := {"pickaxe": 2.0, "axe": 3.0, "shovel": 1.5, "sword": 4.0, "hoe": 1.0}
const MAT_DMG := {"wood": 0.0, "stone": 1.0, "iron": 2.0, "gold": 0.0, "diamond": 3.0}
const ARMOR_PTS := {"leather": [1, 3, 2, 1], "iron": [2, 6, 5, 2], "gold": [2, 5, 3, 1], "diamond": [3, 8, 6, 3]}
const ARMOR_DUR := {"leather": 80, "iron": 240, "gold": 112, "diamond": 528}
const ARMOR_PIECES := ["helmet", "chestplate", "leggings", "boots"]

func _ready() -> void:
	_init_tables()
	_define_blocks()
	_build_texture_array()
	_define_items()
	_define_recipes()
	_build_icons()

# ===================================================================== blocks
func _init_tables() -> void:
	var n := B.COUNT
	b_name.resize(n); b_render.resize(n); b_solid.resize(n); b_opaque.resize(n)
	b_light.resize(n); b_atten.resize(n); b_tool.resize(n); b_tier.resize(n)
	b_hardness.resize(n); b_gravity.resize(n); b_replaceable.resize(n); b_flammable.resize(n)
	b_tint.resize(n); b_sway.resize(n); b_emissive.resize(n); b_sound.resize(n)
	b_front.resize(n); b_item.resize(n)
	b_tex.resize(n)
	for i in n:
		b_front[i] = -1
		b_tex[i] = PackedInt32Array([0, 0, 0, 0, 0, 0])

func _layer(tex_name: String) -> int:
	if not layer_of.has(tex_name):
		layer_of[tex_name] = layer_images.size()
		var img := TexGen.generate(tex_name)
		layer_images.append(img)
	return layer_of[tex_name]

## tex: String (all faces) or Dictionary {top, bottom, side, front}
func _def(id: int, name: String, tex: Variant, p: Dictionary = {}) -> void:
	b_name[id] = name
	b_render[id] = p.get("render", B.R_CUBE)
	var solid_default := 1 if b_render[id] in [B.R_CUBE, B.R_CUTOUT] else 0
	b_solid[id] = p.get("solid", solid_default)
	b_opaque[id] = p.get("opaque", 1 if b_render[id] == B.R_CUBE else 0)
	b_light[id] = p.get("light", 0)
	b_atten[id] = p.get("atten", 0)
	b_tool[id] = p.get("tool", B.T_NONE)
	b_tier[id] = p.get("tier", 0)
	b_hardness[id] = p.get("hard", 1.0)
	b_gravity[id] = p.get("gravity", 0)
	b_replaceable[id] = p.get("replace", 0)
	b_flammable[id] = p.get("flammable", 0)
	b_tint[id] = p.get("tint", 0)
	b_sway[id] = p.get("sway", 0)
	b_emissive[id] = p.get("emissive", 0)
	b_sound[id] = p.get("sound", "stone")
	b_item[id] = p.get("item", name)
	if tex == null:
		return
	var t := PackedInt32Array()
	if tex is String:
		var l := _layer(tex)
		t = PackedInt32Array([l, l, l, l, l, l])
	else:
		var side := _layer(tex.get("side", tex.get("top")))
		var top := _layer(tex.get("top", tex.get("side")))
		var bottom := _layer(tex.get("bottom", tex.get("top", tex.get("side"))))
		t = PackedInt32Array([side, side, top, bottom, side, side])
		if tex.has("front"):
			b_front[id] = _layer(tex["front"])
	b_tex[id] = t

func _define_blocks() -> void:
	var P := B.T_PICK; var A := B.T_AXE; var S := B.T_SHOVEL
	_def(B.AIR, "air", null, {"render": B.R_NONE, "solid": 0, "opaque": 0, "replace": 1, "hard": 0.0})
	_def(B.BEDROCK, "bedrock", "bedrock", {"hard": -1.0})
	_def(B.STONE, "stone", "stone", {"tool": P, "tier": 1, "hard": 1.5, "item": "cobble"})
	_def(B.DIRT, "dirt", "dirt", {"tool": S, "hard": 0.5, "sound": "gravel"})
	_def(B.GRASS, "grass", {"top": "grass_top", "bottom": "dirt", "side": "grass_side"}, {"tool": S, "hard": 0.6, "sound": "grass", "item": "dirt", "tint": 1})
	_def(B.SAND, "sand", "sand", {"tool": S, "hard": 0.5, "gravity": 1, "sound": "sand"})
	_def(B.GRAVEL, "gravel", "gravel", {"tool": S, "hard": 0.6, "gravity": 1, "sound": "gravel"})
	_def(B.SANDSTONE, "sandstone", {"top": "sandstone_top", "side": "sandstone_side"}, {"tool": P, "tier": 1, "hard": 0.8})
	_def(B.CLAY, "clay", "clay", {"tool": S, "hard": 0.6, "sound": "gravel"})
	_def(B.SNOW_GRASS, "snow_grass", {"top": "snow", "bottom": "dirt", "side": "snow_side"}, {"tool": S, "hard": 0.6, "sound": "snow", "item": "dirt"})
	_def(B.ICE, "ice", "ice", {"render": B.R_CUTOUT, "tool": P, "hard": 0.5, "sound": "glass", "atten": 1})
	_def(B.WATER, "water", "water", {"render": B.R_LIQUID, "solid": 0, "replace": 1, "hard": -1.0, "atten": 2, "sound": "water"})
	_def(B.LAVA, "lava", "lava", {"render": B.R_LIQUID, "solid": 0, "replace": 1, "hard": -1.0, "light": 15, "atten": 15, "emissive": 1})
	_def(B.OAK_LOG, "oak_log", {"top": "oak_log_top", "side": "oak_log"}, {"tool": A, "hard": 2.0, "sound": "wood", "flammable": 1})
	_def(B.OAK_LEAVES, "oak_leaves", "oak_leaves", {"render": B.R_CUTOUT, "hard": 0.2, "sound": "grass", "tint": 1, "sway": 1, "flammable": 1, "atten": 1})
	_def(B.BIRCH_LOG, "birch_log", {"top": "birch_log_top", "side": "birch_log"}, {"tool": A, "hard": 2.0, "sound": "wood", "flammable": 1})
	_def(B.BIRCH_LEAVES, "birch_leaves", "birch_leaves", {"render": B.R_CUTOUT, "hard": 0.2, "sound": "grass", "tint": 1, "sway": 1, "flammable": 1, "atten": 1})
	_def(B.PINE_LOG, "pine_log", {"top": "pine_log_top", "side": "pine_log"}, {"tool": A, "hard": 2.0, "sound": "wood", "flammable": 1})
	_def(B.PINE_LEAVES, "pine_leaves", "pine_leaves", {"render": B.R_CUTOUT, "hard": 0.2, "sound": "grass", "sway": 1, "flammable": 1, "atten": 1})
	_def(B.CACTUS, "cactus", {"top": "cactus_top", "side": "cactus_side"}, {"render": B.R_BOX, "solid": 1, "hard": 0.4, "sound": "wool"})
	_def(B.OAK_PLANKS, "oak_planks", "oak_planks", {"tool": A, "hard": 2.0, "sound": "wood", "flammable": 1})
	_def(B.BIRCH_PLANKS, "birch_planks", "birch_planks", {"tool": A, "hard": 2.0, "sound": "wood", "flammable": 1})
	_def(B.PINE_PLANKS, "pine_planks", "pine_planks", {"tool": A, "hard": 2.0, "sound": "wood", "flammable": 1})
	_def(B.COBBLE, "cobble", "cobble", {"tool": P, "tier": 1, "hard": 2.0})
	_def(B.MOSSY_COBBLE, "mossy_cobble", "mossy_cobble", {"tool": P, "tier": 1, "hard": 2.0})
	_def(B.STONE_BRICKS, "stone_bricks", "stone_bricks", {"tool": P, "tier": 1, "hard": 1.5})
	_def(B.BRICKS, "bricks", "bricks", {"tool": P, "tier": 1, "hard": 2.0})
	_def(B.GLASS, "glass", "glass", {"render": B.R_CUTOUT, "hard": 0.3, "sound": "glass", "item": ""})
	_def(B.COAL_ORE, "coal_ore", "coal_ore", {"tool": P, "tier": 1, "hard": 3.0, "item": "coal"})
	_def(B.IRON_ORE, "iron_ore", "iron_ore", {"tool": P, "tier": 2, "hard": 3.0})
	_def(B.GOLD_ORE, "gold_ore", "gold_ore", {"tool": P, "tier": 3, "hard": 3.0})
	_def(B.DIAMOND_ORE, "diamond_ore", "diamond_ore", {"tool": P, "tier": 3, "hard": 3.0, "item": "diamond"})
	_def(B.LUMINITE_ORE, "luminite_ore", "luminite_ore", {"tool": P, "tier": 3, "hard": 3.5, "light": 7, "emissive": 1, "item": "luminite_shard"})
	_def(B.LUMINITE_BLOCK, "luminite_block", "luminite_block", {"tool": P, "tier": 1, "hard": 2.0, "light": 15, "emissive": 1, "sound": "glass"})
	_def(B.IRON_BLOCK, "iron_block", "iron_block", {"tool": P, "tier": 2, "hard": 5.0, "sound": "metal"})
	_def(B.GOLD_BLOCK, "gold_block", "gold_block", {"tool": P, "tier": 3, "hard": 3.0, "sound": "metal"})
	_def(B.DIAMOND_BLOCK, "diamond_block", "diamond_block", {"tool": P, "tier": 3, "hard": 5.0, "sound": "metal"})
	_def(B.WORKBENCH, "workbench", {"top": "workbench_top", "bottom": "oak_planks", "side": "workbench_side", "front": "workbench_front"}, {"tool": A, "hard": 2.5, "sound": "wood", "flammable": 1})
	_def(B.FURNACE, "furnace", {"top": "furnace_top", "side": "furnace_side", "front": "furnace_front"}, {"tool": P, "tier": 1, "hard": 3.5})
	_def(B.FURNACE_LIT, "furnace_lit", {"top": "furnace_top", "side": "furnace_side", "front": "furnace_front_lit"}, {"tool": P, "tier": 1, "hard": 3.5, "light": 13, "item": "furnace"})
	_def(B.CHEST, "chest", {"top": "chest_top", "side": "chest_side", "front": "chest_front"}, {"tool": A, "hard": 2.5, "sound": "wood", "flammable": 1})
	_def(B.TORCH, "torch", "torch", {"render": B.R_BOX, "solid": 0, "hard": 0.0, "light": 14, "sound": "wood", "emissive": 1})
	_def(B.DOOR_LOWER, "door_lower", "door_lower", {"render": B.R_BOX, "solid": 1, "hard": 3.0, "tool": A, "sound": "wood", "item": "oak_door"})
	_def(B.DOOR_UPPER, "door_upper", "door_upper", {"render": B.R_BOX, "solid": 1, "hard": 3.0, "tool": A, "sound": "wood", "item": "oak_door"})
	_def(B.BEDROLL, "bedroll", {"top": "bedroll_top", "side": "bedroll_side", "bottom": "oak_planks"}, {"render": B.R_BOX, "solid": 1, "hard": 0.2, "sound": "wool"})
	_def(B.FARMLAND, "farmland", {"top": "farmland", "side": "dirt", "bottom": "dirt"}, {"tool": S, "hard": 0.6, "sound": "gravel", "item": "dirt"})
	for st in 8:
		_layer("wheat_%d" % st)
	_def(B.WHEAT, "wheat_crop", "wheat_0", {"render": B.R_CROSS, "solid": 0, "opaque": 0, "hard": 0.0, "sound": "grass", "replace": 0, "sway": 2, "item": "seeds"})
	_def(B.TALL_GRASS, "tall_grass", "tall_grass", {"render": B.R_CROSS, "hard": 0.0, "sound": "grass", "replace": 1, "tint": 1, "sway": 2, "item": ""})
	_def(B.FLOWER_RED, "flower_red", "flower_red", {"render": B.R_CROSS, "hard": 0.0, "sound": "grass", "sway": 2})
	_def(B.FLOWER_YELLOW, "flower_yellow", "flower_yellow", {"render": B.R_CROSS, "hard": 0.0, "sound": "grass", "sway": 2})
	_def(B.FLOWER_BLUE, "flower_blue", "flower_blue", {"render": B.R_CROSS, "hard": 0.0, "sound": "grass", "sway": 2})
	_def(B.DEAD_BUSH, "dead_bush", "dead_bush", {"render": B.R_CROSS, "hard": 0.0, "sound": "grass", "replace": 1, "item": "stick"})
	_def(B.MUSHROOM, "mushroom", "mushroom", {"render": B.R_CROSS, "hard": 0.0, "sound": "grass"})
	_def(B.GLOWCAP, "glowcap", "glowcap", {"render": B.R_CROSS, "hard": 0.0, "sound": "grass", "light": 10, "emissive": 1})
	_def(B.CRYSTAL_CLUSTER, "crystal_cluster", "crystal_cluster", {"render": B.R_CROSS, "hard": 1.0, "tool": P, "sound": "glass", "light": 12, "emissive": 1, "item": "luminite_shard"})
	_def(B.REEDS, "reeds", "reeds", {"render": B.R_CROSS, "hard": 0.0, "sound": "grass", "replace": 1, "sway": 2, "item": ""})
	_def(B.OAK_SAPLING, "oak_sapling", "oak_sapling", {"render": B.R_CROSS, "hard": 0.0, "sound": "grass", "sway": 2})
	_def(B.BIRCH_SAPLING, "birch_sapling", "birch_sapling", {"render": B.R_CROSS, "hard": 0.0, "sound": "grass", "sway": 2})
	_def(B.PINE_SAPLING, "pine_sapling", "pine_sapling", {"render": B.R_CROSS, "hard": 0.0, "sound": "grass", "sway": 2})
	_def(B.WOOL_WHITE, "wool_white", "wool_white", {"hard": 0.8, "sound": "wool", "flammable": 1})
	_def(B.WOOL_RED, "wool_red", "wool_red", {"hard": 0.8, "sound": "wool", "flammable": 1})
	_def(B.WOOL_BLUE, "wool_blue", "wool_blue", {"hard": 0.8, "sound": "wool", "flammable": 1})
	_def(B.WOOL_YELLOW, "wool_yellow", "wool_yellow", {"hard": 0.8, "sound": "wool", "flammable": 1})
	_def(B.WOOL_GREEN, "wool_green", "wool_green", {"hard": 0.8, "sound": "wool", "flammable": 1})
	_def(B.WOOL_BLACK, "wool_black", "wool_black", {"hard": 0.8, "sound": "wool", "flammable": 1})
	_def(B.LADDER, "ladder", "ladder", {"render": B.R_BOX, "solid": 0, "hard": 0.4, "tool": A, "sound": "wood"})
	_def(B.BOOKSHELF, "bookshelf", {"top": "oak_planks", "side": "bookshelf"}, {"tool": A, "hard": 1.5, "sound": "wood", "flammable": 1})
	_def(B.SHALE, "shale", "shale", {"tool": P, "tier": 1, "hard": 2.5})
	_def(B.SHALE_BRICKS, "shale_bricks", "shale_bricks", {"tool": P, "tier": 1, "hard": 2.5})
	_def(B.MUD, "mud", "mud", {"tool": S, "hard": 0.5, "sound": "gravel"})
	_def(B.OBSIDIAN, "obsidian", "obsidian", {"tool": P, "tier": 4, "hard": 25.0})
	_def(B.HAY, "hay", {"top": "hay_top", "side": "hay_side"}, {"hard": 0.5, "sound": "grass", "flammable": 1})
	_def(B.CRYSTAL_LAMP, "crystal_lamp", "crystal_lamp", {"tool": A, "hard": 1.0, "light": 15, "emissive": 1, "sound": "glass"})
	_def(B.RED_SAND, "red_sand", "red_sand", {"tool": S, "hard": 0.5, "gravity": 1, "sound": "sand"})
	_def(B.TERRACOTTA, "terracotta", "terracotta", {"tool": P, "tier": 1, "hard": 1.25})
	_def(B.TERRACOTTA_ORANGE, "terracotta_orange", "terracotta_orange", {"tool": P, "tier": 1, "hard": 1.25})
	_def(B.TERRACOTTA_BROWN, "terracotta_brown", "terracotta_brown", {"tool": P, "tier": 1, "hard": 1.25})
	_def(B.MOSSY_STONE_BRICKS, "mossy_stone_bricks", "mossy_stone_bricks", {"tool": P, "tier": 1, "hard": 1.5})
	_def(B.FIRE, "fire", "fire", {"render": B.R_CROSS, "hard": 0.0, "light": 15, "emissive": 1, "replace": 1, "item": "", "sound": "fire"})
	_def(B.SNOW, "snow", "snow", {"tool": S, "hard": 0.2, "sound": "snow"})
	_def(B.POLISHED_STONE, "polished_stone", "polished_stone", {"tool": P, "tier": 1, "hard": 1.5})
	_def(B.SMOOTH_SANDSTONE, "smooth_sandstone", "smooth_sandstone", {"tool": P, "tier": 1, "hard": 0.8})
	_def(B.COAL_BLOCK, "coal_block", "coal_block", {"tool": P, "tier": 1, "hard": 5.0, "flammable": 1})
	_def(B.GLOWMOSS, "glowmoss", "glowmoss", {"tool": S, "hard": 0.4, "light": 6, "emissive": 1, "sound": "grass"})
	for i in 10:
		var l := _layer("destroy_%d" % i)
		if i == 0: destroy_layer0 = l

func _build_texture_array() -> void:
	var imgs: Array[Image] = []
	for img in layer_images:
		var c := img.duplicate() as Image
		c.generate_mipmaps()
		imgs.append(c)
	texture_array = Texture2DArray.new()
	texture_array.create_from_images(imgs)

func is_opaque(id: int) -> bool: return b_opaque[id] == 1
func is_solid(id: int) -> bool: return b_solid[id] == 1
func is_liquid(id: int) -> bool: return id == B.WATER or id == B.LAVA
func is_replaceable(id: int) -> bool: return b_replaceable[id] == 1
func wheat_layer(stage: int) -> int: return layer_of["wheat_%d" % clampi(stage, 0, 7)]

## Collision boxes in block-local coordinates. Empty array = no collision.
func collision_boxes(id: int, meta: int) -> Array:
	match id:
		B.AIR, B.WATER, B.LAVA, B.TORCH, B.LADDER, B.FIRE:
			return []
		B.DOOR_LOWER, B.DOOR_UPPER:
			return [door_box(meta)]
		B.BEDROLL:
			return [AABB(Vector3(0, 0, 0), Vector3(1, 0.4, 1))]
		B.CACTUS:
			return [AABB(Vector3(0.0625, 0, 0.0625), Vector3(0.875, 1, 0.875))]
	if b_solid[id] == 0:
		return []
	return [AABB(Vector3.ZERO, Vector3.ONE)]

## Visual / selection box for box-rendered blocks.
func render_box(id: int, meta: int) -> AABB:
	match id:
		B.TORCH:
			var f := meta & 7
			if f < 4:
				var d: Vector3i = FACING_DIRS[f]
				# attached to the wall opposite to "d"
				var c := Vector3(0.5, 0.2, 0.5) - Vector3(d) * 0.38
				return AABB(c - Vector3(0.0625, 0, 0.0625), Vector3(0.125, 0.625, 0.125))
			return AABB(Vector3(0.4375, 0, 0.4375), Vector3(0.125, 0.625, 0.125))
		B.LADDER:
			var dd: Vector3i = FACING_DIRS[meta & 3]
			# ladder hugs the wall on the side opposite to facing
			var t := 0.0625
			match meta & 3:
				0: return AABB(Vector3(0, 0, 0), Vector3(1, 1, t))
				1: return AABB(Vector3(1 - t, 0, 0), Vector3(t, 1, 1))
				2: return AABB(Vector3(0, 0, 1 - t), Vector3(1, 1, t))
				_: return AABB(Vector3(0, 0, 0), Vector3(t, 1, 1))
		B.DOOR_LOWER, B.DOOR_UPPER:
			return door_box(meta)
		B.BEDROLL:
			return AABB(Vector3(0, 0, 0), Vector3(1, 0.4, 1))
		B.CACTUS:
			return AABB(Vector3(0.0625, 0, 0.0625), Vector3(0.875, 1, 0.875))
	return AABB(Vector3.ZERO, Vector3.ONE)

## meta bits: 0-1 facing, bit 2 open
func door_box(meta: int) -> AABB:
	var f := meta & 3
	if meta & 4:
		f = (f + 1) % 4
	var t := 0.1875
	match f:
		0: return AABB(Vector3(0, 0, 0), Vector3(1, 1, t))
		1: return AABB(Vector3(1 - t, 0, 0), Vector3(t, 1, 1))
		2: return AABB(Vector3(0, 0, 1 - t), Vector3(1, 1, t))
		_: return AABB(Vector3(0, 0, 0), Vector3(t, 1, 1))

# ===================================================================== items
func _add_item(key: String, d: Dictionary) -> int:
	var id: int
	if d.has("block"):
		id = d["block"]
	else:
		id = _next_item_id()
	d["id"] = id
	d["key"] = key
	if not d.has("stack"): d["stack"] = 64
	while items.size() <= id:
		items.append(null)
	items[id] = d
	item_ids[key] = id
	return id

var _item_counter := 256
func _next_item_id() -> int:
	_item_counter += 1
	return _item_counter - 1

func _define_items() -> void:
	# block items (any block whose drop key equals its own name, plus a few extras)
	for id in range(1, B.COUNT):
		var n: String = b_name[id]
		if n in ["water", "lava", "furnace_lit", "door_lower", "door_upper", "wheat_crop", "farmland", "fire", "snow_grass"]:
			continue
		_add_item(n, {"block": id, "place": id})
	var simple := ["stick", "coal", "charcoal", "iron_ingot", "gold_ingot", "diamond", "luminite_shard", "flint",
		"leather", "feather", "string", "bone", "ember_dust", "wheat", "clay_ball", "brick", "egg", "bowl"]
	for k in simple:
		_add_item(k, {})
	items[item_ids["egg"]]["stack"] = 16
	_add_item("seeds", {"place": B.WHEAT})
	_add_item("oak_door", {"place": B.DOOR_LOWER})
	_add_item("hollow_flesh", {"food": 3, "sat": 0.5, "sick": 0.6})
	var foods := {"apple": [4, 2.4], "bread": [5, 6.0], "raw_steak": [3, 1.8], "cooked_steak": [8, 12.8],
		"raw_pork": [3, 1.8], "cooked_pork": [8, 12.8], "raw_fowl": [2, 1.2], "cooked_fowl": [6, 7.2],
		"raw_fish": [2, 0.4], "cooked_fish": [5, 6.0], "raw_hare": [3, 1.8], "cooked_hare": [5, 6.0],
		"mushroom_stew": [6, 7.2]}
	for k in foods:
		_add_item(k, {"food": foods[k][0], "sat": foods[k][1]})
	items[item_ids["mushroom_stew"]]["stack"] = 1
	items[item_ids["mushroom_stew"]]["returns"] = "bowl"
	_add_item("bucket", {"stack": 16})
	_add_item("water_bucket", {"stack": 1, "place": B.WATER, "returns": "bucket"})
	_add_item("lava_bucket", {"stack": 1, "place": B.LAVA, "returns": "bucket"})
	_add_item("arrow", {})
	_add_item("bow", {"stack": 1, "durability": 384, "kind": "bow"})
	_add_item("fishing_rod", {"stack": 1, "durability": 64, "kind": "rod"})
	_add_item("ember_striker", {"stack": 1, "durability": 64, "kind": "striker"})
	_add_item("shears", {"stack": 1, "durability": 238, "kind": "shears"})
	var ttype := {"pickaxe": B.T_PICK, "axe": B.T_AXE, "shovel": B.T_SHOVEL, "sword": B.T_SWORD, "hoe": B.T_HOE}
	for mat in ["wood", "stone", "iron", "gold", "diamond"]:
		for kind in ["pickaxe", "axe", "shovel", "sword", "hoe"]:
			var key: String = ("wooden" if mat == "wood" else mat) + "_" + kind
			if mat == "gold": key = "golden_" + kind
			_add_item(key, {"stack": 1, "tool": ttype[kind], "tier": TOOL_TIERS[mat], "speed": TOOL_SPEED[mat],
				"damage": TOOL_DMG[kind] + MAT_DMG[mat] + (1.0 if kind == "sword" else 0.0), "durability": TOOL_DUR[mat],
				"icon_tool": [kind, mat]})
	for mat in ["leather", "iron", "gold", "diamond"]:
		for i in 4:
			var key2: String = ("golden" if mat == "gold" else mat) + "_" + ARMOR_PIECES[i]
			_add_item(key2, {"stack": 1, "armor_slot": i, "armor": ARMOR_PTS[mat][i], "durability": ARMOR_DUR[mat] * (i + 2) / 4,
				"icon_armor": [ARMOR_PIECES[i], mat]})
	# fuel (seconds)
	fuel = {"coal": 80.0, "charcoal": 80.0, "coal_block": 800.0, "oak_log": 15.0, "birch_log": 15.0, "pine_log": 15.0,
		"oak_planks": 15.0, "birch_planks": 15.0, "pine_planks": 15.0, "stick": 5.0, "workbench": 15.0, "chest": 15.0,
		"ladder": 15.0, "bookshelf": 15.0, "lava_bucket": 1000.0, "oak_sapling": 5.0, "birch_sapling": 5.0,
		"pine_sapling": 5.0, "wooden_pickaxe": 10.0, "wooden_axe": 10.0, "wooden_shovel": 10.0, "wooden_sword": 10.0,
		"wooden_hoe": 10.0, "bow": 10.0, "hay": 20.0, "bowl": 5.0}
	smelting = {"iron_ore": ["iron_ingot", 1], "gold_ore": ["gold_ingot", 1], "sand": ["glass", 1], "red_sand": ["glass", 1],
		"cobble": ["stone", 1], "raw_steak": ["cooked_steak", 1], "raw_pork": ["cooked_pork", 1], "raw_fowl": ["cooked_fowl", 1],
		"raw_fish": ["cooked_fish", 1], "raw_hare": ["cooked_hare", 1], "clay_ball": ["brick", 1], "oak_log": ["charcoal", 1],
		"birch_log": ["charcoal", 1], "pine_log": ["charcoal", 1], "clay": ["terracotta", 1], "stone": ["polished_stone", 1],
		"diamond_ore": ["diamond", 1], "coal_ore": ["coal", 1], "luminite_ore": ["luminite_shard", 2], "sandstone": ["smooth_sandstone", 1],
		"shale": ["shale_bricks", 1]}

func id_of(key: String) -> int:
	return item_ids.get(key, 0)

func item(id: int) -> Dictionary:
	if id <= 0 or id >= items.size() or items[id] == null:
		return {}
	return items[id]

func key_of(id: int) -> String:
	var d := item(id)
	return d.get("key", "")

func max_stack(id: int) -> int:
	return item(id).get("stack", 64)

func item_name(id: int) -> String:
	var k := key_of(id)
	return Locale.t("item." + k)

# ===================================================================== recipes
## Tags: "#planks", "#log", "#wool"
const TAGS := {
	"#planks": ["oak_planks", "birch_planks", "pine_planks"],
	"#log": ["oak_log", "birch_log", "pine_log"],
	"#wool": ["wool_white", "wool_red", "wool_blue", "wool_yellow", "wool_green", "wool_black"],
	"#stone": ["cobble", "shale"],
	"#coal": ["coal", "charcoal"],
}

func _shaped(out: String, count: int, pattern: Array, keys: Dictionary) -> void:
	recipes.append({"out": out, "count": count, "pattern": pattern, "keys": keys})

func _shapeless(out: String, count: int, ingr: Array) -> void:
	recipes.append({"out": out, "count": count, "shapeless": ingr})

func _define_recipes() -> void:
	_shapeless("oak_planks", 4, ["oak_log"])
	_shapeless("birch_planks", 4, ["birch_log"])
	_shapeless("pine_planks", 4, ["pine_log"])
	_shaped("stick", 4, ["P", "P"], {"P": "#planks"})
	_shaped("workbench", 1, ["PP", "PP"], {"P": "#planks"})
	_shaped("torch", 4, ["C", "S"], {"C": "#coal", "S": "stick"})
	_shaped("chest", 1, ["PPP", "P P", "PPP"], {"P": "#planks"})
	_shaped("furnace", 1, ["CCC", "C C", "CCC"], {"C": "#stone"})
	_shaped("ladder", 3, ["S S", "SSS", "S S"], {"S": "stick"})
	_shaped("oak_door", 3, ["PP", "PP", "PP"], {"P": "#planks"})
	_shaped("bedroll", 1, ["WWW", "PPP"], {"W": "#wool", "P": "#planks"})
	_shaped("bookshelf", 1, ["PPP", "LLL", "PPP"], {"P": "#planks", "L": "leather"})
	_shaped("stone_bricks", 4, ["SS", "SS"], {"S": "stone"})
	_shaped("shale_bricks", 4, ["SS", "SS"], {"S": "shale"})
	_shaped("bricks", 1, ["BB", "BB"], {"B": "brick"})
	_shaped("sandstone", 1, ["SS", "SS"], {"S": "sand"})
	_shaped("clay", 1, ["CC", "CC"], {"C": "clay_ball"})
	_shaped("hay", 1, ["WWW", "WWW", "WWW"], {"W": "wheat"})
	_shapeless("wheat", 9, ["hay"])
	_shaped("wool_white", 1, ["SS", "SS"], {"S": "string"})
	_shapeless("wool_red", 1, ["wool_white", "flower_red"])
	_shapeless("wool_yellow", 1, ["wool_white", "flower_yellow"])
	_shapeless("wool_blue", 1, ["wool_white", "flower_blue"])
	_shapeless("wool_green", 1, ["wool_white", "cactus"])
	_shapeless("wool_black", 1, ["wool_white", "coal"])
	_shaped("mossy_cobble", 1, ["CM"], {"C": "cobble", "M": "glowmoss"})
	_shaped("mossy_stone_bricks", 1, ["CM"], {"C": "stone_bricks", "M": "glowmoss"})
	_shaped("iron_block", 1, ["III", "III", "III"], {"I": "iron_ingot"})
	_shaped("gold_block", 1, ["III", "III", "III"], {"I": "gold_ingot"})
	_shaped("diamond_block", 1, ["III", "III", "III"], {"I": "diamond"})
	_shaped("coal_block", 1, ["III", "III", "III"], {"I": "coal"})
	_shaped("luminite_block", 1, ["II", "II"], {"I": "luminite_shard"})
	_shapeless("iron_ingot", 9, ["iron_block"])
	_shapeless("gold_ingot", 9, ["gold_block"])
	_shapeless("diamond", 9, ["diamond_block"])
	_shapeless("coal", 9, ["coal_block"])
	_shaped("crystal_lamp", 1, ["PSP", "SLS", "PSP"], {"P": "#planks", "S": "stick", "L": "luminite_shard"})
	_shaped("bowl", 4, ["P P", " P "], {"P": "#planks"})
	_shapeless("mushroom_stew", 1, ["bowl", "mushroom", "mushroom"])
	_shaped("bread", 1, ["WWW"], {"W": "wheat"})
	_shaped("bucket", 1, ["I I", " I "], {"I": "iron_ingot"})
	_shaped("bow", 1, [" SX", "S X", " SX"], {"S": "stick", "X": "string"})
	_shaped("arrow", 4, ["F", "S", "E"], {"F": "flint", "S": "stick", "E": "feather"})
	_shaped("fishing_rod", 1, ["  S", " SX", "S X"], {"S": "stick", "X": "string"})
	_shapeless("ember_striker", 1, ["iron_ingot", "flint"])
	_shaped("shears", 1, [" I", "I "], {"I": "iron_ingot"})
	_shaped("smooth_sandstone", 4, ["SS", "SS"], {"S": "sandstone"})
	var mats := {"wood": "#planks", "stone": "#stone", "iron": "iron_ingot", "gold": "gold_ingot", "diamond": "diamond"}
	for mat in mats:
		var pre: String = "wooden" if mat == "wood" else ("golden" if mat == "gold" else mat)
		var m: String = mats[mat]
		_shaped(pre + "_pickaxe", 1, ["MMM", " S ", " S "], {"M": m, "S": "stick"})
		_shaped(pre + "_axe", 1, ["MM", "MS", " S"], {"M": m, "S": "stick"})
		_shaped(pre + "_shovel", 1, ["M", "S", "S"], {"M": m, "S": "stick"})
		_shaped(pre + "_sword", 1, ["M", "M", "S"], {"M": m, "S": "stick"})
		_shaped(pre + "_hoe", 1, ["MM", " S", " S"], {"M": m, "S": "stick"})
	var amats := {"leather": "leather", "iron": "iron_ingot", "gold": "gold_ingot", "diamond": "diamond"}
	for mat in amats:
		var pre2: String = "golden" if mat == "gold" else mat
		var m2: String = amats[mat]
		_shaped(pre2 + "_helmet", 1, ["MMM", "M M"], {"M": m2})
		_shaped(pre2 + "_chestplate", 1, ["M M", "MMM", "MMM"], {"M": m2})
		_shaped(pre2 + "_leggings", 1, ["MMM", "M M", "M M"], {"M": m2})
		_shaped(pre2 + "_boots", 1, ["M M", "M M"], {"M": m2})
	# validate: every referenced key must exist
	for r in recipes:
		assert(item_ids.has(r["out"]), "recipe output missing: " + r["out"])

func _matches(key: String, pat: String) -> bool:
	if pat.begins_with("#"):
		return key in TAGS[pat]
	return key == pat

## grid: Array of item ids (0 = empty), width w (2 or 3). Returns {out:id,count:int} or {}.
func match_recipe(grid: Array, w: int) -> Dictionary:
	var h := grid.size() / w
	# bounding box of non-empty cells
	var minx := w; var miny := h; var maxx := -1; var maxy := -1
	var ids: Array = []
	for y in h:
		for x in w:
			if grid[y * w + x] > 0:
				minx = mini(minx, x); maxx = maxi(maxx, x); miny = mini(miny, y); maxy = maxi(maxy, y)
				ids.append(grid[y * w + x])
	if maxx < 0:
		return {}
	var bw := maxx - minx + 1; var bh := maxy - miny + 1
	for r in recipes:
		if r.has("shapeless"):
			var need: Array = r["shapeless"].duplicate()
			if need.size() != ids.size():
				continue
			var ok := true
			for iid in ids:
				var k := key_of(iid)
				var found := -1
				for j in need.size():
					if _matches(k, need[j]):
						found = j; break
				if found < 0:
					ok = false; break
				need.remove_at(found)
			if ok:
				return {"out": id_of(r["out"]), "count": r["count"]}
		else:
			var pat: Array = r["pattern"]
			var ph := pat.size()
			var pw := 0
			for row in pat: pw = maxi(pw, row.length())
			if pw != bw or ph != bh:
				continue
			for mirror in [false, true]:
				var ok2 := true
				for y in ph:
					for x in pw:
						var px := (pw - 1 - x) if mirror else x
						var row2: String = pat[y]
						var ch := row2[px] if px < row2.length() else " "
						var cell: int = grid[(miny + y) * w + (minx + x)]
						if ch == " ":
							if cell != 0: ok2 = false
						else:
							if cell == 0 or not _matches(key_of(cell), r["keys"][ch]): ok2 = false
						if not ok2: break
					if not ok2: break
				if ok2:
					return {"out": id_of(r["out"]), "count": r["count"]}
	return {}

# ===================================================================== icons
func _build_icons() -> void:
	for d in items:
		if d == null:
			continue
		var id: int = d["id"]
		var img: Image
		var flat: Image
		if d.has("icon_tool"):
			flat = Icons.tool_icon(d["icon_tool"][0], d["icon_tool"][1])
		elif d.has("icon_armor"):
			flat = Icons.armor_icon(d["icon_armor"][0], d["icon_armor"][1])
		elif id < B.COUNT:
			var r: int = b_render[id]
			var t: PackedInt32Array = b_tex[id]
			if r == B.R_CROSS or id in [B.TORCH, B.LADDER]:
				flat = layer_images[t[2]]
			else:
				var front: int = b_front[id] if b_front[id] >= 0 else t[4]
				img = TexGen.iso_icon(layer_images[t[2]], layer_images[t[0]], layer_images[front])
				flat = layer_images[front]
		else:
			flat = Icons.icon(d["key"])
		icon_images[id] = flat
		if img == null:
			img = flat.duplicate()
			img.resize(32, 32, Image.INTERPOLATE_NEAREST)
		icons[id] = ImageTexture.create_from_image(img)

func icon(id: int) -> Texture2D:
	return icons.get(id, null)

## Seconds to break a block with the given held item id.
func break_time(block: int, held: int) -> float:
	var hard: float = b_hardness[block]
	if hard < 0.0:
		return INF
	if hard == 0.0:
		return 0.05
	var it := item(held)
	var speed := 1.0
	var tier: int = it.get("tier", 0)
	var correct: bool = it.get("tool", -1) == b_tool[block] and b_tool[block] != B.T_NONE
	if correct:
		speed = it.get("speed", 1.0)
	elif it.get("tool", -1) == B.T_SWORD and b_sway[block] == 1:
		speed = 1.5
	elif it.get("kind", "") == "shears" and (b_sway[block] == 1 or b_name[block].begins_with("wool")):
		speed = 5.0
	var can_drop := b_tier[block] == 0 or (correct and tier >= b_tier[block])
	if not can_drop:
		return hard * 5.0
	return hard * 1.5 / speed

func can_harvest(block: int, held: int) -> bool:
	if b_tier[block] == 0:
		return true
	var it := item(held)
	return it.get("tool", -1) == b_tool[block] and it.get("tier", 0) >= b_tier[block]

## Returns Array of [item_id, count] dropped when a block is broken.
func drops(block: int, meta: int, held: int, rng: RandomNumberGenerator) -> Array:
	if not can_harvest(block, held):
		return []
	var shears: bool = item(held).get("kind", "") == "shears"
	match block:
		B.OAK_LEAVES, B.BIRCH_LEAVES, B.PINE_LEAVES:
			if shears:
				return [[block, 1]]
			var out: Array = []
			if rng.randf() < 0.06:
				var sap: int = {B.OAK_LEAVES: B.OAK_SAPLING, B.BIRCH_LEAVES: B.BIRCH_SAPLING, B.PINE_LEAVES: B.PINE_SAPLING}[block]
				out.append([sap, 1])
			if block == B.OAK_LEAVES and rng.randf() < 0.02:
				out.append([id_of("apple"), 1])
			if rng.randf() < 0.04:
				out.append([id_of("stick"), 1])
			return out
		B.TALL_GRASS, B.REEDS:
			if shears:
				return [[block, 1]]
			if block == B.TALL_GRASS and rng.randf() < 0.14:
				return [[id_of("seeds"), 1]]
			return []
		B.GRAVEL:
			if rng.randf() < 0.12:
				return [[id_of("flint"), 1]]
			return [[block, 1]]
		B.WHEAT:
			if meta >= 7:
				return [[id_of("wheat"), 1], [id_of("seeds"), rng.randi_range(1, 3)]]
			return [[id_of("seeds"), 1]]
		B.CLAY:
			return [[id_of("clay_ball"), 4]]
		B.LUMINITE_ORE:
			return [[id_of("luminite_shard"), rng.randi_range(2, 3)]]
		B.CRYSTAL_CLUSTER:
			return [[id_of("luminite_shard"), rng.randi_range(1, 2)]]
		B.DEAD_BUSH:
			return [[id_of("stick"), rng.randi_range(0, 2)]]
		B.ICE:
			return []
		B.DOOR_UPPER:
			return [] # the lower half drops the door
		B.WOOL_WHITE, B.WOOL_RED, B.WOOL_BLUE, B.WOOL_YELLOW, B.WOOL_GREEN, B.WOOL_BLACK:
			return [[block, 1]]
	var k: String = b_item[block]
	if k == "":
		return []
	return [[id_of(k), 1]]
