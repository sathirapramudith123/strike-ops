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
	await _test_climbing()
	await _test_crouch_and_slide()
	await _test_shooting()
	await _test_reload()
	await _test_gun_against_wall()
	await _test_ramps()
	await _test_pause_disables_input()
	await _test_fall_death_and_respawn()
	_test_lag_compensation()
	_test_voice_codec()
	await _test_voice_loopback()
	await _test_weapon_switching()
	await _test_new_controls()
	await _test_shotgun_and_sniper()
	await _test_loadout_on_respawn()
	await _test_grenades()
	await _test_grenade_wheel_and_arc()
	await _test_flash_and_smoke()
	await _test_audio()
	await _test_controller()
	_test_friendly_fire_and_match_end()
	await _test_bomb_defusal()
	await _test_settings_menu()
	await _test_performance()
	await _test_maps()
	await _test_doors_and_glass()
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
	var at_release := _player.global_position
	_release_all()
	await _frames(30)
	_check(Vector2(_player.velocity.x, _player.velocity.z).length() < 0.1, "player decelerates to a stop")
	var glide := Vector2(_player.global_position.x - at_release.x, _player.global_position.z - at_release.z).length()
	_check(glide < 0.5, "no ice-sliding: stops within %.2f m of letting go at sprint speed" % glide)


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


## A box in front of the player (test map, open floor near the spawn).
func _add_box(center: Vector3, size: Vector3, climbable: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	if climbable:
		body.add_to_group(Climb.GROUP)
	_level.add_child(body)
	body.global_position = center
	return body


func _test_climbing() -> void:
	# A 1.8 m climbable crate: Jump facing it pulls the player up on top.
	var crate := _add_box(Vector3(0, 0.9, 2), Vector3(2, 1.8, 1.5), true)
	await _frames(2)
	_reset_player(Vector3(0, 0.1, 3.4))
	await _frames(10)
	var ledge := Climb.find_ledge(_player.get_world_3d().direct_space_state, _player.global_position, -_player.global_basis.z)
	_check(not ledge.is_empty() and ledge.climbable and absf(ledge.height - 1.8) < 0.15,
		"a 1.8 m crate in front is a climbable ledge (%s)" % str(ledge.get("height")))
	_press_action(&"jump")
	await _frames(3)
	_check(_player.is_climbing, "Jump at the crate starts climbing")
	await _frames(70)
	_check(not _player.is_climbing and _player.global_position.y > 1.7 and _player.global_position.z < 2.6,
		"climbed up on top of the crate (%s)" % _player.global_position.snappedf(0.01))
	_check(_player.current_weapon and not _player.current_weapon.holstered, "gun back in hand after climbing")
	crate.queue_free()

	# The same box without the climbable mark: a jump doesn't get up there.
	var wall := _add_box(Vector3(0, 0.9, 2), Vector3(2, 1.8, 1.5), false)
	await _frames(2)
	_reset_player(Vector3(0, 0.1, 3.4))
	await _frames(10)
	Input.action_press(&"jump")
	Input.action_press(&"move_forward")
	await _frames(60)
	_release_all()
	await _frames(20)
	_check(not _player.is_climbing and _player.global_position.y < 0.5, "a box that isn't climbable can't be climbed")
	wall.queue_free()

	# Jumping at a climbable ledge and holding Jump pulls up in the air.
	var crate2 := _add_box(Vector3(0, 1.0, 2), Vector3(2, 2.0, 1.5), true)
	await _frames(2)
	_reset_player(Vector3(0, 0.1, 5.5))
	await _frames(5)
	Input.action_press(&"move_forward")
	await _frames(20)
	Input.action_press(&"jump")
	var climbed := false
	for i in 60:
		await _frames(1)
		if _player.is_climbing:
			climbed = true
			Input.action_release(&"move_forward") # stay on top
	await _frames(30)
	_release_all()
	_check(climbed, "holding Jump in the air grabs the ledge")
	_check(_player.global_position.y > 1.9, "running jump + hold Jump climbs a 2 m crate (y %.2f)" % _player.global_position.y)
	crate2.queue_free()
	await _frames(2)
	_reset_player(Vector3(0, 0.1, 6))
	await _frames(20)


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
	_check(not _player.is_sliding, "crouch while sprinting doesn't slide (no slipping)")
	Input.action_release(&"crouch")
	await _frames(20)
	Input.action_press(&"slide")
	await _frames(3)
	_check(_player.is_sliding, "the Slide key while sprinting starts a slide")
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


func _test_gun_against_wall() -> void:
	# A wall 0.5 m in front: the gun is pulled back instead of poking through.
	_reset_player(Vector3(0, 0.1, 6))
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.3)
	shape.shape = box
	wall.add_child(shape)
	_level.add_child(wall)
	wall.global_position = Vector3(0, 2, 6 - 0.55 - 0.15) # front face 0.55 m from the eye
	_player.select_slot(0) # the rifle: muzzle ~0.9 m in front of the eye
	var gun := _player.current_weapon
	await _frames(40)
	var pulled := gun._wall_pull
	var tip := _player.camera.to_local(gun.muzzle.global_position)
	_check(pulled > 0.2 and -tip.z < 0.62,
		"gun pulls back at a wall (pull %.2f m, muzzle %.2f m ahead, wall at 0.55 m)" % [pulled, -tip.z])
	wall.queue_free()
	await _frames(40)
	_check(gun._wall_pull < 0.01, "gun back in place away from walls (%.2f)" % gun._wall_pull)


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
	# Body zones by hit height (the remote player is 1.8 m tall).
	var zones := []
	for y in [0.5, 1.0, 1.3, 1.6]:
		zones.append(LagCompensation.trace(space, Vector3(-6, y, 26), Vector3.FORWARD, 50.0, _player, players, t0).get("zone"))
	_check(zones == [&"legs", &"stomach", &"chest", &"head"], "hit zones: legs, stomach, chest, head (%s)" % str(zones))
	_check(Hitbox.ZONE_MULTIPLIERS[&"legs"] < 1.0 and Hitbox.ZONE_MULTIPLIERS[&"stomach"] > 1.0, "legs do less damage, stomach more")
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


