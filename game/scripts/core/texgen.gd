class_name TexGen
## Procedural 16x16 pixel-art texture generator. Every texture shares the same
## palette philosophy (3-5 tone ramps, clustered tileable noise, 1px accents) so the
## whole world keeps a single coherent art direction.

const S := 16

static func h(x: int, y: int, s: int) -> float:
	var n: int = (x * 374761393 + y * 668265263 + s * 1442695041) & 0xffffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0xffffffff
	n = n ^ (n >> 16)
	return float(n & 0xffff) / 65535.0

## Tileable value noise with given cell size (must divide 16).
static func vn(x: int, y: int, cell: int, s: int) -> float:
	var g := S / cell
	var fx := float(x) / cell
	var fy := float(y) / cell
	var x0 := int(floor(fx)); var y0 := int(floor(fy))
	var tx := fx - x0; var ty := fy - y0
	tx = tx * tx * (3.0 - 2.0 * tx); ty = ty * ty * (3.0 - 2.0 * ty)
	var a := h(posmod(x0, g), posmod(y0, g), s)
	var b := h(posmod(x0 + 1, g), posmod(y0, g), s)
	var c := h(posmod(x0, g), posmod(y0 + 1, g), s)
	var d := h(posmod(x0 + 1, g), posmod(y0 + 1, g), s)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)

static func noise(x: int, y: int, s: int) -> float:
	return vn(x, y, 8, s) * 0.35 + vn(x, y, 4, s + 1) * 0.35 + h(x, y, s + 2) * 0.3

static func pal(cols: Array, t: float) -> Color:
	t = clampf(t, 0.0, 0.9999)
	return Color(cols[int(t * cols.size())])

static func new_img() -> Image:
	return Image.create(S, S, false, Image.FORMAT_RGBA8)

static func fill_noise(img: Image, cols: Array, s: int, contrast := 1.0) -> void:
	for y in S:
		for x in S:
			var t := (noise(x, y, s) - 0.5) * contrast + 0.5
			img.set_pixel(x, y, pal(cols, t))

static func shade(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, c.a)

# ---------------------------------------------------------------- palettes
const STONE := ["#5d5f63", "#6c6e72", "#7a7c80", "#888a8e", "#95979b"]
const DIRT := ["#5a3d27", "#6b4a30", "#7a5638", "#8a6443", "#966f4c"]
const GRASS := ["#3f7d2c", "#4b8f34", "#58a03c", "#66b046", "#76bf52"]
const SAND := ["#cdb987", "#d8c592", "#e0cf9c", "#e8d8a8", "#efe1b4"]
const RSAND := ["#a3502a", "#b25d31", "#bf6a39", "#cb7743", "#d6854f"]
const GRAVEL := ["#5a5654", "#6e6a67", "#837e7a", "#97928d", "#aaa59f"]
const SNOWC := ["#d9e3ec", "#e3ebf2", "#ecf2f7", "#f4f8fb", "#ffffff"]
const OAKW := ["#6b4f2e", "#7d5d37", "#8f6c41", "#a07b4b", "#b08955"]
const BIRCHW := ["#b39e72", "#c2ae80", "#cfbd8f", "#dccb9d", "#e6d7ab"]
const PINEW := ["#4a3220", "#573c27", "#65472f", "#725237", "#7f5d40"]
const SHALEC := ["#34363d", "#3d4048", "#474a53", "#51545e", "#5b5f69"]

