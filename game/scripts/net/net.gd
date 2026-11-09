extends Node
## Server-authoritative ENet multiplayer manager: handles hosting, joining,
## world seed handshake, player transform/avatar sync, block modification validation,
## and in-game chat.

signal chat_received(sender: String, text: String)
signal connection_status(status_text: String)
signal remote_world_ready(meta: Dictionary)

var world: VoxelWorld = null
var peer: ENetMultiplayerPeer = null
var player_names: Dictionary = {} # peer_id -> String
var _sync_timer: float = 0.0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func is_active() -> bool:
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func host_server(port: int = 25565) -> bool:
	close_network()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 16)
	if err != OK:
		peer = null
		connection_status.emit("Failed to bind port %d" % port)
		return false
	multiplayer.multiplayer_peer = peer
	player_names[1] = Settings.player_name
	connection_status.emit("Hosting on port %d" % port)
	return true

func join_server(ip: String, port: int = 25565) -> bool:
	close_network()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		peer = null
		connection_status.emit("Connection error")
		return false
	multiplayer.multiplayer_peer = peer
	connection_status.emit("Connecting to %s:%d..." % [ip, port])
	return true

func close_network() -> void:
	if peer != null:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	player_names.clear()

func _process(delta: float) -> void:
	if not is_active() or world == null or world.local_player == null:
		return
	_sync_timer += delta
	if _sync_timer >= 0.05:
		_sync_timer = 0.0
		var p := world.local_player
		_rpc_sync_player.rpc(p.global_position, p.yaw, p.pitch, p.held_item_id())

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server() and world != null:
		var meta := {
			"id": "",
			"name": world.world_name,
			"seed": world.world_seed,
			"mode": world.game_mode,
			"time": world.world_time,
			"days": world.day_count,
			"dimension": world.current_dimension,
		}
		_rpc_init_world.rpc_id(id, meta)

func _on_peer_disconnected(id: int) -> void:
	var pname: String = player_names.get(id, "Player %d" % id)
	player_names.erase(id)
	if world != null and world.remote_players.has(id):
		world.remote_players[id].queue_free()
		world.remote_players.erase(id)
	chat_received.emit("Server", "%s left the world." % pname)

func _on_connected_to_server() -> void:
	connection_status.emit("Connected!")
	_rpc_register_name.rpc_id(1, Settings.player_name)

func _on_connection_failed() -> void:
	connection_status.emit("Connection failed.")
	close_network()

func _on_server_disconnected() -> void:
	connection_status.emit("Disconnected from server.")
	close_network()

@rpc("any_peer", "reliable")
func _rpc_register_name(pname: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	player_names[sender] = pname
	_rpc_chat.rpc("Server", "%s joined the world!" % pname)

@rpc("authority", "reliable")
func _rpc_init_world(meta: Dictionary) -> void:
	remote_world_ready.emit(meta)

@rpc("any_peer", "unreliable_ordered")
func _rpc_sync_player(pos: Vector3, yaw: float, _pitch: float, _held_id: int) -> void:
	if world == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == multiplayer.get_unique_id():
		return
	var avatar: Node3D = world.remote_players.get(sender)
	if avatar == null:
		avatar = world.local_player._build_character_model()
		var lbl := Label3D.new()
		lbl.text = player_names.get(sender, "Player %d" % sender)
		lbl.position = Vector3(0, 2.1, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 28
		avatar.add_child(lbl)
		world.add_child(avatar)
		world.remote_players[sender] = avatar
	avatar.global_position = pos
	avatar.rotation.y = yaw

func broadcast_block_change(wx: int, wy: int, wz: int, id: int, meta_val: int) -> void:
	if not is_active():
		return
	if multiplayer.is_server():
		_rpc_apply_block.rpc(wx, wy, wz, id, meta_val)
	else:
		_rpc_req_block.rpc_id(1, wx, wy, wz, id, meta_val)

@rpc("any_peer", "reliable")
func _rpc_req_block(wx: int, wy: int, wz: int, id: int, meta_val: int) -> void:
	if not multiplayer.is_server() or world == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	# Server-side authority check: validate bounds and reach distance
	if wy <= 0 or wy >= B.HEIGHT or id < 0 or id >= B.COUNT:
		return
	if world.remote_players.has(sender):
		var rpos: Vector3 = world.remote_players[sender].global_position
		if rpos.distance_to(Vector3(wx + 0.5, wy + 0.5, wz + 0.5)) > 10.0:
			return
	world.set_block(wx, wy, wz, id, meta_val, true)
	_rpc_apply_block.rpc(wx, wy, wz, id, meta_val)

@rpc("authority", "reliable")
func _rpc_apply_block(wx: int, wy: int, wz: int, id: int, meta_val: int) -> void:
	if world != null and not multiplayer.is_server():
		world.set_block(wx, wy, wz, id, meta_val, true)

func send_chat(text: String) -> void:
	var clean := text.strip_edges()
	if clean.is_empty():
		return
	if is_active():
		_rpc_chat.rpc(Settings.player_name, clean)
	else:
		chat_received.emit(Settings.player_name, clean)

@rpc("any_peer", "call_local", "reliable")
func _rpc_chat(sender: String, text: String) -> void:
	chat_received.emit(sender, text)
