extends Node
## Match rules and state (autoload: Match).
##
## Server-authoritative: the server assigns teams, counts the score, runs the
## clock, ends the match and rotates to the next map. Clients receive a small
## state sync once per second (plus immediately on changes) and count the
## clock down locally in between.
##
## Modes (GameConfig.Mode):
##   PRACTICE – offline, no limits
##   FFA      – first to `score_limit` kills, or most kills when time runs out
##   TDM      – two teams (auto-balanced), friendly fire off, team score
##   BOMB     – rounds of Bomb Defusal (see BombRules); team_scores = round wins

signal state_changed
signal match_ended(winner_text: String)
signal teams_changed

enum State { PLAYING, ENDED }

const RESULTS_TIME := 10.0

var mode: GameConfig.Mode = GameConfig.Mode.PRACTICE
var state: State = State.PLAYING
var score_limit: int = 0
var time_limit: float = 0.0
var time_left: float = 0.0
var team_scores: PackedInt32Array = [0, 0]
var winner_text: String = ""
## Map vote on the results screen: candidate map paths and their vote counts.
var vote_maps: PackedStringArray = []
var vote_counts: PackedInt32Array = []
## What the local player voted for (-1 = nothing yet).
var my_vote: int = -1
## Seconds the results screen stays up before the next map (server).
var results_time: float = RESULTS_TIME

var _results_timer: float = -1.0
var _votes: Dictionary = {} # server: peer_id -> candidate index
var _sync_timer: float = 0.0

## Round logic for Bomb Defusal.
var bomb: BombRules


func _ready() -> void:
	bomb = BombRules.new()
	bomb.name = "BombRules"
	add_child(bomb)


func _process(delta: float) -> void:
	if state == State.PLAYING and time_limit > 0.0:
		time_left = maxf(time_left - delta, 0.0)
	if not multiplayer.is_server():
		return
	if state == State.PLAYING and time_limit > 0.0 and time_left <= 0.0:
		_end_match(_leader_text(true))
	if state == State.ENDED and _results_timer >= 0.0:
		_results_timer -= delta
		if _results_timer < 0.0:
			_next_map()
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = 1.0
		_broadcast()


# -----------------------------------------------------------------------------
# Setup (server / offline)
# -----------------------------------------------------------------------------

## Chooses the mode and limits for the next match. Pass -1 to keep a default.
func configure(new_mode: GameConfig.Mode, new_score_limit: int = -1, new_time_limit: float = -1.0) -> void:
	mode = new_mode
	var limits: Dictionary = GameConfig.MODE_LIMITS[new_mode]
	score_limit = new_score_limit if new_score_limit >= 0 else limits.score_limit
	time_limit = new_time_limit if new_time_limit >= 0.0 else limits.time_limit


## Server: called by NetworkManager whenever a level finishes loading.
func start_match() -> void:
	state = State.PLAYING
	time_left = time_limit
	team_scores = [0, 0]
	winner_text = ""
	_results_timer = -1.0
	for id: int in NetworkManager.roster:
		NetworkManager.roster[id].kills = 0
		NetworkManager.roster[id].deaths = 0
	_broadcast()
	state_changed.emit()
	if mode == GameConfig.Mode.BOMB:
		bomb.start_match()


## Server: pick a team for a newly joined player (smallest team).
func assign_team(peer_id: int) -> int:
	if not GameConfig.is_team_mode(mode):
		return GameConfig.TEAM_NONE
	var counts := [0, 0]
	for id: int in NetworkManager.roster:
		var t: int = NetworkManager.roster[id].get("team", -1)
		if id != peer_id and t >= 0:
			counts[t] += 1
	return 0 if counts[0] <= counts[1] else 1


# -----------------------------------------------------------------------------
# Queries
# -----------------------------------------------------------------------------

func is_team_mode() -> bool:
	return GameConfig.is_team_mode(mode)


func is_ended() -> bool:
	return state == State.ENDED


## False while the match is over or during Bomb Defusal freeze time.
func can_move() -> bool:
	return not is_ended() and not bomb.is_frozen()


func can_shoot() -> bool:
	return can_move()


func get_team(peer_id: int) -> int:
	return NetworkManager.roster.get(peer_id, {}).get("team", GameConfig.TEAM_NONE)


