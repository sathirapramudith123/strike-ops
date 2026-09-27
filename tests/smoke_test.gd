extends Node
## Headless smoke test for Phase 1 gameplay.
## Run:  godot --headless --path . res://tests/smoke_test.tscn
## Exits with code 0 when every check passes, 1 otherwise.

const TEST_MAP := "res://scenes/levels/test_map.tscn"

var _failures := 0
var _level: Level
var _player: PlayerController


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_level = (load(TEST_MAP) as PackedScene).instantiate() as Level
	add_child(_level)
	await _frames(10)
	_check(_level != null, "test map loads")
	_player = _level.player
	_check(_player != null, "player spawned")
	await _frames(30)
	_check(_player.is_on_floor(), "player lands on the floor")

	await _test_walk_and_sprint()
	await _test_jump()
	await _test_crouch_and_slide()
	await _test_shooting()
	await _test_reload()
	await _test_ramps()
	await _test_pause_disables_input()
	await _test_fall_death_and_respawn()
	_test_lag_compensation()
	_test_voice_codec()
	await _test_voice_loopback()
	await _test_weapon_switching()
	await _test_shotgun_and_sniper()
	await _test_loadout_on_respawn()
	await _test_audio()
	await _test_controller()
	_test_friendly_fire_and_match_end()
	await _test_bomb_defusal()
	await _test_settings_menu()
	await _test_performance()
	await _test_maps()
	_test_hardware_report()

	print("\n%s — %d failure(s)" % ["PASSED" if _failures == 0 else "FAILED", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_walk_and_sprint() -> void:
	_reset_player(Vector3(0, 0.1, 6))
	var start := _player.global_position
	Input.action_press(&"move_forward")
	await _frames(30)
	var walk_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	_check(_player.global_position.z < start.z - 1.0, "walking forward moves the player")
	_check(absf(walk_speed - _player.walk_speed) < 0.3, "walk speed ≈ %.1f (got %.2f)" % [_player.walk_speed, walk_speed])
	Input.action_press(&"sprint")
	await _frames(30)
	var sprint_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	_check(_player.is_sprinting and sprint_speed > walk_speed + 2.0, "sprinting is faster (got %.2f)" % sprint_speed)
	_release_all()
	await _frames(30)
	_check(Vector2(_player.velocity.x, _player.velocity.z).length() < 0.1, "player decelerates to a stop")


func _test_jump() -> void:
	_reset_player(Vector3(0, 0.1, 6))
	await _frames(10)
	var ground_y := _player.global_position.y
	Input.action_press(&"jump")
	await _frames(2)
	Input.action_release(&"jump")
	var peak := ground_y
	for i in 40:
		await get_tree().physics_frame
		peak = maxf(peak, _player.global_position.y)
	_check(peak > ground_y + 1.0, "jump reaches > 1 m (got %.2f)" % (peak - ground_y))
	await _frames(40)
	_check(_player.is_on_floor(), "player lands after jumping")


func _test_crouch_and_slide() -> void:
	_reset_player(Vector3(0, 0.1, 6))
	Input.action_press(&"crouch")
	await _frames(30)
	var shape := _player.get_node("CollisionShape3D").shape as CapsuleShape3D
	_check(_player.is_crouching and shape.height < 1.2, "crouch shrinks the capsule (%.2f)" % shape.height)
	_release_all()
	await _frames(30)
	_check(not _player.is_crouching and shape.height > 1.75, "standing up restores height")

	# Crouch tunnel: stay crouched under the 1.4 m ceiling.
	_reset_player(Vector3(-2.5, 0.1, 15.5))
	Input.action_press(&"crouch")
	Input.action_press(&"move_forward")
	await _frames(70)
	Input.action_release(&"crouch")
	await _frames(10)
	_check(_player.is_crouching, "player stays crouched under a low ceiling")
	_release_all()
	await _frames(60)

	_reset_player(Vector3(0, 0.1, 10))
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _frames(40)
	Input.action_press(&"crouch")
	await _frames(3)
	_check(_player.is_sliding, "crouch while sprinting starts a slide")
	await _frames(100)
	_check(not _player.is_sliding, "slide ends by itself")
	_release_all()
	await _frames(20)


func _test_shooting() -> void:
	var target := _level.get_node("Targets/Target2") as TargetDummy
	_reset_player(Vector3(0, 0.1, -12))
	await _frames(5)
	_aim_at(target.global_position + Vector3(0, 0.8, 0))
	var weapon := _player.current_weapon
	var ammo_before := weapon.ammo_in_magazine
	var hits := [0]
	weapon.hit_confirmed.connect(func(_k: bool, _h: bool) -> void: hits[0] += 1)
	Input.action_press(&"aim")
	await _frames(20)
	_check(weapon.ads_blend > 0.99, "aim down sights")
	_check(_player.camera.fov < SettingsManager.field_of_view, "ADS zooms the camera")
	Input.action_press(&"shoot")
	await _frames(20)
	_release_all()
	_check(weapon.ammo_in_magazine < ammo_before, "shooting uses ammo (%d → %d)" % [ammo_before, weapon.ammo_in_magazine])
	_check(hits[0] > 0, "shots hit the target (%d hits)" % hits[0])
	_check(target.health.current < target.health.max_health or target.health.is_dead, "target takes damage")


func _test_reload() -> void:
	var weapon := _player.current_weapon
	await _frames(40)
	Input.action_press(&"reload")
	await _frames(2)
	Input.action_release(&"reload")
	_check(weapon.is_reloading, "reload starts")
	await _frames(int(weapon.data.reload_time * 60.0) + 10)
	_check(not weapon.is_reloading and weapon.ammo_in_magazine == weapon.data.magazine_size, "reload refills the magazine")


func _test_ramps() -> void:
	# Ramp up to the platform at (18, 3, -18).
	_reset_player(Vector3(18, 0.1, -2))
	Input.action_press(&"move_forward")
	await _frames(240)
	_release_all()
	_check(_player.global_position.y > 2.8, "walk up the ramp onto the platform (y=%.2f)" % _player.global_position.y)

	# Stairs going +z from (-18, 0, -10.25) to the top at z≈-4.75.
	_reset_player(Vector3(-18, 0.1, -13), PI)
	Input.action_press(&"move_forward")
	var highest := 0.0
	for i in 110:
		await get_tree().physics_frame
		highest = maxf(highest, _player.global_position.y)
	_release_all()
	_check(highest > 1.9, "walk up the stairs (max y=%.2f)" % highest)


func _test_pause_disables_input() -> void:
	_reset_player(Vector3(0, 0.1, 6))
	_level.pause_menu.open()
	await _frames(10)
	var start := _player.global_position
	Input.action_press(&"move_forward")
	await _frames(20)
	_release_all()
	var moved := Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length()
	_check(moved < 0.05, "pause menu blocks movement")
	_level.pause_menu.close()


func _test_fall_death_and_respawn() -> void:
	_reset_player(Vector3(0, -35, 6))
	await _frames(5)
	_check(_player.health.is_dead, "falling out of the map kills the player")
	var deaths: int = NetworkManager.roster.get(1, {}).get("deaths", 0)
	_check(deaths >= 1, "death counted in roster (%d)" % deaths)
	await _frames(int(_player.respawn_delay * 60.0) + 10)
	_check(not _player.health.is_dead and _player.global_position.y > -1.0, "player respawns at a spawn point")


func _test_lag_compensation() -> void:
	# Pure math.
	var t_sphere := LagCompensation.ray_sphere(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, -10), 1.0)
	_check(is_equal_approx(t_sphere, 9.0), "ray_sphere distance (%.2f)" % t_sphere)
	var t_caps := LagCompensation.ray_capsule(Vector3(0, 1, 0), Vector3.FORWARD, Vector3(0, 0.35, -10), Vector3(0, 1.4, -10), 0.35)
	_check(is_equal_approx(t_caps, 9.65), "ray_capsule side hit (%.2f)" % t_caps)
	var t_miss := LagCompensation.ray_capsule(Vector3(2, 1, 0), Vector3.FORWARD, Vector3(0, 0.35, -10), Vector3(0, 1.4, -10), 0.35)
	_check(t_miss < 0.0, "ray_capsule miss")

	# Rewind: a remote player was at x=-6 at t0 and x=-2 at t1.
	var remote := _level.spawn_player(99, "Remote", Transform3D(Basis.IDENTITY, Vector3(-6, 0, 20)))
	var t0 := NetworkManager.server_time() + 10.0
	remote.net_sync._push_snapshot(t0, Vector3(-6, 0, 20), 0.0, 0.0, 1.8, 0)
	remote.net_sync._push_snapshot(t0 + 0.2, Vector3(-2, 0, 20), 0.0, 0.0, 1.8, 0)
	var space := _level.get_world_3d().direct_space_state
	var players := _level.get_players()
	var origin := Vector3(-6, 1.2, 26)
	var hit_old := LagCompensation.trace(space, origin, Vector3.FORWARD, 50.0, _player, players, t0)
	_check(hit_old.get("hitbox") == remote.body_hitbox, "shot at the old position hits when rewound")
	var hit_new := LagCompensation.trace(space, origin, Vector3.FORWARD, 50.0, _player, players, t0 + 0.2)
	_check(hit_new.get("hitbox") != remote.body_hitbox, "same shot misses at the newer position")
	var mid := remote.net_sync.get_state_at(t0 + 0.1)
	_check((mid.pos as Vector3).is_equal_approx(Vector3(-4, 0, 20)), "history interpolates between snapshots")
	var head := LagCompensation.trace(space, Vector3(-6, 1.6, 26), Vector3.FORWARD, 50.0, _player, players, t0)
	_check(head.get("hitbox") == remote.head_hitbox, "head height hits the head hitbox")
	_level.despawn_player(99)


func _test_voice_codec() -> void:
	# 440 Hz tone, 40 ms @ 16 kHz.
	var n := 640
	var tone := PackedFloat32Array()
	tone.resize(n)
	for i in n:
		tone[i] = 0.5 * sin(TAU * 440.0 * i / 16000.0)
	var packet := VoiceCodec.encode(tone)
	_check(packet.size() == 3 + n / 2, "ADPCM packet is 4 bits/sample (%d bytes)" % packet.size())
	var decoded := VoiceCodec.decode(packet, n)
	var sig := 0.0
	var err := 0.0
	for i in n:
		sig += tone[i] * tone[i]
		err += (tone[i] - decoded[i]) * (tone[i] - decoded[i])
	var snr := 10.0 * log(sig / maxf(err, 1e-12)) / log(10.0)
	_check(snr > 25.0, "ADPCM round-trip SNR %.1f dB" % snr)

	_test_opus()

	var proc := VoiceProcessor.new()
	proc.set_input_rate(48000.0)
	var in48 := PackedFloat32Array()
	in48.resize(4800)
	var out16 := proc.resample(in48)
	_check(absi(out16.size() - 1600) <= 1, "48 kHz → 16 kHz resampler (%d samples)" % out16.size())

	# Proximity relay rule.
	var near := _level.spawn_player(201, "Near", Transform3D(Basis.IDENTITY, _player.global_position + Vector3(5, 0, 0)))
	var far := _level.spawn_player(202, "Far", Transform3D(Basis.IDENTITY, _player.global_position + Vector3(0, 0, 60)))
	var players := _level.get_players()
	var prox := VoiceChat.recipients_for(1, VoiceChat.Channel.PROXIMITY, players)
	_check(201 in prox and not 202 in prox, "proximity voice only reaches nearby players")
	var team := VoiceChat.recipients_for(1, VoiceChat.Channel.TEAM, players)
	_check(201 in team and 202 in team and not 1 in team, "team voice reaches everyone else")
	_level.despawn_player(201)
	_level.despawn_player(202)


## Phase 5b: Opus codec (GDExtension), FEC, concealment, negotiation.
func _test_opus() -> void:
	_check(VoiceCodec.opus_available(), "Opus extension loaded (%s)" % VoiceCodec.opus_version())
	_check(VoiceChat.use_opus_for({1: {"opus": true}, 2: {"opus": true}}, true) == VoiceCodec.opus_available()
		and not VoiceChat.use_opus_for({1: {"opus": true}, 2: {"opus": false}}, true)
		and not VoiceChat.use_opus_for({1: {"opus": true}, 2: {}}, true),
		"Opus only when every player has it (else ADPCM)")
	if not VoiceCodec.opus_available():
		return
	# One second of a 440 Hz tone, packet by packet.
	var enc := VoiceEncoder.new()
	enc.use_opus = true
	var packets: Array[PackedByteArray] = []
	var bytes := 0
	var frame := PackedFloat32Array()
	frame.resize(VoiceEncoder.PACKET_SAMPLES)
	for k in 25:
		for i in frame.size():
			frame[i] = 0.5 * sin(TAU * 440.0 * (k * frame.size() + i) / 16000.0)
		var p := enc.encode(frame)
		packets.append(p)
		bytes += p.size()
	var kbps := bytes * 8.0 / 1000.0
	_check(packets[0][0] == VoiceCodec.CODEC_OPUS and kbps < 40.0,
		"Opus: %.0f kbps (ADPCM: 64 kbps)" % kbps)

	# Lose packet 12: the decoder rebuilds it from packet 13's FEC data.
	var dec := VoiceDecoder.new()
	var out := PackedFloat32Array()
	for k in 25:
		if k == 12:
			continue
		out.append_array(dec.decode(packets[k], VoiceEncoder.PACKET_SAMPLES, 1 if k == 13 else 0))
	_check(out.size() == 25 * VoiceEncoder.PACKET_SAMPLES and dec.concealed == 1,
		"a lost packet is rebuilt (FEC): %d samples" % out.size())
	var lost_part := out.slice(12 * 640, 13 * 640)
	_check(_rms(lost_part) > 0.15, "rebuilt audio isn't silence (RMS %.2f)" % _rms(lost_part))
	var tail := out.slice(20 * 640)
	var f := _zero_cross_hz(tail)
	_check(absf(f - 440.0) < 10.0 and absf(_rms(tail) - 0.354) < 0.1,
		"Opus round trip: %.0f Hz, RMS %.2f (sent 440 Hz, 0.35)" % [f, _rms(tail)])

	# Two lost in a row: concealment + FEC.
	var dec2 := VoiceDecoder.new()
	var n := 0
	for k in 10:
		if k == 4 or k == 5:
			continue
		n += dec2.decode(packets[k], 640, 2 if k == 6 else 0).size()
	_check(n == 10 * 640 and dec2.concealed == 2, "two lost packets are concealed (%d samples)" % n)

	# A gap the server made on purpose (listener out of proximity range) is not
	# packet loss: nothing is concealed. A real gap is.
	var pb := VoicePlayback.new()
	add_child(pb)
	pb.push_packet(1, 0, packets[0], 640)
	pb.push_packet(3, 0, packets[2], 640, true)
	var after_fresh := pb.concealed
	pb.push_packet(5, 0, packets[4], 640)
	_check(after_fresh == 0 and pb.concealed == 1, "skipped-on-purpose gaps aren't concealed, lost packets are")
	pb.queue_free()

	# End of a sentence: a short tail is padded for Opus and trimmed again.
	var short := enc.encode(frame.slice(0, 300))
	_check(dec.decode(short, 300).size() == 300, "short last packet keeps its length")
	# Garbage never crashes and never returns more than one packet.
	var junk := PackedByteArray([VoiceCodec.CODEC_OPUS, 0xFF, 0xFE, 0x03, 0x99, 0x00, 0x42])
	_check(dec.decode(junk, 640).size() <= 640 and dec.decode(PackedByteArray([7, 1, 2]), 640).is_empty(),
		"corrupt / unknown packets are dropped safely")
	# Same decoder also plays ADPCM packets (codec byte).
	enc.use_opus = false
	var adpcm := enc.encode(frame)
	_check(adpcm[0] == VoiceCodec.CODEC_ADPCM and adpcm.size() == 1 + 3 + 320
		and dec.decode(adpcm, 640).size() == 640, "ADPCM fallback packets decode too")


func _rms(samples: PackedFloat32Array) -> float:
	var s := 0.0
	for v in samples:
		s += v * v
	return sqrt(s / maxf(samples.size(), 1))


func _zero_cross_hz(samples: PackedFloat32Array) -> float:
	var first := -1.0
	var last := -1.0
	var count := 0
	for i in range(1, samples.size()):
		if samples[i - 1] < 0.0 and samples[i] >= 0.0:
			var t := i - 1 + samples[i - 1] / (samples[i - 1] - samples[i])
			if first < 0.0:
				first = t
			else:
				count += 1
			last = t
	return count * 16000.0 / (last - first) if count > 0 else 0.0


func _test_voice_loopback() -> void:
	VoiceChat.loopback = true
	var tone := PackedFloat32Array()
	tone.resize(16000)
	for i in tone.size():
		tone[i] = 0.3 * sin(TAU * 300.0 * i / 16000.0)
	VoiceChat.inject_test_audio(tone)
	await _frames(20)
	var pb := VoiceChat.get_playback(multiplayer.get_unique_id())
	_check(pb != null and pb.samples_decoded >= 15000, "mic test loopback decodes the injected audio")
	_check(VoiceChat.last_codec_sent == (VoiceCodec.CODEC_OPUS if VoiceCodec.opus_available() else VoiceCodec.CODEC_ADPCM),
		"mic test uses %s" % VoiceCodec.codec_name(VoiceChat.last_codec_sent))
	_check(VoiceChat.input_level > 0.05, "mic level meter reacts (%.2f)" % VoiceChat.input_level)
	VoiceChat.loopback = false


func _test_weapon_switching() -> void:
	_reset_player(Vector3(0, 0.1, 6))
	await _frames(5)
	_check(_player.current_weapon.data.weapon_id == "rifle", "starts with the rifle")
	_tap(&"weapon_2")
	await _frames(3)
	_check(_player.current_weapon.data.weapon_id == "pistol", "key 2 switches to the pistol")
	var pistol := _player.current_weapon
	var before := pistol.ammo_in_magazine
	Input.action_press(&"shoot")
	await _frames(30)
	Input.action_release(&"shoot")
	_check(before - pistol.ammo_in_magazine == 1, "pistol is semi-automatic (one shot per click)")
	_tap(&"weapon_1")
	await _frames(3)
	_check(_player.current_weapon.data.weapon_id == "rifle", "key 1 switches back")


func _test_shotgun_and_sniper() -> void:
	var target := _level.get_node("Targets/Target1") as TargetDummy
	_player.apply_loadout("shotgun")
	await _frames(20) # let the dummy finish respawning from earlier tests
	target.health.revive()
	# Close range + aiming so the random pellet spread (4.5° ADS) stays on
	# the target (0.3 m capsule) — keeps the test deterministic.
	_reset_player(target.global_position + Vector3(0, 0.1, 3))
	await _frames(5)
	_aim_at(target.global_position + Vector3(0, 0.9, 0))
	Input.action_press(&"aim")
	await _frames(20)
	_aim_at(target.global_position + Vector3(0, 0.9, 0))
	var hits := [0]
	var on_damaged := func(_a: float, _s: Node, _h: bool) -> void: hits[0] += 1
	target.health.damaged.connect(on_damaged)
	Input.action_press(&"shoot")
	await _frames(2)
	Input.action_release(&"shoot")
	await _frames(2)
	target.health.damaged.disconnect(on_damaged)
	Input.action_release(&"aim")
	_check(hits[0] >= 5, "shotgun pellets hit several times (%d of 9)" % hits[0])
	target.health.revive()

	# Target2 from 10 m has a clear line of sight (see _test_shooting).
	target = _level.get_node("Targets/Target2") as TargetDummy
	target.health.revive()
	_player.apply_loadout("sniper")
	var sniper := _player.current_weapon
	_reset_player(Vector3(0, 0.1, -12))
	await _frames(5)
	_aim_at(target.global_position + Vector3(0, 0.9, 0))
	Input.action_press(&"aim")
	await _frames(30)
	_check(sniper.is_scoped(), "sniper scope engages when aiming")
	_check(_player.camera.fov < SettingsManager.field_of_view * 0.4, "scope zooms in (fov %.0f)" % _player.camera.fov)
	_check(not sniper.get_node("Model").visible, "viewmodel hidden while scoped")
	_aim_at(target.global_position + Vector3(0, 0.9, 0))
	Input.action_press(&"shoot")
	await _frames(2)
	_release_all()
	await _frames(5)
	_check(target.health.is_dead, "one sniper body shot kills")
	_player.apply_loadout("rifle")


func _test_loadout_on_respawn() -> void:
	Match.request_loadout("smg")
	_check(NetworkManager.roster[1].primary == "smg", "loadout stored in roster")
	_reset_player(Vector3(0, -35, 6))
	await _frames(int(_player.respawn_delay * 60.0) + 15)
	_check(_player.primary_id == "smg" and _player.current_weapon.data.weapon_id == "smg",
		"respawn uses the new primary (SMG)")
	_check(_player.current_weapon.ammo_in_magazine == _player.current_weapon.data.magazine_size, "ammo refilled on respawn")
	Match.request_loadout("rifle")


func _test_friendly_fire_and_match_end() -> void:
	# Team deathmatch rules offline: us (blue) + a teammate in front of an enemy.
	Match.configure(GameConfig.Mode.TDM, 1)
	NetworkManager.roster[1].team = 0
	NetworkManager.roster[401] = NetworkManager._new_entry("Mate")
	NetworkManager.roster[401].team = 0
	NetworkManager.roster[402] = NetworkManager._new_entry("Enemy")
	NetworkManager.roster[402].team = 1
	_reset_player(Vector3(-20, 0.1, 20))
	var mate := _level.spawn_player(401, "Mate", Transform3D(Basis.IDENTITY, Vector3(-20, 0, 15)))
	var enemy := _level.spawn_player(402, "Enemy", Transform3D(Basis.IDENTITY, Vector3(-20, 0, 10)))
	var rifle: Weapon = _player.weapons["rifle"]
	var origin := Vector3(-20, 1.2, 20)
	rifle._server_process_shot(origin, PackedVector3Array([Vector3.FORWARD]), NetworkManager.server_time())
	_check(mate.health.current == mate.health.max_health, "no friendly fire (teammate untouched)")
	_check(enemy.health.current < enemy.health.max_health, "bullet passes through teammate and hits the enemy")
	_check(Match.is_friendly(1, 401) and not Match.is_friendly(1, 402), "is_friendly follows teams")

	Match.results_time = 999.0
	NetworkManager.report_kill(1, 402, "AR-7", false)
	_check(Match.team_scores[0] == 1, "team score counts the kill")
	_check(Match.is_ended() and Match.winner_text == "Blue team wins!", "score limit ends the match (%s)" % Match.winner_text)
	_check(_level.hud.get_node("%EndScreen").visible, "results screen shown")
	_check(Audio.stats.get("ui:match_win", 0) == 1 and Audio.current_music == &"",
		"winning team hears the win sting, music fades out")

	# Map vote: rotation-next first, no duplicates, never the current map.
	var candidates := Match.vote_maps
	_check(candidates.size() == 3 and candidates[0] == GameConfig.next_map(NetworkManager.current_map, Match.mode),
		"map vote offers 3 maps, rotation first (%s)" % ", ".join(candidates))
	var unique := {}
	for p in candidates:
		unique[p] = true
	_check(unique.size() == candidates.size() and not NetworkManager.current_map in candidates,
		"map vote candidates are unique and exclude the current map")
	_check(Match.voted_map() == candidates[0], "no votes → rotation map wins")
	Match.request_vote(2)
	_check(Match.my_vote == 2 and Match.vote_counts[2] == 1 and Match.voted_map() == candidates[2],
		"vote is counted and decides the next map")
	Match.request_vote(1)
	_check(Match.vote_counts[2] == 0 and Match.vote_counts[1] == 1, "changing the vote moves it")
	var vote_text: String = _level.hud.get_node("%NextMapLabel").text if _level.hud.has_node("%NextMapLabel") else ""
	_check(vote_text.contains(GameConfig.map_name(candidates[1])) and vote_text.contains("1 vote"),
		"results screen shows the vote (%s)" % vote_text.replace("\n", " | "))
	var bomb_candidates := Match.vote_candidates(NetworkManager.current_map, GameConfig.Mode.BOMB)
	_check(bomb_candidates.size() == 3, "Bomb Defusal vote only needs bomb maps (%d)" % bomb_candidates.size())
	await_safe_cleanup(mate, enemy)


func await_safe_cleanup(mate: PlayerController, enemy: PlayerController) -> void:
	_level.despawn_player(mate.peer_id)
	_level.despawn_player(enemy.peer_id)
	NetworkManager.roster.erase(401)
	NetworkManager.roster.erase(402)
	NetworkManager.roster[1].team = GameConfig.TEAM_NONE
	Match.results_time = Match.RESULTS_TIME
	Match.configure(GameConfig.Mode.PRACTICE)
	Match.start_match()


## Full Bomb Defusal match offline: us (attacker, red) vs a scripted defender.
func _test_bomb_defusal() -> void:
	var b := Match.bomb
	Match.configure(GameConfig.Mode.BOMB, 2)
	b.freeze_time = 0.5
	b.round_time = 30.0
	b.bomb_time = 2.0
	b.round_end_time = 0.5
	b.halftime_after = 0
	Match.results_time = 999.0
	NetworkManager.roster[1].team = 1
	NetworkManager.roster[402] = NetworkManager._new_entry("Defender")
	NetworkManager.roster[402].team = 0
	var defender := _level.spawn_player(402, "Defender", Transform3D(Basis.IDENTITY, Vector3(0, 0, 14)))
	Match.start_match()
	await _frames(2)
	_check(b.round_number == 1 and b.phase == BombRules.Phase.FREEZE, "round 1 starts in freeze time")
	_check(b.is_attacker(1) and not b.is_attacker(402), "red attacks, blue defends")
	var start := _player.global_position
	Input.action_press(&"move_forward")
	await _frames(15)
	Input.action_release(&"move_forward")
	_check(Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length() < 0.05,
		"movement frozen during freeze time")
	await _frames(30)
	_check(b.phase == BombRules.Phase.LIVE, "round goes live after freeze")
	_check(b.bomb_carrier == 1 and b.bomb_state == BombRules.BombState.CARRIED, "the attacker gets the bomb when the round goes live")
	# Armour: full each Bomb Defusal round; soaks 40 % of a weapon hit.
	_check(is_equal_approx(_player.health.armor, 100.0), "bomb round starts with 100 armour")
	_player.health.take_damage(50.0, defender)
	_check(is_equal_approx(_player.health.current, 70.0) and is_equal_approx(_player.health.armor, 80.0),
		"armour takes 40 %% of a hit (health %.0f, armour %.0f)" % [_player.health.current, _player.health.armor])
	_check(_level.hud._armor_label.text == "80" and _level.hud._armor_group.visible, "HUD shows the armour")
	_player.health.take_damage(10.0, null, false, "Fall")
	_check(is_equal_approx(_player.health.current, 60.0), "falls ignore armour")
	_player.health.heal(100.0)

	# Drop + pick up.
	b.on_player_down(1, _player.global_position + Vector3(0.5, 0, 0))
	_check(b.bomb_state == BombRules.BombState.DROPPED, "bomb drops when the carrier goes down")
	await _frames(3)
	_check(b.bomb_state == BombRules.BombState.CARRIED and b.bomb_carrier == 1, "attacker picks the dropped bomb up")

	# Round 1: plant at B, the defender defuses.
	_reset_player(Vector3(9, 0.1, 0))
	await _frames(5)
	_check(b.site_at(_player.global_position) == "B", "standing inside site B")
	b.request_interact(true)
	await _frames(int(BombRules.PLANT_TIME * 60.0) + 10)
	b.request_interact(false)
	_check(b.bomb_state == BombRules.BombState.PLANTED and b.bomb_site == "B" and b.phase == BombRules.Phase.PLANTED,
		"bomb planted at B after holding interact")
	b.bomb_time = 30.0 # give the defender time in this round
	b.phase_time_left = 30.0
	defender.global_position = b.bomb_position + Vector3(1.0, 0, 0)
	b.server_set_interact(402, true)
	await _frames(int(BombRules.DEFUSE_TIME * 60.0) + 10)
	b.server_set_interact(402, false)
	_check(b.bomb_state == BombRules.BombState.DEFUSED and b.round_winner == 0 and b.round_reason == "Bomb defused",
		"defender defuses → Blue wins the round")
	_check(Match.team_scores[0] == 1 and Match.team_scores[1] == 0, "round score 1–0")

	# Round 2: plant at A and let it explode (we stay next to it).
	b.bomb_time = 2.0
	await _frames(45)
	_check(b.round_number == 2 and not _player.health.is_dead and not defender.health.is_dead, "round 2: everyone revived")
	await _frames(35)
	_reset_player(Vector3(-16, 0.1, -4))
	await _frames(3)
	b.request_interact(true)
	await _frames(int(BombRules.PLANT_TIME * 60.0) + 10)
	b.request_interact(false)
	_check(b.bomb_site == "A", "bomb planted at A")
	await _frames(int(2.0 * 60.0) + 15)
	_check(b.bomb_state == BombRules.BombState.EXPLODED and b.round_winner == 1 and b.round_reason == "Bomb exploded",
		"bomb explodes → Red wins the round")
	_check(_player.health.is_dead, "the explosion kills players next to it")
	_check(Match.team_scores[0] == 1 and Match.team_scores[1] == 1, "round score 1–1")

	# Round 3: eliminate the defender → Red reaches 2 round wins.
	await _frames(45)
	await _frames(35)
	_check(b.phase == BombRules.Phase.LIVE and b.round_number == 3, "round 3 live")
	defender.health.take_damage(500.0, _player)
	await _frames(2)
	_check(b.round_reason == "Defenders eliminated", "eliminating the defenders wins the round")
	_check(Match.is_ended() and Match.winner_text == "Red team wins!", "match ends at the round limit (%s)" % Match.winner_text)

	# Halftime: sides swap after the configured number of rounds.
	Match.state = Match.State.PLAYING
	b.halftime_after = 1
	Match.start_match()
	var first := b.attacking_team
	b._end_round(0, "test")
	b._start_round()
	_check(b.attacking_team != first and b.sides_swapped, "sides swap at halftime")

	_level.despawn_player(402)
	NetworkManager.roster.erase(402)
	NetworkManager.roster[1].team = GameConfig.TEAM_NONE
	b.freeze_time = 5.0
	b.round_time = 105.0
	b.bomb_time = 40.0
	b.round_end_time = 5.0
	b.halftime_after = -1
	Match.results_time = Match.RESULTS_TIME
	Match.configure(GameConfig.Mode.PRACTICE)
	Match.start_match()
	await _frames(int(_player.respawn_delay * 60.0) + 10)


func _test_settings_menu() -> void:
	_check(SettingsManager.settings_path == SettingsManager.TEST_SETTINGS_PATH, "tests use their own settings file")
	var menu := (load("res://scenes/ui/settings_menu.tscn") as PackedScene).instantiate() as SettingsMenu
	add_child(menu)
	menu.open()
	await _frames(2)
	var tabs := menu.get_node("%Tabs") as TabContainer
	_check(tabs.get_tab_count() == 6, "settings has 6 tabs")
	var all_built := true
	for i in tabs.get_tab_count():
		all_built = all_built and (tabs.get_child(i).get_node("Grid") as GridContainer).get_child_count() >= 4
	_check(all_built, "every tab has settings rows")

	# Graphics: editing one option turns the preset into Custom.
	SettingsManager.set_graphics_quality(GraphicsPreset.Quality.HIGH)
	menu._build_all()
	var msaa := _row_control(menu, "Graphics", "MSAA") as OptionButton
	msaa.select(0)
	msaa.item_selected.emit(0)
	_check(SettingsManager.graphics.quality == GraphicsPreset.Quality.CUSTOM and SettingsManager.graphics.msaa == Viewport.MSAA_DISABLED,
		"editing a graphics option → Custom preset")
	_check(get_viewport().msaa_3d == Viewport.MSAA_DISABLED, "custom option applied to the viewport")
	var cfg := ConfigFile.new()
	cfg.load(SettingsManager.settings_path)
	_check(cfg.get_value("graphics", "quality") == GraphicsPreset.Quality.CUSTOM, "custom preset saved")

	# Key remapping: jump → J, then jump → W swaps with move forward.
	menu._start_capture(&"jump")
	menu._input(_key(KEY_J))
	_check(SettingsManager.binding_text(&"jump") == "J", "jump rebound to J")
	menu._start_capture(&"jump")
	menu._input(_key(KEY_W))
	_check(SettingsManager.binding_text(&"jump") == "W" and SettingsManager.binding_text(&"move_forward") == "J",
		"rebinding to a used key swaps the two actions")
	cfg.load(SettingsManager.settings_path)
	_check((cfg.get_value("bindings", "jump") as Dictionary).code == KEY_W, "bindings saved to the settings file")
	menu._start_capture(&"reload")
	menu._input(_key(KEY_ESCAPE))
	_check(SettingsManager.binding_text(&"reload") == "R", "Esc cancels a rebind")

	# The new binding really drives the player (and the old key doesn't).
	SettingsManager.reset_bindings()
	menu._start_capture(&"jump")
	menu._input(_key(KEY_J))
	_reset_player(Vector3(0, 0.1, 6))
	await _frames(10)
	var y0 := _player.global_position.y
	Input.parse_input_event(_key(KEY_SPACE))
	await _frames(15)
	Input.parse_input_event(_key(KEY_SPACE, false))
	_check(_player.global_position.y - y0 < 0.1, "old key (Space) no longer jumps")
	await _frames(30)
	Input.parse_input_event(_key(KEY_J))
	await _frames(15)
	Input.parse_input_event(_key(KEY_J, false))
	_check(_player.global_position.y - y0 > 0.5, "new key (J) jumps")
	await _frames(40)
	SettingsManager.reset_bindings()
	_check(SettingsManager.binding_text(&"jump") == "Space" and SettingsManager.binding_text(&"move_forward") == "W",
		"reset restores the default bindings")

	# Toggle aim / crouch.
	SettingsManager.aim_toggle = true
	SettingsManager.crouch_toggle = true
	_reset_player(Vector3(0, 0.1, 6))
	await _frames(5)
	_tap_hold(&"aim")
	await _frames(20)
	_check(_player.current_weapon.is_aiming, "toggle aim stays aimed after releasing")
	_tap_hold(&"aim")
	await _frames(20)
	_check(not _player.current_weapon.is_aiming, "second press stops aiming")
	_tap_hold(&"crouch")
	await _frames(30)
	_check(_player.is_crouching, "toggle crouch stays crouched")
	_tap_hold(&"crouch")
	await _frames(30)
	_check(not _player.is_crouching, "second press stands up")
	SettingsManager.aim_toggle = false
	SettingsManager.crouch_toggle = false

	# Crosshair + reset tab.
	var colour := _row_control(menu, "Gameplay", "Colour") as OptionButton
	var green := SettingsManager.CROSSHAIR_COLORS.keys().find("Green")
	colour.select(green)
	colour.item_selected.emit(green)
	_check(SettingsManager.crosshair_color() == SettingsManager.CROSSHAIR_COLORS["Green"], "crosshair colour setting")
	SettingsManager.mouse_sensitivity = 0.8
	tabs.current_tab = SettingsMenu.TAB_NAMES.find("Controls")
	menu._reset_current_tab()
	_check(is_equal_approx(SettingsManager.mouse_sensitivity, 0.15), "Reset tab restores control defaults")
	menu.close()
	menu.queue_free()
	SettingsManager.crosshair_color_name = "White"
	SettingsManager.set_graphics_quality(GraphicsPreset.Quality.MEDIUM)


## The control next to the label `text` in a settings tab.
func _row_control(menu: SettingsMenu, tab: String, text: String) -> Control:
	var grid := menu._grid(tab)
	for i in range(0, grid.get_child_count() - 1):
		var l := grid.get_child(i) as Label
		if l and l.text == text:
			return grid.get_child(i + 1) as Control
	return null


func _key(code: Key, pressed: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	return e


func _tap_hold(action: StringName) -> void:
	Input.action_press(action)
	await _frames(3)
	Input.action_release(action)


## Phase 7 budgets — these fail if an optimisation regresses.
func _test_performance() -> void:
	# One shared decal node per level (was 32 nodes per weapon).
	var decals := get_tree().get_nodes_in_group(ImpactDecals.GROUP)
	_check(decals.size() == 1, "one ImpactDecals node per level (%d)" % decals.size())
	var before: int = (decals[0] as ImpactDecals).multimesh.visible_instance_count
	var rifle: Weapon = _player.weapons["rifle"]
	rifle._spawn_impact(Vector3(0, 1, -5), Vector3.BACK)
	_check((decals[0] as ImpactDecals).multimesh.visible_instance_count == before + 1 or before == ImpactDecals.MAX_DECALS,
		"impacts go into the shared MultiMesh")

	# Node budget per (remote) player.
	var bot := _level.spawn_player(777, "Budget", Transform3D(Basis.IDENTITY, Vector3(20, 0, 20)))
	var nodes := bot.find_children("*", "", true, false).size() + 1
	_check(nodes <= 90, "player node budget: %d ≤ 90" % nodes)
	_level.despawn_player(777)

	# Static batching on the test range.
	var st: Dictionary = _level.batch_stats
	_check(st.get("source_meshes", 0) > 20 and st.batches <= st.source_meshes / 2,
		"static batching: %d meshes → %d batches" % [st.get("source_meshes", 0), st.get("batches", 0)])
	_check(st.get("occluders", 0) > 0, "occluders created for large boxes (%d)" % st.get("occluders", 0))
	var details: Array = st.details
	var old_scale := SettingsManager.graphics.draw_distance_scale
	SettingsManager.graphics.draw_distance_scale = 0.5
	SettingsManager.apply_graphics()
	_check(details.is_empty() or is_equal_approx((details[0] as MeshInstance3D).visibility_range_end, StaticBatcher.DETAIL_DISTANCE * 0.5),
		"detail props follow the Draw distance setting")
	SettingsManager.graphics.draw_distance_scale = old_scale
	SettingsManager.apply_graphics()

	# Dynamic resolution controller.
	var dr := DynamicResolution.new()
	add_child(dr)
	SettingsManager.dynamic_resolution_target_fps = 60
	var fired := [false]
	dr.struggling.connect(func() -> void: fired[0] = true)
	var start_scale := dr.scale
	for i in 60:
		dr.update(40.0, DynamicResolution.INTERVAL) # 25 FPS: too slow
	_check(is_equal_approx(dr.scale, DynamicResolution.MIN_SCALE), "dynamic resolution drops to %.2f when slow" % dr.scale)
	_check(fired[0], "performance advisor fires when even minimum resolution is too slow")
	for i in 60:
		dr.update(5.0, DynamicResolution.INTERVAL) # 200 FPS: headroom
	_check(is_equal_approx(dr.scale, SettingsManager.graphics.render_scale), "…and recovers to the preset scale (%.2f)" % dr.scale)
	_check(start_scale <= SettingsManager.graphics.render_scale + 0.001, "never above the preset render scale")
	dr.queue_free()
	get_viewport().scaling_3d_scale = SettingsManager.graphics.render_scale

	# Benchmark statistics.
	var bench := BenchmarkRunner.new()
	for i in 99:
		bench._frame_ms.append(10.0)
	bench._frame_ms.append(100.0) # one hitch
	bench._samples = 100
	var stats := bench._stats("unit")
	_check(is_equal_approx(stats.one_percent_low_fps, 10.0) and stats.spikes_over_50ms == 1,
		"benchmark 1%% low = %.1f FPS, spikes = %d" % [stats.one_percent_low_fps, stats.spikes_over_50ms])
	bench.free()
	_check(not SettingsManager.vulkan_fallback_happened(), "no Vulkan-fallback false positive in headless")


func _test_maps() -> void:
	# Warehouse: ramp from the ground up to the catwalk (3 m).
	await _load_map("res://scenes/levels/warehouse.tscn")
	_check(_level.blue_spawn_points.size() >= 3 and _level.red_spawn_points.size() >= 3, "warehouse has team spawns")
	SettingsManager.set_graphics_quality(GraphicsPreset.Quality.LOW)
	_check(not (_level.get_node("Lights") as Node3D).visible, "Low preset turns decorative lights off")
	SettingsManager.set_graphics_quality(GraphicsPreset.Quality.MEDIUM)
	_check((_level.get_node("Lights") as Node3D).visible, "Medium preset turns them back on")
	await _frames(40)
	_check(_player.is_on_floor(), "warehouse: player lands on the floor")
	_reset_player(Vector3(15, 0.1, -2.0))
	Input.action_press(&"move_forward")
	var top := 0.0
	for i in 150:
		await get_tree().physics_frame
		top = maxf(top, _player.global_position.y)
	_release_all()
	_check(top > 2.8, "warehouse: ramp reaches the catwalk (max y=%.2f)" % top)
	# Reverb zones: the same point query the audio engine uses.
	var hall := _reverb_zone_at(Vector3(0, 2, 0))
	var office := _reverb_zone_at(Vector3(-18.5, 1.5, 12.5))
	_check(hall and hall.reverb_bus_name == &"ReverbHall" and office and office.reverb_bus_name == &"ReverbRoom"
		and office.priority > hall.priority, "warehouse: hall echo, drier offices (reverb zones)")
	_check(_reverb_zone_at(Vector3(0, 2, 40)) == null, "no reverb outside the building")

	# Courtyard: ramp inside the west building to the upper floor (3.6 m).
	await _load_map("res://scenes/levels/courtyard.tscn")
	await _frames(40)
	_check(_player.is_on_floor(), "courtyard: player lands on the floor")
	_reset_player(Vector3(-23.5, 0.1, 7.7))
	Input.action_press(&"move_forward")
	top = 0.0
	for i in 150:
		await get_tree().physics_frame
		top = maxf(top, _player.global_position.y)
	_release_all()
	_check(top > 3.4, "courtyard: ramp reaches the upper floor (max y=%.2f)" % top)

	# Rooftops: street ramp up to the north-west roof (4 m).
	await _load_map("res://scenes/levels/rooftops.tscn")
	await _frames(40)
	_check(_player.is_on_floor(), "rooftops: player lands")
	_reset_player(Vector3(-16, 0.1, 2.5))
	top = await _walk_forward_max_y(150)
	_check(top > 3.8, "rooftops: ramp reaches the roof (max y=%.2f)" % top)
	_reset_player(Vector3(-10, 4.1, -14), -PI * 0.5) # face +x, across the bridge
	await _frames(5)
	var across := await _walk_forward_max_y(220)
	_check(_player.global_position.x > 8.0 and _player.global_position.y > 3.8,
		"rooftops: bridge crosses to the other roof (x=%.1f, y=%.2f)" % [_player.global_position.x, _player.global_position.y])

	# Docks: gangway up to the ship deck (3 m).
	await _load_map("res://scenes/levels/docks.tscn")
	await _frames(40)
	_check(_player.is_on_floor(), "docks: player lands")
	_reset_player(Vector3(-18, 0.1, -3))
	await _walk_forward_max_y(200)
	_check(_player.global_position.y > 2.95 and _player.global_position.z < -16.0,
		"docks: gangway leads onto the deck (y=%.2f, z=%.1f)" % [_player.global_position.y, _player.global_position.z])

	# Bunker: walk from a south room door through the atrium to the north side.
	await _load_map("res://scenes/levels/bunker.tscn")
	await _frames(40)
	_check(_player.is_on_floor(), "bunker: player lands")
	_reset_player(Vector3(0, 0.1, 9))
	await _walk_forward_max_y(200)
	_check(_player.global_position.z < -7.0, "bunker: atrium doors are passable (z=%.1f)" % _player.global_position.z)

	# Kasbah: A ramp onto the terrace, Mid doors, the covered B Apartments.
	await _load_map("res://scenes/levels/kasbah.tscn")
	await _frames(40)
	_check(_player.is_on_floor(), "kasbah: player lands")
	_reset_player(Vector3(28, 0.1, -10.5))
	await _walk_forward_max_y(150)
	_check(_player.global_position.y > 0.95 and _player.global_position.z < -18.5,
		"kasbah: A ramp leads up onto the site terrace (y=%.2f, z=%.1f)" % [_player.global_position.y, _player.global_position.z])
	_reset_player(Vector3(0, 0.1, 4))
	await _walk_forward_max_y(150)
	_check(_player.global_position.z < -6.0, "kasbah: Mid doors are passable (z=%.1f)" % _player.global_position.z)
	_reset_player(Vector3(-32, 0.1, 22))
	await _walk_forward_max_y(330)
	_check(_player.global_position.z < -2.0, "kasbah: B Apartments corridor is passable (z=%.1f)" % _player.global_position.z)

	# Radar + location names (built from the map's collision shapes).
	var radar: Minimap = _level.hud._minimap
	_check(radar._polys.size() > 60, "radar outline built from the map (%d shapes)" % radar._polys.size())
	_check((_level.hud._banner.get_node(^"Title") as Label).text == "KASBAH", "map name banner shows KASBAH")
	var signs := _level.get_node_or_null(^"Signs")
	_check(signs != null and signs.get_child_count() >= 8, "painted A/B direction signs on the walls")
	_check(is_zero_approx(_player.health.armor), "no armour outside Bomb Defusal")
	_check(radar.location(Vector3(28, 1.1, -24)) == "Bombsite A" and radar.location(Vector3(0, 0.1, 8)) == "Mid"
		and radar.location(Vector3(-34, 0.1, 10)) == "B Apartments", "location names: Bombsite A, Mid, B Apartments")
	_check(radar.location(Vector3(-28, 0.1, -20)) == "Bombsite B", "bomb site fallback / callout for B")
	var armed := _player.loadout_weapons().all(func(w: Weapon) -> bool:
		return w == null or (w.has_node(^"ArmL") and w.has_node(^"ArmR") and w.has_node(^"Magazine")))
	_check(armed, "first-person weapons have gloved arms and a separate magazine")

	# Reload animation: the left hand pulls the magazine out and puts it back.
	var gun := _player.current_weapon
	gun.ammo_in_magazine = 0
	gun.reload()
	var arm := gun.get_node(^"ArmL") as Node3D
	var mag := gun.get_node(^"Magazine") as Node3D
	var lowest := 0.0
	var mag_lowest := 0.0
	while gun.is_reloading:
		await get_tree().process_frame
		lowest = minf(lowest, arm.position.y)
		mag_lowest = minf(mag_lowest, mag.position.y)
	await _frames(3)
	_check(lowest < -0.2 and mag_lowest < -0.1, "reload: left hand takes the magazine out (hand %.2f, mag %.2f)" % [lowest, mag_lowest])
	_check(arm.position.length() < 0.01 and mag.position.length() < 0.01 and mag.visible,
		"reload: hand and magazine back in place afterwards")
	var body := _player.get_node(^"ThirdPerson/Model") as PlayerModel
	body.start_reload(1.0)
	for i in 20:
		body.animate(1.0 / 60.0, false)
	_check(body.is_reloading() and (body.get_node(^"ArmL") as Node3D).rotation.x < -0.1,
		"third person: the reload swings the left arm down")

	# The other new maps: the player lands; a few routes are open.
	for route: Array in [
			["factory", Vector3(-31, 0.1, 10), -PI / 2, func(p: Vector3) -> bool: return p.x > -7.0, "through the tunnels"],
			["factory", Vector3(24, 0.1, -19), 0.0, func(p: Vector3) -> bool: return p.y > 3.9, "ramp up to the roof"],
			["factory", Vector3(16.8, 0.1, 4), 0.0, func(p: Vector3) -> bool: return p.y > 3.9, "ramp up to the catwalk"],
			["factory", Vector3(5, 0.1, 6), PI, func(p: Vector3) -> bool: return p.z > 20.0, "Lower Mid into B"],
			["office", Vector3(0, 0.1, 40), 0.0, func(p: Vector3) -> bool: return p.z < 24.0, "front doors into the lobby"],
			["office", Vector3(20, 0.1, 4), 0.0, func(p: Vector3) -> bool: return p.y > 3.5, "stairs up to the mezzanine"],
			["subway", Vector3(-15, 0.1, 22), 0.0, func(p: Vector3) -> bool: return p.z < 0.0, "west platform"],
			["subway", Vector3(6, -1.1, -20), 0.0, func(p: Vector3) -> bool: return p.y > -0.1 and p.z < -30.0, "climb out of the track bed"],
			["subway", Vector3(-10, 0.1, 4.7), -PI / 2, func(p: Vector3) -> bool: return p.x > -3.0, "walk through the train"],
			["trainyard", Vector3(0, 0.1, 20), 0.0, func(p: Vector3) -> bool: return p.z < 0.0, "lane between the cars"],
			["trainyard", Vector3(-28.9, 0.1, 7), 0.0, func(p: Vector3) -> bool: return p.y > 3.9, "ramp up to the tower balcony"]]:
		if _level.name.to_lower() != route[0]:
			await _load_map("res://scenes/levels/%s.tscn" % route[0])
			await _frames(30)
			_check(_player.is_on_floor(), "%s: player lands" % route[0])
		_reset_player(route[1], route[2])
		await _frames(2)
		await _walk_forward_max_y(300)
		_check((route[3] as Callable).call(_player.global_position), "%s: %s (at %s)" % [route[0], route[4], _player.global_position.snapped(Vector3.ONE * 0.1)])

	# Every map has team spawns and bomb sites A + B.
	for m: Dictionary in GameConfig.MAPS:
		var lvl := (load(m.path) as PackedScene).instantiate() as Level
		var ok := lvl.blue_spawn_points.size() >= 3 and lvl.red_spawn_points.size() >= 3 and lvl.bomb_sites.size() == 2
		lvl.free()
		_check(ok, "%s: team spawns + bomb sites A/B" % m.name)


## Phase 3: sound effects, occlusion, voices, music, UI and feedback sounds.
func _test_audio() -> void:
	for bus: StringName in [&"SFXOccluded", &"ReverbRoom", &"ReverbHall"]:
		var idx := AudioServer.get_bus_index(bus)
		_check(idx >= 0 and AudioServer.get_bus_send(idx) == &"SFX", "bus %s exists and feeds SFX" % bus)
	var bad := PackedStringArray()
	for sound in SfxLibrary.NAMES:
		var st := SfxLibrary.get_sound(sound)
		if st == null or st.get_length() < 0.02:
			bad.append(sound)
	_check(bad.is_empty(), "all %d placeholder sounds generate (%s)" % [SfxLibrary.NAMES.size(), ", ".join(bad)])

	# Background generation → the level's match music starts.
	var t := 0.0
	while not Audio.generated and t < 30.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	var menu := Audio.music_stream(&"menu") as AudioStreamWAV
	_check(Audio.generated and menu and menu.get_length() > 15.0 and menu.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"music generated in the background (menu loop %.1f s, took %.1f s)" % [menu.get_length() if menu else 0.0, t])
	_check(Audio.current_music == &"match" and Audio.is_music_playing(), "match music plays in a level")

	# Gunfire, footsteps, hit / kill / hurt feedback.
	_reset_player(Vector3(0, 0.1, 10))
	await _frames(5)
	_player.select_slot(0)
	var rifle := _player.current_weapon
	rifle.refill_ammo()
	rifle._cooldown = 0.0
	var before := Audio.stats.duplicate()
	var fired := rifle.try_fire()
	_check(fired and _stat_delta(before, "3d:fire_" + rifle.data.weapon_id) == 1,
		"%s shot plays its own gunshot" % rifle.data.display_name)
	Input.action_press(&"move_forward")
	await _frames(90)
	_release_all()
	var steps := 0
	for i in range(1, 5):
		steps += _stat_delta(before, "local:step%d" % i)
	_check(steps >= 2, "walking plays footsteps (%d)" % steps)
	rifle.hit_confirmed.emit(false, false)
	rifle.hit_confirmed.emit(false, true)
	rifle.hit_confirmed.emit(true, false)
	_check(_stat_delta(before, "ui:hitmarker") == 1 and _stat_delta(before, "ui:headshot") == 1
		and _stat_delta(before, "ui:kill") == 1, "hit marker, headshot and kill sounds")
	SettingsManager.hit_sounds = false
	rifle.hit_confirmed.emit(false, false)
	SettingsManager.hit_sounds = true
	_check(_stat_delta(before, "ui:hitmarker") == 1, "hit sounds can be turned off")
	_player.health.take_damage(5.0, null)
	_check(_stat_delta(before, "local:hurt") == 1, "taking damage plays a hurt sound")

	# Reload sequence: mag out → mag in → bolt.
	rifle.ammo_in_magazine = 1
	rifle.reload()
	await get_tree().create_timer(rifle.data.reload_time + 0.2).timeout
	_check(_stat_delta(before, "3d:mag_out") == 1 and _stat_delta(before, "3d:mag_in") == 1
		and _stat_delta(before, "3d:bolt") == 1, "reload plays mag out, mag in, bolt")

	# A remote player walking nearby is heard in 3D; a bullet past the head whizzes.
	var other := _level.spawn_player(405, "Walker", Transform3D(Basis.IDENTITY, Vector3(3, 0, 10)))
	await _frames(2)
	for i in 60:
		other.apply_remote_state(Vector3(3, 0, 10 - i * 0.1), 0.0, 0.0, other.stand_height, 0)
		await get_tree().physics_frame
	var remote_steps := 0
	for i in range(1, 5):
		remote_steps += _stat_delta(before, "3d:step%d" % i)
	_check(remote_steps >= 2, "remote footsteps are positional (%d)" % remote_steps)
	_level.despawn_player(405)
	var ear := Audio.listener_position()
	Audio.bullet_passed(ear + Vector3(0, 0, -40), ear + Vector3(1.0, 0, 20))
	Audio.bullet_passed(ear + Vector3(0, 0, -40), ear + Vector3(10.0, 0, 20))
	_check(_stat_delta(before, "3d:whiz") == 1, "near miss whizzes, far miss doesn't")

	# Occlusion: a wall between the listener and the sound muffles it.
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 6, 0.5)
	shape.shape = box
	wall.add_child(shape)
	wall.position = ear + Vector3(0, 0, -4)
	add_child(wall)
	await _frames(2)
	var behind := ear + Vector3(0, 0, -9)
	_check(Audio.is_occluded(ear, behind) and not Audio.is_occluded(ear, ear + Vector3(0, 0, 3)),
		"walls block sound (occlusion ray)")
	var v := Audio.play_3d(&"impact", behind, 0.0, 50.0)
	var v2 := Audio.play_3d(&"impact", ear + Vector3(2, 0, 0), 0.0, 50.0)
	_check(v and v.bus == &"SFXOccluded" and v2 and v2.bus == &"SFX", "sound behind a wall goes to the muffled bus")
	_check(Audio.play_3d(&"impact", ear + Vector3(0, 0, 200), 0.0, 50.0) == null, "sounds beyond their range are skipped")
	wall.queue_free()

	# Voice limit follows the audio quality; Low turns reverb off.
	SettingsManager.audio_quality = 0
	SettingsManager.apply_audio()
	for i in 40:
		Audio.play_3d(&"impact", ear + Vector3(1, 0, 0), -30.0, 50.0)
	var room := AudioServer.get_bus_index(&"ReverbRoom")
	_check(Audio.voice_count() <= 16 and AudioServer.is_bus_mute(room), "Low audio: max 16 sounds, no reverb (%d)" % Audio.voice_count())
	SettingsManager.audio_quality = 1
	SettingsManager.apply_audio()
	_check(Audio.max_voices == 40 and not AudioServer.is_bus_mute(room), "High audio: 40 sounds, reverb on")

	# Match music can be switched off; buttons click.
	SettingsManager.match_music = false
	SettingsManager.apply_audio()
	await _frames(2)
	_check(not Audio.is_music_playing(), "match music can be turned off")
	SettingsManager.match_music = true
	SettingsManager.apply_audio()
	_check(Audio.is_music_playing(), "…and back on")
	var button := Button.new()
	add_child(button)
	button.pressed.emit()
	_check(_stat_delta(before, "ui:ui_click") == 1, "buttons click")
	button.queue_free()


## v0.9: controller — layout, stick look, movement, triggers, aim assist, remapping.
func _test_controller() -> void:
	var jump_pad := SettingsManager.get_pad_binding(&"jump") as InputEventJoypadButton
	_check(jump_pad and jump_pad.button_index == JOY_BUTTON_A and SettingsManager.get_binding(&"jump") is InputEventKey
		and SettingsManager.pad_binding_text(&"shoot") == "RT"
		and SettingsManager.pad_binding_text(&"push_to_talk_team") == "D-pad ↑",
		"default controller layout next to the keyboard one")
	_check(absf(GamepadInput.shape_stick(Vector2(0.5, 0), 0.15, 2.0).x - pow(0.35 / 0.85, 2.0)) < 0.001
		and GamepadInput.shape_stick(Vector2(0.1, 0.05), 0.15, 2.0) == Vector2.ZERO, "stick deadzone + response curve")

	# Right stick turns the camera; a tiny push inside the deadzone doesn't.
	_reset_player(Vector3(0, 0.1, 10))
	await _frames(3)
	var yaw := _player.rotation.y
	_pad_axis(JOY_AXIS_RIGHT_X, 0.1)
	await _frames(20)
	_check(absf(_player.rotation.y - yaw) < 0.001, "stick drift inside the deadzone is ignored")
	_pad_axis(JOY_AXIS_RIGHT_X, 1.0)
	var t0 := Time.get_ticks_msec()
	await _frames(30)
	_pad_axis(JOY_AXIS_RIGHT_X, 0.0)
	var turned := rad_to_deg(yaw - _player.rotation.y)
	var expected := SettingsManager.pad_sensitivity * (Time.get_ticks_msec() - t0) / 1000.0
	_check(turned > expected * 0.6 and turned < expected * 1.4, "right stick turns %.0f° (≈%.0f° expected)" % [turned, expected])
	_pad_axis(JOY_AXIS_RIGHT_Y, -1.0)
	await _frames(10)
	_pad_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_check(_player.head.rotation.x > 0.05, "stick up looks up")

	# Left stick walks, right trigger fires.
	_reset_player(Vector3(0, 0.1, 10))
	await _frames(3)
	var start := _player.global_position
	_pad_axis(JOY_AXIS_LEFT_Y, -1.0)
	await _frames(40)
	_pad_axis(JOY_AXIS_LEFT_Y, 0.0)
	_check(start.z - _player.global_position.z > 1.0, "left stick moves forward (%.1f m)" % (start.z - _player.global_position.z))
	_player.select_slot(0)
	var w := _player.current_weapon
	w.refill_ammo()
	var before := w.ammo_in_magazine
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await _frames(20)
	_pad_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await _frames(2)
	_check(w.ammo_in_magazine < before, "right trigger shoots (%d → %d)" % [before, w.ammo_in_magazine])

	# Aim assist: slower over an enemy, only for controller players.
	_reset_player(Vector3(0, 0.1, 10))
	var enemy := _level.spawn_player(406, "Target", Transform3D(Basis.IDENTITY, Vector3(0, 0, 4)))
	await _frames(3)
	GamepadInput.using_pad = true
	var on_target := _player.aim_assist_factor()
	_player.rotation.y = PI * 0.5
	var off_target := _player.aim_assist_factor()
	GamepadInput.using_pad = false
	_player.rotation.y = 0.0
	var mouse := _player.aim_assist_factor()
	_check(on_target < 1.0 and off_target == 1.0 and mouse == 1.0,
		"aim assist slows aim over an enemy (%.2f), not elsewhere or with a mouse" % on_target)
	_level.despawn_player(406)

	# Prompts follow the device in use.
	GamepadInput.using_pad = true
	var pad_prompt := SettingsManager.prompt_text(&"interact")
	GamepadInput.using_pad = false
	_check(pad_prompt == "LB" and SettingsManager.prompt_text(&"interact") == "E", "button prompts follow the device (LB / E)")

	# Remap a controller button (swaps, keeps the keyboard binding, survives a reload).
	var key_jump := SettingsManager.binding_text(&"jump")
	var swapped := SettingsManager.rebind(&"jump", GamepadInput.button(JOY_BUTTON_X))
	_check(SettingsManager.pad_binding_text(&"jump") == "X" and SettingsManager.pad_binding_text(&"reload") == "A"
		and swapped == &"reload" and SettingsManager.binding_text(&"jump") == key_jump,
		"controller remap swaps with Reload and leaves the keyboard alone")
	SettingsManager._set_binding(&"jump", true, null)
	SettingsManager.apply_bindings()
	_check(SettingsManager.pad_binding_text(&"jump") == "X", "controller bindings are saved and loaded")
	var menu := (load("res://scenes/ui/settings_menu.tscn") as PackedScene).instantiate() as SettingsMenu
	add_child(menu)
	menu.open()
	await _frames(2)
	menu._start_capture(&"reload", true)
	menu.capture_event(GamepadInput.axis(JOY_AXIS_TRIGGER_LEFT, 1.0))
	_check(SettingsManager.pad_binding_text(&"reload") == "LT" and SettingsManager.pad_binding_text(&"aim") == "A",
		"Settings captures a controller trigger")
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	menu._unhandled_input(cancel)
	_check(not menu.visible, "B / Esc closes Settings")
	menu.queue_free()
	SettingsManager.reset_bindings()
	_check(SettingsManager.pad_binding_text(&"jump") == "A" and SettingsManager.pad_binding_text(&"reload") == "X",
		"reset restores the controller layout")


func _pad_axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)


