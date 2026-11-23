class_name NetworkManager
extends Node

signal lobby_updated()
signal connection_status_changed(status_text: String, is_connected: bool)
signal game_action_received(sender_seat: int, action_type: String, payload: Dictionary)
signal match_start_received(seed_val: int, starting_pid: int, seat_decks: Dictionary)

const DEFAULT_PORT: int = 7777
const MAX_SEATS: int = 4

var engine: Node = null
var enet_peer: ENetMultiplayerPeer = null
var peer_to_seat: Dictionary = {} # peer_id (int) -> seat_id (1..4)
var seat_to_peer: Dictionary = {} # seat_id (1..4) -> peer_id (int)
var seat_decks: Dictionary = {}   # seat_id (1..4) -> Dictionary {deckName, commander, cards}
var seat_names: Dictionary = {}   # seat_id (1..4) -> String
var is_hosting: bool = false
var is_in_lobby: bool = false

func setup(main_engine: Node) -> void:
	engine = main_engine
	var mp := get_tree().get_multiplayer()
	if not mp.peer_connected.is_connected(_on_peer_connected):
		mp.peer_connected.connect(_on_peer_connected)
	if not mp.peer_disconnected.is_connected(_on_peer_disconnected):
		mp.peer_disconnected.connect(_on_peer_disconnected)
	if not mp.connected_to_server.is_connected(_on_connected_to_server):
		mp.connected_to_server.connect(_on_connected_to_server)
	if not mp.connection_failed.is_connected(_on_connection_failed):
		mp.connection_failed.connect(_on_connection_failed)
	if not mp.server_disconnected.is_connected(_on_server_disconnected):
		mp.server_disconnected.connect(_on_server_disconnected)

func is_network_active() -> bool:
	var mp := get_tree().get_multiplayer()
	return mp != null and mp.has_multiplayer_peer() and enet_peer != null and enet_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED

func get_local_seat_id() -> int:
	if not is_network_active():
		return 1
	var my_peer_id: int = get_tree().get_multiplayer().get_unique_id()
	return int(peer_to_seat.get(my_peer_id, 1))

func is_seat_human(seat_id: int) -> bool:
	if not is_network_active():
		return seat_id == (engine.local_player_id if engine else 1)
	return seat_to_peer.has(seat_id)

func get_local_lan_ip() -> String:
	var candidates: Array[String] = []
	for ip in IP.get_local_addresses():
		if "." in ip and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			candidates.append(ip)
	for c in candidates:
		if c.begins_with("192.168."):
			return c
	for c in candidates:
		if c.begins_with("10."):
			return c
	return candidates[0] if not candidates.is_empty() else "127.0.0.1"

func host_game(port: int = DEFAULT_PORT) -> Error:
	disconnect_game()
	enet_peer = ENetMultiplayerPeer.new()
	enet_peer.set_bind_ip("0.0.0.0")
	var err := enet_peer.create_server(port, MAX_SEATS - 1)
	if err != OK:
		enet_peer = null
		connection_status_changed.emit("Host failed (Error %d)" % err, false)
		return err
	get_tree().get_multiplayer().multiplayer_peer = enet_peer
	is_hosting = true
	is_in_lobby = true
	peer_to_seat = {1: 1}
	seat_to_peer = {1: 1}
	seat_names = {1: "Host (Player 1)"}
	seat_decks.clear()
	connection_status_changed.emit("Hosting on %s:%d (Seat 1)" % [get_local_lan_ip(), port], true)
	lobby_updated.emit()
	return OK

func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	disconnect_game()
	var clean_ip := ip.strip_edges()
	var target_port := clampi(port, 1, 65535)
	if ":" in clean_ip and not clean_ip.begins_with("["):
		var parts := clean_ip.split(":")
		clean_ip = parts[0].strip_edges()
		if parts.size() > 1 and parts[1].strip_edges().is_valid_int():
			target_port = clampi(parts[1].strip_edges().to_int(), 1, 65535)
	if clean_ip.is_empty():
		clean_ip = "127.0.0.1"
	enet_peer = ENetMultiplayerPeer.new()
	var err := enet_peer.create_client(clean_ip, target_port)
	if err != OK:
		enet_peer = null
		var hint := " (check IP, Android INTERNET perm, or Firewall UDP %d)" % target_port if err == ERR_CANT_CREATE else ""
		connection_status_changed.emit("Join failed (Error %d)%s" % [err, hint], false)
		return err
	port = target_port
	get_tree().get_multiplayer().multiplayer_peer = enet_peer
	is_hosting = false
	is_in_lobby = true
	connection_status_changed.emit("Connecting to %s:%d..." % [clean_ip, target_port], false)
	return OK

