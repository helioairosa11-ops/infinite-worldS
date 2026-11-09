class_name Icons
## Item icon art (16x16). Tools are drawn procedurally from shared shapes so every
## material tier lines up; other items use ASCII sprite templates.
## Template roles: o=outline, d=dark, m=mid, l=light, w=highlight, h/H=handle, x=accent

const MATS := {
	"wood": ["#5c4224", "#8f6c41", "#b08955", "#c9a26a"],
	"stone": ["#4a4c50", "#7a7c80", "#95979b", "#b0b2b6"],
	"iron": ["#5e6266", "#c4c7cc", "#dde0e4", "#ffffff"],
	"gold": ["#8a6410", "#e6b52c", "#fbd650", "#fff3a8"],
	"diamond": ["#1d6f6a", "#4fd6d0", "#8ff0ea", "#e8fffd"],
	"leather": ["#4a2c18", "#8a5530", "#a8693d", "#c9875a"],
	"luminite": ["#3d1f8a", "#9c6cf5", "#c3a6ff", "#f4ecff"],
}

static func _p(img: Image, x: int, y: int, c: Variant) -> void:
	if x >= 0 and y >= 0 and x < 16 and y < 16:
		img.set_pixel(x, y, Color(c))

static func _diag_handle(img: Image, from_i: int, to_i: int) -> void:
	# 2px handle running from bottom-left toward top-right
	for i in range(from_i, to_i):
		_p(img, 1 + i, 14 - i, "#4a3420")
		_p(img, 2 + i, 14 - i, "#8f6c41")
		_p(img, 1 + i, 13 - i, "#3a2716")

static func tool_icon(kind: String, mat: String) -> Image:
	var c: Array = MATS.get(mat, MATS["iron"])
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	match kind:
		"pickaxe":
			_diag_handle(img, 0, 10)
			# curved head perpendicular to handle around (10,5)
			for t10 in range(-10, 11):
				var t := t10 / 10.0
				# perpendicular to the handle (direction (1,1)), bowed outward
				var px := 10.0 + t * 5.0 + (1.0 - t * t) * 1.5
				var py := 5.0 + t * 5.0 - (1.0 - t * t) * 1.5
				var ix := int(round(px)); var iy := int(round(py))
				_p(img, ix, iy, c[2]); _p(img, ix - 1, iy, c[1]); _p(img, ix, iy + 1, c[0])
				if absf(t) < 0.5: _p(img, ix + 1, iy - 1, c[3])
		"axe":
			_diag_handle(img, 0, 11)
			for y in range(1, 8):
				for x in range(5, 12):
					var dx := x - 8.0; var dy := y - 4.0
					if dx * dx * 0.6 + dy * dy < 11.0 and x + y < 16 and x - y < 10:
						var shade: String = c[1]
						if x + y < 9: shade = c[3]
						elif x + y < 11: shade = c[2]
						elif y > 5: shade = c[0]
						_p(img, x, y, shade)
			_p(img, 9, 5, "#4a3420"); _p(img, 10, 4, "#8f6c41")
		"shovel":
			_diag_handle(img, 0, 9)
			for y in range(0, 8):
				for x in range(8, 16):
					var dx := x - 11.5; var dy := y - 3.5
					var r := (dx + dy) * (dx + dy) * 0.18 + (dx - dy) * (dx - dy) * 0.5
					if r < 6.0:
						var sh: Variant = c[1]
						if dx - dy < -1.5: sh = c[3]
						elif dx - dy < 0: sh = c[2]
						elif dx - dy > 2: sh = c[0]
						_p(img, x, y, sh)
		"sword":
			for i in range(0, 10):
				_p(img, 5 + i, 10 - i, c[2]); _p(img, 6 + i, 10 - i, c[1]); _p(img, 5 + i, 9 - i, c[3])
				_p(img, 6 + i, 11 - i, c[0])
			_p(img, 15, 0, c[3])
			# guard
			for k in range(-2, 3):
				_p(img, 4 + k, 10 + k, "#3a2716"); _p(img, 5 + k, 11 + k, "#5c4224")
			# grip and pommel
			_p(img, 3, 12, "#8f6c41"); _p(img, 2, 13, "#5c4224"); _p(img, 1, 14, c[1]); _p(img, 0, 15, c[0])
		"hoe":
			_diag_handle(img, 0, 11)
			for i in range(0, 5):
				_p(img, 11 - i, 2, c[2]); _p(img, 11 - i, 3, c[0]); _p(img, 11 - i, 1, c[3])
			_p(img, 6, 4, c[0]); _p(img, 7, 4, c[1])
	return img

