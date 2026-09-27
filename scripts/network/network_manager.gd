extends Node
## Multiplayer session manager (autoload: NetworkManager).
##
## Modes:
##   OFFLINE   – single player, no network peer (the local game is its own server)
##   HOST      – listen server: this machine is the server AND has a local player
##   DEDICATED – headless server without a local player (`-- --server`)
##   CLIENT    – connected to a remote server
##
## Authority model: the server owns health, damage, kills and respawns.
## Each client owns its own movement (the server sanity-checks it) and sends
## shots to the server, which verifies them with lag compensation.
##
## Join flow:
##   client connects → _register_player → server replies _client_load_map →
##   client loads the map → _level_ready → server sends existing players and
##   spawns the new one on every ready peer.

signal connection_failed(reason: String)
signal server_disconnected
signal roster_changed
## killer_id is -1 for environmental deaths (falling).
signal kill_feed(killer_id: int, victim_id: int, weapon_name: String, headshot: bool)

enum Mode { OFFLINE, HOST, DEDICATED, CLIENT }

const PROTOCOL_VERSION := 4
const DEFAULT_PORT := 7777
const DEFAULT_MAX_PLAYERS := 16
const DEFAULT_MAP := "res://scenes/levels/test_map.tscn"
const MAIN_MENU := "res://scenes/main/main_menu.tscn"
const CONNECT_TIMEOUT := 10.0

## Anti-cheat: a player who sends more than this many invalid actions
## (impossible fire rate, shooting an empty gun, speed/fly hacks) within
## VIOLATION_WINDOW seconds is kicked. Generous, so bad connections never trip it.
const VIOLATION_LIMIT := 25
const VIOLATION_WINDOW := 10.0

## ENet channels: 0 = reliable game events, 1 = player state, 2 = voice (Phase 5).
const CHANNEL_STATE := 1
const CHANNEL_VOICE := 2

## Remote players are rendered this far in the past so there are always two
## snapshots to interpolate between.
const INTERPOLATION_DELAY := 0.1
## Maximum time the server will rewind for lag compensation.
const MAX_REWIND := 0.4

var mode: Mode = Mode.OFFLINE
var local_name: String = "Player"
var current_map: String = DEFAULT_MAP
## Shown by the main menu after being kicked back to it.
var last_error: String = ""
## peer_id -> { "name", "kills", "deaths", "ping", "team" (-1 = none), "primary" (weapon id) }
var roster: Dictionary = {}
## Round-trip time to the server in milliseconds (clients only).
var ping_ms: int = 0

var _ready_peers: Dictionary = {} # server: peer_id -> true once their level is loaded
var _level: Level
var _clock_offset: float = 0.0
var _clock_synced: bool = false
var _ping_timer: float = 0.0
var _roster_timer: float = 0.0
var _connect_timer: float = -1.0
var _violations: Dictionary = {} # server: peer_id -> Array[float] timestamps


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_start_dedicated_from_args.call_deferred()


func _process(delta: float) -> void:
	if _connect_timer >= 0.0:
		_connect_timer += delta
		if _connect_timer > CONNECT_TIMEOUT:
			_fail("Connection timed out.")
	if mode == Mode.CLIENT and _level:
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_ping_timer = 1.0
			_ping.rpc_id(1, _local_time())
	elif is_online() and multiplayer.is_server():
		_roster_timer -= delta
		if _roster_timer <= 0.0:
			_roster_timer = 2.0
			broadcast_roster()


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

func is_online() -> bool:
	return mode != Mode.OFFLINE


func is_dedicated() -> bool:
	return mode == Mode.DEDICATED


## Server clock in seconds, shared by all peers (clients estimate it via ping).
func server_time() -> float:
	if multiplayer.is_server():
		return _local_time()
	return _local_time() + _clock_offset


func start_offline(map_path: String = DEFAULT_MAP) -> void:
	_reset_peer()
	mode = Mode.OFFLINE
	current_map = map_path
	Match.configure(GameConfig.Mode.PRACTICE)
	get_tree().change_scene_to_file(map_path)


