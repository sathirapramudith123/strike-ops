class_name WeaponData
extends Resource
## All tunable stats of one weapon. Stored as .tres in res://resources/weapons/.

@export var display_name: String = "Weapon"
## Key in GameConfig.WEAPONS.
@export var weapon_id: String = ""

@export_group("Firing")
@export var automatic: bool = true
## Fire modes B cycles through ("auto", "burst", "semi"); empty = only the
## mode `automatic` gives. The first one is the default.
@export var fire_modes: PackedStringArray = []
## Shots per trigger pull in "burst" mode.
@export var burst_count: int = 3
## Melee weapon (knife): no ammo, no spread, no aiming, short reach.
@export var melee: bool = false
## Rounds per minute.
@export var fire_rate: float = 600.0
## Damage per pellet.
@export var damage: float = 25.0
## Projectiles per shot (shotguns > 1). All pellets are sent in one packet.
@export_range(1, 16) var pellets: int = 1
@export var headshot_multiplier: float = 2.0
@export var max_range: float = 150.0
## Damage starts dropping after this distance…
@export var falloff_start: float = 30.0
## …down to damage * this at max_range.
@export_range(0.1, 1.0, 0.05) var min_damage_multiplier: float = 0.6
## Share of the damage that goes straight through armour (the rest is
## soaked up by the armour). High for rifles and snipers, low for pistols
## and shotguns — as in CS.
@export_range(0.0, 1.0, 0.05) var armor_penetration: float = 0.75

@export_group("Ammo")
@export var magazine_size: int = 30
@export var starting_reserve: int = 120
@export var reload_time: float = 2.0
## Shotgun: load one shell at a time (reload_start, then shell_time per
## shell, then reload_end to pump); firing stops the reload with what is in.
@export var shell_reload: bool = false
@export var shell_time: float = 0.45
@export var reload_start: float = 0.3
@export var reload_end: float = 0.4

@export_group("Handling")
## Walking speed while this weapon is out (heavy guns are slower).
@export_range(0.5, 1.0, 0.01) var move_speed_multiplier: float = 1.0

@export_group("Accuracy (degrees)")
@export var hip_spread: float = 2.5
@export var ads_spread: float = 0.3
@export var spread_per_shot: float = 0.35
@export var max_bloom: float = 3.0
@export var bloom_recovery: float = 6.0
@export var moving_spread: float = 1.5
@export var air_spread: float = 4.0

@export_group("Recoil (degrees)")
@export var recoil_pitch: float = 1.2
@export var recoil_yaw: float = 0.4
@export var ads_recoil_multiplier: float = 0.65

@export_group("Aim down sights")
@export var ads_time: float = 0.18
## Camera FOV multiplier while aiming (0.8 = 20% zoom).
@export_range(0.15, 1.0, 0.05) var ads_fov_multiplier: float = 0.8
@export_range(0.1, 1.0, 0.05) var ads_sensitivity_multiplier: float = 0.7
@export_range(0.1, 1.0, 0.05) var ads_move_speed_multiplier: float = 0.6
## Sniper scope: hides the viewmodel and shows a scope overlay while aiming.
@export var scoped: bool = false
## Extra zoom steps (FOV multipliers) the mouse wheel steps through while
## scoped; ads_fov_multiplier is the first step.
@export var zoom_levels: PackedFloat32Array = []
