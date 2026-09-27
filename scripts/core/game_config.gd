class_name GameConfig
extends RefCounted
## Static catalogue of maps, game modes and weapons. Add new content here.

enum Mode { PRACTICE, FFA, TDM, BOMB }

const MODE_NAMES := {
	Mode.PRACTICE: "Practice",
	Mode.FFA: "Free-for-All",
	Mode.TDM: "Team Deathmatch",
	Mode.BOMB: "Bomb Defusal",
}
const MODE_IDS := { "practice": Mode.PRACTICE, "ffa": Mode.FFA, "tdm": Mode.TDM, "bomb": Mode.BOMB }

## Defaults per mode: score limit (kills — or round wins for BOMB),
## time limit (seconds, 0 = none; BOMB uses per-round timers instead).
const MODE_LIMITS := {
	Mode.PRACTICE: { "score_limit": 0, "time_limit": 0.0 },
	Mode.FFA: { "score_limit": 20, "time_limit": 600.0 },
	Mode.TDM: { "score_limit": 50, "time_limit": 600.0 },
	Mode.BOMB: { "score_limit": 5, "time_limit": 0.0 },
}

const MAPS: Array[Dictionary] = [
	# "bomb": the map has bomb sites A and B (playable in Bomb Defusal).
	{ "id": "test_map", "name": "Test Range", "path": "res://scenes/levels/test_map.tscn", "bomb": true },
	{ "id": "warehouse", "name": "Warehouse", "path": "res://scenes/levels/warehouse.tscn", "bomb": true },
	{ "id": "courtyard", "name": "Courtyard", "path": "res://scenes/levels/courtyard.tscn", "bomb": true },
]

const TEAM_NONE := -1
const TEAM_NAMES: PackedStringArray = ["Blue", "Red"]
const TEAM_COLORS: Array[Color] = [Color(0.25, 0.5, 0.95), Color(0.92, 0.3, 0.25)]
const FFA_COLOR := Color(0.85, 0.55, 0.2)

## Weapon ids → viewmodel scene. Every player has all of them as children of
## WeaponHolder (so node paths match on every peer); the loadout decides
## which ones are usable.
const WEAPONS := {
	"rifle": "res://scenes/weapons/assault_rifle.tscn",
	"smg": "res://scenes/weapons/smg.tscn",
	"shotgun": "res://scenes/weapons/shotgun.tscn",
	"sniper": "res://scenes/weapons/sniper.tscn",
	"pistol": "res://scenes/weapons/pistol.tscn",
}
const PRIMARY_WEAPONS: PackedStringArray = ["rifle", "smg", "shotgun", "sniper"]
const PRIMARY_NAMES := {
	"rifle": "AR-7 Assault Rifle", "smg": "V-10 SMG", "shotgun": "M-12 Shotgun", "sniper": "LR-50 Sniper",
}
const SECONDARY_WEAPON := "pistol"
const DEFAULT_PRIMARY := "rifle"


static func map_index(path: String) -> int:
	for i in MAPS.size():
		if MAPS[i].path == path or MAPS[i].id == path:
			return i
	return -1


static func map_path(id_or_path: String) -> String:
	var i := map_index(id_or_path)
	return MAPS[i].path if i >= 0 else id_or_path


static func map_name(path: String) -> String:
	var i := map_index(path)
	return MAPS[i].name if i >= 0 else path.get_file().get_basename()


## Next map in the rotation that supports `mode`.
static func next_map(path: String, mode: Mode = Mode.FFA) -> String:
	var i := map_index(path)
	for step in range(1, MAPS.size() + 1):
		var m: Dictionary = MAPS[(i + step) % MAPS.size()]
		if mode != Mode.BOMB or m.get("bomb", false):
			return m.path
	return path


static func is_team_mode(mode: Mode) -> bool:
	return mode == Mode.TDM or mode == Mode.BOMB


static func team_color(team: int) -> Color:
	return TEAM_COLORS[team] if team >= 0 and team < TEAM_COLORS.size() else FFA_COLOR
