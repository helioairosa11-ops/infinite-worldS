class_name GameUI
extends CanvasLayer
## Complete UI system: Main Menu, World Creation/Selection, Multiplayer Menu,
## 4-Tab Settings (Graphics, Audio, Keybind Controls, Language), HUD (Hearts, Hunger,
## Armor, Oxygen, Hotbar, Boss Bar, F3 Debug, Chat), Inventory, 2x2 & 3x3 Crafting
## with Quick Recipe Book, Furnace, Chest, Pause Menu, and Death/Respawn screen.

signal start_singleplayer(meta: Dictionary)
signal host_multiplayer(meta: Dictionary, port: int)
signal join_multiplayer(ip: String, port: int)
signal quit_to_title

var world: VoxelWorld = null

# UI Screens
var main_menu_root: Control
var sp_panel: Control
var mp_panel: Control
var settings_panel: Control
var hud_root: Control
var inv_modal: Control
var pause_modal: Control
var death_modal: Control
var chat_box: Control

# State
var in_game: bool = false
var station_mode: String = "inv" # "inv", "workbench", "furnace", "chest"
var station_pos: Vector3i = Vector3i.ZERO
var craft_grid: Array = [] # 9 slots
var craft_out: Dictionary = {"id": 0, "count": 0, "dur": 0}
var waiting_key_action: String = ""
var waiting_key_btn: Button = null
var settings_return_to_pause: bool = false
var hud_visible: bool = true
var debug_visible: bool = false
var chat_open: bool = false

# Dynamic HUD widgets
var hotbar_slots: Array[Button] = []
var hp_bar: ProgressBar
var hp_label: Label
var hunger_bar: ProgressBar
var hunger_label: Label
var armor_label: Label
var oxy_bar: ProgressBar
var held_name_label: Label
var banner_label: Label
var banner_timer: float = 0.0
var debug_label: Label
var boss_bar_box: Control
var boss_bar: ProgressBar
var boss_name_lbl: Label
var chat_log: RichTextLabel
var chat_input: LineEdit
var cursor_preview: Control
var cursor_icon: TextureRect
var cursor_count: Label

# Inventory & Station widgets
var inv_title_lbl: Label
var inv_slot_btns: Array[Button] = []
var armor_slot_btns: Array[Button] = []
var craft_box: Control
var craft_slot_btns: Array[Button] = []
var craft_out_btn: Button
var recipe_list_vbox: VBoxContainer
var furnace_box: Control
var furnace_in_btn: Button
var furnace_fuel_btn: Button
var furnace_out_btn: Button
var furnace_prog_lbl: Label
var chest_box: Control
var chest_slot_btns: Array[Button] = []

# Singleplayer world list widgets
var world_list_vbox: VBoxContainer
var new_world_name: LineEdit
var new_world_seed: LineEdit
var new_world_mode: OptionButton
var mp_status_lbl: Label

func _ready() -> void:
	craft_grid.resize(9)
	for i in 9:
		craft_grid[i] = {"id": 0, "count": 0, "dur": 0}
	_build_all_ui()
	Settings.changed.connect(_refresh_texts)
	Net.chat_received.connect(_on_chat_received)
	Net.connection_status.connect(func(st: String) -> void:
		if mp_status_lbl != null: mp_status_lbl.text = st
	)
	show_main_menu()

func is_blocking_gameplay() -> bool:
	return not in_game or inv_modal.visible or pause_modal.visible or death_modal.visible or settings_panel.visible or chat_open

func _style_box(bg: Color, border: Color, radius: int = 6, bw: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(10)
	return sb

func _make_btn(txt: String, min_sz := Vector2(220, 42)) -> Button:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = min_sz
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_stylebox_override("normal", _style_box(Color("#252c3d"), Color("#4a5a78"), 5, 2))
	b.add_theme_stylebox_override("hover", _style_box(Color("#323e56"), Color("#7896c8"), 5, 2))
	b.add_theme_stylebox_override("pressed", _style_box(Color("#1b202c"), Color("#9ab8eb"), 5, 2))
	b.pressed.connect(func() -> void: Sfx.play_ui("click"))
	return b

func _make_slot_btn(sz: float = 52.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(sz, sz)
	b.add_theme_stylebox_override("normal", _style_box(Color(0.12, 0.14, 0.18, 0.92), Color("#465066"), 4, 2))
	b.add_theme_stylebox_override("hover", _style_box(Color(0.20, 0.24, 0.32, 0.95), Color("#8aa4d6"), 4, 2))
	b.add_theme_stylebox_override("pressed", _style_box(Color(0.10, 0.12, 0.16, 0.95), Color("#b2ccf8"), 4, 2))

	var tr := TextureRect.new()
	tr.name = "Icon"
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(tr)

	var lbl := Label.new()
	lbl.name = "Count"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	b.add_child(lbl)

	var dbar := ColorRect.new()
	dbar.name = "Dur"
	dbar.color = Color("#46e060")
	dbar.position = Vector2(5, sz - 7)
	dbar.size = Vector2(sz - 10, 3)
	dbar.visible = false
	dbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(dbar)
	return b

func _render_slot_btn(b: Button, slot: Dictionary, highlighted: bool = false) -> void:
	var tr: TextureRect = b.get_node("Icon")
	var lbl: Label = b.get_node("Count")
	var dbar: ColorRect = b.get_node("Dur")
	if highlighted:
		b.add_theme_stylebox_override("normal", _style_box(Color(0.24, 0.30, 0.42, 0.96), Color("#ffd25a"), 4, 3))
	else:
		b.add_theme_stylebox_override("normal", _style_box(Color(0.12, 0.14, 0.18, 0.92), Color("#465066"), 4, 2))
	var id: int = slot.get("id", 0)
	var cnt: int = slot.get("count", 0)
	var dur: int = slot.get("dur", 0)
	if id <= 0 or cnt <= 0:
		tr.texture = null
		lbl.text = ""
		dbar.visible = false
		b.tooltip_text = ""
		return
	tr.texture = Registry.icon(id)
	lbl.text = str(cnt) if cnt > 1 else ""
	b.tooltip_text = Registry.item_name(id)
	var max_d: int = Registry.item(id).get("durability", 0)
	if max_d > 0 and dur < max_d:
		dbar.visible = true
		var ratio := clampf(float(dur) / float(max_d), 0.0, 1.0)
		dbar.size.x = (b.custom_minimum_size.x - 10.0) * ratio
		dbar.color = Color("#e03c28").lerp(Color("#46e060"), ratio)
	else:
		dbar.visible = false

func _build_all_ui() -> void:
	_build_main_menu()
	_build_sp_panel()
	_build_mp_panel()
	_build_settings_panel()
	_build_hud()
	_build_inventory_modal()
	_build_pause_and_death()
	_build_cursor_item()

func _build_main_menu() -> void:
	main_menu_root = Control.new()
	main_menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main_menu_root)

	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.14, 0.38)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_menu_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_menu_root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(Color(0.11, 0.14, 0.21, 0.96), Color("#5c749e"), 10, 2))
	panel.custom_minimum_size = Vector2(460, 440)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("#7fd96a"))
	vbox.add_child(title)

	var sub := Label.new()
	sub.name = "Subtitle"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color("#b4c4dc"))
	vbox.add_child(sub)

	var btn_sp := _make_btn("")
	btn_sp.name = "BtnSP"
	btn_sp.pressed.connect(func() -> void:
		main_menu_root.visible = false
		_refresh_world_list()
		sp_panel.visible = true
	)
	vbox.add_child(btn_sp)

	var btn_mp := _make_btn("")
	btn_mp.name = "BtnMP"
	btn_mp.pressed.connect(func() -> void:
		main_menu_root.visible = false
		mp_panel.visible = true
	)
	vbox.add_child(btn_mp)

	var btn_set := _make_btn("")
	btn_set.name = "BtnSet"
	btn_set.pressed.connect(func() -> void:
		settings_return_to_pause = false
		main_menu_root.visible = false
		settings_panel.visible = true
	)
	vbox.add_child(btn_set)

	var btn_quit := _make_btn("")
	btn_quit.name = "BtnQuit"
	btn_quit.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(btn_quit)

