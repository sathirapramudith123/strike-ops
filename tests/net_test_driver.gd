extends Node
## Drives one side of the multiplayer integration test.
##
## host:   listen server with a local player that stands still at its spawn.
## client: joins, walks, then shoots the host until the host dies.
## Both sides check that state replicated correctly and exit 0 on success.

const TIMEOUT := 30.0

var _role := "host"
var _port := 7788
var _failures := 0
var _kill_feed_seen := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			_port = arg.get_slice("=", 1).to_int()
	NetworkManager.kill_feed.connect(func(_k: int, _v: int, _w: String, _h: bool) -> void:
		_kill_feed_seen = true)
	get_tree().create_timer(TIMEOUT * 2.0).timeout.connect(func() -> void:
		print("[%s] global timeout" % _role)
		get_tree().quit(2))
	match _role:
		"host": _run_host()
		"observer": _run_observer()
		"bomb_host": _run_bomb_host()
		"bomb_client": _run_bomb_client()
		_: _run_client()


func _run_host() -> void:
	NetworkManager.local_name = "Host"
	# Team deathmatch, first kill wins, short results screen → quick map rotation.
	Match.configure(GameConfig.Mode.TDM, 1)
	Match.results_time = 3.0
	# game_mode -1 keeps the limits configured above.
	_check(NetworkManager.host(_port, 4, false, GameConfig.map_path("test_map"), -1) == OK and Match.mode == GameConfig.Mode.TDM,
		"host starts listening (TDM)")
	var level: Level = await _wait_for(func() -> Variant: return _level())
	var me: PlayerController = await _wait_for(func() -> Variant: return level.get_player(1))
	_check(me != null and me.is_local, "host has a local player")

	var client: PlayerController = await _wait_for(func() -> Variant:
		var ps := level.get_players().filter(func(p: PlayerController) -> bool: return p.peer_id != 1)
		return ps[0] if not ps.is_empty() else null)
	_check(client != null and not client.is_local, "client player spawned on host")
	if client == null:
		return _finish()
	var client_id := client.peer_id # the node is freed when the client leaves
	_check(Match.get_team(1) == 0 and Match.get_team(client_id) == 1, "teams auto-balanced (host blue, client red)")
	var start := client.global_position
	var moved: Variant = await _wait_for(func() -> Variant:
		return true if client.global_position.distance_to(start) > 1.0 else null)
	_check(moved == true, "client movement replicated to host")

	await _voice_exchange(client_id, 500.0, 440.0)

	var hurt: Variant = await _wait_for(func() -> Variant:
		return true if me.health.current < me.health.max_health or me.health.is_dead else null)
	_check(hurt == true, "client's shots damage the host (server-side hit)")
	var died: Variant = await _wait_for(func() -> Variant: return true if me.health.is_dead else null)
	_check(died == true, "host player dies")
	_check(NetworkManager.roster.get(client_id, {}).get("kills", 0) >= 1, "kill credited to client")
	_check(NetworkManager.roster.get(1, {}).get("deaths", 0) >= 1, "death credited to host")
	_check(_kill_feed_seen, "kill feed on host")
	_check(Match.team_scores[1] == 1, "red team scores")
	_check(Match.is_ended() and Match.winner_text == "Red team wins!", "score limit ends the match (%s)" % Match.winner_text)

	# Map rotation: after the results screen everyone moves to the next map.
	var rotated: Variant = await _wait_for(func() -> Variant:
		var l := _level()
		return l if l and l.name == "Warehouse" and l.get_player(1) and l.get_player(client_id) else null)
	_check(rotated != null, "map rotates to Warehouse with both players respawned")
	_check(not Match.is_ended() and Match.team_scores[0] == 0 and Match.team_scores[1] == 0, "new match starts with a fresh score")
	level = rotated if rotated else level

	var left: Variant = await _wait_for(func() -> Variant:
		return true if NetworkManager.roster.size() == 1 and level.get_player(client_id) == null else null)
	_check(left == true, "client leaves cleanly (despawned + roster)")
	_finish()