static func generate(name: String) -> Image:
	var s := name.hash() & 0xffff
	var img := new_img()
	match name:
		"stone":
			fill_noise(img, STONE, s, 1.2)
			_cracks(img, s, Color("#55575b"), 3)
		"polished_stone":
			fill_noise(img, ["#7d7f83", "#83858a", "#898b90"], s, 0.6)
			_frame(img, Color("#6a6c70"), Color("#9a9ca0"))
		"bedrock":
			fill_noise(img, ["#1e1e22", "#2c2c31", "#3a3a40", "#4a4a50", "#5c5c62"], s, 1.8)
		"dirt":
			fill_noise(img, DIRT, s, 1.2)
			_specks(img, s, Color("#a07a55"), 6)
			_specks(img, s + 9, Color("#4a3120"), 6)
		"farmland":
			fill_noise(img, ["#3e2a1a", "#4a3220", "#563b27"], s)
			for y in S:
				if y % 4 == 0:
					for x in S: img.set_pixel(x, y, Color("#33231a"))
		"mud":
			fill_noise(img, ["#3b2e26", "#45362c", "#4f3e33", "#59473a"], s, 1.0)
			_specks(img, s, Color("#6a5646"), 5)
		"clay":
			fill_noise(img, ["#8d939e", "#979da8", "#a1a7b2", "#abb1bc"], s, 0.9)
		"grass_top":
			fill_noise(img, GRASS, s, 1.3)
			_specks(img, s, Color("#85cc5e"), 8)
			_specks(img, s + 3, Color("#386f27"), 8)
		"grass_side":
			fill_noise(img, DIRT, s, 1.2)
			_specks(img, s + 9, Color("#4a3120"), 5)
			for x in S:
				var d := 3 + int(h(x, 0, s) * 3.0)
				for y in d:
					img.set_pixel(x, y, pal(GRASS, noise(x, y, s + 4)))
				img.set_pixel(x, d, Color("#386f27"))
		"snow":
			fill_noise(img, SNOWC, s, 0.8)
		"snow_side":
			fill_noise(img, DIRT, s, 1.2)
			for x in S:
				var d := 4 + int(h(x, 0, s) * 3.0)
				for y in d:
					img.set_pixel(x, y, pal(SNOWC, noise(x, y, s + 4)))
				img.set_pixel(x, d, Color("#b9c6d2"))
		"ice":
			fill_noise(img, ["#8fb8e8", "#9cc4ef", "#a9cff4", "#b8d9f8"], s, 0.8)
			for i in 3:
				var x0 := int(h(i, 1, s) * 16)
				for k in 6:
					img.set_pixel(posmod(x0 + k, 16), posmod(int(h(i, 2, s) * 16) + k, 16), Color("#d8ecff"))
			_alpha(img, 0.82)
		"sand":
			fill_noise(img, SAND, s, 1.0)
			_specks(img, s, Color("#b8a273"), 7)
		"red_sand":
			fill_noise(img, RSAND, s, 1.0)
			_specks(img, s, Color("#8c4223"), 7)
		"sandstone_top", "smooth_sandstone":
			fill_noise(img, SAND, s, 0.6)
			if name == "smooth_sandstone":
				_frame(img, Color("#c7b282"), Color("#efe1b4"))
		"sandstone_side":
			fill_noise(img, SAND, s, 0.7)
			for y in [3, 4, 10, 15]:
				for x in S:
					img.set_pixel(x, y, Color("#bea978") if y != 4 else Color("#efe1b4"))
		"gravel":
			_cells(img, GRAVEL, s, 9, Color("#4c4846"))
		"cobble":
			_cells(img, STONE, s, 7, Color("#46484c"))
		"mossy_cobble":
			_cells(img, STONE, s, 7, Color("#46484c"))
			_moss(img, s)
		"stone_bricks":
			_stone_bricks(img, s, STONE)
		"mossy_stone_bricks":
			_stone_bricks(img, s, STONE)
			_moss(img, s)
		"shale":
			fill_noise(img, SHALEC, s, 1.0)
			for y in S:
				if h(0, y, s) > 0.7:
					for x in S:
						if h(x, y, s + 1) > 0.3: img.set_pixel(x, y, Color("#2c2e34"))
		"shale_bricks":
			_stone_bricks(img, s, SHALEC)
		"bricks":
			for y in S:
				for x in S:
					var row := y / 4
					var off := 4 if row % 2 == 0 else 0
					var mortar := (y % 4 == 3) or ((x + off) % 8 == 7)
					if mortar:
						img.set_pixel(x, y, Color("#b5ab9d").darkened(h(x, y, s) * 0.15))
					else:
						var bid := (x + off) / 8 + row * 3
						var base := pal(["#8e3b2c", "#9c4332", "#a94c38", "#b4553f"], h(bid, row, s))
						img.set_pixel(x, y, shade(base, 0.9 + h(x, y, s) * 0.2))
		"obsidian":
			fill_noise(img, ["#120d1c", "#1a1328", "#231a35", "#2e2244", "#3d2d5a"], s, 1.6)
			_specks(img, s, Color("#6a4fa0"), 4)
		"oak_log": _log_side(img, s, OAKW, Color("#3e2c18"))
		"birch_log":
			fill_noise(img, ["#d9d4c8", "#e3dfd4", "#ece9e0", "#f5f3ec"], s, 0.8)
			for i in 9:
				var x0 := int(h(i, 0, s) * 16); var y0 := int(h(i, 1, s) * 16)
				var w := 2 + int(h(i, 2, s) * 3)
				for k in w: img.set_pixel(posmod(x0 + k, 16), y0, Color("#2b2a28"))
		"pine_log": _log_side(img, s, PINEW, Color("#2a1b10"))
		"oak_log_top": _log_top(img, s, OAKW, Color("#5c4224"))
		"birch_log_top": _log_top(img, s, BIRCHW, Color("#d9d4c8"))
		"pine_log_top": _log_top(img, s, PINEW, Color("#3a2716"))
		"oak_planks": _planks(img, s, OAKW)
		"birch_planks": _planks(img, s, BIRCHW)
		"pine_planks": _planks(img, s, PINEW)
		"oak_leaves": _leaves(img, s, ["#2d6420", "#377528", "#418530", "#4d9539", "#5aa443"])
		"birch_leaves": _leaves(img, s, ["#557f2a", "#618f31", "#6d9e38", "#7aab42", "#88b84d"])
		"pine_leaves": _leaves(img, s, ["#1f4a2c", "#265634", "#2e623c", "#376f45", "#417c4e"])
		"cactus_side":
			fill_noise(img, ["#2f6e2a", "#378032", "#3f8e39", "#48993f"], s, 0.8)
			for y in S:
				img.set_pixel(0, y, Color("#22521f")); img.set_pixel(15, y, Color("#22521f"))
				if y % 4 == 1:
					img.set_pixel(4, y, Color("#e8e2b0")); img.set_pixel(11, posmod(y + 2, 16), Color("#e8e2b0"))
		"cactus_top":
			fill_noise(img, ["#3f8e39", "#48993f", "#52a547"], s, 0.6)
			_frame(img, Color("#22521f"), Color("#5bb04f"))
		"glass":
			for y in S:
				for x in S:
					img.set_pixel(x, y, Color(0.8, 0.9, 1.0, 0.0))
			_frame(img, Color("#c7dfe8"), Color("#e9f6fb"))
			for k in 4:
				img.set_pixel(3 + k, 3 + k, Color(1, 1, 1, 0.7))
				img.set_pixel(9 + k / 2, 4 + k, Color(1, 1, 1, 0.5))
		"coal_ore": _ore(img, s, ["#1b1b1d", "#2a2a2e", "#3a3a3f"], STONE)
		"iron_ore": _ore(img, s, ["#a3785a", "#c29473", "#ddb393"], STONE)
		"gold_ore": _ore(img, s, ["#c99a1c", "#e8bd35", "#fbe17a"], STONE)
		"diamond_ore": _ore(img, s, ["#2aa6a6", "#4fd6d0", "#a6fff6"], STONE)
		"luminite_ore": _ore(img, s, ["#6d3fd1", "#9c6cf5", "#d8c2ff"], SHALEC)
		"coal_block": _metal_block(img, s, ["#151517", "#1f1f22", "#29292d", "#35353a"])
		"iron_block": _metal_block(img, s, ["#b9bcc0", "#c9ccd0", "#d8dbdf", "#e6e8eb"])
		"gold_block": _metal_block(img, s, ["#d39e1d", "#e6b52c", "#f4cb45", "#fde27a"])
		"diamond_block": _metal_block(img, s, ["#3cb7b0", "#55cfc7", "#74e3da", "#a6f6ef"])
		"luminite_block":
			_cells(img, ["#7a4ee0", "#8c5ff0", "#a57cf8", "#c3a6ff"], s, 6, Color("#5b34b8"))
		"crystal_lamp":
			_planks(img, s, PINEW)
			for y in range(3, 13):
				for x in range(3, 13):
					var t := 1.0 - (absf(x - 7.5) + absf(y - 7.5)) / 10.0
					img.set_pixel(x, y, Color("#b998ff").lerp(Color("#f4ecff"), t))
			_frame(img, Color("#2a1b10"), Color("#7f5d40"))
		"workbench_top":
			_planks(img, s, OAKW)
			_frame(img, Color("#4a3420"), Color("#b08955"))
			for i in 12:
				img.set_pixel(2 + i, 5, Color("#4a3420")); img.set_pixel(5, 2 + i, Color("#4a3420"))
		"workbench_side", "workbench_front":
			_planks(img, s, OAKW)
			for x in S:
				img.set_pixel(x, 0, Color("#4a3420")); img.set_pixel(x, 1, Color("#b08955"))
			if name == "workbench_front":
				# hanging tools: saw and hammer
				for y in range(3, 11): img.set_pixel(4, y, Color("#5c4224"))
				for x in range(2, 7): img.set_pixel(x, 3, Color("#8c8f94"))
				for y in range(3, 12): img.set_pixel(10, y, Color("#c4c7cc"))
				for y in range(3, 12): img.set_pixel(11, y, Color("#9a9da2") if y % 2 == 0 else Color("#c4c7cc"))
			else:
				for y in range(4, 14): img.set_pixel(8, y, Color("#5c4224"))
		"furnace_side", "furnace_top":
			_cells(img, STONE, s, 7, Color("#46484c"))
			if name == "furnace_top":
				_frame(img, Color("#46484c"), Color("#95979b"))
		"furnace_front", "furnace_front_lit":
			_cells(img, STONE, s, 7, Color("#46484c"))
			for y in range(8, 14):
				for x in range(3, 13):
					var c := Color("#141414")
					if name == "furnace_front_lit":
						var t := float(y - 8) / 6.0 + h(x, y, s) * 0.3
						c = Color("#ff4a12").lerp(Color("#ffd04a"), clampf(t, 0, 1))
					img.set_pixel(x, y, c)
			for x in range(2, 14):
				img.set_pixel(x, 7, Color("#3a3c40")); img.set_pixel(x, 14, Color("#3a3c40"))
			for x in range(3, 13): img.set_pixel(x, 4, Color("#3a3c40"))
		"chest_front", "chest_side", "chest_top":
			_planks(img, s, OAKW)
			_frame(img, Color("#3e2c18"), Color("#b08955"))
			if name != "chest_top":
				for x in S: img.set_pixel(x, 5, Color("#3e2c18"))
			if name == "chest_front":
				for y in range(4, 8):
					for x in range(7, 9): img.set_pixel(x, y, Color("#d8dbdf") if y != 7 else Color("#8c8f94"))
		"bookshelf":
			_planks(img, s, OAKW)
			var bcols := ["#7a2a24", "#2a4a7a", "#3f6a2a", "#7a6a2a", "#5a2a6a", "#2a6a6a"]
			for row in 2:
				var y0 := 2 + row * 7
				var x := 1
				while x < 15:
					var w := 1 + int(h(x, row, s) * 2.0)
					var c := Color(bcols[int(h(x, row + 5, s) * bcols.size()) % bcols.size()])
					var tall := 4 + int(h(x, row + 9, s) * 2.0)
					for xx in w:
						for yy in tall:
							if x + xx < 15: img.set_pixel(x + xx, y0 + 5 - yy, shade(c, 0.85 + 0.15 * float(xx)))
					x += w
				for xx in S: img.set_pixel(xx, y0 + 6, Color("#3e2c18"))
		"torch":
			for y in S:
				for x in S: img.set_pixel(x, y, Color(0, 0, 0, 0))
			for y in range(8, 16):
				img.set_pixel(7, y, Color("#6b4f2e")); img.set_pixel(8, y, Color("#8f6c41"))
			img.set_pixel(7, 6, Color("#ffd04a")); img.set_pixel(8, 6, Color("#fff2a8"))
			img.set_pixel(7, 7, Color("#ff8a1a")); img.set_pixel(8, 7, Color("#ffc23a"))
		"door_lower", "door_upper":
			_planks(img, s, OAKW)
			for y in S:
				img.set_pixel(0, y, Color("#4a3420")); img.set_pixel(15, y, Color("#4a3420"))
			if name == "door_upper":
				for x in S: img.set_pixel(x, 0, Color("#4a3420"))
				for y in range(3, 10):
					for x in range(3, 13):
						img.set_pixel(x, y, Color(0.75, 0.88, 1.0, 0.35) if (x != 7 and x != 8 and y != 6) else Color("#4a3420"))
			else:
				for x in S: img.set_pixel(x, 15, Color("#4a3420"))
				img.set_pixel(12, 2, Color("#d8dbdf")); img.set_pixel(12, 3, Color("#8c8f94"))
		"bedroll_top":
			for y in S:
				for x in S:
					var c := Color("#a8312c") if y > 5 else Color("#e8e4dc")
					img.set_pixel(x, y, shade(c, 0.9 + h(x, y, s) * 0.15))
			for x in S: img.set_pixel(x, 6, Color("#7a221f"))
		"bedroll_side":
			for y in S:
				for x in S:
					img.set_pixel(x, y, shade(Color("#a8312c") if y < 12 else Color("#6b4f2e"), 0.9 + h(x, y, s) * 0.15))
		"hay_top":
			fill_noise(img, ["#a8861c", "#bd9a25", "#cfad31", "#ddbd3f"], s)
			_frame(img, Color("#7a5f12"), Color("#e8cb55"))
		"hay_side":
			for y in S:
				for x in S:
					img.set_pixel(x, y, pal(["#a8861c", "#bd9a25", "#cfad31", "#ddbd3f"], h(x, y / 3, s)))
			for x in S:
				img.set_pixel(x, 4, Color("#6b4f2e")); img.set_pixel(x, 11, Color("#6b4f2e"))
		"terracotta": fill_noise(img, ["#8f5a44", "#98614a", "#a06850"], s, 0.6)
		"terracotta_orange": fill_noise(img, ["#b5612a", "#bf6a30", "#c87436"], s, 0.6)
		"terracotta_brown": fill_noise(img, ["#5a3a28", "#62402c", "#6a4630"], s, 0.6)
		"wool_white": _wool(img, s, Color("#e9ecec"))
		"wool_red": _wool(img, s, Color("#a83030"))
		"wool_blue": _wool(img, s, Color("#3546a3"))
		"wool_yellow": _wool(img, s, Color("#e6c532"))
		"wool_green": _wool(img, s, Color("#4f7a2a"))
		"wool_black": _wool(img, s, Color("#25252b"))
		"ladder":
			for y in S:
				for x in S: img.set_pixel(x, y, Color(0, 0, 0, 0))
			for y in S:
				for x in [2, 3, 12, 13]:
					img.set_pixel(x, y, pal(OAKW, h(x, y, s) * 0.6 + 0.2))
			for r in [2, 6, 10, 14]:
				for x in range(4, 12): img.set_pixel(x, r, pal(OAKW, h(x, r, s) * 0.5 + 0.4))
		"tall_grass": _plant_blades(img, s, GRASS, 7)
		"reeds": _plant_blades(img, s, ["#5c7a2a", "#6b8a33", "#7a9a3c", "#c9b77a"], 4)
		"dead_bush": _plant_blades(img, s, ["#6b4f2e", "#7d5d37", "#8f6c41"], 6)
		"flower_red": _flower(img, s, Color("#d22b2b"), Color("#ffd04a"))
		"flower_yellow": _flower(img, s, Color("#f0cf2a"), Color("#c46a12"))
		"flower_blue": _flower(img, s, Color("#3a7ee0"), Color("#f4f8fb"))
		"mushroom":
			_clear(img)
			for y in range(10, 16): img.set_pixel(7, y, Color("#e8e0cc")); img.set_pixel(8, y, Color("#d8d0bc"))
			for y in range(7, 10):
				for x in range(5 - (9 - y), 11 + (9 - y)):
					if x >= 0 and x < 16: img.set_pixel(x, y, Color("#9a6a44").lightened(h(x, y, s) * 0.2))
		"glowcap":
			_clear(img)
			for y in range(9, 16): img.set_pixel(7, y, Color("#bfe8ff")); img.set_pixel(8, y, Color("#9fd0f0"))
			for y in range(5, 9):
				for x in range(4 - (8 - y), 12 + (8 - y)):
					if x >= 0 and x < 16: img.set_pixel(x, y, Color("#3fd6e0").lightened(h(x, y, s) * 0.4))
			img.set_pixel(6, 6, Color("#e8ffff")); img.set_pixel(9, 7, Color("#e8ffff"))
		"crystal_cluster":
			_clear(img)
			for c in 4:
				var cx := 3 + int(h(c, 0, s) * 10.0)
				var ht := 6 + int(h(c, 1, s) * 8.0)
				for y in ht:
					var w := 1 if y > ht - 3 else 2
					for xx in w:
						img.set_pixel(clampi(cx + xx, 0, 15), 15 - y, Color("#9c6cf5").lerp(Color("#f0e6ff"), float(y) / ht))
		"glowmoss":
			fill_noise(img, ["#1d4a3a", "#256048", "#2f7a56", "#3fa070"], s, 1.2)
			_specks(img, s, Color("#9fffcf"), 9)
		"fire":
			_clear(img)
			for x in S:
				var ht := 6 + int(vn(x, 0, 4, s) * 9.0)
				for y in ht:
					var t := float(y) / ht
					img.set_pixel(x, 15 - y, Color("#ff3a0a").lerp(Color("#ffe27a"), 1.0 - t).lerp(Color("#ff8a1a"), t * 0.5))
		"water":
			for y in S:
				for x in S:
					var t := vn(x, y, 8, s) * 0.5 + vn(x, y, 4, s + 1) * 0.5
					var c := Color("#2a5fc4").lerp(Color("#4d8ae8"), t)
					if t > 0.7: c = c.lightened(0.2)
					c.a = 0.72
					img.set_pixel(x, y, c)
		"lava":
			for y in S:
				for x in S:
					var t := vn(x, y, 8, s) * 0.6 + vn(x, y, 4, s + 1) * 0.4
					var c := Color("#c2260c").lerp(Color("#ff9a1f"), t)
					if t > 0.72: c = Color("#ffe066")
					if t < 0.3: c = Color("#7a1606")
					img.set_pixel(x, y, c)
		_:
			if name.begins_with("wheat_"):
				_wheat(img, s, int(name.substr(6)))
			elif name.begins_with("destroy_"):
				_destroy(img, int(name.substr(8)))
			elif name.ends_with("_sapling"):
				var lc: Array = {"oak": ["#2d6420", "#418530", "#5aa443"], "birch": ["#557f2a", "#6d9e38", "#88b84d"], "pine": ["#1f4a2c", "#2e623c", "#417c4e"]}[name.get_slice("_", 0)]
				_clear(img)
				for y in range(9, 16): img.set_pixel(7, y, Color("#6b4f2e")); img.set_pixel(8, y, Color("#5a4026"))
				for y in range(2, 11):
					var w := 4 - absi(y - 6) / 2
					for x in range(8 - w, 8 + w):
						if h(x, y, s) > 0.25: img.set_pixel(x, y, pal(lc, h(x, y, s + 1)))
			else:
				fill_noise(img, ["#ff00ff", "#000000"], s)
	return img