func _build_sp_panel() -> void:
	sp_panel = CenterContainer.new()
	sp_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	sp_panel.visible = false
	add_child(sp_panel)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(Color(0.10, 0.13, 0.19, 0.96), Color("#5c749e"), 10, 2))
	panel.custom_minimum_size = Vector2(760, 520)
	sp_panel.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	panel.add_child(hbox)

	# Left: existing worlds list
	var left_v := VBoxContainer.new()
	left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_v.add_theme_constant_override("separation", 10)
	hbox.add_child(left_v)

	var w_lbl := Label.new()
	w_lbl.text = "Mundos Guardados / Saved Worlds"
	w_lbl.add_theme_font_size_override("font_size", 20)
	left_v.add_child(w_lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_v.add_child(scroll)

	world_list_vbox = VBoxContainer.new()
	world_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(world_list_vbox)

	# Right: create new world
	var right_v := VBoxContainer.new()
	right_v.custom_minimum_size = Vector2(300, 0)
	right_v.add_theme_constant_override("separation", 10)
	hbox.add_child(right_v)

	var nw_lbl := Label.new()
	nw_lbl.name = "LblNewWorld"
	nw_lbl.add_theme_font_size_override("font_size", 20)
	right_v.add_child(nw_lbl)

	new_world_name = LineEdit.new()
	new_world_name.text = "Novo Mundo"
	new_world_name.placeholder_text = "World Name"
	right_v.add_child(new_world_name)

	new_world_seed = LineEdit.new()
	new_world_seed.placeholder_text = "Seed (ex: 42891)"
	right_v.add_child(new_world_seed)

	new_world_mode = OptionButton.new()
	new_world_mode.add_item("Sobrevivência / Survival", 0)
	new_world_mode.add_item("Criativo / Creative", 1)
	right_v.add_child(new_world_mode)

	var btn_create := _make_btn("Criar e Jogar / Create")
	btn_create.pressed.connect(func() -> void:
		var s_txt := new_world_seed.text.strip_edges()
		var s_val := randi() if s_txt.is_empty() else (int(s_txt) if s_txt.is_valid_int() else s_txt.hash())
		var meta := WorldSave.create_world(new_world_name.text, s_val, new_world_mode.selected)
		sp_panel.visible = false
		start_singleplayer.emit(meta)
	)
	right_v.add_child(btn_create)

	var btn_back := _make_btn("Voltar / Back")
	btn_back.pressed.connect(func() -> void:
		sp_panel.visible = false
		main_menu_root.visible = true
	)
	right_v.add_child(btn_back)

func _refresh_world_list() -> void:
	for c in world_list_vbox.get_children():
		c.queue_free()
	var worlds := WorldSave.list_worlds()
	for w in worlds:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var play_b := _make_btn("%s  (Dia %d | Seed: %d)" % [w.get("name", "World"), int(w.get("days", 1)), int(w.get("seed", 0))], Vector2(260, 40))
		play_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var wid: String = w["id"]
		play_b.pressed.connect(func() -> void:
			sp_panel.visible = false
			start_singleplayer.emit(WorldSave.load_meta(wid))
		)
		row.add_child(play_b)

		var del_b := _make_btn("X", Vector2(42, 40))
		del_b.pressed.connect(func() -> void:
			WorldSave.delete_world(wid)
			_refresh_world_list()
		)
		row.add_child(del_b)
		world_list_vbox.add_child(row)

func _build_mp_panel() -> void:
	mp_panel = CenterContainer.new()
	mp_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	mp_panel.visible = false
	add_child(mp_panel)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(Color(0.10, 0.13, 0.19, 0.96), Color("#5c749e"), 10, 2))
	panel.custom_minimum_size = Vector2(460, 400)
	mp_panel.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "MULTIJOGADOR / MULTIPLAYER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var name_ed := LineEdit.new()
	name_ed.text = Settings.player_name
	name_ed.placeholder_text = "Nome do Jogador / Player Name"
	name_ed.text_changed.connect(func(t: String) -> void: Settings.player_name = t; Settings.save_settings())
	vbox.add_child(name_ed)

	var ip_ed := LineEdit.new()
	ip_ed.text = Settings.last_ip
	ip_ed.placeholder_text = "IP (127.0.0.1)"
	vbox.add_child(ip_ed)

	var port_ed := LineEdit.new()
	port_ed.text = "25565"
	port_ed.placeholder_text = "Port (25565)"
	vbox.add_child(port_ed)

	mp_status_lbl = Label.new()
	mp_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(mp_status_lbl)

	var btn_host := _make_btn("Alojar Mundo (Host)")
	btn_host.pressed.connect(func() -> void:
		var meta := WorldSave.create_world("Multiplayer World", randi(), 0)
		mp_panel.visible = false
		host_multiplayer.emit(meta, int(port_ed.text))
	)
	vbox.add_child(btn_host)

	var btn_join := _make_btn("Entrar no Servidor (Join)")
	btn_join.pressed.connect(func() -> void:
		Settings.last_ip = ip_ed.text
		Settings.save_settings()
		join_multiplayer.emit(ip_ed.text.strip_edges(), int(port_ed.text))
	)
	vbox.add_child(btn_join)

	var btn_back := _make_btn("Voltar / Back")
	btn_back.pressed.connect(func() -> void:
		mp_panel.visible = false
		main_menu_root.visible = true
	)
	vbox.add_child(btn_back)

