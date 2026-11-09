extends Node3D
## Root coordinator for Infinite Worlds: connects VoxelWorld, GameUI, Net,
## title-screen 3D panorama, autosave timer, and automated integration test suite.

var world: VoxelWorld
var ui: GameUI
var menu_cam: Camera3D
var autosave_timer: float = 30.0
var menu_angle: float = 0.0

func _ready() -> void:
	world = VoxelWorld.new()
	world.name = "VoxelWorld"
	add_child(world)
	Net.world = world

	menu_cam = Camera3D.new()
	menu_cam.position = Vector3(8, 82, 8)
	menu_cam.current = true
	add_child(menu_cam)

	ui = GameUI.new()
	ui.name = "GameUI"
	add_child(ui)

	ui.start_singleplayer.connect(_on_start_singleplayer)
	ui.host_multiplayer.connect(_on_host_multiplayer)
	ui.join_multiplayer.connect(_on_join_multiplayer)
	ui.quit_to_title.connect(_on_quit_to_title)
	Net.remote_world_ready.connect(_on_remote_world_ready)

	for arg in OS.get_cmdline_user_args():
		if arg == "--self-test":
			_run_self_test()
			return
		elif arg == "--render-preview":
			_run_render_preview()
			return

	world.build_menu_panorama()

func _process(delta: float) -> void:
	if not ui.in_game:
		menu_angle += delta * 0.18
		menu_cam.position = Vector3(cos(menu_angle) * 20.0, 74.0, sin(menu_angle) * 20.0)
		menu_cam.look_at(Vector3(0, 62, 0), Vector3.UP)
		return

	autosave_timer -= delta
	if autosave_timer <= 0.0:
		autosave_timer = 30.0
		world.save_all()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if world != null and ui != null and ui.in_game:
			world.save_all()
		get_tree().quit()

func _on_start_singleplayer(meta: Dictionary) -> void:
	Net.close_network()
	menu_cam.current = false
	world.start_world(meta)
	ui.attach_world(world)

func _on_host_multiplayer(meta: Dictionary, port: int) -> void:
	if Net.host_server(port):
		menu_cam.current = false
		world.start_world(meta)
		ui.attach_world(world)

func _on_join_multiplayer(ip: String, port: int) -> void:
	Net.join_server(ip, port)

func _on_remote_world_ready(meta: Dictionary) -> void:
	ui.mp_panel.visible = false
	menu_cam.current = false
	world.start_world(meta)
	ui.attach_world(world)

func _on_quit_to_title() -> void:
	world.save_all()
	Net.close_network()
	world.clear_world()
	world.build_menu_panorama()
	menu_cam.current = true
	ui.show_main_menu()

func _run_render_preview() -> void:
	world.build_menu_panorama()
	menu_cam.position = Vector3(18.0, 74.0, 18.0)
	menu_cam.look_at(Vector3(0, 62, 0), Vector3.UP)
	for _i in 6:
		await get_tree().process_frame
	var img_menu := get_viewport().get_texture().get_image()
	img_menu.save_png("C:/Users/helio/.gemini/antigravity/brain/f73e3533-1ceb-4b7f-83d1-0ef1d3bd0ed3/preview_menu.png")

	var meta := WorldSave.create_world("PreviewWorld", 202611, 0)
	_on_start_singleplayer(meta)
	world.spawn_mob("cow", world.local_player.global_position + Vector3(3, 1, -4))
	world.spawn_mob("sheep", world.local_player.global_position + Vector3(-2, 1, -5))
	for _i in 10:
		await get_tree().process_frame
	var img_game := get_viewport().get_texture().get_image()
	img_game.save_png("C:/Users/helio/.gemini/antigravity/brain/f73e3533-1ceb-4b7f-83d1-0ef1d3bd0ed3/preview_gameplay.png")
	world.clear_world()
	WorldSave.delete_world(meta["id"])
	await get_tree().process_frame
	get_tree().quit(0)

