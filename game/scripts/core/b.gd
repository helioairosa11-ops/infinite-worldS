class_name B
## Block id constants and world dimension constants.

const CHUNK := 16
const HEIGHT := 128
const SEA := 56
const SECTION := 16
const SECTIONS := 8

const AIR := 0
const BEDROCK := 1
const STONE := 2
const DIRT := 3
const GRASS := 4
const SAND := 5
const GRAVEL := 6
const SANDSTONE := 7
const CLAY := 8
const SNOW_GRASS := 9
const ICE := 10
const WATER := 11
const LAVA := 12
const OAK_LOG := 13
const OAK_LEAVES := 14
const BIRCH_LOG := 15
const BIRCH_LEAVES := 16
const PINE_LOG := 17
const PINE_LEAVES := 18
const CACTUS := 19
const OAK_PLANKS := 20
const BIRCH_PLANKS := 21
const PINE_PLANKS := 22
const COBBLE := 23
const MOSSY_COBBLE := 24
const STONE_BRICKS := 25
const BRICKS := 26
const GLASS := 27
const COAL_ORE := 28
const IRON_ORE := 29
const GOLD_ORE := 30
const DIAMOND_ORE := 31
const LUMINITE_ORE := 32
const LUMINITE_BLOCK := 33
const IRON_BLOCK := 34
const GOLD_BLOCK := 35
const DIAMOND_BLOCK := 36
const WORKBENCH := 37
const FURNACE := 38
const FURNACE_LIT := 39
const CHEST := 40
const TORCH := 41
const DOOR_LOWER := 42
const DOOR_UPPER := 43
const BEDROLL := 44
const FARMLAND := 45
const WHEAT := 46
const TALL_GRASS := 47
const FLOWER_RED := 48
const FLOWER_YELLOW := 49
const DEAD_BUSH := 50
const MUSHROOM := 51
const WOOL_WHITE := 52
const WOOL_RED := 53
const WOOL_BLUE := 54
const WOOL_YELLOW := 55
const WOOL_GREEN := 56
const WOOL_BLACK := 57
const LADDER := 58
const BOOKSHELF := 59
const SHALE := 60
const SHALE_BRICKS := 61
const MUD := 62
const OBSIDIAN := 63
const HAY := 64
const CRYSTAL_LAMP := 65
const RED_SAND := 66
const TERRACOTTA := 67
const TERRACOTTA_ORANGE := 68
const TERRACOTTA_BROWN := 69
const MOSSY_STONE_BRICKS := 70
const FIRE := 71
const SNOW := 72
const GLOWCAP := 73
const CRYSTAL_CLUSTER := 74
const POLISHED_STONE := 75
const SMOOTH_SANDSTONE := 76
const REEDS := 77
const FLOWER_BLUE := 78
const COAL_BLOCK := 79
const GLOWMOSS := 80
const OAK_SAPLING := 81
const BIRCH_SAPLING := 82
const PINE_SAPLING := 83
const COUNT := 84

# render types
const R_NONE := 0
const R_CUBE := 1
const R_CROSS := 2
const R_LIQUID := 3
const R_BOX := 4
const R_CUTOUT := 5 # leaves / glass: cube with alpha

# tool types
const T_NONE := 0
const T_PICK := 1
const T_AXE := 2
const T_SHOVEL := 3
const T_HOE := 4
const T_SWORD := 5

static func idx(x: int, y: int, z: int) -> int:
	return x + (z << 4) + (y << 8)