func _build_settings_panel() -> void:
	settings_panel = CenterContainer.new()
	settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_panel.visible = false
	add_child(settings_panel)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(Color(0.10, 0.13, 0.19, 0.97), Color("#5c749e"), 10, 2))
	panel.custom_minimum_size = Vector2(720, 520)
	settings_panel.add_child(panel)

	var main_v := VBoxContainer.new()
	main_v.add_theme_constant_override("separation", 12)
	panel.add_child(main_v)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_v.add_child(tabs)

	# Tab 1: Graphics
	var g_vbox := VBoxContainer.new()
	g_vbox.name = "Gráficos / Graphics"
	g_vbox.add_theme_constant_override("separation", 10)
	tabs.add_child(g_vbox)
	_add_slider(g_vbox, "menu.render_distance", 4, 12, 1, Settings.render_distance, func(v: float) -> void: Settings.render_distance = int(v); Settings.apply())
	_add_slider(g_vbox, "menu.fov", 60, 110, 1, Settings.fov, func(v: float) -> void: Settings.fov = v; Settings.apply())
	_add_slider(g_vbox, "menu.sensitivity", 0.05, 1.0, 0.05, Settings.mouse_sensitivity, func(v: float) -> void: Settings.mouse_sensitivity = v; Settings.apply())
	_add_check(g_vbox, "menu.shadows", Settings.shadows, func(b: bool) -> void: Settings.shadows = b; Settings.apply())
	_add_check(g_vbox, "menu.vsync", Settings.vsync, func(b: bool) -> void: Settings.vsync = b; Settings.apply())
	_add_check(g_vbox, "menu.fullscreen", Settings.fullscreen, func(b: bool) -> void: Settings.fullscreen = b; Settings.apply())
	_add_check(g_vbox, "menu.clouds", Settings.clouds, func(b: bool) -> void: Settings.clouds = b; Settings.apply())
	_add_check(g_vbox, "menu.view_bobbing", Settings.view_bobbing, func(b: bool) -> void: Settings.view_bobbing = b; Settings.apply())

	# Tab 2: Audio
	var a_vbox := VBoxContainer.new()
	a_vbox.name = "Áudio / Audio"
	a_vbox.add_theme_constant_override("separation", 10)
	tabs.add_child(a_vbox)
	_add_slider(a_vbox, "menu.vol_master", 0.0, 1.0, 0.05, Settings.vol_master, func(v: float) -> void: Settings.vol_master = v; Settings.apply())
	_add_slider(a_vbox, "menu.vol_music", 0.0, 1.0, 0.05, Settings.vol_music, func(v: float) -> void: Settings.vol_music = v; Settings.apply())
	_add_slider(a_vbox, "menu.vol_sfx", 0.0, 1.0, 0.05, Settings.vol_sfx, func(v: float) -> void: Settings.vol_sfx = v; Settings.apply())
	_add_slider(a_vbox, "menu.vol_ambient", 0.0, 1.0, 0.05, Settings.vol_ambient, func(v: float) -> void: Settings.vol_ambient = v; Settings.apply())

	# Tab 3: Controls (keybinding)
	var c_scroll := ScrollContainer.new()
	c_scroll.name = "Controlos / Controls"
	tabs.add_child(c_scroll)
	var c_vbox := VBoxContainer.new()
	c_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c_vbox.add_theme_constant_override("separation", 6)
	c_scroll.add_child(c_vbox)
	_add_check(c_vbox, "menu.invert_y", Settings.invert_y, func(b: bool) -> void: Settings.invert_y = b; Settings.apply())
	for act in ["move_forward", "move_back", "move_left", "move_right", "jump", "sneak", "sprint", "inventory", "drop", "chat", "debug", "perspective"]:
		var row := HBoxContainer.new()
		var albl := Label.new()
		albl.text = Locale.t("ctrl." + act)
		albl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(albl)
		var kbtn := _make_btn(Settings.key_name(act), Vector2(140, 34))
		var bind_act: String = act
		kbtn.pressed.connect(func() -> void:
			waiting_key_action = bind_act
			waiting_key_btn = kbtn
			kbtn.text = Locale.t("menu.press_key")
		)
		row.add_child(kbtn)
		c_vbox.add_child(row)

	# Tab 4: Language
	var l_vbox := VBoxContainer.new()
	l_vbox.name = "Idioma / Language"
	l_vbox.add_theme_constant_override("separation", 12)
	tabs.add_child(l_vbox)
	for code in ["pt", "en"]:
		var b_lang := _make_btn(Locale.LANGS[code])
		var lc: String = code
		b_lang.pressed.connect(func() -> void:
			Settings.language = lc
			Settings.apply()
			Settings.save_settings()
		)
		l_vbox.add_child(b_lang)

	var btn_close := _make_btn("Guardar e Voltar / Save & Back")
	btn_close.pressed.connect(func() -> void:
		Settings.save_settings()
		settings_panel.visible = false
		if settings_return_to_pause:
			pause_modal.visible = true
		else:
			main_menu_root.visible = true
	)
	main_v.add_child(btn_close)

func _add_slider(parent: Node, label_key: String, min_v: float, max_v: float, step_v: float, cur_v: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "%s: %s" % [Locale.t(label_key), str(snappedf(cur_v, step_v))]
	lbl.custom_minimum_size = Vector2(280, 0)
	row.add_child(lbl)
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.value = cur_v
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(v: float) -> void:
		lbl.text = "%s: %s" % [Locale.t(label_key), str(snappedf(v, step_v))]
		cb.call(v)
	)
	row.add_child(sl)
	parent.add_child(row)

func _add_check(parent: Node, label_key: String, cur_v: bool, cb: Callable) -> void:
	var chk := CheckButton.new()
	chk.text = Locale.t(label_key)
	chk.button_pressed = cur_v
	chk.toggled.connect(cb)
	parent.add_child(chk)

