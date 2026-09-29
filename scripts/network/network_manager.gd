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
## Custom match room (before the match): settings or members changed.
signal room_changed
## A chat line in the room.
signal room_chat(from_name: String, text: String)
## killer_id is -1 for environmental deaths (falling).
signal kill_feed(killer_id: int, victim_id: int, weapon_name: String, headshot: bool)

enum Mode { OFFLINE, HOST, DEDICATED, CLIENT }

const PROTOCOL_VERSION := 7
const DEFAULT_PORT := 7777
const DEFAULT_MAX_PLAYERS := 16
const DEFAULT_MAP := "res://scenes/levels/test_map.tscn"
## Offline game mode (Practice, or a mode against bots) and the bots to add
## when the first level of a session loads (main menu / --bots).
var offline_mode: int = GameConfig.Mode.PRACTICE
## Offline match settings (Bot Match): -1 = the mode's defaults.
var offline_score_limit: int = -1
var offline_time_limit: float = -1.0
var offline_friendly_fire: bool = false
var start_bots: int = 0
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
## peer_id -> { "name", "kills", "deaths", "ping", "team" (-1 = none), "primary" (weapon id), "money" (Bomb Defusal) }
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

## Custom match room: players gather in the lobby (characters, ready,
## chat) while the host picks the map, mode and settings, then the host
## starts the match for everyone. `room` is the host's settings, synced.
var in_room: bool = false
var room: Dictionary = {}
const ROOM_KEYS: PackedStringArray = ["map", "mode", "time_limit", "score_limit", "bots", "bot_skill",
	"friendly_fire", "max_players"]
const CHAT_MAX := 120


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


## Offline: Practice on your own, or `game_mode` against `bots` training
## bots (with its score / time limits, -1 = defaults, and friendly fire).
func start_offline(map_path: String = DEFAULT_MAP, bots: int = 0, game_mode: int = -1,
		score_limit: int = -1, time_limit: float = -1.0, friendly_fire: bool = false) -> void:
	_reset_peer()
	mode = Mode.OFFLINE
	current_map = map_path
	offline_mode = game_mode if bots > 0 and game_mode >= 0 else GameConfig.Mode.PRACTICE
	offline_score_limit = score_limit if offline_mode != GameConfig.Mode.PRACTICE else -1
	offline_time_limit = time_limit if offline_mode != GameConfig.Mode.PRACTICE else -1.0
	offline_friendly_fire = friendly_fire
	start_bots = bots
	Match.configure(offline_mode)
	_goto_map(map_path)


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
	_goto_map(map_path)
	return OK


## Hosts a Custom match room: the server runs in the lobby until
## start_room_match(). `settings` = the room (ROOM_KEYS).
func host_room(port: int, settings: Dictionary) -> Error:
	_reset_peer()
	var max_players := clampi(int(settings.get("max_players", 8)), 2, DEFAULT_MAX_PLAYERS)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_players)
	if err != OK:
		last_error = "Could not host on port %d (%s)." % [port, error_string(err)]
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	in_room = true
	room = sanitize_room(settings)
	room.max_players = max_players
	Match.configure(room.mode as GameConfig.Mode)
	_add_local_entry()
	roster[1].ready = true
	print("[net] Room open on port %d (max %d players)" % [port, max_players])
	room_changed.emit()
	roster_changed.emit()
	return OK


## A valid room from anything (the menu, the network).
static func sanitize_room(raw: Dictionary) -> Dictionary:
	var map_path: String = str(raw.get("map", GameConfig.MAPS[0].path))
	if GameConfig.map_index(map_path) < 0:
		map_path = GameConfig.MAPS[0].path
	var game_mode := clampi(int(raw.get("mode", GameConfig.Mode.TDM)), GameConfig.Mode.FFA, GameConfig.Mode.BOMB)
	if game_mode == GameConfig.Mode.BOMB and not GameConfig.map_info(map_path).get("bomb", false):
		game_mode = GameConfig.Mode.TDM
	return {
		"map": map_path, "mode": game_mode,
		"time_limit": clampf(float(raw.get("time_limit", 600.0)), 0.0, 3600.0),
		"score_limit": clampi(int(raw.get("score_limit", 50)), 1, 500),
		"bots": clampi(int(raw.get("bots", 0)), 0, BotManager.MAX_BOTS),
		"bot_skill": clampi(int(raw.get("bot_skill", 1)), 0, 2),
		"friendly_fire": bool(raw.get("friendly_fire", false)),
		"max_players": clampi(int(raw.get("max_players", 8)), 2, DEFAULT_MAX_PLAYERS),
	}