## The PUBG-style layout: default keys, knife, fire modes, scope zoom,
## lean, walk toggle, grenade slot, big map.
func _test_new_controls() -> void:
	var expect := { &"crouch": "C", &"slide": "Ctrl", &"lean_left": "Q", &"lean_right": "E",
		&"walk_toggle": "CapsLock", &"weapon_3": "3", &"weapon_4": "4", &"fire_mode": "B", &"interact": "F",
		&"map": "M", &"chat_all": "Y", &"push_to_talk_team": "U", &"reload": "R", &"sprint": "Shift" }
	var wrong := PackedStringArray()
	for action: StringName in expect:
		var got := _key_of(action)
		if got != expect[action]:
			wrong.append("%s=%s" % [action, got])
	_check(wrong.is_empty(), "default keys follow the new layout (%s)" % ", ".join(wrong))
	var keys := {}
	var dup := PackedStringArray()
	for action: StringName in SettingsManager.REMAPPABLE_ACTIONS:
		var k := _key_of(action)
		if k != "" and keys.has(k):
			dup.append("%s: %s + %s" % [k, keys[k], action])
		keys[k] = action
	_check(dup.is_empty(), "no key is used twice (%s)" % ", ".join(dup))
	# Only changed keys are saved; a settings file from the old layout (every
	# key saved, crouch on Ctrl) gets the new defaults.
	SettingsManager.save()
	_check(not SettingsManager._config.has_section_key("bindings", "crouch"), "default keys aren't written to the settings file")
	var cfg := SettingsManager._config
	cfg.set_value("bindings_meta", "layout", 1)
	cfg.set_value("bindings", "crouch", { "type": "key", "code": KEY_CTRL, "physical": true })
	SettingsManager.apply_bindings()
	_check(_key_of(&"crouch") == "C" and not cfg.has_section("bindings")
		and int(cfg.get_value("bindings_meta", "layout", 0)) == SettingsManager.BINDINGS_LAYOUT,
		"an old settings file switches to the new layout (crouch %s)" % _key_of(&"crouch"))

	# Knife (3): short reach, no ammo, hurts the dummy.
	var target := _level.get_node("Targets/Target2") as TargetDummy
	target.health.revive()
	_reset_player(Vector3(0, 0.1, -20.6))
	await _frames(3)
	_aim_at(target.global_position + Vector3(0, 1.1, 0))
	_tap(&"weapon_3")
	await _frames(3)
	var knife := _player.current_weapon
	_check(knife.data.melee and knife.data.weapon_id == "knife", "key 3 takes out the knife")
	Input.action_press(&"shoot")
	await _frames(45)
	Input.action_release(&"shoot")
	_check(target.health.current < target.health.max_health or target.health.is_dead,
		"knife hits at arm's length (%.0f hp left)" % target.health.current)
	target.health.revive()
	_reset_player(Vector3(0, 0.1, -17))
	_aim_at(target.global_position + Vector3(0, 1.1, 0))
	await _frames(3)
	Input.action_press(&"shoot")
	await _frames(30)
	Input.action_release(&"shoot")
	_check(target.health.current == target.health.max_health, "knife doesn't reach 5 m")
	_tap(&"weapon_1")
	await _frames(3)

	# Fire modes (B): rifle auto → burst → semi → auto.
	var rifle := _player.current_weapon
	rifle.refill_ammo()
	_player.head.rotation.x = deg_to_rad(80) # at the sky
	_check(rifle.fire_mode() == "auto", "rifle starts on full auto")
	_tap(&"fire_mode")
	await _frames(2)
	var shots := rifle.ammo_in_magazine
	Input.action_press(&"shoot")
	await _frames(2)
	Input.action_release(&"shoot")
	await _frames(40)
	_check(rifle.fire_mode() == "burst" and shots - rifle.ammo_in_magazine == 3,
		"B → burst: one click fires 3 (%d)" % (shots - rifle.ammo_in_magazine))
	_check(_level.hud._weapon_label.text.ends_with("BURST"), "HUD shows the fire mode (%s)" % _level.hud._weapon_label.text)
	_tap(&"fire_mode")
	await _frames(2)
	shots = rifle.ammo_in_magazine
	Input.action_press(&"shoot")
	await _frames(40)
	Input.action_release(&"shoot")
	_check(rifle.fire_mode() == "semi" and shots - rifle.ammo_in_magazine == 1, "B → semi: one shot per click")
	_tap(&"fire_mode")
	await _frames(2)
	_check(rifle.fire_mode() == "auto", "B → back to auto")

	# Scope zoom: the wheel steps the sniper's zoom while scoped.
	_player.apply_loadout("sniper", 0)
	await _frames(3)
	Input.action_press(&"aim")
	await _frames(70)
	var fov1 := _player.camera.fov
	_tap(&"weapon_next")
	await _frames(25)
	_check(_player.current_weapon.data.weapon_id == "sniper" and _player.camera.fov < fov1 * 0.7,
		"wheel zooms the scope in (%.0f → %.0f)" % [fov1, _player.camera.fov])
	_tap(&"weapon_prev")
	await _frames(60)
	_check(absf(_player.camera.fov - fov1) < 1.0, "wheel zooms back out (%.0f)" % _player.camera.fov)
	Input.action_release(&"aim")
	_player.apply_loadout("rifle", 0)
	await _frames(20)

	# Lean (Q / E): the head moves sideways, the server's head moves too.
	_reset_player(Vector3(0, 0.1, 6))
	_player.head.rotation.x = 0.0
	await _frames(3)
	var eye_x := _player.camera.global_position.x
	Input.action_press(&"lean_right")
	await _frames(30)
	var leaned := _player.camera.global_position.x - eye_x
	_check(leaned > 0.3, "E leans right (eye moved %.2f m)" % leaned)
	var head_y := _player.global_position.y + _player.current_height() - LagCompensation.HEAD_DROP
	var from := Vector3(_player.global_position.x + PlayerController.LEAN_OFFSET, head_y, _player.global_position.z - 6)
	var hit := LagCompensation.trace(_player.get_world_3d().direct_space_state, from, Vector3.BACK, 10.0, null,
		[_player], NetworkManager.server_time())
	_check(hit.get("hitbox") == _player.head_hitbox, "lag compensation moves the head with the lean")
	Input.action_release(&"lean_right")
	await _frames(30)
	_check(absf(_player.camera.global_position.x - eye_x) < 0.02, "lean returns to the middle")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 4, 4)
	shape.shape = box
	wall.add_child(shape)
	_level.add_child(wall)
	wall.global_position = Vector3(_player.global_position.x - 0.5, 2, 6)
	await _frames(2)
	Input.action_press(&"lean_left")
	await _frames(30)
	Input.action_release(&"lean_left")
	_check(eye_x - _player.camera.global_position.x < 0.15, "can't lean through a wall (%.2f m)"
		% (eye_x - _player.camera.global_position.x))
	wall.queue_free()
	await _frames(20)

	# Walk toggle (Caps Lock): slow and quiet.
	_tap(&"walk_toggle")
	await _frames(2)
	Input.action_press(&"move_forward")
	await _frames(40)
	var walk := Vector2(_player.velocity.x, _player.velocity.z).length()
	_release_all()
	_check(_player.is_walking and absf(walk - _player.walk_speed * PlayerController.WALK_TOGGLE_SPEED) < 0.3,
		"Caps Lock walks (%.2f m/s)" % walk)
	_check(_level.hud._walk_label.visible, "HUD shows WALK")
	_tap(&"walk_toggle")
	await _frames(2)
	_check(not _player.is_walking, "Caps Lock again runs")

	# Grenade slot (4): in hand, gun put away; 4 again switches; 1 puts it away.
	var t := _player.throwables
	_press_action(&"weapon_4")
	await _frames(2)
	_check(t.held_kind == Throwables.Kind.HE and _player.current_weapon.holstered, "4 takes the HE grenade in hand")
	_press_action(&"weapon_4")
	await _frames(2)
	_check(t.held_kind == Throwables.Kind.FLASH, "4 again switches to the flashbang")
	_tap(&"weapon_1")
	await _frames(2)
	_check(not t.is_holding() and not _player.current_weapon.holstered and t.counts[Throwables.Kind.FLASH] == 2,
		"1 puts the grenade away, nothing thrown")

	# Big map (M).
	_tap(&"map")
	await _frames(3)
	var big: Minimap = _level.hud._big_map
	_check(big.visible and big._polys.size() > 10, "M opens the big map (%d shapes)" % big._polys.size())
	_tap(&"map")
	await _frames(2)
	_check(not big.visible, "M closes it")