func _build_hud() -> void:
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.visible = false
	add_child(hud_root)

	# Crosshair
	var ch_h := ColorRect.new()
	ch_h.color = Color(1, 1, 1, 0.85)
	ch_h.size = Vector2(16, 2)
	ch_h.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ch_h.position -= Vector2(8, 1)
	ch_h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(ch_h)

	var ch_v := ColorRect.new()
	ch_v.color = Color(1, 1, 1, 0.85)
	ch_v.size = Vector2(2, 16)
	ch_v.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ch_v.position -= Vector2(1, 8)
	ch_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(ch_v)

	# Bottom Hotbar + Survival Bars (centered across full width)
	var bot_wrap := CenterContainer.new()
	bot_wrap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot_wrap.offset_top = -138
	bot_wrap.offset_bottom = -12
	bot_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(bot_wrap)

	var bot_center := VBoxContainer.new()
	bot_center.alignment = BoxContainer.ALIGNMENT_END
	bot_center.add_theme_constant_override("separation", 6)
	bot_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bot_wrap.add_child(bot_center)

	held_name_label = Label.new()
	held_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	held_name_label.add_theme_font_size_override("font_size", 16)
	held_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	held_name_label.add_theme_constant_override("outline_size", 4)
	bot_center.add_child(held_name_label)

	var bars_row := HBoxContainer.new()
	bars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bars_row.add_theme_constant_override("separation", 18)
	bot_center.add_child(bars_row)

	hp_bar = ProgressBar.new()
	hp_bar.max_value = 20.0
	hp_bar.value = 20.0
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(180, 18)
	hp_bar.add_theme_stylebox_override("background", _style_box(Color("#2a1216"), Color("#5a2228"), 4, 1))
	hp_bar.add_theme_stylebox_override("fill", _style_box(Color("#e03434"), Color("#ff6868"), 4, 0))
	bars_row.add_child(hp_bar)

	hp_label = Label.new()
	hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_label.add_theme_font_size_override("font_size", 13)
	hp_bar.add_child(hp_label)

	armor_label = Label.new()
	armor_label.add_theme_font_size_override("font_size", 15)
	armor_label.add_theme_color_override("font_color", Color("#9ec4ff"))
	bars_row.add_child(armor_label)

	hunger_bar = ProgressBar.new()
	hunger_bar.max_value = 20.0
	hunger_bar.value = 20.0
	hunger_bar.show_percentage = false
	hunger_bar.custom_minimum_size = Vector2(180, 18)
	hunger_bar.add_theme_stylebox_override("background", _style_box(Color("#2a1c10"), Color("#5a3e22"), 4, 1))
	hunger_bar.add_theme_stylebox_override("fill", _style_box(Color("#d4842a"), Color("#f5b04c"), 4, 0))
	bars_row.add_child(hunger_bar)

	hunger_label = Label.new()
	hunger_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	hunger_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hunger_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hunger_label.add_theme_font_size_override("font_size", 13)
	hunger_bar.add_child(hunger_label)

	oxy_bar = ProgressBar.new()
	oxy_bar.max_value = 10.0
	oxy_bar.value = 10.0
	oxy_bar.show_percentage = false
	oxy_bar.custom_minimum_size = Vector2(180, 10)
	oxy_bar.visible = false
	oxy_bar.add_theme_stylebox_override("fill", _style_box(Color("#3a98f0"), Color("#78c4ff"), 3, 0))
	bot_center.add_child(oxy_bar)

	var hbar := HBoxContainer.new()
	hbar.alignment = BoxContainer.ALIGNMENT_CENTER
	hbar.add_theme_constant_override("separation", 4)
	bot_center.add_child(hbar)
	for i in 9:
		var sb := _make_slot_btn(54.0)
		var idx := i
		sb.pressed.connect(func() -> void:
			if world != null and world.local_player != null:
				world.local_player.select_hotbar(idx)
		)
		hotbar_slots.append(sb)
		hbar.add_child(sb)

	# Top-Center Boss Bar & Region Discovery Banner
	var top_wrap := CenterContainer.new()
	top_wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_wrap.offset_top = 16
	top_wrap.offset_bottom = 96
	top_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(top_wrap)

	var top_center := VBoxContainer.new()
	top_center.custom_minimum_size = Vector2(360, 0)
	top_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_wrap.add_child(top_center)

	boss_bar_box = VBoxContainer.new()
	boss_bar_box.visible = false
	top_center.add_child(boss_bar_box)
	boss_name_lbl = Label.new()
	boss_name_lbl.text = "Colosso de Cristal (Umbra Guardian)"
	boss_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_name_lbl.add_theme_color_override("font_color", Color("#d8b6ff"))
	boss_bar_box.add_child(boss_name_lbl)
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(360, 16)
	boss_bar.show_percentage = false
	boss_bar.add_theme_stylebox_override("fill", _style_box(Color("#9c52f2"), Color("#d8b6ff"), 4, 0))
	boss_bar_box.add_child(boss_bar)

	banner_label = Label.new()
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_size_override("font_size", 22)
	banner_label.add_theme_color_override("font_color", Color("#ffe066"))
	banner_label.add_theme_color_override("font_outline_color", Color.BLACK)
	banner_label.add_theme_constant_override("outline_size", 5)
	top_center.add_child(banner_label)

	# Top-Left Status & F3 Debug Overlay
	debug_label = Label.new()
	debug_label.position = Vector2(14, 14)
	debug_label.add_theme_font_size_override("font_size", 14)
	debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	debug_label.add_theme_constant_override("outline_size", 4)
	hud_root.add_child(debug_label)

	# Bottom-Left Chat Box
	chat_box = VBoxContainer.new()
	chat_box.position = Vector2(16, 560)
	chat_box.custom_minimum_size = Vector2(420, 220)
	chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(chat_box)

	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_box.add_child(chat_log)

	chat_input = LineEdit.new()
	chat_input.placeholder_text = "Escreve mensagem ou /comando (Enter)..."
	chat_input.visible = false
	chat_input.text_submitted.connect(_on_chat_submitted)
	chat_box.add_child(chat_input)