## Host: change the room's settings (everyone sees them).
func set_room(settings: Dictionary) -> void:
	if not in_room or not multiplayer.is_server():
		return
	var keep_max: int = room.get("max_players", 8)
	room = sanitize_room(settings)
	room.max_players = keep_max
	Match.configure(room.mode as GameConfig.Mode)
	_room_state.rpc(room)
	room_changed.emit()


## Client: ready / not ready.
func set_ready(on: bool) -> void:
	if not in_room:
		return
	if multiplayer.is_server():
		_apply_ready(1, on)
	else:
		_request_ready.rpc_id(1, on)


func _apply_ready(id: int, on: bool) -> void:
	if roster.has(id):
		roster[id].ready = on
		broadcast_roster()


## A line in the room chat (everyone in the room sees it).
func send_chat(text: String) -> void:
	var clean := text.strip_edges().strip_escapes().substr(0, CHAT_MAX)
	if clean.is_empty() or not is_online():
		return
	if multiplayer.is_server():
		_relay_chat(1, clean)
	else:
		_request_chat.rpc_id(1, clean)


func _relay_chat(from_id: int, text: String) -> void:
	var from_name := get_player_name(from_id)
	room_chat.emit(from_name, text)
	_chat.rpc(from_name, text)


## Host: start the match with the room's settings — everyone loads the map.
func start_room_match() -> void:
	if not in_room or not multiplayer.is_server():
		return
	in_room = false
	var r := room
	Match.configure(r.mode as GameConfig.Mode, r.score_limit, r.time_limit if r.mode != GameConfig.Mode.BOMB else 0.0)
	Match.friendly_fire = r.friendly_fire
	Match.bots.difficulty = r.bot_skill
	start_bots = r.bots
	# Teams for the chosen mode, balanced.
	for id: int in roster:
		roster[id].team = GameConfig.TEAM_NONE
	for id: int in roster:
		roster[id].team = Match.assign_team(id)
	print("[net] Room starts: %s on %s" % [GameConfig.MODE_NAMES[r.mode], GameConfig.map_name(r.map)])
	change_map(r.map)


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


## "v0.9.0 beta" — shown in menus, bug reports and the server log.
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
		if id != 1 and not BotManager.is_bot(id):
			_client_load_map.rpc_id(id, map_path)
	_goto_map(map_path)


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
			Match.configure(offline_mode, offline_score_limit, offline_time_limit)
			Match.friendly_fire = offline_friendly_fire
		Match.start_match()
		if mode != Mode.DEDICATED:
			if not roster.has(1):
				_add_local_entry()
			_ready_peers[1] = true
			_server_spawn(1)
		Match.bots.on_level_loaded(level)
		if start_bots > 0:
			Match.bots.set_count(start_bots)
			start_bots = 0
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
	_disable_throttle(id)
	if multiplayer.is_server():
		print("[net] Peer %d connected" % id)


## ENet's packet throttle drops *unreliable* packets (voice, player movement)
## whenever round-trip times fluctuate — a busy PC or Wi-Fi was enough to lose
## a large share of voice packets and cause movement stutter. Our unreliable
## traffic is small and time-critical, so it always goes out at full rate.
func _disable_throttle(id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var peer := enet.get_peer(id) if enet else null
	if peer:
		peer.throttle_configure(5000, 2, 0) # interval ms, acceleration, deceleration 0 = never slow down


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
		VoiceCodec.opus_available(), CharacterLook.pack(SettingsManager.character))


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
func _register_player(player_name: String, protocol: int, primary: String, opus: bool, look: Array = []) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL_VERSION:
		_kicked.rpc_id(id, "Version mismatch (server %d, client %d)." % [PROTOCOL_VERSION, protocol])
		return
	roster[id] = _new_entry(_sanitize_name(player_name, id), primary, opus)
	roster[id].look = CharacterLook.pack(CharacterLook.unpack(look))
	roster[id].team = Match.assign_team(id)
	print("[net] %s (%d) joined" % [roster[id].name, id])
	if in_room:
		roster[id].ready = false
		_room_state.rpc_id(id, room)
	else:
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
	# Doors (open / broken pieces) and windows (cracked / shattered).
	for n in get_tree().get_nodes_in_group(Door.NET_GROUP):
		n.send_state_to(id)
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
func _room_state(settings: Dictionary) -> void:
	in_room = true
	room = sanitize_room(settings)
	room.max_players = int(settings.get("max_players", 8))
	Match.configure(room.mode as GameConfig.Mode)
	room_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _chat(from_name: String, text: String) -> void:
	room_chat.emit(from_name, text)