# ---------------------------------------------------------------- helpers
static func _clear(img: Image) -> void:
	img.fill(Color(0, 0, 0, 0))

static func _alpha(img: Image, a: float) -> void:
	for y in S:
		for x in S:
			var c := img.get_pixel(x, y); c.a = a; img.set_pixel(x, y, c)

static func _specks(img: Image, s: int, c: Color, n: int) -> void:
	for i in n:
		img.set_pixel(int(h(i, 0, s) * 16), int(h(i, 1, s) * 16), c)

static func _cracks(img: Image, s: int, c: Color, n: int) -> void:
	for i in n:
		var x := int(h(i, 3, s) * 16); var y := int(h(i, 4, s) * 16)
		for k in 3 + int(h(i, 5, s) * 4):
			img.set_pixel(posmod(x, 16), posmod(y, 16), c)
			x += 1 if h(i, k, s) > 0.4 else 0
			y += 1 if h(k, i, s) > 0.5 else 0

static func _frame(img: Image, dark: Color, light: Color) -> void:
	for i in S:
		img.set_pixel(i, 0, light); img.set_pixel(0, i, light)
		img.set_pixel(i, 15, dark); img.set_pixel(15, i, dark)

static func _cells(img: Image, cols: Array, s: int, n: int, border: Color) -> void:
	var pts: Array = []
	for i in n:
		pts.append(Vector2(h(i, 0, s) * 16.0, h(i, 1, s) * 16.0))
	for y in S:
		for x in S:
			var best := 999.0; var second := 999.0; var bi := 0
			for i in n:
				for ox in [-16, 0, 16]:
					for oy in [-16, 0, 16]:
						var d := Vector2(x + 0.5, y + 0.5).distance_to(pts[i] + Vector2(ox, oy))
						if d < best:
							second = best; best = d; bi = i
						elif d < second:
							second = d
			if second - best < 1.1:
				img.set_pixel(x, y, border)
			else:
				var base := pal(cols, 0.15 + h(bi, 7, s) * 0.7)
				var hl := 1.08 if (pts[bi].x - x) + (pts[bi].y - y) > 1.0 else 0.95
				img.set_pixel(x, y, shade(base, hl * (0.95 + h(x, y, s) * 0.1)))

