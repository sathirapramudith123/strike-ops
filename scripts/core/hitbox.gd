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


## Where a bullet lands on a player's body and how much that changes the
## damage (the head uses the weapon's own headshot multiplier instead).
## Armour covers head, chest and stomach — not the legs.
const ZONE_MULTIPLIERS := { &"head": 1.0, &"chest": 1.0, &"stomach": 1.25, &"legs": 0.75 }
const ARMORED_ZONES: Array[StringName] = [&"head", &"chest", &"stomach"]


## Returns true if this hit killed the owner. `armor_penetration` < 0 uses
## the default; `armored` = false for hits armour doesn't cover (legs).
func apply_hit(base_damage: float, source: Node, armor_penetration: float = -1.0, armored: bool = true) -> bool:
	if health == null:
		return false
	return health.take_damage(base_damage * damage_multiplier, source, is_head, "", armor_penetration, armored)


## Body zone of a hit at world height `hit_y` on a player standing on
## `feet_y` who is `height` tall (for this body hitbox; the head hitbox is
## always "head"). Legs below half the height, stomach up to ~2/3, chest above.
static func zone_at(hit_y: float, feet_y: float, height: float) -> StringName:
	var f := (hit_y - feet_y) / maxf(height, 0.1)
	if f < 0.5:
		return &"legs"
	if f < 0.65:
		return &"stomach"
	return &"chest"