## `game_mode` = -1 keeps whatever Match.configure() set last (default FFA).
func host(port: int = DEFAULT_PORT, max_players: int = DEFAULT_MAX_PLAYERS,
		dedicated: bool = false, map_path: String = DEFAULT_MAP, game_mode: int = -1) -> Error:
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		last_error = "Could not host on port %d (%s)." % [port, error_string(err)]
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.DEDICATED if dedicated else Mode.HOST
	current_map = map_path
	if game_mode >= 0:
		Match.configure(game_mode as GameConfig.Mode)
	elif Match.mode == GameConfig.Mode.PRACTICE:
		Match.configure(GameConfig.Mode.FFA)
	if not dedicated:
		_add_local_entry()
	print("[net] %s server listening on port %d (max %d players, %s on %s)" % [
		"Dedicated" if dedicated else "Listen", port, max_players,
		GameConfig.MODE_NAMES[Match.mode], GameConfig.map_name(map_path)])
	get_tree().change_scene_to_file(map_path)
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	_reset_peer()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		last_error = "Could not connect to %s:%d (%s)." % [address, port, error_string(err)]
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	_connect_timer = 0.0
	print("[net] Connecting to %s:%d…" % [address, port])
	return OK


## Leaves the session (or offline game) and returns to the main menu.
func leave(reason: String = "") -> void:
	last_error = reason
	_reset_peer()
	mode = Mode.OFFLINE
	get_tree().change_scene_to_file(MAIN_MENU)


func get_player_name(peer_id: int) -> String:
	if peer_id < 0:
		return "World"
	return roster.get(peer_id, {}).get("name", "Player %d" % peer_id)


## "v0.8.0 beta" — shown in menus, bug reports and the server log.
static func version_string() -> String:
	var v: String = ProjectSettings.get_setting("application/config/version", "0.0.0")
	var channel: String = ProjectSettings.get_setting("application/config/release_channel", "")
	return "v%s%s" % [v, (" " + channel) if channel != "" else ""]


## The level currently loaded on this peer (null in menus).
func current_level() -> Level:
	return _level if is_instance_valid(_level) else null


## Server: count an invalid action from `peer_id`; kicks when over the limit.
func report_violation(peer_id: int, reason: String) -> void:
	if not multiplayer.is_server() or peer_id == 1 or not is_online():
		return
	var now := _local_time()
	var list: Array = _violations.get(peer_id, [])
	list = list.filter(func(t: float) -> bool: return now - t < VIOLATION_WINDOW)
	list.append(now)
	_violations[peer_id] = list
	if list.size() == 1 or list.size() % 10 == 0:
		print("[anticheat] %s (%d): %s (%d in %ds)" % [get_player_name(peer_id), peer_id, reason, list.size(), VIOLATION_WINDOW])
	if list.size() > VIOLATION_LIMIT:
		kick(peer_id, "Kicked by anti-cheat (%s)." % reason)


## Server: disconnect a player with a message.
func kick(peer_id: int, reason: String) -> void:
	if not multiplayer.is_server() or not multiplayer.get_peers().has(peer_id):
		return
	print("[net] Kicking %s (%d): %s" % [get_player_name(peer_id), peer_id, reason])
	_kicked.rpc_id(peer_id, reason)
	_violations.erase(peer_id)
	# Give the message a moment to arrive before dropping the connection.
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer and multiplayer.get_peers().has(peer_id):
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id))


## Server: push the roster to everyone now (and to local listeners).
func broadcast_roster() -> void:
	if is_online() and multiplayer.is_server():
		_sync_roster.rpc(roster)
	roster_changed.emit()


## Server: switch every peer to another map (map rotation). Players stay
## connected; each client reloads and goes through _level_ready again.
func change_map(map_path: String) -> void:
	if not multiplayer.is_server():
		return
	print("[net] Changing map to %s" % GameConfig.map_name(map_path))
	current_map = map_path
	_ready_peers.clear()
	_level = null
	for id: int in roster:
		if id != 1:
			_client_load_map.rpc_id(id, map_path)
	get_tree().change_scene_to_file(map_path)


## Sends an RPC to every peer that has finished loading the level.
## The server itself is never included (call the method locally instead).
func send_to_ready(node: Node, method: StringName, args: Array = [], exclude: Array = []) -> void:
	if not is_online() or not multiplayer.is_server():
		return
	for id: int in _ready_peers:
		if id == 1 or id in exclude:
			continue
		node.callv(&"rpc_id", [id, method] + args)


func ready_peer_ids() -> Array:
	return _ready_peers.keys()


## Called by Level._ready() on every peer.
func on_level_loaded(level: Level) -> void:
	_level = level
	if multiplayer.is_server():
		if mode == Mode.OFFLINE:
			Match.configure(GameConfig.Mode.PRACTICE)
		Match.start_match()
		if mode != Mode.DEDICATED:
			if not roster.has(1):
				_add_local_entry()
			_ready_peers[1] = true
			_server_spawn(1)
	else:
		_level_ready.rpc_id(1)