static func _moss(img: Image, s: int) -> void:
	for y in S:
		for x in S:
			if vn(x, y, 8, s + 50) > 0.58 and h(x, y, s + 51) > 0.25:
				img.set_pixel(x, y, pal(["#3f6a2a", "#4d7f33", "#5a913c"], h(x, y, s + 52)))

static func _stone_bricks(img: Image, s: int, cols: Array) -> void:
	for y in S:
		for x in S:
			var row := y / 8
			var off := 4 if row % 2 == 1 else 0
			var bx := (x + off) % 8
			var by := y % 8
			var c := pal(cols, 0.3 + noise(x, y, s) * 0.5)
			if by == 7 or bx == 7:
				c = shade(Color(cols[0]), 0.8)
			elif by == 0 or bx == 0:
				c = Color(cols[cols.size() - 1])
			img.set_pixel(x, y, c)

static func _log_side(img: Image, s: int, cols: Array, dark: Color) -> void:
	for y in S:
		for x in S:
			var t := vn(x, y, 4, s) * 0.3 + h(x, y / 4, s) * 0.5 + h(x, y, s + 1) * 0.2
			var c := pal(cols, t)
			if h(x, y / 3, s + 2) > 0.82: c = dark
			img.set_pixel(x, y, c)

static func _log_top(img: Image, s: int, cols: Array, bark: Color) -> void:
	for y in S:
		for x in S:
			var d := Vector2(x - 7.5, y - 7.5).length()
			var c: Color
			if x == 0 or y == 0 or x == 15 or y == 15:
				c = bark
			else:
				var ring := int(d + h(x, y, s) * 0.8) % 2
				c = pal(cols, 0.55 + 0.3 * ring - h(x, y, s) * 0.15)
			img.set_pixel(x, y, c)