@rpc("any_peer", "call_remote", "reliable")
func _request_ready(on: bool) -> void:
	if multiplayer.is_server() and in_room:
		_apply_ready(multiplayer.get_remote_sender_id(), on)


@rpc("any_peer", "call_remote", "reliable")
func _request_chat(text: String) -> void:
	if not multiplayer.is_server():
		return
	var clean := text.strip_edges().strip_escapes().substr(0, CHAT_MAX)
	var id := multiplayer.get_remote_sender_id()
	if not clean.is_empty() and roster.has(id):
		_relay_chat(id, clean)


@rpc("authority", "call_remote", "reliable")
func _client_load_map(map_path: String) -> void:
	in_room = false
	current_map = map_path
	_goto_map(map_path)


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
	if Match.mode == GameConfig.Mode.BOMB:
		primary = "" # pistol + knife until something is bought (Economy)
	var p := _level.spawn_player(peer_id, player_name, xform, primary, 0)
	send_to_ready(self, &"_spawn_player", [peer_id, player_name, xform, primary, 0])
	# Bomb Defusal: joining mid-round means waiting (spectating) for the next round.
	if Match.mode == GameConfig.Mode.BOMB and Match.bomb.round_number > 0 \
			and Match.bomb.phase != BombRules.Phase.FREEZE:
		p.health.set_dead_silently()


func _add_local_entry() -> void:
	roster[1] = _new_entry(local_name, SettingsManager.preferred_primary, VoiceCodec.opus_available())
	roster[1].look = CharacterLook.pack(SettingsManager.character)
	roster[1].team = Match.assign_team(1)


func _reset_peer() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	roster.clear()
	in_room = false
	room = {}
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
		"team": GameConfig.TEAM_NONE, "primary": primary, "opus": opus, "money": Economy.START_MONEY,
		"look": CharacterLook.pack(CharacterLook.default_look()),
	}


## A player's look (CharacterLook) from the roster.
func look_of(peer_id: int) -> Dictionary:
	return CharacterLook.unpack(roster.get(peer_id, {}).get("look", []))


func _sanitize_name(raw: String, id: int) -> String:
	var clean := raw.strip_edges().strip_escapes().substr(0, 16)
	return clean if not clean.is_empty() else "Player %d" % id


## Loads a map behind the loading screen (map name, progress, steps), then
## switches to it. Headless (servers, tests): straight away.
func _goto_map(map_path: String) -> void:
	if DisplayServer.get_name() == "headless" or not ResourceLoader.exists(map_path):
		get_tree().change_scene_to_file(map_path)
		return
	var screen := LoadingScreen.open(get_tree(), map_path)
	if ResourceLoader.load_threaded_request(map_path) != OK:
		get_tree().change_scene_to_file(map_path)
		return
	var progress: Array = []
	while true:
		var status := ResourceLoader.load_threaded_get_status(map_path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			get_tree().change_scene_to_file(map_path)
			return
		screen.set_load_progress(float(progress[0]) if not progress.is_empty() else 0.0)
		await get_tree().process_frame
	screen.set_step(1) # building the level
	var packed := ResourceLoader.load_threaded_get(map_path) as PackedScene
	await get_tree().process_frame
	if current_map != map_path:
		return # another map was asked for meanwhile
	get_tree().change_scene_to_packed(packed)


func _local_time() -> float:
	return Time.get_ticks_usec() / 1_000_000.0


## `godot --headless -- --server [--port 7777] [--max-players 16] [--map docks] [--mode tdm]`
## `godot -- --connect 1.2.3.4:7777 [--name Bob]`
func _start_dedicated_from_args() -> void:
	var args := OS.get_cmdline_user_args()
	# The server export also accepts options without the "--" separator
	# (./StrikeOps-server.x86_64 --port 7777), which is what admins type.
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
		var join_port := DEFAULT_PORT
		if target.count(":") == 1:
			join_port = target.get_slice(":", 1).to_int()
			target = target.get_slice(":", 0)
		join(target, join_port)
		return
	# The "Linux Server" export has the dedicated_server feature: always a server.
	if not "--server" in args and not OS.has_feature("dedicated_server"):
		return
	print("[net] Strike Ops %s dedicated server" % version_string())
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
			"--bots": start_bots = clampi(value.to_int(), 0, BotManager.MAX_BOTS)
			"--bot-skill": Match.bots.difficulty = clampi(value.to_int(), 0, 2)
	if host(port, max_players, true, map_path, game_mode) != OK:
		push_error(last_error)
		get_tree().quit(1)