## Server only: called when a player is killed by another player.
func report_kill(killer_id: int, victim_id: int, weapon_name: String, headshot: bool) -> void:
	if not multiplayer.is_server():
		return
	if roster.has(victim_id):
		roster[victim_id].deaths += 1
	if roster.has(killer_id) and killer_id != victim_id:
		roster[killer_id].kills += 1
	Match.on_kill(killer_id, victim_id)
	_announce_kill(killer_id, victim_id, weapon_name, headshot)
	if is_online():
		_announce_kill.rpc(killer_id, victim_id, weapon_name, headshot)
	broadcast_roster()


# -----------------------------------------------------------------------------
# Connection callbacks
# -----------------------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		print("[net] Peer %d connected" % id)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	print("[net] %s (%d) left" % [get_player_name(id), id])
	var leaving := _level.get_player(id) if _level else null
	var leaving_pos := leaving.global_position if leaving else Vector3.ZERO
	roster.erase(id)
	_ready_peers.erase(id)
	if _level:
		_level.despawn_player(id)
	Match.on_player_left(id, leaving_pos)
	send_to_ready(self, &"_despawn_player", [id])
	broadcast_roster()


func _on_connected_to_server() -> void:
	_connect_timer = -1.0
	print("[net] Connected as peer %d" % multiplayer.get_unique_id())
	_register_player.rpc_id(1, local_name, PROTOCOL_VERSION, SettingsManager.preferred_primary,
		VoiceCodec.opus_available())


func _on_connection_failed() -> void:
	_fail("Could not connect to the server.")


func _on_server_disconnected() -> void:
	server_disconnected.emit()
	leave("Disconnected from the server.")


func _fail(reason: String) -> void:
	_connect_timer = -1.0
	connection_failed.emit(reason)
	leave(reason)


# -----------------------------------------------------------------------------
# RPCs — client → server
# -----------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _register_player(player_name: String, protocol: int, primary: String, opus: bool) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL_VERSION:
		_kicked.rpc_id(id, "Version mismatch (server %d, client %d)." % [PROTOCOL_VERSION, protocol])
		return
	roster[id] = _new_entry(_sanitize_name(player_name, id), primary, opus)
	roster[id].team = Match.assign_team(id)
	print("[net] %s (%d) joined" % [roster[id].name, id])
	_client_load_map.rpc_id(id, current_map)
	broadcast_roster()


@rpc("any_peer", "call_remote", "reliable")
func _level_ready() -> void:
	if not multiplayer.is_server() or _level == null:
		return
	var id := multiplayer.get_remote_sender_id()
	if not roster.has(id):
		return
	_ready_peers[id] = true
	# 1) Match state, 2) existing players, 3) current health of everything,
	# 4) the new player.
	Match.send_state_to(id)
	Match.bomb.send_state_to(id)
	for p: PlayerController in _level.get_players():
		_spawn_player.rpc_id(id, p.peer_id, p.player_name, p.global_transform, p.primary_id, p.current_slot)
	for h: Health in get_tree().get_nodes_in_group(Health.NET_GROUP):
		h.send_state_to(id)
	_server_spawn(id)


@rpc("any_peer", "call_remote", "reliable")
func _ping(client_time: float) -> void:
	if multiplayer.is_server():
		_pong.rpc_id(multiplayer.get_remote_sender_id(), client_time, server_time())