func disconnect_game() -> void:
	is_hosting = false
	is_in_lobby = false
	peer_to_seat.clear()
	seat_to_peer.clear()
	seat_decks.clear()
	seat_names.clear()
	var mp := get_tree().get_multiplayer()
	if mp and mp.has_multiplayer_peer():
		mp.multiplayer_peer = null
	if enet_peer:
		enet_peer.close()
		enet_peer = null
	connection_status_changed.emit("Offline (Solo / AI Mode)", false)
	lobby_updated.emit()

func _on_peer_connected(peer_id: int) -> void:
	if not is_hosting:
		return
	var assigned_seat := -1
	for s in [1, 2, 3, 4]:
		if not seat_to_peer.has(s):
			assigned_seat = s
			break
	if assigned_seat == -1:
		return
	peer_to_seat[peer_id] = assigned_seat
	seat_to_peer[assigned_seat] = peer_id
	seat_names[assigned_seat] = "Player %d (Peer %d)" % [assigned_seat, peer_id]
	_sync_lobby_state.rpc(peer_to_seat, seat_to_peer, seat_names)
	lobby_updated.emit()

func _on_peer_disconnected(peer_id: int) -> void:
	if not is_hosting:
		return
	if peer_to_seat.has(peer_id):
		var seat_id: int = int(peer_to_seat[peer_id])
		peer_to_seat.erase(peer_id)
		seat_to_peer.erase(seat_id)
		seat_names.erase(seat_id)
		seat_decks.erase(seat_id)
		_sync_lobby_state.rpc(peer_to_seat, seat_to_peer, seat_names)
		lobby_updated.emit()

func _on_connected_to_server() -> void:
	var my_id := get_tree().get_multiplayer().get_unique_id()
	connection_status_changed.emit("Connected (Peer %d)" % my_id, true)
	lobby_updated.emit()

func _on_connection_failed() -> void:
	disconnect_game()
	connection_status_changed.emit("Connection failed", false)

func _on_server_disconnected() -> void:
	disconnect_game()
	connection_status_changed.emit("Host disconnected", false)

@rpc("authority", "call_local", "reliable")
func _sync_lobby_state(p2s: Dictionary, s2p: Dictionary, s_names: Dictionary) -> void:
	peer_to_seat = p2s.duplicate(true)
	seat_to_peer = s2p.duplicate(true)
	seat_names = s_names.duplicate(true)
	var my_seat := get_local_seat_id()
	if engine:
		engine.local_player_id = my_seat
	connection_status_changed.emit("Connected as Seat %d (%d/4 Humans)" % [my_seat, seat_to_peer.size()], true)
	lobby_updated.emit()

func submit_local_deck(deck_payload: Dictionary) -> void:
	if not is_network_active():
		return
	var my_seat := get_local_seat_id()
	_rpc_submit_deck.rpc(my_seat, deck_payload)

@rpc("any_peer", "call_local", "reliable")
func _rpc_submit_deck(seat_id: int, deck_payload: Dictionary) -> void:
	seat_decks[seat_id] = deck_payload
	lobby_updated.emit()

func host_start_network_match(starting_pid: int, all_seat_decks: Dictionary) -> void:
	if not is_network_active() or not is_hosting:
		return
	var rng_seed := randi()
	_rpc_start_match.rpc(rng_seed, starting_pid, all_seat_decks)

@rpc("authority", "call_local", "reliable")
func _rpc_start_match(rng_seed: int, starting_pid: int, all_seat_decks: Dictionary) -> void:
	seed(rng_seed)
	seat_decks = all_seat_decks.duplicate(true)
	match_start_received.emit(rng_seed, starting_pid, seat_decks)

func dispatch_game_action(action_type: String, payload: Dictionary = {}) -> void:
	if not is_network_active():
		return
	var my_seat := get_local_seat_id()
	_rpc_game_action.rpc(my_seat, action_type, payload)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_game_action(sender_seat: int, action_type: String, payload: Dictionary) -> void:
	game_action_received.emit(sender_seat, action_type, payload)