## True when `a` must not damage `b` (same player, or teammates in team modes).
func is_friendly(a: int, b: int) -> bool:
	if a == b:
		return true
	if not is_team_mode():
		return false
	var ta := get_team(a)
	return ta >= 0 and ta == get_team(b)


## peer_id -> team for the voice relay.
func team_map() -> Dictionary:
	var result := {}
	for id: int in NetworkManager.roster:
		result[id] = get_team(id)
	return result


# -----------------------------------------------------------------------------
# Server: scoring
# -----------------------------------------------------------------------------

## Called by NetworkManager.report_kill() after the roster was updated.
func on_kill(killer_id: int, victim_id: int) -> void:
	if not multiplayer.is_server() or state != State.PLAYING or mode == GameConfig.Mode.PRACTICE:
		return
	if mode == GameConfig.Mode.BOMB:
		var level := NetworkManager.current_level()
		var victim := level.get_player(victim_id) if level else null
		bomb.on_player_down(victim_id, victim.global_position if victim else Vector3.ZERO)
	elif is_team_mode():
		var t := get_team(killer_id)
		if killer_id > 0 and killer_id != victim_id and t >= 0 and t != get_team(victim_id):
			team_scores[t] += 1
			if score_limit > 0 and team_scores[t] >= score_limit:
				_end_match("%s team wins!" % GameConfig.TEAM_NAMES[t])
	elif killer_id > 0 and killer_id != victim_id:
		var kills: int = NetworkManager.roster.get(killer_id, {}).get("kills", 0)
		if score_limit > 0 and kills >= score_limit:
			_end_match("%s wins!" % NetworkManager.get_player_name(killer_id))
	_broadcast()


func _end_match(text: String) -> void:
	state = State.ENDED
	winner_text = text
	_results_timer = results_time
	vote_maps = vote_candidates(NetworkManager.current_map, mode)
	vote_counts = PackedInt32Array()
	vote_counts.resize(vote_maps.size())
	_votes.clear()
	my_vote = -1
	print("[match] Match over: %s" % text)
	_broadcast()
	state_changed.emit()
	match_ended.emit(text)


func _leader_text(time_up: bool) -> String:
	var prefix := "Time's up — " if time_up else ""
	if is_team_mode():
		if team_scores[0] == team_scores[1]:
			return prefix + "Draw!"
		var t := 0 if team_scores[0] > team_scores[1] else 1
		return prefix + "%s team wins!" % GameConfig.TEAM_NAMES[t]
	var best_id := -1
	var best := -1
	var tie := false
	for id: int in NetworkManager.roster:
		var k: int = NetworkManager.roster[id].kills
		if k > best:
			best = k
			best_id = id
			tie = false
		elif k == best:
			tie = true
	if best_id < 0 or tie:
		return prefix + "Draw!"
	return prefix + "%s wins!" % NetworkManager.get_player_name(best_id)


func _next_map() -> void:
	_results_timer = -1.0
	if NetworkManager.is_online():
		NetworkManager.change_map(voted_map())
	else:
		get_tree().reload_current_scene()


## Up to 3 maps for the vote: the next map in the rotation first, then
## random others that support the mode (never the map just played).
static func vote_candidates(current: String, game_mode: int) -> PackedStringArray:
	var result := PackedStringArray([GameConfig.next_map(current, game_mode)])
	var others: Array = GameConfig.MAPS.filter(func(m: Dictionary) -> bool:
		return m.path != current and not m.path in result \
			and (game_mode != GameConfig.Mode.BOMB or m.get("bomb", false)))
	others.shuffle()
	for m: Dictionary in others.slice(0, 2):
		result.append(m.path)
	return result


## The winning map: most votes; ties (and no votes) go to the earliest
## candidate, i.e. the normal rotation.
func voted_map() -> String:
	if vote_maps.is_empty():
		return GameConfig.next_map(NetworkManager.current_map, mode)
	var best := 0
	for i in vote_counts.size():
		if vote_counts[i] > vote_counts[best]:
			best = i
	return vote_maps[best]


## Local player votes for candidate `index` (keys 1–3 on the results screen).
func request_vote(index: int) -> void:
	if not is_ended() or index < 0 or index >= vote_maps.size():
		return
	my_vote = index
	if multiplayer.is_server():
		_set_vote(multiplayer.get_unique_id(), index)
	else:
		_request_vote.rpc_id(1, index)


