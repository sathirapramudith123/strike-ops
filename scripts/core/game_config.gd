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

## Every playable map. "bomb": has bomb sites A and B. "players": suggested
## player count. The map selection screen shows name, style and description.
const MAPS: Array[Dictionary] = [
	{ "id": "test_map", "name": "Test Range", "path": "res://scenes/levels/test_map.tscn", "bomb": true,
		"style": "Training", "players": "1–8",
		"description": "Shooting range with targets, a ramp, stairs and a crouch tunnel. Good for practice." },
	{ "id": "docks", "name": "Docks", "path": "res://scenes/levels/docks.tscn", "bomb": true,
		"style": "Port · 3 lanes", "players": "6–16",
		"description": "Mid runs through the Port Authority warehouse. A in the container yard under a gantry crane, B on the quay beside the ship; A Long is a raised loading platform, B Long the quay." },
	{ "id": "bunker", "name": "Bunker", "path": "res://scenes/levels/bunker.tscn", "bomb": true,
		"style": "Indoor · 3 lanes", "players": "4–12",
		"description": "Underground base: A Long up to a balcony over A, B one level down through the rock tunnel, a reactor hall in Mid." },
	{ "id": "oasis", "name": "Oasis", "path": "res://scenes/levels/oasis.tscn", "bomb": true,
		"style": "Desert town · bomb defusal", "players": "6–16",
		"description": "Sun-baked town: A Long, Mid and the covered B Apartments. A is a raised terrace, B a courtyard around a well." },
	{ "id": "factory", "name": "Factory", "path": "res://scenes/levels/factory.tscn", "bomb": true,
		"style": "Industrial · 3 lanes", "players": "6–16",
		"description": "A under a gantry crane by the silos, B in a walled yard. Warehouse, Mid catwalk, Tunnels, Rail Yard and a roof over A." },
	{ "id": "office", "name": "Office", "path": "res://scenes/levels/office.tscn", "bomb": true,
		"style": "Indoor · two floors", "players": "4–12",
		"description": "Office block: lobby and reception, open-plan office (A), server room (B), a mezzanine with two stairs." },
	{ "id": "subway", "name": "Subway", "path": "res://scenes/levels/subway.tscn", "bomb": true,
		"style": "Underground · 3 lanes", "players": "6–16",
		"description": "Riverside station: A Long, Mid and B Long platforms with trains parked between them to walk through. A and B beside terminating trains." },
	{ "id": "trainyard", "name": "Train Yard", "path": "res://scenes/levels/trainyard.tscn", "bomb": true,
		"style": "Outdoor · 3 lanes", "players": "6–16",
		"description": "Trains parked in Mid under a gantry crane. A inside a warehouse off the loading dock, B in a lower yard down the rail cut." },
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
	"lmg": "res://scenes/weapons/lmg.tscn",
	"pistol": "res://scenes/weapons/pistol.tscn",
	"knife": "res://scenes/weapons/knife.tscn",
}
const PRIMARY_WEAPONS: PackedStringArray = ["rifle", "smg", "shotgun", "sniper", "lmg"]
const PRIMARY_NAMES := {
	"rifle": "AR-7 Assault Rifle", "smg": "V-10 SMG", "shotgun": "M-12 Shotgun", "sniper": "LR-50 Sniper",
	"lmg": "K-100 LMG",
}
const SECONDARY_WEAPON := "pistol"
## Slot 3 for everyone.
const MELEE_WEAPON := "knife"
const DEFAULT_PRIMARY := "rifle"


## Old map ids that were renamed (saved settings, server command lines).
const RENAMED := { "kasbah": "oasis" }


static func map_index(path: String) -> int:
	var key := path.get_file().get_basename() if path.begins_with("res://") else path
	if RENAMED.has(key):
		path = RENAMED[key]
	for i in MAPS.size():
		if MAPS[i].path == path or MAPS[i].id == path:
			return i
	return -1


static func map_path(id_or_path: String) -> String:
	var i := map_index(id_or_path)
	return MAPS[i].path if i >= 0 else id_or_path


static func map_info(id_or_path: String) -> Dictionary:
	var i := map_index(id_or_path)
	return MAPS[i] if i >= 0 else {}


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
