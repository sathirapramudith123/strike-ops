class_name Hitbox
extends StaticBody3D
## A damageable collision region (body, head, limbs) that forwards hits to a Health node.
## Put hitboxes on the "hitbox" physics layer (layer 3) so weapon raycasts find them.

@export var health: Health
## Damage multiplier for this region (e.g. 2.0 for the head).
@export var damage_multiplier: float = 1.0
@export var is_head: bool = false


func _ready() -> void:
	collision_layer = 1 << 2 # "hitbox"
	collision_mask = 0


## Returns true if this hit killed the owner.
func apply_hit(base_damage: float, source: Node) -> bool:
	if health == null:
		return false
	return health.take_damage(base_damage * damage_multiplier, source, is_head)