@rpc("any_peer", "call_remote", "reliable")
func _request_vote(index: int) -> void:
	if multiplayer.is_server():
		_set_vote(multiplayer.get_remote_sender_id(), index)


func _set_vote(peer_id: int, index: int) -> void:
	if not is_ended() or index < 0 or index >= vote_maps.size() or not NetworkManager.roster.has(peer_id):
		return
	_votes[peer_id] = index
	vote_counts = PackedInt32Array()
	vote_counts.resize(vote_maps.size())
	for id: int in _votes:
		vote_counts[_votes[id]] += 1
	_broadcast()
	state_changed.emit()


# -----------------------------------------------------------------------------
# Client requests
# -----------------------------------------------------------------------------

## Local player asks to switch team (TDM). Allowed if it doesn't make the
## teams more than one player apart.
func request_team_switch() -> void:
	if multiplayer.is_server():
		_do_team_switch(multiplayer.get_unique_id())
	else:
		_request_team_switch.rpc_id(1)


## Local player picks the primary weapon for the next respawn.
func request_loadout(primary: String) -> void:
	SettingsManager.preferred_primary = primary
	SettingsManager.save()
	if multiplayer.is_server():
		_set_loadout(multiplayer.get_unique_id(), primary)
	else:
		_request_loadout.rpc_id(1, primary)


@rpc("any_peer", "call_remote", "reliable")
func _request_team_switch() -> void:
	if multiplayer.is_server():
		_do_team_switch(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _request_loadout(primary: String) -> void:
	if multiplayer.is_server():
		_set_loadout(multiplayer.get_remote_sender_id(), primary)


func _do_team_switch(peer_id: int) -> void:
	if not is_team_mode() or not NetworkManager.roster.has(peer_id) or is_ended():
		return
	var current := get_team(peer_id)
	var target := 1 - current
	var counts := [0, 0]
	for id: int in NetworkManager.roster:
		var t := get_team(id)
		if t >= 0:
			counts[t] += 1
	if counts[target] + 1 > counts[current]:
		return # would unbalance the teams
	var level := NetworkManager.current_level()
	var p := level.get_player(peer_id) if level else null
	if mode == GameConfig.Mode.BOMB and p:
		bomb.on_player_down(peer_id, p.global_position) # drops the bomb if carried
	NetworkManager.roster[peer_id].team = target
	NetworkManager.broadcast_roster()
	teams_changed.emit()
	if p:
		if mode == GameConfig.Mode.BOMB and bomb.phase != BombRules.Phase.FREEZE:
			p.health.set_dead_silently() # wait for the next round
		else:
			p.net_sync.server_force_respawn()


## Server: a player disconnected.
func on_player_left(peer_id: int, last_position: Vector3) -> void:
	if mode == GameConfig.Mode.BOMB:
		bomb.on_player_down(peer_id, last_position)


func _set_loadout(peer_id: int, primary: String) -> void:
	if primary in GameConfig.PRIMARY_WEAPONS and NetworkManager.roster.has(peer_id):
		NetworkManager.roster[peer_id].primary = primary


# -----------------------------------------------------------------------------
# Sync
# -----------------------------------------------------------------------------

func send_state_to(peer_id: int) -> void:
	_sync_state.rpc_id(peer_id, mode, state, score_limit, time_limit, time_left, team_scores, winner_text,
		vote_maps, vote_counts)


func _broadcast() -> void:
	if NetworkManager.is_online() and multiplayer.is_server():
		_sync_state.rpc(mode, state, score_limit, time_limit, time_left, team_scores, winner_text,
			vote_maps, vote_counts)


@rpc("authority", "call_remote", "reliable")
func _sync_state(new_mode: int, new_state: int, new_score_limit: int, new_time_limit: float,
		new_time_left: float, scores: PackedInt32Array, winner: String,
		maps: PackedStringArray, counts: PackedInt32Array) -> void:
	var was_ended := state == State.ENDED
	if not was_ended and new_state == State.ENDED:
		my_vote = -1
	vote_maps = maps
	vote_counts = counts
	mode = new_mode as GameConfig.Mode
	state = new_state as State
	score_limit = new_score_limit
	time_limit = new_time_limit
	time_left = new_time_left
	team_scores = scores
	winner_text = winner
	state_changed.emit()
	if state == State.ENDED and not was_ended:
		match_ended.emit(winner)