## Keyboard key of `action` ("C", "Shift", "CapsLock") or "".
func _key_of(action: StringName) -> String:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := e as InputEventKey
			return OS.get_keycode_string(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
		if e is InputEventMouseButton:
			return "Mouse%d" % (e as InputEventMouseButton).button_index
	return ""


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


func _press_action(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	Input.parse_input_event(up)


func _test_grenades() -> void:
	var t := _player.throwables
	_check(t != null and t.counts[Throwables.Kind.HE] == 1 and t.counts[Throwables.Kind.MOLOTOV] == 1,
		"spawn with one HE grenade and one Molotov")
	var slots := _level.hud._weapon_slots.get_children().map(func(l: Label) -> String: return l.text)
	_check(slots.any(func(x: String) -> bool: return x.begins_with("HE ×1")) \
		and slots.any(func(x: String) -> bool: return x.begins_with("Molotov ×1")), "HUD lists the grenades (%s)" % str(slots))
	_player.health.protect(0.0)

	# HE: the G key throws it, it flies, bounces and explodes after the fuse.
	_reset_player(Vector3(0, 0.1, -12), PI)
	_player.head.rotation.x = deg_to_rad(10)
	await _frames(3)
	_press_action(&"throw_grenade")
	await _frames(2)
	_check(t.counts[Throwables.Kind.HE] == 0, "G throws the HE grenade")
	var nade := _level.find_child("Grenade_*", true, false) as GrenadeProjectile
	_check(nade != null and nade.linear_velocity.length() > 10.0, "grenade flies out")
	var thrown_from := nade.global_position if nade else Vector3.ZERO
	await _frames(int(Throwables.HE_FUSE * 60.0) - 20)
	_check(is_instance_valid(nade) and nade.global_position.distance_to(thrown_from) > 5.0, "grenade still flying before the fuse")
	await _frames(40)
	_check(not is_instance_valid(nade) or nade.is_queued_for_deletion(), "grenade explodes after its fuse")
	_check(_level.find_child("Explosion", true, false) != null, "explosion effect spawned")
	_press_action(&"throw_grenade")
	await _frames(2)
	_check(_level.find_child("Grenade_*", true, false) == null, "no second throw with none left")

	# Blast damage: falls off with distance, stopped by walls.
	var target := _level.get_node("Targets/Target2") as TargetDummy
	target.health.revive()
	var at := target.global_position
	t._server_blast(at + Vector3(1.0, 0.1, 0.0))
	var close_dmg := target.health.max_health - target.health.current
	target.health.revive()
	t._server_blast(at + Vector3(4.0, 0.1, 0.0))
	var far_dmg := target.health.max_health - target.health.current
	target.health.revive()
	t._server_blast(at + Vector3(7.0, 0.1, 0.0))
	var out_dmg := target.health.max_health - target.health.current
	_check(close_dmg > 60.0 and far_dmg > 5.0 and far_dmg < close_dmg and out_dmg == 0.0,
		"HE damage falls off (1 m %.0f, 4 m %.0f, 7 m %.0f)" % [close_dmg, far_dmg, out_dmg])
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 4.0, 4.0)
	shape.shape = box
	wall.add_child(shape)
	_level.add_child(wall)
	wall.global_position = at + Vector3(1.5, 1.0, 0.0)
	await _frames(2)
	target.health.revive()
	t._server_blast(at + Vector3(2.5, 0.1, 0.0))
	_check(target.health.current == target.health.max_health, "walls block the blast")
	wall.queue_free()
	target.health.revive()

	# Molotov: Q throws it at our feet; it breaks on the floor and burns.
	_reset_player(Vector3(0, 0.1, -12), PI)
	_player.head.rotation.x = deg_to_rad(-80)
	_player.health.revive()
	_player.health.protect(0.0)
	await _frames(3)
	await _throw_from_hand(Throwables.Kind.MOLOTOV)
	await _frames(40)
	_check(t.counts[Throwables.Kind.MOLOTOV] == 0, "4 until the Molotov is in hand, then click throws it")
	var fire := _level.find_child("Fire_*", true, false) as FireZone
	_check(fire != null and fire.is_burning(), "Molotov breaks on the floor and starts a fire")
	await _frames(60)
	_check(_player.health.current < _player.health.max_health, "fire burns the player standing in it (%.0f)" % _player.health.current)
	_check(fire != null and fire.covers(fire.global_position + Vector3(1.0, 0.0, 0.0)) \
		and not fire.covers(fire.global_position + Vector3(FireZone.RADIUS + 1.0, 0.0, 0.0)), "fire covers its radius only")
	# Dying in the fire shows "Molotov" in the kill feed.
	var feed := []
	var on_feed := func(_k: int, _v: int, w: String, _h: bool) -> void: feed.append(w)
	NetworkManager.kill_feed.connect(on_feed)
	_player.health.current = 3.0
	await _frames(20)
	NetworkManager.kill_feed.disconnect(on_feed)
	_check(_player.health.is_dead and "Molotov" in feed, "kill feed names the Molotov (%s)" % str(feed))
	if fire:
		fire.queue_free()
	await _frames(int(_player.respawn_delay * 60.0) + 15)
	_check(not _player.health.is_dead and t.counts[Throwables.Kind.HE] == 1 and t.counts[Throwables.Kind.MOLOTOV] == 1,
		"grenades refilled on respawn")


## Key 4 until `kind` is in hand, then a left click throws it.
func _throw_from_hand(kind: int) -> void:
	var t := _player.throwables
	for i in 5:
		if t.held_kind == kind:
			break
		_press_action(&"weapon_4")
		await _frames(1)
	Input.action_press(&"shoot")
	await _frames(2)
	Input.action_release(&"shoot")


func _test_grenade_wheel_and_arc() -> void:
	var t := _player.throwables
	t.refill()
	_reset_player(Vector3(0, 0.1, -12), PI)
	_player.health.revive()
	_player.health.protect(0.0)
	await _frames(3)
	# Hold 4: the wheel opens (look is locked); point left = Molotov; let go.
	var down := InputEventAction.new()
	down.action = &"weapon_4"
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(15)
	await get_tree().process_frame
	_check(t.wheel_open and _player.grenade_wheel_open and _level.hud.grenade_wheel.visible, "holding 4 opens the grenade wheel")
	var yaw := _player.rotation.y
	t._point_wheel(Vector2(-90, 5))
	_check(t.wheel_choice == Throwables.Kind.MOLOTOV and is_equal_approx(_player.rotation.y, yaw),
		"pointing left picks the Molotov; the view stays still")
	_check(Throwables.wheel_kind_at(Vector2(0, -1)) == Throwables.Kind.HE and Throwables.wheel_kind_at(Vector2(1, 0)) == Throwables.Kind.FLASH
		and Throwables.wheel_kind_at(Vector2(0, 1)) == Throwables.Kind.SMOKE, "wheel: HE top, flash right, smoke bottom")
	var up := InputEventAction.new()
	up.action = &"weapon_4"
	Input.parse_input_event(up)
	await _frames(2)
	_check(not t.wheel_open and t.held_kind == Throwables.Kind.MOLOTOV, "letting go of 4 takes the Molotov in hand")
	_press_action(&"weapon_4")
	await _frames(2)
	_check(t.held_kind == Throwables.Kind.HE, "a quick tap on 4 still takes the next grenade")
	_press_action(&"weapon_2")
	await _frames(2)

	# Throw path: shown while a grenade is in hand; the Molotov lands in the ring.
	_player.head.rotation.x = deg_to_rad(-12)
	_press_action(&"weapon_4")
	await _frames(1)
	for i in 4:
		if t.held_kind == Throwables.Kind.MOLOTOV:
			break
		_press_action(&"weapon_4")
		await _frames(1)
	await _frames(2)
	await get_tree().process_frame
	_check(t.arc != null and t.arc.visible, "the throw path is drawn while a grenade is in hand")
	var launch := t.throw_launch(1.0)
	var path := GrenadeArc.predict(_player.get_world_3d().direct_space_state, launch[0], launch[1], Throwables.Kind.MOLOTOV)
	Input.action_press(&"shoot")
	await _frames(2)
	Input.action_release(&"shoot")
	await _frames(3)
	_check(not t.arc.visible, "the path hides after the throw")
	await _frames(120)
	var fire := _level.find_child("Fire_*", true, false) as Node3D
	var off := fire.global_position.distance_to(path.end) if fire else 99.0
	_check(fire != null and off < 1.2, "the Molotov burns where the path said (%.2f m off)" % off)
	for f in get_tree().get_nodes_in_group(FireZone.GROUP):
		(f as FireZone).extinguish()
	t.refill()
	await _frames(10)


func _test_flash_and_smoke() -> void:
	var t := _player.throwables
	_check(t.counts[Throwables.Kind.FLASH] == 2 and t.counts[Throwables.Kind.SMOKE] == 1, "spawn with two flashbangs and a smoke")
	var slots := _level.hud._weapon_slots.get_children().map(func(l: Label) -> String: return l.text)
	_check(slots.any(func(x: String) -> bool: return x.begins_with("Flash ×2")) \
		and slots.any(func(x: String) -> bool: return x.begins_with("Smoke ×1")), "HUD lists flash and smoke")

	# How blind: looking at it, looking away, far away, behind a wall.
	var space := _player.get_world_3d().direct_space_state
	var eye := Vector3(0, 1.6, -12)
	var fl := eye + Vector3(0, -0.5, 4)
	var facing := GrenadeFx.blind_seconds(space, eye, Vector3(0, 0, 1), fl)
	var away := GrenadeFx.blind_seconds(space, eye, Vector3(0, 0, -1), fl)
	var far := GrenadeFx.blind_seconds(space, eye, Vector3(0, 0, 1), eye + Vector3(0, 0, 30))
	_check(facing > 3.0 and away > 0.0 and away < 1.0 and far == 0.0,
		"flash blinds by where you look and how far (facing %.1f s, away %.1f s, 30 m %.1f s)" % [facing, away, far])
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 0.3)
	shape.shape = box
	wall.add_child(shape)
	_level.add_child(wall)
	wall.global_position = eye + Vector3(0, 0, 2)
	await _frames(2)
	_check(GrenadeFx.blind_seconds(space, eye, Vector3(0, 0, 1), fl) == 0.0, "walls stop the flash")
	wall.queue_free()

	# F throws a flash; looking its way whites out the screen.
	_reset_player(Vector3(0, 0.1, -12), PI)
	_player.head.rotation.x = deg_to_rad(-5)
	await _frames(3)
	await _throw_from_hand(Throwables.Kind.FLASH)
	await _frames(2)
	_check(t.counts[Throwables.Kind.FLASH] == 1, "4 + click throws a flashbang")
	await _frames(int(Throwables.FUSES[Throwables.Kind.FLASH] * 60.0) + 10)
	_check(_player.blind_time > 0.5, "flashbang blinds the player looking at it (%.1f s)" % _player.blind_time)
	await _frames(2)
	_check(_level.hud._flash_overlay.visible and _level.hud._flash_overlay.color.a > 0.3, "screen whites out")
	_player.blind_time = 0.0

	# Z throws a smoke; the cloud blocks sight and puts out fire.
	await _frames(40)
	_reset_player(Vector3(0, 0.1, -12), PI)
	_player.head.rotation.x = deg_to_rad(-40)
	await _frames(3)
	await _throw_from_hand(Throwables.Kind.SMOKE)
	await _frames(int(Throwables.FUSES[Throwables.Kind.SMOKE] * 60.0) + 20)
	_check(t.counts[Throwables.Kind.SMOKE] == 0, "4 + click throws a smoke grenade")
	var cloud := _level.find_child("Smoke_*", true, false) as SmokeCloud
	_check(cloud != null and cloud.is_active(), "smoke grenade makes a cloud")
	if cloud:
		var c := cloud.global_position + Vector3.UP * 1.2
		_check(SmokeCloud.blocks_line(get_tree(), c + Vector3(-8, 0, 0), c + Vector3(8, 0, 0))
			and not SmokeCloud.blocks_line(get_tree(), c + Vector3(-8, 0, 8), c + Vector3(8, 0, 8)),
			"smoke blocks lines through it, not beside it")
		var bottle := FireZone.new()
		_level.add_child(bottle)
		bottle.ignite(cloud.global_position + Vector3.UP * 0.5)
		await _frames(1)
		_check(not is_instance_valid(bottle) or not bottle.is_burning(), "Molotov fizzles in smoke")
		cloud.queue_free()
		await _frames(2)
	var fire := FireZone.new()
	_level.add_child(fire)
	fire.ignite(Vector3(0, 0.5, -20))
	_check(fire.is_burning(), "fire lit for the smoke test")
	var put_out := SmokeCloud.new()
	_level.add_child(put_out)
	put_out.start(fire.global_position + Vector3(1.5, 0, 0))
	_check(not fire.is_burning(), "smoke puts out a burning fire")
	put_out.queue_free()
	fire.queue_free()


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
	# Grenades follow the same rule: an HE between them only hurts the enemy.
	var enemy_hp := enemy.health.current
	_player.throwables._server_blast(Vector3(-20, 0.1, 12.5))
	_check(mate.health.current == mate.health.max_health and enemy.health.current < enemy_hp,
		"HE grenade spares teammates, hurts enemies")

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


