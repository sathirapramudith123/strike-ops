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
	_test_friendly_fire_and_match_end()
	await _test_bomb_defusal()
	await _test_settings_menu()
	await _test_maps()

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
	_check(not sniper.get_node("Receiver").visible, "viewmodel hidden while scoped")
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


func _test_maps() -> void:
	# Warehouse: ramp from the ground up to the catwalk (3 m).
	await _load_map("res://scenes/levels/warehouse.tscn")
	_check(_level.blue_spawn_points.size() >= 3 and _level.red_spawn_points.size() >= 3, "warehouse has team spawns")
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