const T_HELMET := ["", "", "....oooooooo....", "...ollllllmmo...", "..olmmmmmmmmdo..", "..olmmmmmmmmdo..", "..omdddddddddo..", "..omo......odo..", "..omo......odo..", "..ooo......ooo.."]
const T_CHEST := ["", "..ooo......ooo..", ".olmmo....omddo.", ".olmmmooooommdo.", ".olmmmmmmmmmmdo.", "..oolmmmmmmdoo..", "....olmmmmdo....", "....olmmmmdo....", "....olmmmmdo....", "....olmmmmdo....", "....olmmmmdo....", "....oddddddo....", "....oooooooo...."]
const T_LEGS := ["", "", "...oooooooooo...", "...olmmmmmmdo...", "...olmmmmmmdo...", "...olmmoommdo...", "...olmo..omdo...", "...olmo..omdo...", "...olmo..omdo...", "...olmo..omdo...", "...olmo..omdo...", "...oddo..oddo...", "...oooo..oooo..."]
const T_BOOTS := ["", "", "", "", "", "", "...ooo....ooo...", "...olo....olo...", "...olo....olo...", "...omo....omo...", "..oomo....omoo..", ".olmmo....omddo.", ".odddo....odddo.", ".ooooo....ooooo."]
const T_INGOT := ["", "", "", "", "", ".....oooooo.....", "....olllllmo....", "...olmmmmmmdo...", "..olmmmmmmmmdo..", "..oddddddddddo..", "..oooooooooooo.."]
const T_GEM := ["", "", "", ".....oooooo.....", "....olwllmmo....", "...olwlmmmmdo...", "..oooooooooooo..", "...odmmmmmmdo...", "....odmmmmdo....", ".....odmmdo.....", "......oddo......", ".......oo......."]
const T_SHARD := ["", ".......oo.......", "......olmo......", "......olmo......", ".....olwmdo.....", ".....olmmdo.....", "....olwmmmdo....", "....olmmmmdo....", "....olmmmddo....", ".....olmmdo.....", ".....olmddo.....", "......omdo......", ".......oo......."]
const T_LUMP := ["", "", "", "", "......oooo......", "....oolmmdoo....", "...olmmmmmmdo...", "...olmmdmmmdo...", "..olmmmmmmmmdo..", "..odmmmmmdmddo..", "...oddmmmmddo...", "....ooddddoo....", "......oooo......"]
const T_MEAT := ["", "", "", "......oooo......", "....oollllo.....", "...olllmmmlo....", "..olmmmmmmmlo...", "..olmmwmmmmmo...", "..olmmmmmmmmdo..", "...olmmmmmmddo..", "....oommmmddo...", "......ooooddo...", "..........ooo..."]
const T_DRUM := ["", "", "..........oo....", ".........owwo...", "........owwo....", ".......owo......", "....ooolmo......", "...olllmmdo.....", "..olmmmmmdo.....", "..olmmmmddo.....", "..omdmmddo......", "...oddddo.......", "....oooo........"]
const T_FISH := ["", "", "", "", "", "....oooooo......", "...olllllloo..oo", "..olwollllmmoolo", "..olllllmmmmmmdo", "...odmmmmmmoodo.", "....oooooooo.oo."]
const T_BREAD := ["", "", "", "", "", "....ooooooooo...", "...ollwllwlllo..", "..olmmmmmmmmmdo.", "..olmmmmmmmmmdo.", "..odddddddddddo.", "...ooooooooooo.."]
const T_APPLE := ["", ".......oo.......", "........oho.....", "....ooo.oooo....", "...olllomlmmo...", "..olwllmmmmmdo..", "..olllmmmmmmdo..", "..olmmmmmmmmdo..", "..olmmmmmmmmdo..", "...ommmmmmmdo...", "...odmmmmmmdo...", "....oddoodddo...", ".....oo..ooo...."]
const T_WHEAT := ["", "......l..l......", ".....lml.lml....", "......l.l.l.....", ".....lmlmlml....", "......lll.l.....", ".......hhh......", ".......hhh......", "......h.h.h.....", "......h.h.h.....", ".....h..h..h....", ".....h..h..h....", "....h...h...h..."]
const T_SEEDS := ["", "", "", "", "", "", "......l...m.....", "....m...l...l...", "......m....m....", "...l....m.......", ".....l...l..m...", "........m......."]
const T_BOWL := ["", "", "", "", "", "", "..oooooooooooo..", "..oxxxxxxxxxxo..", "...olmmmmmmdo...", "....odmmmmdo....", ".....oooooo....."]
const T_BUCKET := ["", "", "....oooooooo....", "...o........o...", "..o..........o..", "..oooooooooooo..", "..oxxxxxxxxxxo..", "...olmmmmmmmo...", "...olmmmmmmdo...", "...olmmmmmmdo...", "....olmmmmdo....", "....oddddddo....", ".....oooooo....."]
const T_FEATHER := ["", "...........oo...", "..........olo...", ".........olwo...", "........olwlo...", ".......olwlo....", "......olwlo.....", ".....olwlo......", "....olwlo.......", "...olwlo........", "...owlo.........", "..oho...........", ".oh.............", "oh.............."]
const T_LEATHER := ["", "", "...oooo..oooo...", "..ollllooolllo..", "..olmmmmmmmmlo..", "...olmmmmmmdo...", "...olmmmmmmdo...", "..olmmmmmmmmdo..", "..olmmmmmmmmdo..", "..oddmmmmmmddo..", "...oooddddooo...", "......oooo......"]
const T_STRING := ["", "............ll..", "...........l....", "..........l.....", "..........l.....", ".........l......", "........l.......", ".......l........", "......l.........", ".....l..........", "....l...........", "....l...........", "...l............", "..l............."]
const T_BONE := ["", "............oo..", "...........owwo.", "..........owwwo.", "...........owo..", "..........owo...", ".........owo....", "........owo.....", ".......owo......", "......owo.......", ".....owo........", "..owwwo.........", ".owwwo..........", ".owwo...........", "..oo............"]
const T_DUST := ["", "", "", "", "", "", "", "......m.l.......", "....l..m..m.....", "...m.lmmlm.l....", "..l.mmlmmmlm....", "..mlmmmmmmmml...", ".dmmmmmmmmmmmd..", ".ddddddddddddd.."]
const T_EGG := ["", "", "", "......oooo......", ".....olllmo.....", "....olwllmmo....", "....olllmmmo....", "...olllmmmmdo...", "...ollmmmmmdo...", "...olmmmmmmdo...", "....ommmmmdo....", ".....oddddo.....", "......oooo......"]
const T_ARROW := ["", "..........oooo..", "...........llo..", "..........l.lo..", ".........h...o..", "........h.......", ".......h........", "......h.........", ".....h..........", "....h...........", "..wh............", ".wwh............", "..w.............", ""]
const T_BOW := ["", "......hhhh......", "....hh....x.....", "...h.....x......", "..h.....x.......", "..h....x........", ".h....x.........", ".h...x..........", ".h..x...........", ".h.x............", ".hx.............", "..h.............", "..h.............", "...h............"]
const T_ROD := ["", "............hh..", "...........hHx..", "..........hH.x..", ".........hH..x..", "........hH...x..", ".......hH....x..", "......hH.....x..", ".....hH......x..", "....hH.......x..", "...hH.......ooo.", "..hH........olo.", ".hH..........o..", "oH.............."]
const T_STRIKER := ["", "", "", "...oooo.........", "..olllmo........", ".olo..omo.......", ".olo...omo......", "..o....omo......", ".......omo......", "......omo.......", ".........xxx....", "........xxxxx...", ".........xxx....", ""]
const T_DOOR := ["", "....oooooooo....", "....olmmmmdo....", "....oxxooxxo....", "....oxxooxxo....", "....oooooooo....", "....olmmmmdo....", "....olmmmmdo....", "....olmmmwdo....", "....olmmmmdo....", "....olmmmmdo....", "....olmmmmdo....", "....oddddddo....", "....oooooooo...."]
const T_STEW := ["", "", "", "", "", "", "..oooooooooooo..", "..oxxlxxxlxxxo..", "...olmmmmmmdo...", "....odmmmmdo....", ".....oooooo....."]
const T_STICK := ["", "", "", "", "............ho..", "...........hH...", "..........hH....", ".........hH.....", "........hH......", ".......hH.......", "......hH........", ".....hH.........", "....hH..........", "...oh..........."]
const T_FLESH := ["", "", "", "......oooo......", "....oollllo.....", "...olllmmmlo....", "..olmmdmmmmlo...", "..olmmmmmdmmo...", "..olmdmmmmmmdo..", "...olmmmdmmddo..", "....oommmmddo...", "......ooooddo...", "..........ooo..."]
const T_SHEARS := ["", "", "...........oo...", "..........olo...", ".........olo....", "...oo...olo.....", "..olo..olo......", "...olollo.......", "....ollo........", "....hoho........", "...hh..hh.......", "..h.h..h.h......", "..hh....hh......", ""]
const T_BRICK := ["", "", "", "", "", "", ".....oooooo.....", "....olllllmo....", "...olmmmmmmdo...", "...oddddddddo...", "...oooooooooo..."]