## Round 1 freeze time at the red spawn: money, the buy menu and its limits.
func _test_buying() -> void:
	var eco := Match.economy
	var hud := _level.hud
	_check(Economy.money_of(1) == Economy.START_MONEY, "start with $%d" % Economy.START_MONEY)
	_check(_player.primary_id == "" and _player.current_weapon.data.weapon_id == "pistol"
		and is_zero_approx(_player.health.armor) and _player.throwables.counts_array() == [0, 0, 0, 0],
		"first round: pistol and knife, no armour, no grenades")
	_check(Economy.buy_block_reason(_player) == "", "can buy at the spawn in freeze time")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(hud._buy_hint.visible and "Buy" in hud._buy_hint.text and hud._money_label.text == "$800",
		"HUD shows the money and the buy key (%s / %s)" % [hud._money_label.text, hud._buy_hint.text])
	_press_action(&"buy_menu")
	await _frames(2)
	await get_tree().process_frame
	var menu := hud.buy_menu
	_check(menu.visible and not _player.input_enabled, "X opens the buy menu")
	_check(not menu._buttons["vest"].disabled and menu._buttons["sniper"].disabled
		and menu._buttons["sniper"].tooltip_text == "Not enough money", "unaffordable items are greyed out")
	menu._buttons["vest"].pressed.emit()
	await _frames(1)
	_check(is_equal_approx(_player.health.armor, 100.0) and not _player.health.helmet
		and Economy.money_of(1) == Economy.START_MONEY - 650, "bought a vest for $650")
	var refused := []
	eco.buy_refused.connect(func(r: String) -> void: refused.append(r))
	eco.request_buy("rifle")
	_check(_player.primary_id == "" and refused == ["Not enough money"], "can't buy without the money")
	_press_action(&"buy_menu")
	await _frames(2)
	_check(not menu.visible and _player.input_enabled, "X closes it again")

	NetworkManager.roster[1].money = 10000
	eco.request_buy("rifle")
	_check(_player.primary_id == "rifle" and _player.current_weapon.data.weapon_id == "rifle"
		and Economy.money_of(1) == 10000 - 2700, "bought the AR-7: in hand, $2700 taken")
	eco.request_buy("rifle")
	_check(refused.back() == "You already have it", "no second copy of the same gun")
	_check(Economy.price_of("vest_helmet", _player) == Economy.HELMET_PRICE, "full vest: the helmet alone costs $%d" % Economy.HELMET_PRICE)
	eco.request_buy("vest_helmet")
	_check(_player.health.helmet and Economy.money_of(1) == 10000 - 2700 - Economy.HELMET_PRICE, "bought the helmet")
	for item: String in ["flash", "flash", "flash", "he", "smoke", "molotov"]:
		eco.request_buy(item)
	_check(_player.throwables.counts_array() == [1, 0, 2, 1], "2 flashes, 1 HE, 1 smoke (%s)" % str(_player.throwables.counts_array()))
	_check(refused.slice(-2) == ["You can't carry more", "You can't carry more grenades"], "grenade limits (%s)" % str(refused))
	NetworkManager.roster[1].money = 400


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
	b.phase_time_left = 5.0 # time for the buying checks
	await _frames(2)
	_check(b.round_number == 1 and b.phase == BombRules.Phase.FREEZE, "round 1 starts in freeze time")
	_check(b.is_attacker(1) and not b.is_attacker(402), "red attacks, blue defends")
	await _test_buying()
	var start := _player.global_position
	Input.action_press(&"move_forward")
	await _frames(15)
	Input.action_release(&"move_forward")
	_check(Vector2(_player.global_position.x - start.x, _player.global_position.z - start.z).length() < 0.05,
		"movement frozen during freeze time")
	b.phase_time_left = minf(b.phase_time_left, 0.2) # end the (long) test freeze now
	await _frames(30)
	_check(b.phase == BombRules.Phase.LIVE, "round goes live after freeze")
	_check(b.bomb_carrier == 1 and b.bomb_state == BombRules.BombState.CARRIED, "the attacker gets the bomb when the round goes live")
	# Armour (bought above): soaks 40 % of a weapon hit.
	_check(is_equal_approx(_player.health.armor, 100.0), "bought armour is full")
	_player.health.take_damage(50.0, defender)
	_check(is_equal_approx(_player.health.current, 70.0) and is_equal_approx(_player.health.armor, 80.0),
		"armour takes 40 %% of a hit (health %.0f, armour %.0f)" % [_player.health.current, _player.health.armor])
	_check(_level.hud._armor_label.text == "80" and _level.hud._armor_group.visible, "HUD shows the armour")
	_player.health.take_damage(10.0, null, false, "Fall")
	_check(is_equal_approx(_player.health.current, 60.0), "falls ignore armour")
	_player.health.heal(100.0)
	# Per-weapon penetration: a rifle bullet (78 %) loses little to armour, a
	# pistol bullet (50 %) half; legs are not covered by armour.
	var armour_before := _player.health.armor
	_player.health.take_damage(20.0, defender, false, "", 0.78)
	_check(is_equal_approx(_player.health.current, 100.0 - 15.6) and is_equal_approx(_player.health.armor, armour_before - 4.4),
		"rifle penetrates armour (health %.1f, armour %.1f)" % [_player.health.current, _player.health.armor])
	_player.health.heal(100.0)
	_player.health.take_damage(20.0, defender, false, "", 0.5)
	_check(is_equal_approx(_player.health.current, 90.0), "pistol loses half to armour (health %.1f)" % _player.health.current)
	_player.health.heal(100.0)
	armour_before = _player.health.armor
	_player.health.take_damage(20.0, defender, false, "", 0.5, false)
	_check(is_equal_approx(_player.health.current, 80.0) and is_equal_approx(_player.health.armor, armour_before),
		"leg hits ignore armour")
	_player.health.heal(100.0)
	# The helmet makes armour cover head hits too.
	armour_before = _player.health.armor
	_player.health.take_damage(20.0, defender, true, "", 0.5)
	_check(is_equal_approx(_player.health.current, 90.0) and _player.health.armor < armour_before,
		"helmet: armour soaks a head hit (health %.1f)" % _player.health.current)
	_player.health.heal(100.0)
	_player.health.helmet = false
	armour_before = _player.health.armor
	_player.health.take_damage(20.0, defender, true, "", 0.5)
	_check(is_equal_approx(_player.health.current, 80.0) and is_equal_approx(_player.health.armor, armour_before),
		"no helmet: head hits ignore armour")
	_player.health.helmet = true
	_player.health.heal(100.0)

	# Drop + pick up.
	b.on_player_down(1, _player.global_position + Vector3(0.5, 0, 0))
	_check(b.bomb_state == BombRules.BombState.DROPPED, "bomb drops when the carrier goes down")
	await _frames(3)
	_check(b.bomb_state == BombRules.BombState.CARRIED and b.bomb_carrier == 1, "attacker picks the dropped bomb up")

	# Round 1: plant at B, the defender defuses.
	var money_before := Economy.money_of(1)
	var defender_money := Economy.money_of(402)
	var armour_kept := _player.health.armor
	_reset_player(Vector3(9, 0.1, 0))
	await _frames(5)
	_check(b.site_at(_player.global_position) == "B", "standing inside site B")
	b.request_interact(true)
	await _frames(int(BombRules.PLANT_TIME * 60.0) + 10)
	b.request_interact(false)
	_check(b.bomb_state == BombRules.BombState.PLANTED and b.bomb_site == "B" and b.phase == BombRules.Phase.PLANTED,
		"bomb planted at B after holding interact")
	_check(Economy.money_of(1) == money_before + Economy.PLANT_REWARD, "planting pays $%d" % Economy.PLANT_REWARD)
	b.bomb_time = 30.0 # give the defender time in this round
	b.phase_time_left = 30.0
	defender.global_position = b.bomb_position + Vector3(1.0, 0, 0)
	b.server_set_interact(402, true)
	await _frames(int(BombRules.DEFUSE_TIME * 60.0) + 10)
	b.server_set_interact(402, false)
	_check(b.bomb_state == BombRules.BombState.DEFUSED and b.round_winner == 0 and b.round_reason == "Bomb defused",
		"defender defuses → Blue wins the round")
	_check(Match.team_scores[0] == 1 and Match.team_scores[1] == 0, "round score 1–0")
	_check(Economy.money_of(402) == defender_money + Economy.DEFUSE_REWARD + Economy.BOMB_WIN_REWARD,
		"defuser gets the defuse and bomb win money ($%d)" % Economy.money_of(402))
	_check(Economy.money_of(1) == money_before + Economy.PLANT_REWARD + Economy.LOSS_REWARD + Economy.PLANTED_LOSS_BONUS,
		"losing attackers get the loss bonus + $%d for the plant ($%d)" % [Economy.PLANTED_LOSS_BONUS, Economy.money_of(1)])
	var rewards := _level.hud._money_events.get_children().map(func(l: Label) -> String: return l.text)
	_check(rewards.any(func(x: String) -> bool: return "Round lost" in x), "HUD shows the round money (%s)" % str(rewards))

	# Round 2: plant at A and let it explode (we stay next to it).
	b.bomb_time = 2.0
	await _frames(45)
	_check(b.round_number == 2 and not _player.health.is_dead and not defender.health.is_dead, "round 2: everyone revived")
	_check(_player.primary_id == "rifle" and is_equal_approx(_player.health.armor, armour_kept) and _player.health.helmet
		and _player.throwables.counts[Throwables.Kind.FLASH] == 2 and _player.throwables.counts[Throwables.Kind.SMOKE] == 1,
		"a survivor keeps gun, armour, helmet and grenades (%s, %.0f)" % [_player.primary_id, _player.health.armor])
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
	_check(b.round_number == 3 and _player.primary_id == "" and _player.current_weapon.data.weapon_id == "pistol"
		and is_zero_approx(_player.health.armor) and _player.throwables.counts_array() == [0, 0, 0, 0],
		"after dying: pistol and knife only, no armour, no grenades")
	await _frames(35)
	_check(b.phase == BombRules.Phase.LIVE and b.round_number == 3, "round 3 live")
	_check(Economy.buy_block_reason(_player) == "", "buying stays open just after the freeze time")
	_reset_player(Vector3(-16, 0.1, -4)) # site A, well away from the red spawn
	await _frames(2)
	_check(Economy.buy_block_reason(_player) == "Go back to your spawn to buy", "no buying away from your spawn")
	b.phase_time_left = b.round_time - Economy.BUY_TIME - 1.0
	_check(Economy.buy_time_left() <= 0.0, "buy time closes %ds into the round" % Economy.BUY_TIME)
	money_before = Economy.money_of(1)
	defender.health.take_damage(500.0, _player)
	await _frames(2)
	_check(b.round_reason == "Defenders eliminated", "eliminating the defenders wins the round")
	_check(Economy.money_of(1) == money_before + Economy.KILL_REWARD + Economy.WIN_REWARD,
		"pistol kill $%d + round win $%d ($%d)" % [Economy.KILL_REWARD, Economy.WIN_REWARD, Economy.money_of(1)])
	_check(Match.is_ended() and Match.winner_text == "Red team wins!", "match ends at the round limit (%s)" % Match.winner_text)

	# Halftime: sides swap after the configured number of rounds.
	Match.state = Match.State.PLAYING
	b.halftime_after = 1
	Match.start_match()
	var first := b.attacking_team
	b._end_round(0, "test")
	b._start_round()
	_check(b.attacking_team != first and b.sides_swapped, "sides swap at halftime")
	_check(Economy.money_of(1) == Economy.START_MONEY and Economy.money_of(402) == Economy.START_MONEY,
		"halftime resets the money")

	# Overtime: first to 2 → regulation is 2 rounds; 1–1 → overtime (halves of 1 round).
	Match.state = Match.State.PLAYING
	b.halftime_after = -1
	b.overtime_half = 1
	Match.start_match()
	b._end_round(0, "test")
	b._start_round()
	b._end_round(1, "test")
	_check(b.overtime == 1 and b.win_target == 3 and not Match.is_ended(),
		"level at the end of regulation → overtime, first to %d" % b.win_target)
	b._start_round()
	_check(b.sides_swapped and Economy.money_of(1) == Economy.OVERTIME_MONEY, "overtime: sides swap, $%d each" % Economy.OVERTIME_MONEY)
	b._end_round(0, "test")
	b._start_round()
	b._end_round(0, "test")
	_check(Match.is_ended() and "overtime" in Match.winner_text, "overtime winner takes the match (%s)" % Match.winner_text)
	b.overtime_half = 3

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
	# Docks: lights per preset, the warehouse echo, the ramp up onto A Long.
	await _load_map("res://scenes/levels/docks.tscn")
	_check(_level.blue_spawn_points.size() >= 3 and _level.red_spawn_points.size() >= 3, "docks has team spawns")
	SettingsManager.set_graphics_quality(GraphicsPreset.Quality.LOW)
	_check(not (_level.get_node("Lights") as Node3D).visible, "Low preset turns decorative lights off")
	SettingsManager.set_graphics_quality(GraphicsPreset.Quality.MEDIUM)
	_check((_level.get_node("Lights") as Node3D).visible, "Medium preset turns them back on")
	await _frames(40)
	_check(_player.is_on_floor(), "docks: player lands")
	var hall := _reverb_zone_at(Vector3(0, 2, 0))
	_check(hall and hall.reverb_bus_name == &"ReverbHall", "docks: the Port Authority warehouse echoes (reverb zone)")
	_check(_reverb_zone_at(Vector3(4, 2, 30)) == null, "no reverb out on the quay")
	_reset_player(Vector3(48, 0.1, -13))
	await _walk_forward_max_y(200)
	_check(_player.global_position.y > 1.9 and _player.global_position.z < -24.0,
		"docks: ramp from T spawn up onto A Long (y=%.2f, z=%.1f)" % [_player.global_position.y, _player.global_position.z])
	_reset_player(Vector3(2, 0.1, 36), PI) # facing the water
	await _walk_forward_max_y(90)
	_check(_player.global_position.z < 40.0 and _player.global_position.y > -0.5, "docks: the quay edge keeps players out of the water")

	# Oasis: A ramp onto the terrace, Mid doors, the covered B Apartments.
	await _load_map("res://scenes/levels/oasis.tscn")
	await _frames(40)
	_open_all_doors()
	_check(_player.is_on_floor(), "oasis: player lands")
	_reset_player(Vector3(28, 0.1, -10.5))
	await _walk_forward_max_y(150)
	_check(_player.global_position.y > 0.95 and _player.global_position.z < -18.5,
		"oasis: A ramp leads up onto the site terrace (y=%.2f, z=%.1f)" % [_player.global_position.y, _player.global_position.z])
	_reset_player(Vector3(0, 0.1, 4))
	await _walk_forward_max_y(150)
	_check(_player.global_position.z < -6.0, "oasis: Mid doors are passable (z=%.1f)" % _player.global_position.z)
	_reset_player(Vector3(-32, 0.1, 22))
	await _walk_forward_max_y(330)
	_check(_player.global_position.z < -2.0, "oasis: B Apartments corridor is passable (z=%.1f)" % _player.global_position.z)
	# Enterable houses: in through a door, up the stairs.
	_reset_player(Vector3(32, 0.1, -6.2), PI / 2)
	await _walk_forward_max_y(150)
	_check(_player.global_position.x < 25.0, "oasis: door into the house on A Long (x=%.1f)" % _player.global_position.x)
	_reset_player(Vector3(19.15, 0.1, -8.5), PI)
	var upstairs := await _walk_forward_max_y(200)
	_check(upstairs > 3.9, "oasis: stairs to the house's upper floor (y=%.2f)" % upstairs)
	_reset_player(Vector3(-33, 0.1, 0.3), -PI / 2)
	await _walk_forward_max_y(150)
	_check(_player.global_position.x > -27.0, "oasis: door into the house by B (x=%.1f)" % _player.global_position.x)

	# Radar + location names (built from the map's collision shapes).
	var radar: Minimap = _level.hud._minimap
	_check(radar._polys.size() > 60, "radar outline built from the map (%d shapes)" % radar._polys.size())
	_check((_level.hud._banner.get_node(^"Title") as Label).text == "OASIS", "map name banner shows OASIS")
	var tex := load("res://assets/textures/surfaces_albedo.png") as TextureLayered
	var nrm := load("res://assets/textures/surfaces_normal.png") as TextureLayered
	_check(tex != null and nrm != null and tex.get_layers() == 7 and nrm.get_layers() == 7
		and ProjectSettings.has_setting("shader_globals/surface_albedo"), "surface detail texture arrays (7 layers each)")
	var signs := _level.get_node_or_null(^"Signs")
	_check(signs != null and signs.get_child_count() >= 8, "painted A/B direction signs on the walls")
	_check(is_zero_approx(_player.health.armor), "no armour outside Bomb Defusal")
	_check(radar.location(Vector3(28, 1.1, -24)) == "Bombsite A" and radar.location(Vector3(0, 0.1, 8)) == "Mid"
		and radar.location(Vector3(-34, 0.1, 10)) == "B Apartments", "location names: Bombsite A, Mid, B Apartments")
	_check(radar.location(Vector3(-28, 0.1, -20)) == "Bombsite B", "bomb site fallback / callout for B")
	var armed := _player.loadout_weapons().all(func(w: Weapon) -> bool:
		return w == null or (w.has_node(^"ArmR") and (w.data.melee or (w.has_node(^"ArmL") and w.has_node(^"Magazine")))))
	_check(armed, "first-person weapons have gloved arms and a separate magazine (the knife: one hand)")

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
			["factory", Vector3(4.8, 0.1, -19), 0.0, func(p: Vector3) -> bool: return p.z < -29.5, "through the Lanka Steel doors to A"],
			["factory", Vector3(-4.8, 0.1, -23.15), -PI / 2, func(p: Vector3) -> bool: return p.y > 4.3, "stairs to Lanka Steel's upper floor"],
			["factory", Vector3(-31, 0.1, 10), -PI / 2, func(p: Vector3) -> bool: return p.x > -7.0, "through the tunnels"],
			["factory", Vector3(24, 0.1, -19), 0.0, func(p: Vector3) -> bool: return p.y > 3.9, "ramp up to the roof"],
			["factory", Vector3(16.8, 0.1, 4), 0.0, func(p: Vector3) -> bool: return p.y > 3.9, "ramp up to the catwalk"],
			["factory", Vector3(5, 0.1, 6), PI, func(p: Vector3) -> bool: return p.z > 20.0, "Lower Mid into B"],
			["office", Vector3(0, 0.1, 40), 0.0, func(p: Vector3) -> bool: return p.z < 24.0, "front doors into the lobby"],
			["office", Vector3(20, 0.1, 4), 0.0, func(p: Vector3) -> bool: return p.y > 3.5, "stairs up to the mezzanine"],
			["subway", Vector3(-15, 0.1, 22), 0.0, func(p: Vector3) -> bool: return p.z < 0.0, "west platform"],
			["subway", Vector3(6, -1.1, -20), 0.0, func(p: Vector3) -> bool: return p.y > -0.1 and p.z < -30.0, "climb out of the track bed"],
			["subway", Vector3(-10, 0.1, 4.7), -PI / 2, func(p: Vector3) -> bool: return p.x > -3.0, "walk through the train"],
			# Docks: Mid through the warehouse, A Short / B Short, B Long, the CT routes.
			["docks", Vector3(30, 0.1, 0), PI / 2, func(p: Vector3) -> bool: return p.x < 10.0, "T Mid through the east door into the warehouse"],
			["docks", Vector3(-30, 0.1, 0), -PI / 2, func(p: Vector3) -> bool: return p.x > -10.0, "CT Mid through the west door"],
			["docks", Vector3(-5, 0.1, -5), 0.0, func(p: Vector3) -> bool: return p.z < -24.0, "north door up A Short into A"],
			["docks", Vector3(4, 0.1, 5), PI, func(p: Vector3) -> bool: return p.z > 22.0, "south door down B Short onto B"],
			["docks", Vector3(48, 0.1, 9), PI, func(p: Vector3) -> bool: return p.z > 22.0, "the road from T spawn down to B Long"],
			["docks", Vector3(-44, 0.1, -10), 0.0, func(p: Vector3) -> bool: return p.z < -32.0, "CT to the A yard"],
			["docks", Vector3(-46, 0.1, 10), PI, func(p: Vector3) -> bool: return p.z > 26.0, "CT down to the B quay"],
			["docks", Vector3(24, 2.1, -27), PI / 2, func(p: Vector3) -> bool: return p.x < 4.0, "along A Long and down into A"],
			# Bunker: A Long up to the balcony over A, B Long down the tunnel, Mid.
			["bunker", Vector3(-41, 0.1, -8.5), 0.0, func(p: Vector3) -> bool: return p.y > 2.4 and p.z < -24.0, "A Long ramp up to the upper corridor"],
			["bunker", Vector3(-30, 2.6, -31), -PI / 2, func(p: Vector3) -> bool: return p.x > -13.0, "A Long Upper onto the balcony over A"],
			["bunker", Vector3(-11, 2.6, -30), PI, func(p: Vector3) -> bool: return p.z > -21.0, "balcony stairs down into A"],
			["bunker", Vector3(-41, 0.1, 8.5), PI, func(p: Vector3) -> bool: return p.z > 24.0, "B Long ramp down into the tunnel"],
			["bunker", Vector3(-34, -2.9, 25), -PI / 2, func(p: Vector3) -> bool: return p.x > -12.0, "tunnel into B"],
			["bunker", Vector3(0, 0.1, 10), PI, func(p: Vector3) -> bool: return p.z > 21.0, "B stairs from Mid"],
			["bunker", Vector3(0, 0.1, -5), 0.0, func(p: Vector3) -> bool: return p.z < -21.0, "A Short from Mid"],
			["bunker", Vector3(-34, 0.1, 0), -PI / 2, func(p: Vector3) -> bool: return p.x > -12.0, "T Mid into Mid"],
			["bunker", Vector3(-26, 0.1, 0), 0.0, func(p: Vector3) -> bool: return p.z < -6.0, "door into Storage"],
			["bunker", Vector3(-16.5, 0.1, -1), 0.0, func(p: Vector3) -> bool: return p.y > 3.3, "ramp up to the Mid catwalk"],
			# Train Yard: dock (A Long), warehouse A, A Main, B stairs, B Long, CT routes.
			["trainyard", Vector3(-43, 0.1, -9), 0.0, func(p: Vector3) -> bool: return p.y > 1.1 and p.z < -24.0, "ramp up onto the A Long dock"],
			["trainyard", Vector3(-30, 1.3, -28), -PI / 2, func(p: Vector3) -> bool: return p.x > -18.0, "dock door into the A warehouse"],
			["trainyard", Vector3(-4, 1.3, -26), PI, func(p: Vector3) -> bool: return p.z > -8.0, "A Main ramp down into Mid"],
			["trainyard", Vector3(-1, 0.1, 5), PI, func(p: Vector3) -> bool: return p.z > 24.0, "B stairs down into B"],
			["trainyard", Vector3(-43, 0.1, 9), PI, func(p: Vector3) -> bool: return p.z > 30.0, "B Long down into the rail cut"],
			["trainyard", Vector3(-34, -2.4, 31), -PI / 2, func(p: Vector3) -> bool: return p.x > -14.0, "rail cut into B"],
			["trainyard", Vector3(-2, 1.3, -37), -PI / 2, func(p: Vector3) -> bool: return p.x > 12.0, "warehouse east door down to the water tower"],
			["trainyard", Vector3(42, 0.1, 7), PI, func(p: Vector3) -> bool: return p.z > 29.0, "CT ramp down towards B"],
			["trainyard", Vector3(-34, 0.1, 1), -PI / 2, func(p: Vector3) -> bool: return p.x > -20.0, "T Mid into the rail yard"]]:
		if _level.name.to_lower() != route[0]:
			await _load_map("res://scenes/levels/%s.tscn" % route[0])
			await _frames(30)
			_check(_player.is_on_floor(), "%s: player lands" % route[0])
			_open_all_doors()
		_reset_player(route[1], route[2])
		await _frames(2)
		# The check sees where the walk ended, with y = the highest point reached.
		var peak := await _walk_forward_max_y(300)
		var at := Vector3(_player.global_position.x, peak, _player.global_position.z)
		_check((route[3] as Callable).call(at), "%s: %s (at %s)" % [route[0], route[4], at.snapped(Vector3.ONE * 0.1)])

	# Every map has team spawns and bomb sites A + B.
	for m: Dictionary in GameConfig.MAPS:
		var lvl := (load(m.path) as PackedScene).instantiate() as Level
		var ok := lvl.blue_spawn_points.size() >= 3 and lvl.red_spawn_points.size() >= 3 and lvl.bomb_sites.size() == 2
		lvl.free()
		_check(ok, "%s: team spawns + bomb sites A/B" % m.name)

	# No "sometimes jumpable" ledges: anything a jump only reaches with the
	# right run-up (Climb.BORDERLINE_*) is climbable instead (tools/ledge_check.gd).
	var ledge_check := preload("res://tools/ledge_check.gd")
	for m: Dictionary in GameConfig.MAPS:
		var lvl := (load(m.path) as PackedScene).instantiate() as Level
		lvl.preview_only = true
		lvl.position = Vector3(0, -500, 0) # away from the current map
		get_tree().root.add_child(lvl)
		await _frames(2)
		var found: PackedStringArray = ledge_check.scan(lvl)
		lvl.queue_free()
		await _frames(1)
		_check(found.is_empty(), "%s: no half-jumpable ledges %s" % [m.name, str(found.slice(0, 3))])


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
	# Shoot at the sky: a real hit on a (strafing) target would add a hit
	# marker of its own and make the counts below timing-dependent.
	_player.head.rotation.x = deg_to_rad(80)
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
		and _stat_delta(before, "ui:kill") == 1, "hit marker, headshot and kill sounds (%d / %d / %d)"
		% [_stat_delta(before, "ui:hitmarker"), _stat_delta(before, "ui:headshot"), _stat_delta(before, "ui:kill")])
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
	_check(pad_prompt == "LB" and SettingsManager.prompt_text(&"interact") == "F", "button prompts follow the device (LB / F)")

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