func _stat_delta(before: Dictionary, key: String) -> int:
	return int(Audio.stats.get(key, 0)) - int(before.get(key, 0))


func _reverb_zone_at(pos: Vector3) -> Area3D:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = pos
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = Audio.AUDIO_ZONE_MASK
	var best: Area3D = null
	for hit in _level.get_world_3d().direct_space_state.intersect_point(q):
		var a := hit.collider as Area3D
		if a and a.reverb_bus_enabled and (best == null or a.priority > best.priority):
			best = a
	return best


## Phase 7b: GPU tiers, report logic (the full test itself needs restarts —
## CI runs it separately with `-- --hardware-test --quick --quit`).
func _test_hardware_report() -> void:
	_check(SettingsManager.normalize_gpu_name("Mesa Intel(R) UHD Graphics 620 (KBL GT2)") == "intel uhd graphics 620"
		and SettingsManager.normalize_gpu_name("NVIDIA GeForce GTX 1050/PCIe/SSE2") == "nvidia geforce gtx 1050"
		and SettingsManager.normalize_gpu_name("AMD Radeon(TM) Vega 8 Graphics") == "amd radeon vega 8 graphics",
		"GPU names normalised like tools/tune_presets.py")
	_check(SettingsManager.gpu_tier("Intel(R) UHD Graphics 620") == GraphicsPreset.Quality.LOW
		and SettingsManager.gpu_tier("AMD Radeon(TM) Vega 8 Graphics") == GraphicsPreset.Quality.LOW
		and SettingsManager.gpu_tier("NVIDIA GeForce RTX 3060") == -1, "minimum-spec GPUs start on Low (gpu_tiers.cfg)")
	var cfg := ConfigFile.new()
	cfg.set_value("nvidia geforce gtx 1650", "preset", "medium")
	cfg.set_value("uhd graphics 6", "preset", "low")
	cfg.save("user://gpu_tiers_test.cfg")
	_check(SettingsManager.gpu_tier("NVIDIA GeForce GTX 1650/PCIe/SSE2", "user://gpu_tiers_test.cfg") == GraphicsPreset.Quality.MEDIUM,
		"measured GPU entries are used")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://gpu_tiers_test.cfg"))

	# Report from synthetic results: Medium smooth, High not → Medium.
	var mk := func(n: String, r: String, vs: String, avg: float, low: float) -> Dictionary:
		return { "name": n, "renderer": r, "preset": 0, "set": {}, "vs": vs, "avg_fps": avg, "low_fps": low,
			"avg_frame_ms": 1000.0 / avg, "low_frame_ms": 1000.0 / low, "draw_calls": 40, "video_mem_mb": 100.0 }
	var state := { "quick": false, "stages": {
		"gl_compatibility": { "status": "ok", "results": [mk.call("Low", "gl_compatibility", "", 140.0, 110.0),
			mk.call("Low + glow", "gl_compatibility", "Low", 130.0, 100.0)] },
		"forward_plus": { "status": "ok", "results": [mk.call("Medium", "forward_plus", "", 90.0, 70.0),
			mk.call("High", "forward_plus", "", 55.0, 40.0), mk.call("Ultra", "forward_plus", "", 25.0, 18.0),
			mk.call("Medium + SSAO", "forward_plus", "Medium", 70.0, 55.0)] } } }
	var report := HardwareTest.build_report(state)
	_check(report.recommended == "Medium", "recommends the highest smooth preset (%s)" % report.recommended)
	_check(report.option_costs.size() == 2 and report.option_costs[0].name == "Medium + SSAO"
		and absf(report.option_costs[0].delta_ms - (1000.0 / 70.0 - 1000.0 / 90.0)) < 0.02,
		"option costs vs their baseline, most expensive first")
	var md: String = report.markdown
	_check("| Medium | Vulkan | 90 | 70 | ✔ smooth |" in md and "| Ultra | Vulkan | 25 | 18 | ✘ too slow |" in md
		and "Recommended preset:** Medium" in md, "Markdown report table")
	_check("[table=5]" in HardwareTest.bbcode(report) and HardwareTest.issue_url(report).length() < 8000,
		"in-game view + GitHub link fit (%d chars)" % HardwareTest.issue_url(report).length())
	state.stages.forward_plus = { "status": "unsupported" }
	var no_vulkan := HardwareTest.build_report(state)
	_check(no_vulkan.recommended == "Low" and "Vulkan unsupported" in no_vulkan.markdown,
		"no Vulkan → Low, and the report says so")


func _walk_forward_max_y(frames: int) -> float:
	Input.action_press(&"move_forward")
	var top := 0.0
	for i in frames:
		await get_tree().physics_frame
		top = maxf(top, _player.global_position.y)
	_release_all()
	return top


func _load_map(path: String) -> void:
	_level.queue_free()
	await _frames(2)
	_level = (load(path) as PackedScene).instantiate() as Level
	add_child(_level)
	await _frames(5)
	_player = _level.player


func _tap(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


# -----------------------------------------------------------------------------

func _reset_player(pos: Vector3, yaw: float = 0.0) -> void:
	_release_all()
	_player.global_position = pos
	_player.rotation = Vector3(0, yaw, 0)
	_player.head.rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO


func _aim_at(point: Vector3) -> void:
	var eye := _player.camera.global_position
	var flat := Vector3(point.x - eye.x, 0, point.z - eye.z)
	_player.rotation.y = atan2(-flat.x, -flat.z)
	_player.head.rotation.x = atan2(point.y - eye.y, flat.length())


func _release_all() -> void:
	for action in InputMap.get_actions():
		Input.action_release(action)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(condition: bool, label: String) -> void:
	print("%s %s" % ["  ✔" if condition else "  ✘", label])
	if not condition:
		_failures += 1
