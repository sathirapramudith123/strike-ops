class_name BombRules
extends Node
## Bomb Defusal rounds (child of the Match autoload: /root/Match/BombRules).
##
## Attackers carry one bomb and must plant it at site A or B (hold Interact
## for PLANT_TIME inside the site). Defenders win by defusing it (hold
## Interact for DEFUSE_TIME next to it), by eliminating the attackers before
## a plant, or when the round clock runs out. Attackers win when the bomb
## explodes or every defender is dead. No respawns during a round; the next
## round revives everyone. First team to `Match.score_limit` round wins takes
## the match; sides swap at halftime.
##
## Server-authoritative: clients only send "interact held / released" and
## receive a compact state sync (plus local countdowns in between).

signal round_changed
signal round_started(round_number: int)
signal round_ended(winner_team: int, reason: String)
signal bomb_planted(site: String)
signal bomb_exploded(position: Vector3)
signal bomb_defused

enum Phase { FREEZE, LIVE, PLANTED, ROUND_END }
enum BombState { CARRIED, DROPPED, PLANTED, DEFUSED, EXPLODED }
enum Action { NONE, PLANT, DEFUSE }

const PLANT_TIME := 3.0
const DEFUSE_TIME := 5.0
const DEFUSE_RANGE := 2.0
const PICKUP_RANGE := 1.5
const SITE_RADIUS := 3.5
const EXPLOSION_RADIUS := 15.0
const EXPLOSION_DAMAGE := 250.0
## Max movement per physics frame while planting/defusing (≈ standing still).
const STILL_DISTANCE := 0.05

# Tunables (server; tests shorten them).
var freeze_time: float = 5.0
var round_time: float = 105.0
var bomb_time: float = 40.0
var round_end_time: float = 5.0
## Swap sides after this many rounds (-1 = score_limit - 1, 0 = never).
var halftime_after: int = -1

# Replicated state.
var phase: Phase = Phase.FREEZE
var phase_time_left: float = 0.0
var round_number: int = 0
var attacking_team: int = 1
var bomb_state: BombState = BombState.CARRIED
var bomb_carrier: int = -1
var bomb_position: Vector3 = Vector3.ZERO
var bomb_site: String = ""
var action: Action = Action.NONE
var action_player: int = -1
var action_progress: float = 0.0
var round_winner: int = -1
var round_reason: String = ""
var sides_swapped: bool = false
## Freeze time is on hold until both teams have at least one player.
var waiting_for_players: bool = false

var _interact: Dictionary = {} # server: peer_id -> holding Interact
var _last_positions: Dictionary = {} # server: peer_id -> position last frame
var _sync_timer: float = 0.0


func _process(delta: float) -> void:
	if Match.mode != GameConfig.Mode.BOMB:
		return
	phase_time_left = maxf(phase_time_left - delta, 0.0)
	if not multiplayer.is_server() or round_number == 0:
		return
	if Match.is_ended():
		return
	match phase:
		Phase.FREEZE:
			var waiting := not (_team_has_players(0) and _team_has_players(1))
			if waiting != waiting_for_players:
				waiting_for_players = waiting
				_sync()
			if waiting:
				phase_time_left = freeze_time
			elif phase_time_left <= 0.0:
				_go_live()
		Phase.LIVE:
			_update_carrier_and_plant(delta)
			if phase == Phase.LIVE and phase_time_left <= 0.0:
				_end_round(defending_team(), "Time ran out")
		Phase.PLANTED:
			_update_defuse(delta)
			if phase == Phase.PLANTED and phase_time_left <= 0.0:
				_explode()
		Phase.ROUND_END:
			if phase_time_left <= 0.0:
				_start_round()
	_remember_positions()
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = 0.2
		_sync()


# -----------------------------------------------------------------------------
# Queries
# -----------------------------------------------------------------------------

func defending_team() -> int:
	return 1 - attacking_team


func is_attacker(peer_id: int) -> bool:
	return Match.get_team(peer_id) == attacking_team


## Movement is frozen during the buy/freeze time.
func is_frozen() -> bool:
	return Match.mode == GameConfig.Mode.BOMB and phase == Phase.FREEZE and round_number > 0


## Name of the bomb site containing `pos` ("" if none).
func site_at(pos: Vector3) -> String:
	var level := _level()
	if level == null:
		return ""
	for m: Marker3D in level.bomb_sites:
		var d := m.global_position
		if Vector2(pos.x - d.x, pos.z - d.z).length() <= SITE_RADIUS and absf(pos.y - d.y) < 3.0:
			return m.name
	return ""


func alive_count(team: int) -> int:
	var n := 0
	var level := _level()
	if level:
		for p in level.get_players():
			if Match.get_team(p.peer_id) == team and not p.health.is_dead:
				n += 1
	return n


# -----------------------------------------------------------------------------
# Server: round flow
# -----------------------------------------------------------------------------