func _build_inventory_modal() -> void:
	inv_modal = CenterContainer.new()
	inv_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	inv_modal.visible = false
	add_child(inv_modal)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(Color(0.11, 0.13, 0.18, 0.97), Color("#6c82a8"), 10, 2))
	inv_modal.add_child(panel)

	var outer_h := HBoxContainer.new()
	outer_h.add_theme_constant_override("separation", 18)
	panel.add_child(outer_h)

	var main_v := VBoxContainer.new()
	main_v.add_theme_constant_override("separation", 12)
	outer_h.add_child(main_v)

	inv_title_lbl = Label.new()
	inv_title_lbl.add_theme_font_size_override("font_size", 20)
	inv_title_lbl.add_theme_color_override("font_color", Color("#dce8ff"))
	main_v.add_child(inv_title_lbl)

	# Top section: Armor + Crafting (2x2 or 3x3) OR Furnace OR Chest
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 20)
	main_v.add_child(top_h)

	# Armor column
	var armor_v := VBoxContainer.new()
	armor_v.add_theme_constant_override("separation", 4)
	top_h.add_child(armor_v)
	var arm_lbl := Label.new()
	arm_lbl.text = "Armadura"
	arm_lbl.add_theme_font_size_override("font_size", 13)
	armor_v.add_child(arm_lbl)
	for i in 4:
		var ab := _make_slot_btn(48.0)
		var a_idx := i
		ab.pressed.connect(func() -> void: _on_armor_slot_clicked(a_idx))
		armor_slot_btns.append(ab)
		armor_v.add_child(ab)

	# Crafting section (3x3 grid + arrow + output)
	craft_box = HBoxContainer.new()
	craft_box.add_theme_constant_override("separation", 14)
	top_h.add_child(craft_box)
	var cgrid := GridContainer.new()
	cgrid.columns = 3
	cgrid.add_theme_constant_override("h_separation", 4)
	cgrid.add_theme_constant_override("v_separation", 4)
	craft_box.add_child(cgrid)
	for i in 9:
		var cb := _make_slot_btn(50.0)
		var c_idx := i
		cb.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed:
				_on_craft_slot_clicked(c_idx, ev.button_index == MOUSE_BUTTON_RIGHT)
		)
		craft_slot_btns.append(cb)
		cgrid.add_child(cb)

	var arrow_lbl := Label.new()
	arrow_lbl.text = "  ->  "
	arrow_lbl.add_theme_font_size_override("font_size", 24)
	craft_box.add_child(arrow_lbl)

	craft_out_btn = _make_slot_btn(58.0)
	craft_out_btn.pressed.connect(_on_craft_output_clicked)
	craft_box.add_child(craft_out_btn)

	# Furnace section
	furnace_box = HBoxContainer.new()
	furnace_box.visible = false
	furnace_box.add_theme_constant_override("separation", 14)
	top_h.add_child(furnace_box)
	var f_left := VBoxContainer.new()
	furnace_box.add_child(f_left)
	furnace_in_btn = _make_slot_btn(50.0)
	furnace_in_btn.pressed.connect(func() -> void: _on_furnace_slot_clicked("in"))
	f_left.add_child(furnace_in_btn)
	furnace_prog_lbl = Label.new()
	furnace_prog_lbl.text = "Fogo: 0% | 0%"
	f_left.add_child(furnace_prog_lbl)
	furnace_fuel_btn = _make_slot_btn(50.0)
	furnace_fuel_btn.pressed.connect(func() -> void: _on_furnace_slot_clicked("fuel"))
	f_left.add_child(furnace_fuel_btn)
	furnace_out_btn = _make_slot_btn(58.0)
	furnace_out_btn.pressed.connect(func() -> void: _on_furnace_slot_clicked("out"))
	furnace_box.add_child(furnace_out_btn)

	# Chest section (9x3 = 27 slots)
	chest_box = GridContainer.new()
	chest_box.columns = 9
	chest_box.visible = false
	chest_box.add_theme_constant_override("h_separation", 4)
	chest_box.add_theme_constant_override("v_separation", 4)
	top_h.add_child(chest_box)
	for i in 27:
		var chb := _make_slot_btn(48.0)
		var ch_idx := i
		chb.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed:
				_on_chest_slot_clicked(ch_idx, ev.button_index == MOUSE_BUTTON_RIGHT)
		)
		chest_slot_btns.append(chb)
		chest_box.add_child(chb)

	# Player backpack (slots 9..35)
	var bp_grid := GridContainer.new()
	bp_grid.columns = 9
	bp_grid.add_theme_constant_override("h_separation", 4)
	bp_grid.add_theme_constant_override("v_separation", 4)
	main_v.add_child(bp_grid)

	inv_slot_btns.resize(36)
	for i in range(9, 36):
		var ib := _make_slot_btn(50.0)
		var s_idx := i
		ib.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed:
				_on_inv_slot_clicked(s_idx, ev.button_index == MOUSE_BUTTON_RIGHT)
		)
		inv_slot_btns[i] = ib
		bp_grid.add_child(ib)

	# Player hotbar row (slots 0..8)
	var hb_grid := GridContainer.new()
	hb_grid.columns = 9
	hb_grid.add_theme_constant_override("h_separation", 4)
	main_v.add_child(hb_grid)
	for i in range(0, 9):
		var hb := _make_slot_btn(50.0)
		var h_idx := i
		hb.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed:
				_on_inv_slot_clicked(h_idx, ev.button_index == MOUSE_BUTTON_RIGHT)
		)
		inv_slot_btns[i] = hb
		hb_grid.add_child(hb)

	# Right sidebar: Quick Recipe Book (1-click craftable recipes!)
	var r_vbox := VBoxContainer.new()
	r_vbox.custom_minimum_size = Vector2(240, 420)
	outer_h.add_child(r_vbox)
	var r_title := Label.new()
	r_title.text = Locale.t("ui.recipes")
	r_title.add_theme_font_size_override("font_size", 17)
	r_vbox.add_child(r_title)
	var r_scroll := ScrollContainer.new()
	r_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_vbox.add_child(r_scroll)
	recipe_list_vbox = VBoxContainer.new()
	recipe_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	recipe_list_vbox.add_theme_constant_override("separation", 4)
	r_scroll.add_child(recipe_list_vbox)

func _build_pause_and_death() -> void:
	pause_modal = CenterContainer.new()
	pause_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_modal.visible = false
	add_child(pause_modal)

	var p_panel := PanelContainer.new()
	p_panel.add_theme_stylebox_override("panel", _style_box(Color(0.09, 0.11, 0.16, 0.95), Color("#6c82a8"), 10, 2))
	p_panel.custom_minimum_size = Vector2(360, 280)
	pause_modal.add_child(p_panel)

	var pv := VBoxContainer.new()
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override("separation", 12)
	p_panel.add_child(pv)

	var b_res := _make_btn("Continuar / Resume")
	b_res.pressed.connect(func() -> void: set_pause(false))
	pv.add_child(b_res)

	var b_set := _make_btn("Configurações / Settings")
	b_set.pressed.connect(func() -> void:
		settings_return_to_pause = true
		pause_modal.visible = false
		settings_panel.visible = true
	)
	pv.add_child(b_set)

	var b_quit := _make_btn("Guardar e Sair / Save & Quit")
	b_quit.pressed.connect(func() -> void:
		pause_modal.visible = false
		quit_to_title.emit()
	)
	pv.add_child(b_quit)

	# Death Modal
	death_modal = CenterContainer.new()
	death_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_modal.visible = false
	add_child(death_modal)

	var d_panel := PanelContainer.new()
	d_panel.add_theme_stylebox_override("panel", _style_box(Color(0.28, 0.05, 0.06, 0.92), Color("#e04040"), 10, 2))
	d_panel.custom_minimum_size = Vector2(380, 220)
	death_modal.add_child(d_panel)

	var dv := VBoxContainer.new()
	dv.alignment = BoxContainer.ALIGNMENT_CENTER
	dv.add_theme_constant_override("separation", 16)
	d_panel.add_child(dv)

	var dlbl := Label.new()
	dlbl.text = Locale.t("menu.you_died")
	dlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dlbl.add_theme_font_size_override("font_size", 32)
	dv.add_child(dlbl)

	var b_resp := _make_btn(Locale.t("menu.respawn"))
	b_resp.pressed.connect(func() -> void:
		death_modal.visible = false
		if world != null and world.local_player != null:
			world.local_player.respawn()
		_update_mouse_mode()
	)
	dv.add_child(b_resp)