func _run_client() -> void:
	await get_tree().create_timer(1.0).timeout
	NetworkManager.local_name = "Client"
	_check(NetworkManager.join("127.0.0.1", _port) == OK, "client starts connecting")
	var level: Level = await _wait_for(func() -> Variant: return _level())
	var me: PlayerController = await _wait_for(func() -> Variant: return level.player if level else null)
	_check(me != null and me.peer_id == multiplayer.get_unique_id(), "client spawned its local player")
	var host: PlayerController = await _wait_for(func() -> Variant: return level.get_player(1))
	_check(host != null and not host.is_local, "host player visible on client")
	if me == null or host == null:
		return _finish()
	_check(NetworkManager.roster.size() == 2, "roster has both players")

	_check(Match.mode == GameConfig.Mode.TDM, "client knows the game mode (TDM)")
	_check(Match.get_team(me.peer_id) == 1 and Match.get_team(1) == 0, "client sees the teams")

	# Walk forward a bit (server must accept it — no snap-back).
	await _frames(20)
	var start := me.global_position
	Input.action_press(&"move_forward")
	await _frames(40)
	Input.action_release(&"move_forward")
	await _frames(30)
	_check(me.global_position.distance_to(start) > 1.5, "client moves (not corrected by server)")

	await _voice_exchange(1, 440.0, 500.0)

	# Shoot the host until the server says it is dead.
	Input.action_press(&"aim")
	var t := 0.0
	while not host.health.is_dead and t < 10.0:
		_aim_at(me, host.global_position + Vector3.UP * 1.0)
		Input.action_press(&"shoot")
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	Input.action_release(&"shoot")
	Input.action_release(&"aim")
	_check(host.health.is_dead, "host death replicated to client")
	await _frames(10)
	_check(NetworkManager.roster.get(me.peer_id, {}).get("kills", 0) >= 1, "client sees its kill in roster")
	_check(_kill_feed_seen, "kill feed on client")
	var ended: Variant = await _wait_for(func() -> Variant: return true if Match.is_ended() else null)
	_check(ended == true and Match.winner_text == "Red team wins!", "match end replicated (%s)" % Match.winner_text)
	_check(NetworkManager.ping_ms >= 0 and NetworkManager.ping_ms < 200, "ping measured (%d ms)" % NetworkManager.ping_ms)

	var rotated: Variant = await _wait_for(func() -> Variant:
		var l := _level()
		return l if l and l.name == "Warehouse" and l.player and l.get_player(1) else null)
	_check(rotated != null, "client follows the map rotation and respawns")
	_check(not Match.is_ended(), "client sees the new match running")

	NetworkManager.leave()
	await _frames(30)
	_finish()


# -----------------------------------------------------------------------------
# Bomb Defusal: 3 rounds, first to 2.
#   R1: client (red, attacker) plants at B → host (blue) walks over and defuses.
#   R2: client eliminates the host.
#   R3: client plants again and the bomb explodes → Red wins the match.
# -----------------------------------------------------------------------------

func _configure_bomb() -> void:
	var b := Match.bomb
	b.freeze_time = 1.5
	b.round_time = 60.0
	b.bomb_time = 3.0
	b.round_end_time = 1.5
	b.halftime_after = 0
	Match.results_time = 30.0


func _run_bomb_host() -> void:
	var b := Match.bomb
	NetworkManager.local_name = "Host"
	Match.configure(GameConfig.Mode.BOMB, 2)
	_configure_bomb()
	_check(NetworkManager.host(_port, 4, false, GameConfig.map_path("test_map"), -1) == OK, "bomb host starts")
	var level: Level = await _wait_for(func() -> Variant: return _level())
	var me: PlayerController = await _wait_for(func() -> Variant: return level.get_player(1))
	var waiting: Variant = await _wait_for(func() -> Variant: return true if b.waiting_for_players else null)
	_check(waiting == true and b.phase == BombRules.Phase.FREEZE, "freeze waits while only one team has players")
	var client: PlayerController = await _wait_for(func() -> Variant:
		var ps := level.get_players().filter(func(p: PlayerController) -> bool: return p.peer_id != 1)
		return ps[0] if not ps.is_empty() else null)
	if client == null:
		return _finish()
	var client_id := client.peer_id
	_check(not b.is_attacker(1) and b.is_attacker(client_id), "host defends, client attacks")
	var live: Variant = await _wait_for(func() -> Variant: return true if b.phase == BombRules.Phase.LIVE else null)
	_check(live == true and b.bomb_carrier == client_id, "round 1 live, client carries the bomb")

	# R1: wait for the plant, walk to the bomb and defuse with the real Interact key.
	var planted: Variant = await _wait_for(func() -> Variant: return true if b.bomb_state == BombRules.BombState.PLANTED else null)
	_check(planted == true and b.bomb_site == "B", "host sees the bomb planted at B")
	b.bomb_time = 30.0 # the host needs time to walk over (server-side timer)
	b.phase_time_left = 30.0
	await _walk_to(me, b.bomb_position, 1.2)
	await _frames(20)
	_press(&"interact", true)
	var defused: Variant = await _wait_for(func() -> Variant: return true if b.bomb_state == BombRules.BombState.DEFUSED else null)
	_press(&"interact", false)
	_check(defused == true and b.round_winner == 0, "host defuses → Blue wins round 1")
	b.bomb_time = 3.0

	# R2: stand still at spawn and get eliminated.
	var r2: Variant = await _wait_for(func() -> Variant: return true if b.round_number == 2 else null)
	_check(r2 == true and not me.health.is_dead, "round 2: host revived")
	var r2_end: Variant = await _wait_for(func() -> Variant: return true if b.phase == BombRules.Phase.ROUND_END else null)
	_check(r2_end == true and b.round_reason == "Defenders eliminated" and b.round_winner == 1, "client eliminates the host → Red wins round 2")

	# R3: the bomb explodes.
	var over: Variant = await _wait_for(func() -> Variant: return true if Match.is_ended() else null)
	_check(over == true and b.round_reason == "Bomb exploded", "round 3: bomb explodes (%s)" % b.round_reason)
	_check(Match.winner_text == "Red team wins!" and Match.team_scores[1] == 2 and Match.team_scores[0] == 1,
		"Red wins the match 2–1")
	var left: Variant = await _wait_for(func() -> Variant:
		return true if level.get_player(client_id) == null else null)
	_check(left == true, "client leaves")
	_finish()


