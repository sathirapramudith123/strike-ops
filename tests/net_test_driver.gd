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
	NetworkManager.kill_feed.connect(func(_k: String, _v: String, _w: String, _h: bool) -> void:
		_kill_feed_seen = true)
	get_tree().create_timer(TIMEOUT * 2.0).timeout.connect(func() -> void:
		print("[%s] global timeout" % _role)
		get_tree().quit(2))
	match _role:
		"host": _run_host()
		"observer": _run_observer()
		_: _run_client()


func _run_host() -> void:
	NetworkManager.local_name = "Host"
	_check(NetworkManager.host(_port, 4) == OK, "host starts listening")
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
	var start := client.global_position
	var moved: Variant = await _wait_for(func() -> Variant:
		return true if client.global_position.distance_to(start) > 1.0 else null)
	_check(moved == true, "client movement replicated to host")

	var hurt: Variant = await _wait_for(func() -> Variant:
		return true if me.health.current < me.health.max_health or me.health.is_dead else null)
	_check(hurt == true, "client's shots damage the host (server-side hit)")
	var died: Variant = await _wait_for(func() -> Variant: return true if me.health.is_dead else null)
	_check(died == true, "host player dies")
	_check(NetworkManager.roster.get(client_id, {}).get("kills", 0) >= 1, "kill credited to client")
	_check(NetworkManager.roster.get(1, {}).get("deaths", 0) >= 1, "death credited to host")
	_check(_kill_feed_seen, "kill feed on host")
	var back: Variant = await _wait_for(func() -> Variant: return true if not me.health.is_dead else null)
	_check(back == true and me.health.current == me.health.max_health, "host respawns with full health")

	await _voice_exchange(client_id, 500.0, 440.0)

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

	# Walk forward a bit (server must accept it — no snap-back).
	await _frames(20)
	var start := me.global_position
	Input.action_press(&"move_forward")
	await _frames(40)
	Input.action_release(&"move_forward")
	await _frames(30)
	_check(me.global_position.distance_to(start) > 1.5, "client moves (not corrected by server)")

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
	var respawned: Variant = await _wait_for(func() -> Variant:
		return true if not host.health.is_dead and host.visible else null)
	_check(respawned == true, "host respawn replicated to client")
	_check(NetworkManager.ping_ms >= 0 and NetworkManager.ping_ms < 200, "ping measured (%d ms)" % NetworkManager.ping_ms)

	await _voice_exchange(1, 440.0, 500.0)

	NetworkManager.leave()
	await _frames(30)
	_finish()


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
	var started := [false]
	var stopped := [false]
	VoiceChat.speaking_changed.connect(func(id: int, speaking: bool) -> void:
		if id == other_id:
			if speaking: started[0] = true
			else: stopped[0] = true)
	Input.action_press(&"push_to_talk_team")
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
	Input.action_release(&"push_to_talk_team")
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