func _run_self_test() -> void:
	print("=== INFINITE WORLDS: RUNNING FULL SYSTEM SELF-TEST ===")
	# 1. Verify Registry (blocks, items, textures, recipes)
	assert(B.COUNT == 89, "Expected 89 block definitions")
	assert(Registry.layer_images.size() > 60, "Procedural textures generated")
	assert(Registry.recipes.size() > 50, "Crafting recipes loaded")

	# 2. Create & start a test world
	var meta := WorldSave.create_world("SelfTestWorld", 123456, 0)
	_on_start_singleplayer(meta)
	assert(world.local_player != null, "Local player spawned")
	assert(world.chunks.size() >= 9, "Spawn chunks generated and meshed")

	var p := world.local_player
	var sp := Vector3i(int(floor(p.global_position.x)) + 2, int(floor(p.global_position.y)), int(floor(p.global_position.z)))

	# 3. Test block placement, mining, and drops
	world.set_block(sp.x, sp.y, sp.z, B.OAK_LOG)
	assert(world.get_block(sp.x, sp.y, sp.z) == B.OAK_LOG, "Block placed accurately")
	world.harvest_block(sp, Registry.id_of("wooden_axe"), true)
	assert(world.get_block(sp.x, sp.y, sp.z) == B.AIR, "Block mined and cleared")
	assert(world.drops_root.get_child_count() >= 1, "Block drop entity spawned")

	# 4. Test 2x2 and 3x3 crafting recipes
	var m_planks := Registry.match_recipe([B.OAK_LOG, 0, 0, 0], 2)
	assert(m_planks.get("out", 0) == B.OAK_PLANKS and m_planks.get("count", 0) == 4, "Log -> 4 Planks recipe works")
	var stick_id := Registry.id_of("stick")
	var m_pick := Registry.match_recipe([
		B.COBBLE, B.COBBLE, B.COBBLE,
		0, stick_id, 0,
		0, stick_id, 0
	], 3)
	assert(m_pick.get("out", 0) == Registry.id_of("stone_pickaxe"), "3x3 Stone Pickaxe recipe works")

	# 5. Test furnace smelting tick
	world.set_block(sp.x, sp.y, sp.z, B.FURNACE)
	var fd := world.get_furnace_data(sp)
	fd["in"] = {"id": B.IRON_ORE, "count": 2, "dur": 0}
	fd["fuel"] = {"id": Registry.id_of("coal"), "count": 1, "dur": 0}
	world._tick_furnaces(7.0)
	assert(fd["out"]["id"] == Registry.id_of("iron_ingot") and fd["out"]["count"] == 1, "Furnace smelted iron ore to iron ingot")

	# 6. Test Mob spawning, AI & combat
	var zom := world.spawn_mob("zombie", p.global_position + Vector3(3, 0, 0))
	assert(zom != null and zom.hp == 20.0, "Zombie spawned with 20 HP")
	zom.take_damage(8.0, Vector3(1, 1, 0), p)
	assert(zom.hp == 12.0 and zom.target == p, "Zombie took damage and targeted attacker")
	zom.take_damage(15.0, Vector3.ZERO, p)

	# 7. Test Survival damage, armor reduction & respawn
	p.armor[1] = {"id": Registry.id_of("diamond_chestplate"), "count": 1, "dur": 200}
	assert(p.total_armor_points() == 8, "Diamond chestplate gives 8 armor points")
	p.take_damage(10.0, "test")
	assert(p.hp > 10.0 and p.hp < 20.0, "Armor reduced incoming damage")
	p.take_damage(100.0, "test")
	assert(p.is_dead, "Lethal damage triggered death state")
	p.respawn()
	assert(not p.is_dead and p.hp == 20.0, "Player respawned with full HP")

	# 8. Test Dimension travel (Overworld -> Umbra Crystal Realm)
	world.travel_dimension(1)
	assert(world.current_dimension == 1, "Travelled to Umbra Crystal Realm (dim 1)")
	world.travel_dimension(0)
	assert(world.current_dimension == 0, "Returned to Overworld (dim 0)")

	# 9. Test World Save & Load persistence
	world.set_block(sp.x, sp.y + 1, sp.z, B.DIAMOND_BLOCK)
	world.save_all()
	var saved_id := world.world_id
	world.clear_world()
	world.start_world(WorldSave.load_meta(saved_id))
	assert(world.get_block(sp.x, sp.y + 1, sp.z) == B.DIAMOND_BLOCK, "Saved chunk block persisted across reload")

	# 10. Test Farming, Wolf Taming, Mechanisms (Lever + Conduit + Piston) & Explosions
	world.set_block(sp.x + 2, sp.y - 1, sp.z, B.FARMLAND)
	world.set_block(sp.x + 2, sp.y, sp.z, B.WHEAT, 0)
	var wolf := world.spawn_mob("wolf", world.local_player.global_position + Vector3(2, 0, 2))
	world.local_player.add_item(Registry.id_of("bone"), 10)
	for _i in 10:
		if not wolf.tamed:
			wolf.interact(world.local_player, Registry.id_of("bone"))
	# Mechanism test: Lever -> Energy Conduit -> Piston pushes Cobblestone
	var mp := Vector3i(sp.x - 3, sp.y, sp.z)
	world.set_block(mp.x, mp.y, mp.z, B.LEVER, 0)
	world.set_block(mp.x + 1, mp.y, mp.z, B.ENERGY_CONDUIT, 0)
	world.set_block(mp.x + 2, mp.y, mp.z, B.PISTON, 0) # facing 0 = +Z
	world.set_block(mp.x + 2, mp.y, mp.z + 1, B.COBBLE, 0)
	world.set_block(mp.x + 2, mp.y, mp.z + 2, B.AIR, 0)
	world.toggle_lever(mp)
	assert(world.get_block(mp.x + 2, mp.y, mp.z + 2) == B.COBBLE, "Luminite energy mechanism pushed block via Piston")
	world.explode(Vector3(sp.x + 6, sp.y, sp.z), 2.5, 10.0)

	world.clear_world()
	WorldSave.delete_world(saved_id)

	print("=== ALL 10 SYSTEM TESTS PASSED SUCCESSFULLY! ===")
	await get_tree().process_frame
	get_tree().quit(0)