static func p4(o: String, d: String, m: String, l: String, w: String = "#ffffff", x: String = "#000000", h: String = "#5c4224", H: String = "#8f6c41") -> Dictionary:
	return {"o": o, "d": d, "m": m, "l": l, "w": w, "x": x, "h": h, "H": H}

static func armor_icon(piece: String, mat: String) -> Image:
	var c: Array = MATS.get(mat, MATS["iron"])
	var t: Array = {"helmet": T_HELMET, "chestplate": T_CHEST, "leggings": T_LEGS, "boots": T_BOOTS}[piece]
	var p := p4(Color(c[0]).darkened(0.4).to_html(), c[0], c[1], c[2], c[3])
	return TexGen.from_ascii(t, p)

static func icon(key: String) -> Image:
	match key:
		"stick": return TexGen.from_ascii(T_STICK, p4("#2a1b10", "#3a2716", "#5c4224", "#8f6c41", "#b08955", "#000", "#5c4224", "#a07b4b"))
		"coal": return TexGen.from_ascii(T_LUMP, p4("#0c0c0e", "#141416", "#26262a", "#3d3d44"))
		"charcoal": return TexGen.from_ascii(T_LUMP, p4("#140c08", "#21150e", "#3a2618", "#55382a"))
		"iron_ingot": return TexGen.from_ascii(T_INGOT, p4("#4a4d52", "#8c9096", "#c4c7cc", "#e8eaee"))
		"gold_ingot": return TexGen.from_ascii(T_INGOT, p4("#6b4a08", "#b8860f", "#e6b52c", "#fde27a"))
		"brick": return TexGen.from_ascii(T_BRICK, p4("#4a1d14", "#7a2e22", "#a94c38", "#c86a52"))
		"diamond": return TexGen.from_ascii(T_GEM, p4("#14504c", "#2aa6a6", "#4fd6d0", "#8ff0ea", "#ffffff"))
		"luminite_shard": return TexGen.from_ascii(T_SHARD, p4("#2a1460", "#6d3fd1", "#9c6cf5", "#c3a6ff", "#ffffff"))
		"flint": return TexGen.from_ascii(T_SHARD, p4("#141416", "#26262a", "#3d3d44", "#5a5a62", "#8a8a92"))
		"clay_ball": return TexGen.from_ascii(T_LUMP, p4("#5a606a", "#7a808b", "#979da8", "#b5bbc6"))
		"leather": return TexGen.from_ascii(T_LEATHER, p4("#3a2010", "#6b3f22", "#8a5530", "#a8693d"))
		"feather": return TexGen.from_ascii(T_FEATHER, p4("#8a8a92", "#c8c8d0", "#e8e8ee", "#d0d0d8", "#ffffff", "#000", "#6b6b72"))
		"string": return TexGen.from_ascii(T_STRING, p4("#000", "#000", "#c8c8d0", "#e8e8ee"))
		"bone": return TexGen.from_ascii(T_BONE, p4("#8a8270", "#c8c0a8", "#d8d0bc", "#e8e2d0", "#f4f0e4"))
		"ember_dust": return TexGen.from_ascii(T_DUST, p4("#000", "#7a1606", "#e8501a", "#ffc23a"))
		"wheat": return TexGen.from_ascii(T_WHEAT, p4("#000", "#000", "#c99a1c", "#e8c34a", "#fff", "#000", "#6b8a33"))
		"seeds": return TexGen.from_ascii(T_SEEDS, p4("#000", "#000", "#4b8f34", "#9ab84d"))
		"apple": return TexGen.from_ascii(T_APPLE, p4("#4a0c0c", "#8a1616", "#c82828", "#e85a4a", "#ffc8c0", "#000", "#5c4224"))
		"bread": return TexGen.from_ascii(T_BREAD, p4("#4a2a10", "#8a5520", "#c08a3a", "#d8a855", "#f0d08a"))
		"raw_steak": return TexGen.from_ascii(T_MEAT, p4("#4a0c0c", "#8a2020", "#c23b3b", "#e86a6a", "#f4d0c0"))
		"cooked_steak": return TexGen.from_ascii(T_MEAT, p4("#2a140a", "#5a2e14", "#8a4a22", "#a8653a", "#d8b090"))
		"raw_pork": return TexGen.from_ascii(T_MEAT, p4("#5a2a2a", "#c8707a", "#e8909a", "#f4b0b8", "#fff0f0"))
		"cooked_pork": return TexGen.from_ascii(T_MEAT, p4("#3a1a0a", "#8a5a2a", "#b8804a", "#d8a06a", "#f0d0a0"))
		"raw_fowl": return TexGen.from_ascii(T_DRUM, p4("#5a3a3a", "#c8909a", "#e8b0b0", "#f4d0c8", "#ffffff"))
		"cooked_fowl": return TexGen.from_ascii(T_DRUM, p4("#3a1a0a", "#8a5a2a", "#c08a4a", "#d8a86a", "#f4f0e4"))
		"raw_fish": return TexGen.from_ascii(T_FISH, p4("#1a3a5a", "#3a6a8a", "#6a9aba", "#9ac8e0", "#ffffff"))
		"cooked_fish": return TexGen.from_ascii(T_FISH, p4("#3a2010", "#8a5a2a", "#b8804a", "#d8a06a", "#ffffff"))
		"raw_hare": return TexGen.from_ascii(T_DRUM, p4("#5a2a2a", "#a8606a", "#c88088", "#e8a8b0", "#ffffff"))
		"cooked_hare": return TexGen.from_ascii(T_DRUM, p4("#3a1a0a", "#7a4a1a", "#a8703a", "#c8905a", "#f4f0e4"))
		"egg": return TexGen.from_ascii(T_EGG, p4("#8a7a5a", "#c8b898", "#e0d4b8", "#f4ecd8", "#ffffff"))
		"hollow_flesh": return TexGen.from_ascii(T_FLESH, p4("#2a3020", "#4a5a30", "#6a7a40", "#8a9a5a", "#c0c890"))
		"bowl": return TexGen.from_ascii(T_BOWL, p4("#2a1b10", "#5c4224", "#8f6c41", "#b08955", "#fff", "#3a2716"))
		"mushroom_stew": return TexGen.from_ascii(T_STEW, p4("#2a1b10", "#5c4224", "#8f6c41", "#b08955", "#fff", "#a8703a"))
		"bucket": return TexGen.from_ascii(T_BUCKET, p4("#3a3d42", "#8c9096", "#c4c7cc", "#e8eaee", "#fff", "#3a3d42"))
		"water_bucket": return TexGen.from_ascii(T_BUCKET, p4("#3a3d42", "#8c9096", "#c4c7cc", "#e8eaee", "#fff", "#3a7ee0"))
		"lava_bucket": return TexGen.from_ascii(T_BUCKET, p4("#3a3d42", "#8c9096", "#c4c7cc", "#e8eaee", "#fff", "#ff7a1a"))
		"arrow": return TexGen.from_ascii(T_ARROW, p4("#3a3a3e", "#3a3a3e", "#8a8a92", "#b0b0b8", "#e8e8ee", "#000", "#8f6c41"))
		"bow": return TexGen.from_ascii(T_BOW, p4("#000", "#000", "#000", "#000", "#fff", "#e8e8ee", "#8f6c41"))
		"fishing_rod": return TexGen.from_ascii(T_ROD, p4("#a8a8b0", "#000", "#000", "#c82828", "#fff", "#e8e8ee", "#5c4224", "#8f6c41"))
		"ember_striker": return TexGen.from_ascii(T_STRIKER, p4("#3a3d42", "#8c9096", "#8c9096", "#c4c7cc", "#fff", "#3d3d44"))
		"oak_door": return TexGen.from_ascii(T_DOOR, p4("#3e2c18", "#5c4224", "#8f6c41", "#b08955", "#d8dbdf", "#9cc4ef"))
		"shears": return TexGen.from_ascii(T_SHEARS, p4("#3a3d42", "#8c9096", "#8c9096", "#e8eaee", "#fff", "#000", "#5c4224"))
	return TexGen.generate("missing")