static func _planks(img: Image, s: int, cols: Array) -> void:
	for y in S:
		for x in S:
			var board := y / 4
			var off := int(h(board, 0, s) * 16)
			var t := 0.35 + h(board, 1, s) * 0.3 + (vn(x, board * 4, 4, s) - 0.5) * 0.3 + (h(x, y, s) - 0.5) * 0.1
			var c := pal(cols, t)
			if y % 4 == 3: c = shade(Color(cols[0]), 0.75)
			elif (x + off) % 16 == 0: c = shade(Color(cols[0]), 0.8)
			elif y % 4 == 0: c = shade(c, 1.08)
			img.set_pixel(x, y, c)

static func _leaves(img: Image, s: int, cols: Array) -> void:
	for y in S:
		for x in S:
			var t := noise(x, y, s)
			if h(x, y, s + 7) < 0.2:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				var c := pal(cols, t)
				if h(x, y, s + 8) > 0.9: c = c.lightened(0.15)
				img.set_pixel(x, y, c)

static func _ore(img: Image, s: int, ore: Array, base: Array) -> void:
	fill_noise(img, base, s, 1.1)
	for b in 4 + int(h(0, 9, s) * 2):
		var cx := 2 + int(h(b, 0, s) * 12); var cy := 2 + int(h(b, 1, s) * 12)
		for k in 4:
			var px := cx + int(h(b, k + 2, s) * 3) - 1
			var py := cy + int(h(b, k + 7, s) * 3) - 1
			img.set_pixel(clampi(px, 0, 15), clampi(py, 0, 15), Color(ore[1]))
		img.set_pixel(clampi(cx, 0, 15), clampi(cy, 0, 15), Color(ore[2]))
		img.set_pixel(clampi(cx + 1, 0, 15), clampi(cy + 1, 0, 15), Color(ore[0]))

