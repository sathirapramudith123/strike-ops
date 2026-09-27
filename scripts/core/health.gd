class_name Health
extends Node
## Reusable health component. Add as a child of anything that can take damage
## (players, target dummies, destructible props) and point Hitboxes at it.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source: Node, is_headshot: bool)
signal died(source: Node)
signal revived

@export var max_health: float = 100.0
## Seconds without damage before regeneration starts (0 = no regen).
@export var regen_delay: float = 0.0
@export var regen_per_second: float = 0.0

var current: float
var is_dead: bool = false

var _time_since_damage: float = 0.0


func _ready() -> void:
	current = max_health


func _process(delta: float) -> void:
	if is_dead or regen_per_second <= 0.0 or current >= max_health:
		return
	_time_since_damage += delta
	if _time_since_damage >= regen_delay:
		heal(regen_per_second * delta)


## Returns true if this hit killed the owner.
func take_damage(amount: float, source: Node = null, is_headshot: bool = false) -> bool:
	if is_dead or amount <= 0.0:
		return false
	_time_since_damage = 0.0
	current = maxf(current - amount, 0.0)
	damaged.emit(amount, source, is_headshot)
	health_changed.emit(current, max_health)
	if current <= 0.0:
		is_dead = true
		died.emit(source)
		return true
	return false


func heal(amount: float) -> void:
	if is_dead:
		return
	current = minf(current + amount, max_health)
	health_changed.emit(current, max_health)


func revive() -> void:
	is_dead = false
	current = max_health
	_time_since_damage = 0.0
	health_changed.emit(current, max_health)
	revived.emit()
