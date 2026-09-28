class_name Health
extends Node
## Reusable health component. Add as a child of anything that can take damage
## (players, target dummies, destructible props) and point Hitboxes at it.
##
## Networking: only the server changes health. After every change it pushes the
## new state to all ready clients, which replay the same signals locally.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source: Node, is_headshot: bool)
signal died(source: Node)
signal revived
signal armor_changed(armor: float)

const NET_GROUP := &"net_health"

@export var max_health: float = 100.0
## Seconds without damage before regeneration starts (0 = no regen).
@export var regen_delay: float = 0.0
@export var regen_per_second: float = 0.0
## Players get armour (Bomb Defusal only, full at each round start). While
## there is armour, it takes ARMOR_ABSORB of every weapon hit and loses that
## much; the rest hurts. Falls and the bomb ignore armour.
@export var uses_armor: bool = false
const MAX_ARMOR := 100.0
## Share of a hit the armour soaks when the attacker gives no penetration
## (weapons pass their own `armor_penetration`: absorbed = 1 - penetration).
const ARMOR_ABSORB := 0.4

var current: float
var armor: float = 0.0
var is_dead: bool = false
## Whether the most recent hit was a headshot (used for kill feed).
var last_hit_headshot: bool = false
## What caused the last damage when there was no attacker ("Fall", "Bomb").
var last_cause: String = ""
## True when the last death was administrative (late join / team switch in
## Bomb Defusal) — no kill feed, no death counted.
var silent_death: bool = false

var _time_since_damage: float = 0.0
var _protected_until: float = 0.0
var _regen_sync_timer: float = 0.0


func _ready() -> void:
	current = max_health
	# Same rule on every peer, so players who spawn mid-freeze have armour too.
	if uses_armor and Match.mode == GameConfig.Mode.BOMB:
		armor = MAX_ARMOR
	add_to_group(NET_GROUP)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if is_dead or regen_per_second <= 0.0 or current >= max_health:
		return
	_time_since_damage += delta
	if _time_since_damage >= regen_delay:
		current = minf(current + regen_per_second * delta, max_health)
		health_changed.emit(current, max_health)
		# Regen is continuous — sync it a few times per second, not every frame.
		_regen_sync_timer -= delta
		if _regen_sync_timer <= 0.0 or current >= max_health:
			_regen_sync_timer = 0.25
			_broadcast(0.0)


## Server only. Returns true if this hit killed the owner.
func take_damage(amount: float, source: Node = null, is_headshot: bool = false, cause: String = "",
		armor_penetration: float = -1.0, armored: bool = true) -> bool:
	if not multiplayer.is_server() or is_dead or amount <= 0.0:
		return false
	# Spawn protection (fall damage still applies so nobody gets stuck).
	if is_protected() and source != null:
		return false
	_time_since_damage = 0.0
	last_hit_headshot = is_headshot
	last_cause = cause
	silent_death = false
	var hurt := amount
	if armor > 0.0 and source != null and armored:
		var soak := ARMOR_ABSORB if armor_penetration < 0.0 else 1.0 - clampf(armor_penetration, 0.0, 1.0)
		var absorbed := minf(amount * soak, armor)
		armor -= absorbed
		hurt = amount - absorbed
	current = maxf(current - hurt, 0.0)
	var killed := current <= 0.0
	if killed:
		is_dead = true
	_broadcast(hurt, is_headshot)
	damaged.emit(hurt, source, is_headshot)
	health_changed.emit(current, max_health)
	armor_changed.emit(armor)
	if killed:
		died.emit(source)
	return killed


## Server only.
func heal(amount: float) -> void:
	if not multiplayer.is_server() or is_dead:
		return
	current = minf(current + amount, max_health)
	_broadcast(0.0)
	health_changed.emit(current, max_health)


## Server only.
func revive() -> void:
	if not multiplayer.is_server():
		return
	is_dead = false
	current = max_health
	armor = MAX_ARMOR if uses_armor and Match.mode == GameConfig.Mode.BOMB else 0.0
	_time_since_damage = 0.0
	_broadcast(0.0)
	health_changed.emit(current, max_health)
	armor_changed.emit(armor)
	revived.emit()


## Server only: mark as dead without a kill (joined mid-round, switched team).
func set_dead_silently() -> void:
	if not multiplayer.is_server() or is_dead:
		return
	silent_death = true
	is_dead = true
	current = 0.0
	_broadcast(0.0)
	health_changed.emit(current, max_health)
	died.emit(null)


## Server only: ignore damage from other players for `seconds`.
func protect(seconds: float) -> void:
	_protected_until = Time.get_ticks_msec() / 1000.0 + seconds


func is_protected() -> bool:
	return Time.get_ticks_msec() / 1000.0 < _protected_until


## Server only: sends the current state to one peer (late joiners).
func send_state_to(peer_id: int) -> void:
	if is_inside_tree():
		_net_sync.rpc_id(peer_id, current, is_dead, 0.0, false, armor)


func _broadcast(damage_amount: float, is_headshot: bool = false) -> void:
	NetworkManager.send_to_ready(self, &"_net_sync", [current, is_dead, damage_amount, is_headshot, armor])


@rpc("authority", "call_remote", "reliable")
func _net_sync(new_current: float, new_dead: bool, damage_amount: float, is_headshot: bool, new_armor: float = 0.0) -> void:
	var was_dead := is_dead
	current = new_current
	if new_armor != armor:
		armor = new_armor
		armor_changed.emit(armor)
	is_dead = new_dead
	last_hit_headshot = is_headshot
	if damage_amount > 0.0:
		damaged.emit(damage_amount, null, is_headshot)
	health_changed.emit(current, max_health)
	if is_dead and not was_dead:
		died.emit(null)
	elif was_dead and not is_dead:
		revived.emit()