@rpc("any_peer", "call_remote", "reliable")
func _report_ping(ms: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and roster.has(id):
		roster[id].ping = clampi(ms, 0, 9999)


# -----------------------------------------------------------------------------
# RPCs — server → client
# -----------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _client_load_map(map_path: String) -> void:
	current_map = map_path
	get_tree().change_scene_to_file(map_path)


@rpc("authority", "call_remote", "reliable")
func _spawn_player(peer_id: int, player_name: String, xform: Transform3D, primary: String, slot: int) -> void:
	if _level:
		_level.spawn_player(peer_id, player_name, xform, primary, slot)


@rpc("authority", "call_remote", "reliable")
func _despawn_player(peer_id: int) -> void:
	if _level:
		_level.despawn_player(peer_id)


@rpc("authority", "call_remote", "reliable")
func _sync_roster(data: Dictionary) -> void:
	roster = data
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _announce_kill(killer_id: int, victim_id: int, weapon_name: String, headshot: bool) -> void:
	kill_feed.emit(killer_id, victim_id, weapon_name, headshot)


@rpc("authority", "call_remote", "reliable")
func _pong(client_time: float, server_t: float) -> void:
	var now := _local_time()
	var rtt := now - client_time
	ping_ms = int(rtt * 1000.0)
	var offset := server_t + rtt * 0.5 - now
	_clock_offset = offset if not _clock_synced else lerpf(_clock_offset, offset, 0.2)
	_clock_synced = true
	_report_ping.rpc_id(1, ping_ms)


@rpc("authority", "call_remote", "reliable")
func _kicked(reason: String) -> void:
	leave(reason)


# -----------------------------------------------------------------------------
# Internals
# -----------------------------------------------------------------------------

func _server_spawn(peer_id: int) -> void:
	var xform := _level.next_spawn_transform(peer_id)
	var player_name := get_player_name(peer_id)
	var primary: String = roster.get(peer_id, {}).get("primary", GameConfig.DEFAULT_PRIMARY)
	var p := _level.spawn_player(peer_id, player_name, xform, primary, 0)
	send_to_ready(self, &"_spawn_player", [peer_id, player_name, xform, primary, 0])
	# Bomb Defusal: joining mid-round means waiting (spectating) for the next round.
	if Match.mode == GameConfig.Mode.BOMB and Match.bomb.round_number > 0 \
			and Match.bomb.phase != BombRules.Phase.FREEZE:
		p.health.set_dead_silently()


func _add_local_entry() -> void:
	roster[1] = _new_entry(local_name, SettingsManager.preferred_primary, VoiceCodec.opus_available())
	roster[1].team = Match.assign_team(1)


func _reset_peer() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster.clear()
	_ready_peers.clear()
	_level = null
	_clock_offset = 0.0
	_clock_synced = false
	_connect_timer = -1.0
	ping_ms = 0


## `opus`: the player can decode Opus voice (see VoiceChat.use_opus_for).
func _new_entry(player_name: String, primary: String = GameConfig.DEFAULT_PRIMARY, opus: bool = false) -> Dictionary:
	if not primary in GameConfig.PRIMARY_WEAPONS:
		primary = GameConfig.DEFAULT_PRIMARY
	return {
		"name": player_name, "kills": 0, "deaths": 0, "ping": 0,
		"team": GameConfig.TEAM_NONE, "primary": primary, "opus": opus,
	}


func _sanitize_name(raw: String, id: int) -> String:
	var clean := raw.strip_edges().strip_escapes().substr(0, 16)
	return clean if not clean.is_empty() else "Player %d" % id


func _local_time() -> float:
	return Time.get_ticks_usec() / 1_000_000.0


## `godot --headless -- --server [--port 7777] [--max-players 16] [--map warehouse] [--mode tdm]`
## `godot -- --connect 1.2.3.4:7777 [--name Bob]`
func _start_dedicated_from_args() -> void:
	var args := OS.get_cmdline_user_args()
	# The server export also accepts options without the "--" separator
	# (./FPSGame-server.x86_64 --port 7777), which is what admins type.
	if OS.has_feature("dedicated_server"):
		args = OS.get_cmdline_args() + args
	# `-- --connect 1.2.3.4:7777 [--name Bob]` joins a server straight away.
	var connect_i := args.find("--connect")
	if connect_i >= 0 and connect_i + 1 < args.size() and not "--server" in args:
		var name_i := args.find("--name")
		if name_i >= 0 and name_i + 1 < args.size():
			local_name = args[name_i + 1]
			SettingsManager.player_name = local_name
		var target := args[connect_i + 1]
		var port := DEFAULT_PORT
		if target.count(":") == 1:
			port = target.get_slice(":", 1).to_int()
			target = target.get_slice(":", 0)
		join(target, port)
		return
	# The "Linux Server" export has the dedicated_server feature: always a server.
	if not "--server" in args and not OS.has_feature("dedicated_server"):
		return
	print("[net] FPS Game %s dedicated server" % version_string())
	var port := DEFAULT_PORT
	var max_players := DEFAULT_MAX_PLAYERS
	var map_path := DEFAULT_MAP
	var game_mode := GameConfig.Mode.FFA
	for i in args.size():
		var key := args[i]
		var value := args[i + 1] if i + 1 < args.size() else ""
		if "=" in key:
			value = key.get_slice("=", 1)
			key = key.get_slice("=", 0)
		match key:
			"--port": port = value.to_int()
			"--max-players": max_players = value.to_int()
			"--map": map_path = GameConfig.map_path(value)
			"--mode": game_mode = GameConfig.MODE_IDS.get(value.to_lower(), GameConfig.Mode.FFA)
	if host(port, max_players, true, map_path, game_mode) != OK:
		push_error(last_error)
		get_tree().quit(1)