func _build_cursor_item() -> void:
	cursor_preview = Control.new()
	cursor_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_preview.visible = false
	add_child(cursor_preview)
	cursor_icon = TextureRect.new()
	cursor_icon.size = Vector2(40, 40)
	cursor_icon.position = Vector2(-20, -20)
	cursor_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cursor_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_preview.add_child(cursor_icon)
	cursor_count = Label.new()
	cursor_count.position = Vector2(4, 4)
	cursor_count.add_theme_font_size_override("font_size", 14)
	cursor_preview.add_child(cursor_count)

func _refresh_texts() -> void:
	var panel := main_menu_root.get_child(1).get_child(0).get_child(0)
	panel.get_node("Title").text = Locale.t("menu.title")
	panel.get_node("Subtitle").text = Locale.t("menu.subtitle")
	panel.get_node("BtnSP").text = Locale.t("menu.singleplayer")
	panel.get_node("BtnMP").text = Locale.t("menu.multiplayer")
	panel.get_node("BtnSet").text = Locale.t("menu.settings")
	panel.get_node("BtnQuit").text = Locale.t("menu.quit")

func show_main_menu() -> void:
	in_game = false
	main_menu_root.visible = true
	sp_panel.visible = false
	mp_panel.visible = false
	settings_panel.visible = false
	hud_root.visible = false
	inv_modal.visible = false
	pause_modal.visible = false
	death_modal.visible = false
	_refresh_texts()
	_update_mouse_mode()

func attach_world(w: VoxelWorld) -> void:
	world = w
	w.main_ui = self
	in_game = true
	main_menu_root.visible = false
	sp_panel.visible = false
	mp_panel.visible = false
	hud_root.visible = true
	inv_modal.visible = false
	pause_modal.visible = false
	death_modal.visible = false

	var p := w.local_player
	p.stats_changed.connect(_refresh_hud)
	p.inventory_changed.connect(_refresh_hud)
	p.died.connect(func() -> void:
		death_modal.visible = true
		_update_mouse_mode()
	)
	p.open_station.connect(open_inventory_modal)
	p.message_shown.connect(show_banner)
	w.region_discovered.connect(func(rname: String) -> void:
		show_banner(Locale.tf("ui.discovered", [rname]))
	)
	_refresh_hud()
	_update_mouse_mode()

func show_banner(txt: String) -> void:
	banner_label.text = txt
	banner_timer = 3.8

func open_inventory_modal(mode: String = "inv", pos: Vector3i = Vector3i.ZERO) -> void:
	station_mode = mode
	station_pos = pos
	inv_modal.visible = true
	craft_box.visible = mode in ["inv", "workbench"]
	furnace_box.visible = (mode == "furnace")
	chest_box.visible = (mode == "chest")

	# Show 2x2 slots in inventory mode or all 3x3 slots in workbench mode
	var is_3x3 := (mode == "workbench")
	for i in 9:
		craft_slot_btns[i].visible = is_3x3 or (i in [0, 1, 3, 4])

	inv_title_lbl.text = Locale.t("ui." + ("inventory" if mode == "inv" else mode))
	_populate_recipe_book(is_3x3)
	_refresh_inventory_modal()
	_update_mouse_mode()

func close_inventory_modal() -> void:
	if world != null and world.local_player != null:
		var p := world.local_player
		for i in 9:
			if craft_grid[i]["id"] > 0 and craft_grid[i]["count"] > 0:
				p.add_item(craft_grid[i]["id"], craft_grid[i]["count"], craft_grid[i]["dur"])
				craft_grid[i] = {"id": 0, "count": 0, "dur": 0}
		if p.cursor_slot["id"] > 0 and p.cursor_slot["count"] > 0:
			p.add_item(p.cursor_slot["id"], p.cursor_slot["count"], p.cursor_slot["dur"])
			p.cursor_slot = {"id": 0, "count": 0, "dur": 0}
	craft_out = {"id": 0, "count": 0, "dur": 0}
	inv_modal.visible = false
	cursor_preview.visible = false
	_update_mouse_mode()

func set_pause(paused: bool) -> void:
	pause_modal.visible = paused
	_update_mouse_mode()