static func _metal_block(img: Image, s: int, cols: Array) -> void:
	fill_noise(img, cols, s, 0.5)
	_frame(img, shade(Color(cols[0]), 0.8), Color(cols[3]))
	for i in 4:
		img.set_pixel(2 + i, 2, Color(cols[3])); img.set_pixel(2, 2 + i, Color(cols[3]))

static func _wool(img: Image, s: int, c: Color) -> void:
	for y in S:
		for x in S:
			var f := 0.88 + noise(x, y, s) * 0.18
			if (x + y) % 4 == 0: f -= 0.05
			img.set_pixel(x, y, shade(c, f))

static func _plant_blades(img: Image, s: int, cols: Array, n: int) -> void:
	_clear(img)
	for b in n:
		var x := 1 + int(h(b, 0, s) * 14)
		var ht := 6 + int(h(b, 1, s) * 9)
		var lean := (h(b, 2, s) - 0.5) * 0.6
		for y in ht:
			var px := clampi(int(round(x + lean * y)), 0, 15)
			img.set_pixel(px, 15 - y, pal(cols, float(y) / ht * 0.8 + 0.1))

static func _flower(img: Image, s: int, petal: Color, center: Color) -> void:
	_plant_blades(img, s, GRASS, 2)
	for y in range(7, 16): img.set_pixel(7, y, Color("#3f7d2c"))
	img.set_pixel(8, 11, Color("#58a03c")); img.set_pixel(9, 10, Color("#58a03c"))
	for o in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1)]:
		img.set_pixel(7 + o.x, 5 + o.y, petal if abs(o.x) + abs(o.y) == 1 else shade(petal, 0.8))
	img.set_pixel(7, 5, center)