func _run_bomb_client() -> void:
	var b := Match.bomb
	await get_tree().create_timer(1.0).timeout
	NetworkManager.local_name = "Client"
	_check(NetworkManager.join("127.0.0.1", _port) == OK, "bomb client connects")
	var level: Level = await _wait_for(func() -> Variant: return _level())
	var me: PlayerController = await _wait_for(func() -> Variant: return level.player if level else null)
	var host: PlayerController = await _wait_for(func() -> Variant: return level.get_player(1))
	if me == null or host == null:
		return _finish()
	_check(Match.mode == GameConfig.Mode.BOMB, "client knows it's Bomb Defusal")
	var live: Variant = await _wait_for(func() -> Variant:
		return true if b.phase == BombRules.Phase.LIVE and b.bomb_carrier == me.peer_id else null)
	_check(live == true, "client carries the bomb when round 1 goes live")

	# R1: walk to site B and plant with the Interact key.
	await _plant_at_b(me)
	_check(b.bomb_state == BombRules.BombState.PLANTED and b.bomb_site == "B", "client planted at B")
	var r1: Variant = await _wait_for(func() -> Variant: return true if b.bomb_state == BombRules.BombState.DEFUSED else null)
	_check(r1 == true and b.round_winner == 0 and Match.team_scores[0] == 1, "client sees the defuse (Blue 1–0)")

	# R2: shoot the host.
	var r2: Variant = await _wait_for(func() -> Variant:
		return true if b.round_number == 2 and b.phase == BombRules.Phase.LIVE else null)
	_check(r2 == true, "round 2 live")
	Input.action_press(&"aim")
	var t := 0.0
	while not host.health.is_dead and t < 15.0:
		_aim_at(me, host.global_position + Vector3.UP * 1.0)
		Input.action_press(&"shoot")
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_release_inputs()
	var r2_end: Variant = await _wait_for(func() -> Variant: return true if b.phase == BombRules.Phase.ROUND_END else null)
	_check(r2_end == true and b.round_winner == 1, "Red wins round 2 (1–1)")

	# R3: plant and wait for the explosion.
	var r3: Variant = await _wait_for(func() -> Variant:
		return true if b.round_number == 3 and b.phase == BombRules.Phase.LIVE and b.bomb_carrier == me.peer_id else null)
	_check(r3 == true, "round 3 live with the bomb")
	await _plant_at_b(me)
	var over: Variant = await _wait_for(func() -> Variant: return true if Match.is_ended() else null)
	_check(over == true and Match.winner_text == "Red team wins!", "client sees Red win the match")
	NetworkManager.leave()
	await _frames(10)
	_finish()


func _plant_at_b(me: PlayerController) -> void:
	var site: Vector3 = (_level().bomb_sites.filter(func(m: Marker3D) -> bool: return m.name == "B")[0] as Marker3D).global_position
	await _walk_to(me, site, 0.8)
	await _frames(20)
	_press(&"interact", true)
	await _wait_for(func() -> Variant:
		return true if Match.bomb.bomb_state == BombRules.BombState.PLANTED else null)
	_press(&"interact", false)


## Walks `p` (the local player) towards `target` until within `radius` metres.
func _walk_to(p: PlayerController, target: Vector3, radius: float) -> void:
	var t := 0.0
	while t < 20.0:
		var flat := Vector3(target.x - p.global_position.x, 0, target.z - p.global_position.z)
		if flat.length() <= radius:
			break
		p.rotation.y = atan2(-flat.x, -flat.z)
		Input.action_press(&"move_forward")
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	Input.action_release(&"move_forward")


