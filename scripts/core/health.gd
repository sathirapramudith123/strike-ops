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

const NET_GROUP := &"net_health"

@export var max_health: float = 100.0
## Seconds without damage before regeneration starts (0 = no regen).
@export var regen_delay: float = 0.0
@export var regen_per_second: float = 0.0

var current: float
var is_dead: bool = false
## Whether the most recent hit was a headshot (used for kill feed).
var last_hit_headshot: bool = false

var _time_since_damage: float = 0.0
var _regen_sync_timer: float = 0.0


func _ready() -> void:
	current = max_health
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
func take_damage(amount: float, source: Node = null, is_headshot: bool = false) -> bool:
	if not multiplayer.is_server() or is_dead or amount <= 0.0:
		return false
	_time_since_damage = 0.0
	last_hit_headshot = is_headshot
	current = maxf(current - amount, 0.0)
	var killed := current <= 0.0
	if killed:
		is_dead = true
	_broadcast(amount, is_headshot)
	damaged.emit(amount, source, is_headshot)
	health_changed.emit(current, max_health)
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
	_time_since_damage = 0.0
	_broadcast(0.0)
	health_changed.emit(current, max_health)
	revived.emit()


## Server only: sends the current state to one peer (late joiners).
func send_state_to(peer_id: int) -> void:
	if is_inside_tree():
		_net_sync.rpc_id(peer_id, current, is_dead, 0.0, false)


func _broadcast(damage_amount: float, is_headshot: bool = false) -> void:
	NetworkManager.send_to_ready(self, &"_net_sync", [current, is_dead, damage_amount, is_headshot])


@rpc("authority", "call_remote", "reliable")
func _net_sync(new_current: float, new_dead: bool, damage_amount: float, is_headshot: bool) -> void:
	var was_dead := is_dead
	current = new_current
	is_dead = new_dead
	last_hit_headshot = is_headshot
	if damage_amount > 0.0:
		damaged.emit(damage_amount, null, is_headshot)
	health_changed.emit(current, max_health)
	if is_dead and not was_dead:
		died.emit(null)
	elif was_dead and not is_dead:
		revived.emit()