static func _wheat(img: Image, s: int, stage: int) -> void:
	_clear(img)
	var ht := 3 + stage * 12 / 7
	var ripe := stage >= 7
	for b in 6:
		var x := 1 + b * 3 % 15
		for y in ht:
			var c := Color("#58a03c").lerp(Color("#d8b63c"), float(stage) / 7.0)
			if ripe and y > ht - 4: c = Color("#c99a1c") if (y + b) % 2 == 0 else Color("#e8c34a")
			var off := 1 if (y % 3 == 0 and b % 2 == 0) else 0
			img.set_pixel(clampi(x + off, 0, 15), 15 - y, c)

static func _destroy(img: Image, stage: int) -> void:
	_clear(img)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var n := 2 + stage * 3
	for i in n:
		var x := rng.randi_range(2, 13); var y := rng.randi_range(2, 13)
		for k in 2 + stage / 2:
			img.set_pixel(clampi(x, 0, 15), clampi(y, 0, 15), Color(0, 0, 0, 0.55))
			x += rng.randi_range(-1, 1); y += rng.randi_range(-1, 1)

# ---------------------------------------------------------------- item icons
## Draw an icon from an ASCII template. Template chars map to palette roles.
static func from_ascii(rows: Array, palette: Dictionary) -> Image:
	var img := new_img()
	img.fill(Color(0, 0, 0, 0))
	for y in mini(rows.size(), 16):
		var r: String = rows[y]
		for x in mini(r.length(), 16):
			var ch := r[x]
			if palette.has(ch):
				img.set_pixel(x, y, Color(palette[ch]))
	return img