func start_match() -> void:
	round_number = 0
	attacking_team = 1
	sides_swapped = false
	_start_round()


func _start_round() -> void:
	if Match.is_ended():
		return
	var halftime := halftime_after if halftime_after >= 0 else maxi(Match.score_limit - 1, 0)
	sides_swapped = halftime > 0 and round_number == halftime
	if sides_swapped:
		attacking_team = 1 - attacking_team
	round_number += 1
	phase = Phase.FREEZE
	phase_time_left = freeze_time
	bomb_state = BombState.CARRIED
	bomb_carrier = -1
	bomb_site = ""
	round_winner = -1
	round_reason = ""
	_reset_action()
	_interact.clear()

	var level := _level()
	if level:
		for p in level.get_players():
			p.net_sync.server_force_respawn()
	print("[bomb] Round %d — %s attack%s" % [round_number, GameConfig.TEAM_NAMES[attacking_team],
		" (sides swapped)" if sides_swapped else ""])
	_sync()
	round_started.emit(round_number)
	round_changed.emit()


## Freeze time over: hand the bomb to a random living attacker and start the clock.
func _go_live() -> void:
	phase = Phase.LIVE
	phase_time_left = round_time
	var level := _level()
	if level and bomb_carrier < 0:
		var attackers := level.get_players().filter(func(p: PlayerController) -> bool:
			return is_attacker(p.peer_id) and not p.health.is_dead)
		if not attackers.is_empty():
			var carrier: PlayerController = attackers.pick_random()
			bomb_carrier = carrier.peer_id
			bomb_position = carrier.global_position
	_sync()
	round_changed.emit()


func _end_round(winner: int, reason: String) -> void:
	if phase == Phase.ROUND_END:
		return
	phase = Phase.ROUND_END
	phase_time_left = round_end_time
	round_winner = winner
	round_reason = reason
	_reset_action()
	Match.team_scores[winner] += 1
	print("[bomb] Round %d → %s (%s)" % [round_number, GameConfig.TEAM_NAMES[winner], reason])
	_sync()
	round_ended.emit(winner, reason)
	round_changed.emit()
	if Match.score_limit > 0 and Match.team_scores[winner] >= Match.score_limit:
		Match._end_match("%s team wins!" % GameConfig.TEAM_NAMES[winner])


## Called by Match.on_kill() and when a player leaves.
func on_player_down(victim_id: int, position: Vector3) -> void:
	if not multiplayer.is_server() or round_number == 0:
		return
	if bomb_state == BombState.CARRIED and victim_id == bomb_carrier:
		bomb_state = BombState.DROPPED
		bomb_carrier = -1
		bomb_position = position
		_sync()
	_check_elimination()


func _check_elimination() -> void:
	if phase != Phase.LIVE and phase != Phase.PLANTED:
		return
	var att := alive_count(attacking_team)
	var def := alive_count(defending_team())
	if def == 0 and _team_has_players(defending_team()):
		_end_round(attacking_team, "Defenders eliminated")
	elif att == 0 and phase == Phase.LIVE and _team_has_players(attacking_team):
		_end_round(defending_team(), "Attackers eliminated")


func _team_has_players(team: int) -> bool:
	for id: int in NetworkManager.roster:
		if Match.get_team(id) == team:
			return true
	return false


# -----------------------------------------------------------------------------
# Server: bomb
# -----------------------------------------------------------------------------

func _update_carrier_and_plant(delta: float) -> void:
	var level := _level()
	if level == null:
		return
	if bomb_state == BombState.CARRIED:
		var carrier := level.get_player(bomb_carrier)
		if carrier == null or carrier.health.is_dead:
			on_player_down(bomb_carrier, carrier.global_position if carrier else bomb_position)
			return
		bomb_position = carrier.global_position
		var site := site_at(carrier.global_position)
		if _interact.get(bomb_carrier, false) and site != "" and _is_still(carrier):
			if action != Action.PLANT or action_player != bomb_carrier:
				action = Action.PLANT
				action_player = bomb_carrier
				action_progress = 0.0
			action_progress += delta / PLANT_TIME
			if action_progress >= 1.0:
				_plant(site, carrier.global_position)
		elif action == Action.PLANT:
			_reset_action()
	elif bomb_state == BombState.DROPPED:
		for p in level.get_players():
			if is_attacker(p.peer_id) and not p.health.is_dead \
					and p.global_position.distance_to(bomb_position) <= PICKUP_RANGE:
				bomb_state = BombState.CARRIED
				bomb_carrier = p.peer_id
				_sync()
				break


func _plant(site: String, pos: Vector3) -> void:
	bomb_state = BombState.PLANTED
	bomb_site = site
	bomb_position = pos
	bomb_carrier = -1
	phase = Phase.PLANTED
	phase_time_left = bomb_time
	_reset_action()
	print("[bomb] Bomb planted at %s" % site)
	_sync()
	bomb_planted.emit(site)
	round_changed.emit()