## Sends a real input event (reaches _unhandled_input like a key press).
func _press(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _release_inputs() -> void:
	for a in InputMap.get_actions():
		Input.action_release(a)


## Joins a dedicated server (started with `-- --server`) and checks the basics.
func _run_observer() -> void:
	await get_tree().create_timer(1.5).timeout
	NetworkManager.local_name = "Observer"
	_check(NetworkManager.join("127.0.0.1", _port) == OK, "observer starts connecting")
	var level: Level = await _wait_for(func() -> Variant: return _level())
	var me: PlayerController = await _wait_for(func() -> Variant: return level.player if level else null)
	_check(me != null, "spawned on dedicated server")
	_check(level.get_player(1) == null, "dedicated server has no player of its own")
	_check(NetworkManager.roster.size() == 1, "roster only contains us")
	NetworkManager.leave()
	await _frames(10)
	_finish()


## Both sides talk at once (push-to-talk, team channel) with a test tone and
## check that the other side's tone arrives intact.
func _voice_exchange(other_id: int, my_freq: float, their_freq: float) -> void:
	# The other side may already be talking when we get here.
	var started := [VoiceChat.is_speaking(other_id)]
	var stopped := [false]
	VoiceChat.speaking_changed.connect(func(id: int, speaking: bool) -> void:
		if id == other_id:
			if speaking: started[0] = true
			else: stopped[0] = true)
	# Different teams → proximity chat (team chat would not cross teams).
	Input.action_press(&"push_to_talk_proximity")
	var phase := 0.0
	var t := 0.0
	var got: Variant = null
	while t < 15.0:
		# Feed ~one frame of "microphone" audio, like a real mic would.
		var chunk := PackedFloat32Array()
		chunk.resize(16000 / 60)
		for i in chunk.size():
			chunk[i] = 0.3 * sin(phase)
			phase += TAU * my_freq / 16000.0
		VoiceChat.inject_test_audio(chunk)
		await get_tree().process_frame
		t += get_process_delta_time()
		var pb := VoiceChat.get_playback(other_id)
		if t > 2.0 and pb and pb.packets_received > 20:
			got = pb
			break
	# Keep talking a little so the other side also finishes its check.
	for i in 60:
		var chunk := PackedFloat32Array()
		chunk.resize(16000 / 60)
		for j in chunk.size():
			chunk[j] = 0.3 * sin(phase)
			phase += TAU * my_freq / 16000.0
		VoiceChat.inject_test_audio(chunk)
		await get_tree().process_frame
	Input.action_release(&"push_to_talk_proximity")
	_check(VoiceChat.packets_sent > 20, "voice packets sent (%d)" % VoiceChat.packets_sent)
	var pb: VoicePlayback = got
	_check(pb != null, "voice received from the other player (%d packets)" % (pb.packets_received if pb else 0))
	if pb:
		var f := _estimate_frequency(pb.last_decoded)
		_check(absf(f - their_freq) < 10.0, "received tone is %.0f Hz (expected %.0f)" % [f, their_freq])
	_check(started[0], "speaking indicator turned on")
	await get_tree().create_timer(1.0).timeout
	_check(stopped[0], "speaking indicator turned off after release")


## Frequency from the time between the first and last zero crossing
## (sub-sample accurate), so short packets still give a precise answer.
static func _estimate_frequency(samples: PackedFloat32Array) -> float:
	var crossings: Array[float] = []
	for i in range(1, samples.size()):
		var a := samples[i - 1]
		var b := samples[i]
		if (a < 0.0) != (b < 0.0):
			crossings.append(i - 1 + a / (a - b))
	if crossings.size() < 3:
		return 0.0
	var span := (crossings[-1] - crossings[0]) / 16000.0
	return (crossings.size() - 1) * 0.5 / span


# -----------------------------------------------------------------------------

func _level() -> Level:
	return get_tree().current_scene as Level


func _aim_at(p: PlayerController, point: Vector3) -> void:
	var eye := p.camera.global_position
	var flat := Vector3(point.x - eye.x, 0, point.z - eye.z)
	p.rotation.y = atan2(-flat.x, -flat.z)
	p.head.rotation.x = atan2(point.y - eye.y, flat.length())


## Polls `getter` every physics frame until it returns non-null (or times out).
func _wait_for(getter: Callable) -> Variant:
	var t := 0.0
	while t < TIMEOUT:
		var v: Variant = getter.call()
		if v != null:
			return v
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return null


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(ok: bool, label: String) -> void:
	print("[%s] %s %s" % [_role, "✔" if ok else "✘", label])
	if not ok:
		_failures += 1


func _finish() -> void:
	print("[%s] %s — %d failure(s)" % [_role, "PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)