func _update_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if is_blocking_gameplay():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event: InputEvent) -> void:
	# Key rebinding capture
	if waiting_key_action != "" and event is InputEventKey and event.pressed:
		Settings.keys[waiting_key_action] = event.physical_keycode
		Settings.apply()
		if waiting_key_btn != null:
			waiting_key_btn.text = Settings.key_name(waiting_key_action)
		waiting_key_action = ""
		waiting_key_btn = null
		get_viewport().set_input_as_handled()
		return

	if not in_game or world == null or world.local_player == null:
		return
	var p := world.local_player

	if event is InputEventMouseMotion and not is_blocking_gameplay():
		p.rotate_look(event.relative.x, event.relative.y)
		return

	if event is InputEventMouseButton and event.pressed and not is_blocking_gameplay():
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			p.select_hotbar(p.hotbar_idx - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			p.select_hotbar(p.hotbar_idx + 1)

	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if chat_open:
				chat_open = false
				chat_input.visible = false
				_update_mouse_mode()
			elif inv_modal.visible:
				close_inventory_modal()
			elif settings_panel.visible:
				settings_panel.visible = false
				pause_modal.visible = true
			else:
				set_pause(not pause_modal.visible)
			get_viewport().set_input_as_handled()
			return

		if chat_open:
			return

		if event.is_action_pressed("inventory"):
			if inv_modal.visible:
				close_inventory_modal()
			elif not is_blocking_gameplay():
				open_inventory_modal("inv")
			get_viewport().set_input_as_handled()
			return

		if not is_blocking_gameplay():
			if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_9:
				p.select_hotbar(event.physical_keycode - KEY_1)
			elif event.is_action_pressed("drop"):
				p.drop_held_item(Input.is_key_pressed(KEY_CTRL))
			elif event.is_action_pressed("toggle_hud"):
				hud_visible = not hud_visible
				hud_root.visible = hud_visible
			elif event.is_action_pressed("debug"):
				debug_visible = not debug_visible
			elif event.is_action_pressed("perspective"):
				p.toggle_perspective()
			elif event.is_action_pressed("chat"):
				chat_open = true
				chat_input.visible = true
				chat_input.grab_focus()
				_update_mouse_mode()
				get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not in_game or world == null or world.local_player == null:
		return
	if banner_timer > 0.0:
		banner_timer -= delta
		if banner_timer <= 0.0:
			banner_label.text = ""

	if inv_modal.visible:
		cursor_preview.position = get_viewport().get_mouse_position()
		if station_mode == "furnace":
			_refresh_furnace_ui()

	_update_boss_bar()
	_update_debug_overlay()

func _update_boss_bar() -> void:
	var boss: VoxelMob = null
	for m in world.mobs_root.get_children():
		if m is VoxelMob and m.def.get("boss", false) and m.global_position.distance_to(world.local_player.global_position) < 36.0:
			boss = m
			break
	boss_bar_box.visible = (boss != null)
	if boss != null:
		boss_bar.max_value = boss.max_hp
		boss_bar.value = boss.hp

func _update_debug_overlay() -> void:
	var p := world.local_player
	var px := int(floor(p.global_position.x))
	var py := int(floor(p.global_position.y))
	var pz := int(floor(p.global_position.z))
	var b_idx := world.gen.biome_at(px, pz)
	if world.current_dimension == 0 and py < 24:
		b_idx = WorldGen.BIOME_CRYSTAL
	var b_name := Locale.t("biome." + WorldGen.BIOME_KEYS[b_idx])
	var w_name := Locale.t("ui.weather_" + world.weather)
	var dim_name := Locale.t("ui.dimension_overworld" if world.current_dimension == 0 else "ui.dimension_aether")
	var clock_h := int(world.world_time * 24.0)
	var clock_m := int(fmod(world.world_time * 24.0 * 60.0, 60.0))

	if not debug_visible:
		debug_label.text = "%s (%02d:%02d) | %s | %s" % [Locale.tf("ui.day", [world.day_count]), clock_h, clock_m, b_name, w_name]
	else:
		debug_label.text = "INFINITE WORLDS 1.0 (Godot 4.4) | %d FPS\nXYZ: %.1f / %.1f / %.1f  (Chunk: %d, %d)\nDim: %s | Bioma: %s | Clima: %s\nChunks: %d | Mobs: %d | Drops: %d | Seed: %d\nLuz Céu: %d | Modo: %s" % [
			Engine.get_frames_per_second(),
			p.global_position.x, p.global_position.y, p.global_position.z, px >> 4, pz >> 4,
			dim_name, b_name, w_name,
			world.chunks.size(), world.mobs_root.get_child_count(), world.drops_root.get_child_count(), world.world_seed,
			world.get_skylight(px, py + 1, pz),
			Locale.t("menu.mode_creative" if p.game_mode == 1 else "menu.mode_survival")
		]

func _refresh_hud() -> void:
	if world == null or world.local_player == null:
		return
	var p := world.local_player
	hp_bar.value = p.hp
	hp_label.text = "HP %d / %d" % [int(ceil(p.hp)), int(p.max_hp)]
	hunger_bar.value = p.hunger
	hunger_label.text = "Fome %d / %d" % [int(ceil(p.hunger)), int(p.max_hunger)]
	var arm := p.total_armor_points()
	armor_label.text = ("Armadura: %d" % arm) if arm > 0 else ""
	oxy_bar.visible = p.head_underwater or p.oxygen < p.max_oxygen - 0.1
	oxy_bar.value = p.oxygen

	for i in 9:
		_render_slot_btn(hotbar_slots[i], p.inv[i], i == p.hotbar_idx)
	var hid := p.held_item_id()
	held_name_label.text = Registry.item_name(hid) if hid > 0 else ""

	if inv_modal.visible:
		_refresh_inventory_modal()

func _refresh_inventory_modal() -> void:
	if world == null or world.local_player == null:
		return
	var p := world.local_player
	for i in 36:
		_render_slot_btn(inv_slot_btns[i], p.inv[i], i == p.hotbar_idx)
	for i in 4:
		_render_slot_btn(armor_slot_btns[i], p.armor[i])
	for i in 9:
		_render_slot_btn(craft_slot_btns[i], craft_grid[i])
	_update_craft_output()
	_render_slot_btn(craft_out_btn, craft_out)

	if station_mode == "chest":
		var cslots := world.get_chest_slots(station_pos)
		for i in mini(27, cslots.size()):
			_render_slot_btn(chest_slot_btns[i], cslots[i])
	elif station_mode == "furnace":
		_refresh_furnace_ui()

	var cs := p.cursor_slot
	if cs["id"] > 0 and cs["count"] > 0:
		cursor_preview.visible = true
		cursor_icon.texture = Registry.icon(cs["id"])
		cursor_count.text = str(cs["count"]) if cs["count"] > 1 else ""
	else:
		cursor_preview.visible = false

func _refresh_furnace_ui() -> void:
	var fd := world.get_furnace_data(station_pos)
	if fd.is_empty():
		return
	_render_slot_btn(furnace_in_btn, fd["in"])
	_render_slot_btn(furnace_fuel_btn, fd["fuel"])
	_render_slot_btn(furnace_out_btn, fd["out"])
	var b_pct := int((fd["burn"] / maxf(1.0, fd["burn_max"])) * 100.0)
	var p_pct := int(fd["prog"] * 100.0)
	furnace_prog_lbl.text = "Chama: %d%%  |  Fundição: %d%%" % [b_pct, p_pct]

func _swap_or_merge(slot_ref: Dictionary, right_click: bool) -> void:
	var cs := world.local_player.cursor_slot
	if cs["id"] == 0:
		if slot_ref["id"] == 0:
			return
		if right_click and slot_ref["count"] > 1:
			var half := int(ceil(slot_ref["count"] / 2.0))
			world.local_player.cursor_slot = {"id": slot_ref["id"], "count": half, "dur": slot_ref["dur"]}
			slot_ref["count"] -= half
		else:
			world.local_player.cursor_slot = slot_ref.duplicate()
			slot_ref["id"] = 0; slot_ref["count"] = 0; slot_ref["dur"] = 0
	else:
		if slot_ref["id"] == 0:
			var put: int = 1 if right_click else cs["count"]
			slot_ref["id"] = cs["id"]; slot_ref["count"] = put; slot_ref["dur"] = cs["dur"]
			cs["count"] -= put
			if cs["count"] <= 0:
				world.local_player.cursor_slot = {"id": 0, "count": 0, "dur": 0}
		elif slot_ref["id"] == cs["id"] and Registry.max_stack(cs["id"]) > 1:
			var space: int = Registry.max_stack(cs["id"]) - int(slot_ref["count"])
			var add: int = mini(space, 1 if right_click else int(cs["count"]))
			slot_ref["count"] += add
			cs["count"] -= add
			if cs["count"] <= 0:
				world.local_player.cursor_slot = {"id": 0, "count": 0, "dur": 0}
		else:
			var tmp := slot_ref.duplicate()
			slot_ref["id"] = cs["id"]; slot_ref["count"] = cs["count"]; slot_ref["dur"] = cs["dur"]
			world.local_player.cursor_slot = tmp
	Sfx.play_ui("click", 1.1, -4.0)

func _on_inv_slot_clicked(idx: int, right_click: bool) -> void:
	var p := world.local_player
	# Shift-click auto-equips armor or moves between chest and inventory
	if Input.is_key_pressed(KEY_SHIFT) and p.inv[idx]["id"] > 0:
		var it := Registry.item(p.inv[idx]["id"])
		if it.has("armor_slot"):
			var aslot: int = it["armor_slot"]
			if p.armor[aslot]["id"] == 0:
				p.armor[aslot] = p.inv[idx].duplicate()
				p.inv[idx] = {"id": 0, "count": 0, "dur": 0}
				p.inventory_changed.emit()
				return
	_swap_or_merge(p.inv[idx], right_click)
	p._refresh_hand_visual()
	p.inventory_changed.emit()

func _on_armor_slot_clicked(a_idx: int) -> void:
	var p := world.local_player
	var cs := p.cursor_slot
	if cs["id"] > 0 and Registry.item(cs["id"]).get("armor_slot", -1) != a_idx:
		return
	_swap_or_merge(p.armor[a_idx], false)
	p.stats_changed.emit()
	p.inventory_changed.emit()

func _on_craft_slot_clicked(c_idx: int, right_click: bool) -> void:
	_swap_or_merge(craft_grid[c_idx], right_click)
	_refresh_inventory_modal()

func _update_craft_output() -> void:
	var ids := []
	for i in 9:
		ids.append(craft_grid[i]["id"])
	var m := Registry.match_recipe(ids, 3)
	if m.is_empty():
		craft_out = {"id": 0, "count": 0, "dur": 0}
	else:
		var out_id: int = m["out"]
		craft_out = {"id": out_id, "count": m["count"], "dur": Registry.item(out_id).get("durability", 0)}

func _on_craft_output_clicked() -> void:
	if craft_out["id"] <= 0:
		return
	var p := world.local_player
	var rem := p.add_item(craft_out["id"], craft_out["count"], craft_out["dur"])
	if rem == 0:
		for i in 9:
			if craft_grid[i]["id"] > 0:
				craft_grid[i]["count"] -= 1
				if craft_grid[i]["count"] <= 0:
					craft_grid[i] = {"id": 0, "count": 0, "dur": 0}
		Sfx.play_ui("click", 1.3)
		_refresh_inventory_modal()

func _on_furnace_slot_clicked(key: String) -> void:
	var fd := world.get_furnace_data(station_pos)
	if fd.is_empty():
		return
	_swap_or_merge(fd[key], false)
	_refresh_inventory_modal()

func _on_chest_slot_clicked(ch_idx: int, right_click: bool) -> void:
	var cslots := world.get_chest_slots(station_pos)
	if ch_idx >= cslots.size():
		return
	_swap_or_merge(cslots[ch_idx], right_click)
	_refresh_inventory_modal()

func _populate_recipe_book(allow_3x3: bool) -> void:
	for c in recipe_list_vbox.get_children():
		c.queue_free()
	if world != null and world.local_player != null and world.local_player.game_mode == 1:
		for d in Registry.items:
			if d == null:
				continue
			var iid: int = d["id"]
			var cbtn := _make_btn(Registry.item_name(iid), Vector2(210, 34))
			cbtn.icon = Registry.icon(iid)
			cbtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			cbtn.pressed.connect(func() -> void:
				world.local_player.add_item(iid, Registry.max_stack(iid))
				_refresh_inventory_modal()
			)
			recipe_list_vbox.add_child(cbtn)
		return
	for r in Registry.recipes:
		if not allow_3x3 and r.has("pattern"):
			var pat: Array = r["pattern"]
			if pat.size() > 2 or pat[0].length() > 2:
				continue
		var out_id := Registry.id_of(r["out"])
		var btn := _make_btn("%s (x%d)" % [Registry.item_name(out_id), r["count"]], Vector2(210, 34))
		btn.icon = Registry.icon(out_id)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var rec: Dictionary = r
		btn.pressed.connect(func() -> void: _try_quick_craft(rec))
		recipe_list_vbox.add_child(btn)

func _try_quick_craft(rec: Dictionary) -> void:
	var p := world.local_player
	# Collect required ingredient tags/keys
	var needed: Array = []
	if rec.has("shapeless"):
		needed = rec["shapeless"].duplicate()
	else:
		for row in rec["pattern"]:
			for i in row.length():
				var ch: String = row[i]
				if ch != " ":
					needed.append(rec["keys"][ch])

	# Verify player has all ingredients in inventory
	var temp_counts := {}
	for i in 36:
		var iid: int = p.inv[i]["id"]
		if iid > 0:
			temp_counts[iid] = temp_counts.get(iid, 0) + p.inv[i]["count"]

	var consume_ids: Array[int] = []
	for req in needed:
		var found_id := 0
		for iid in temp_counts.keys():
			if temp_counts[iid] > 0 and Registry._matches(Registry.key_of(iid), req):
				found_id = iid
				temp_counts[iid] -= 1
				break
		if found_id == 0:
			return # Missing ingredient
		consume_ids.append(found_id)

	var out_id := Registry.id_of(rec["out"])
	if p.add_item(out_id, rec["count"]) == 0:
		for cid in consume_ids:
			p._consume_item_id(cid, 1)
		Sfx.play_ui("click", 1.35)
		_refresh_inventory_modal()

func _on_chat_submitted(text: String) -> void:
	chat_input.text = ""
	chat_open = false
	chat_input.visible = false
	_update_mouse_mode()
	var t := text.strip_edges()
	if t.is_empty():
		return
	if t.begins_with("/"):
		_execute_command(t)
	else:
		Net.send_chat(t)

func _execute_command(cmd: String) -> void:
	var parts := cmd.substr(1).split(" ", false)
	if parts.is_empty() or world == null or world.local_player == null:
		return
	var p := world.local_player
	match parts[0].to_lower():
		"time":
			if parts.size() > 1:
				world.world_time = 0.30 if parts[1] == "day" else 0.85
				_on_chat_received("System", "Time set to " + parts[1])
		"weather":
			if parts.size() > 1 and parts[1] in ["clear", "rain", "storm", "blood_moon"]:
				world.weather = parts[1]
				_on_chat_received("System", "Weather set to " + parts[1])
		"gamemode", "gm":
			if parts.size() > 1:
				p.game_mode = 1 if parts[1] in ["1", "creative", "c"] else 0
				_on_chat_received("System", "Game mode updated.")
		"give":
			if parts.size() > 1:
				var iid := Registry.id_of(parts[1])
				var qty := int(parts[2]) if parts.size() > 2 else 1
				if iid > 0:
					p.add_item(iid, qty)
					_on_chat_received("System", "Gave %d x %s" % [qty, Registry.item_name(iid)])
		"umbra":
			world.travel_dimension(1 - world.current_dimension)
		"tp":
			if parts.size() >= 4:
				p.global_position = Vector3(float(parts[1]), float(parts[2]), float(parts[3]))
				p.fall_peak_y = p.global_position.y

func _on_chat_received(sender: String, text: String) -> void:
	if chat_log != null:
		chat_log.append_text("[b][color=#8fd8ff]<%s>[/color][/b] %s\n" % [sender, text])