func _update_defuse(delta: float) -> void:
	var level := _level()
	if level == null:
		return
	var defuser: PlayerController = null
	for p in level.get_players():
		if not is_attacker(p.peer_id) and not p.health.is_dead and _interact.get(p.peer_id, false) \
				and p.global_position.distance_to(bomb_position) <= DEFUSE_RANGE and _is_still(p):
			# Keep the current defuser if they're still valid.
			if defuser == null or p.peer_id == action_player:
				defuser = p
	if defuser == null:
		if action == Action.DEFUSE:
			_reset_action()
		return
	if action != Action.DEFUSE or action_player != defuser.peer_id:
		action = Action.DEFUSE
		action_player = defuser.peer_id
		action_progress = 0.0
	action_progress += delta / DEFUSE_TIME
	if action_progress >= 1.0:
		bomb_state = BombState.DEFUSED
		print("[bomb] Bomb defused by %s" % NetworkManager.get_player_name(defuser.peer_id))
		bomb_defused.emit()
		_end_round(defending_team(), "Bomb defused")


func _explode() -> void:
	bomb_state = BombState.EXPLODED
	# End the round first so blast deaths don't count as an "elimination".
	_end_round(attacking_team, "Bomb exploded")
	bomb_exploded.emit(bomb_position)
	var level := _level()
	if level:
		for p in level.get_players():
			var d := p.global_position.distance_to(bomb_position)
			if d < EXPLOSION_RADIUS and not p.health.is_dead:
				p.health.take_damage(EXPLOSION_DAMAGE * (1.0 - d / EXPLOSION_RADIUS), null, false, "Bomb")


func _reset_action() -> void:
	action = Action.NONE
	action_player = -1
	action_progress = 0.0


func _is_still(p: PlayerController) -> bool:
	var last: Vector3 = _last_positions.get(p.peer_id, p.global_position)
	return last.distance_to(p.global_position) <= STILL_DISTANCE


func _remember_positions() -> void:
	var level := _level()
	if level:
		for p in level.get_players():
			_last_positions[p.peer_id] = p.global_position


# -----------------------------------------------------------------------------
# Interact (plant / defuse key)
# -----------------------------------------------------------------------------

## Local player pressed / released Interact.
func request_interact(held: bool) -> void:
	if multiplayer.is_server():
		_interact[multiplayer.get_unique_id()] = held
	elif NetworkManager.is_online():
		_set_interact.rpc_id(1, held)


## Server: set another peer's Interact state (tests / bots).
func server_set_interact(peer_id: int, held: bool) -> void:
	_interact[peer_id] = held


@rpc("any_peer", "call_remote", "reliable")
func _set_interact(held: bool) -> void:
	if multiplayer.is_server():
		_interact[multiplayer.get_remote_sender_id()] = held


# -----------------------------------------------------------------------------
# Sync
# -----------------------------------------------------------------------------

func send_state_to(peer_id: int) -> void:
	_sync_round.rpc_id(peer_id, _pack())


func _sync() -> void:
	if NetworkManager.is_online() and multiplayer.is_server():
		_sync_round.rpc(_pack())


func _pack() -> Array:
	return [phase, phase_time_left, round_number, attacking_team, bomb_state, bomb_carrier,
		bomb_position, bomb_site, action, action_player, action_progress, round_winner,
		round_reason, sides_swapped, Match.team_scores, waiting_for_players]


@rpc("authority", "call_remote", "reliable")
func _sync_round(data: Array) -> void:
	var old_round := round_number
	var old_phase := phase
	var old_bomb := bomb_state
	phase = data[0]
	phase_time_left = data[1]
	round_number = data[2]
	attacking_team = data[3]
	bomb_state = data[4]
	bomb_carrier = data[5]
	bomb_position = data[6]
	bomb_site = data[7]
	action = data[8]
	action_player = data[9]
	action_progress = data[10]
	round_winner = data[11]
	round_reason = data[12]
	sides_swapped = data[13]
	Match.team_scores = data[14]
	waiting_for_players = data[15]
	if round_number != old_round:
		round_started.emit(round_number)
	if phase == Phase.ROUND_END and old_phase != Phase.ROUND_END:
		round_ended.emit(round_winner, round_reason)
	if bomb_state == BombState.PLANTED and old_bomb != BombState.PLANTED:
		bomb_planted.emit(bomb_site)
	if bomb_state == BombState.EXPLODED and old_bomb != BombState.EXPLODED:
		bomb_exploded.emit(bomb_position)
	if bomb_state == BombState.DEFUSED and old_bomb != BombState.DEFUSED:
		bomb_defused.emit()
	round_changed.emit()


func _level() -> Level:
	return NetworkManager.current_level()