## Isometric block icon (32x32) composed from top/left/right face images.
static func iso_icon(top: Image, left: Image, right: Image) -> Image:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(16, 8)
	for py in 32:
		for px in 32:
			var p := Vector2(px + 0.5, py + 0.5)
			# top face: rhombus centered at (16,8): u along (+14,+7)/16, v along (-14,+7)/16
			var d := p - Vector2(16, 1)
			var u := (d.x / 14.0 + d.y / 7.0) * 0.5
			var v := (-d.x / 14.0 + d.y / 7.0) * 0.5
			if u >= 0 and u < 1 and v >= 0 and v < 1:
				img.set_pixel(px, py, top.get_pixel(int(u * 16), int(v * 16)))
				continue
			# left face
			var dl := p - Vector2(2, 8)
			var lu := dl.x / 14.0
			var lv := (dl.y - lu * 7.0) / 16.0
			if lu >= 0 and lu < 1 and lv >= 0 and lv < 1:
				var col := left.get_pixel(int(lu * 16), int(lv * 16))
				img.set_pixel(px, py, shade(col, 0.8))
				continue
			var dr := p - Vector2(16, 15)
			var ru := dr.x / 14.0
			var rv := (dr.y + ru * 7.0) / 16.0
			if ru >= 0 and ru < 1 and rv >= 0 and rv < 1:
				var col2 := right.get_pixel(int(ru * 16), int(rv * 16))
				img.set_pixel(px, py, shade(col2, 0.62))
	return img