## Routes walk straight through doorways: open every door first.
func _open_all_doors() -> void:
	for d in get_tree().get_nodes_in_group(Door.GROUP):
		(d as Door).set_open(1, true)


## Office: a door opens with F (away from you), breaks where it is shot;
## glass cracks, then shatters, and bullets / grenades go through.
func _test_doors_and_glass() -> void:
	await _load_map("res://scenes/levels/office.tscn")
	await _frames(30)
	var doors := get_tree().get_nodes_in_group(Door.GROUP)
	_check(doors.size() >= 8, "office has doors (%d)" % doors.size())
	var panes := get_tree().get_nodes_in_group(GlassPane.GROUP)
	_check(panes.size() >= 10, "office has glass panes (%d)" % panes.size())
	# The store room door (StoreWall, z = -12).
	var door: Door = null
	for d: Door in doors:
		if (d as Node3D).global_position.distance_to(Vector3(13.9, 0, -12)) < 0.5:
			door = d
	_check(door != null and not door.is_open(), "store room door found, closed")
	if door == null:
		return
	_reset_player(Vector3(13.9, 0.1, -9.6))
	await _frames(5)
	await _walk_forward_max_y(60)
	_check(_player.global_position.z > -11.7, "a closed door blocks the way (z=%.2f)" % _player.global_position.z)
	_reset_player(Vector3(13.9, 0.1, -10.2))
	await _frames(3)
	_press_action(&"interact")
	await _frames(30)
	_check(door.is_open() and door.open_side == -1, "F opens the door away from the player (side %d)" % door.open_side)
	await _walk_forward_max_y(90)
	_check(_player.global_position.z < -13.0, "walk through the open door (z=%.2f)" % _player.global_position.z)
	_reset_player(Vector3(13.2, 0.1, -12.9), PI) # turn round, the leaf is beside us
	_aim_at(Vector3(13.9, 1.2, -12.0))
	await _frames(3)
	_press_action(&"interact")
	await _frames(30)
	_check(not door.is_open(), "F again closes it")
	# Shoot the closed door: the piece under the crosshair splinters and breaks.
	_reset_player(Vector3(13.9, 0.1, -7.0))
	_player.select_slot(0, true)
	_player.health.protect(0.0)
	await _frames(20)
	var target := Vector3(13.6, 1.25, -12)
	var before := door.pieces_left()
	for i in 6:
		_aim_at(target)
		Input.action_press(&"shoot")
		await _frames(2)
		Input.action_release(&"shoot")
		await _frames(10)
	_check(door.pieces_left() < before, "shots break the door where they hit (%d → %d pieces)" % [before, door.pieces_left()])
	var eye := _player.camera.global_position
	var q := PhysicsRayQueryParameters3D.create(eye, eye + (target - eye) * 1.5, 1)
	var through := get_tree().root.get_world_3d().direct_space_state.intersect_ray(q)
	var past: bool = through.is_empty() or (through.position as Vector3).z < -12.2
	_check(past, "a bullet hole: the view goes through the broken piece")

	# Glass: the conference room wall (z = 14).
	var pane: GlassPane = null
	for gp: GlassPane in panes:
		if (gp as Node3D).global_position.distance_to(Vector3(-19.5, 1.6, 14)) < 2.5:
			pane = gp
	_check(pane != null and not pane.broken, "conference room glass found")
	if pane == null:
		return
	_reset_player(Vector3(pane.global_position.x, 0.1, 10.0), PI)
	await _frames(10)
	_aim_at(pane.global_position)
	_player.select_slot(1, true) # the pistol: one shot at a time
	await _frames(20)
	_aim_at(pane.global_position)
	Input.action_press(&"shoot")
	await _frames(2)
	Input.action_release(&"shoot")
	await _frames(15)
	_check(pane.cracked and not pane.broken, "the first shot cracks the glass")
	_aim_at(pane.global_position + Vector3(0.3, 0.2, 0))
	Input.action_press(&"shoot")
	await _frames(2)
	Input.action_release(&"shoot")
	await _frames(15)
	_check(pane.broken, "the second shot shatters it")
	_reset_player(Vector3(pane.global_position.x, 0.1, 12.5), PI)
	await _walk_forward_max_y(60)
	_check(_player.global_position.z > 14.3, "walk through the shattered window (z=%.2f)" % _player.global_position.z)
	# An HE blast shatters glass round it and splinters doors.
	var other: GlassPane = null
	for gp: GlassPane in panes:
		if not (gp as GlassPane).broken:
			other = gp
			break
	_player.throwables._blast_breakables(other.global_position + Vector3(0, 0, 1.0), Throwables.HE_RADIUS, 160.0)
	_check(other.broken, "an HE blast shatters nearby windows")
	_player.select_slot(0, true)


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
