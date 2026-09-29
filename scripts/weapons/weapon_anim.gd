class_name WeaponAnim
extends RefCounted
## First-person animation profiles: one base system (Weapon._update_viewmodel)
## for every gun, with different values per weapon — the "same system, every
## gun, unique feel" sheet:
##
##   idle sway (breathing), walk / run bob, how the gun lags behind the
##   mouse, the equip raise, fire kick (back, up, rotation) and how fast it
##   recovers, the bolt / pump cycle after each shot, reload tilt and the
##   sounds along the reload, how quickly the hands move, and the inspect.
##
## tilt: degrees the gun rolls towards you to reload (4 pistol … 10 sniper).
## hands: hand speed (1 = rifle; the LMG's hands are slow and heavy).
## cycle: "" / "bolt" (sniper: the right hand works the bolt after each
## shot) / "pump" (shotgun: the left hand racks the pump).
## reload_cues: [progress, sound] along a magazine reload.
## inspect: "rotate", "mag_check", "check", "shells", "scope", "belt", "flip".

const PROFILES := {
	"pistol": { "tilt": 4.0, "hands": 1.35, "sway": 0.6, "bob": 0.9, "lag": 0.8, "equip": 0.35,
		"kick_back": 0.035, "kick_up": 0.02, "kick_rot": 0.14, "kick_roll": 0.05, "recover": 16.0, "cycle": "",
		"reload_cues": [[0.0, "mag_out"], [0.5, "mag_in"], [0.82, "bolt"]], "inspect": "rotate" },
	"smg": { "tilt": 5.0, "hands": 1.3, "sway": 0.7, "bob": 0.95, "lag": 0.9, "equip": 0.4,
		"kick_back": 0.03, "kick_up": 0.008, "kick_rot": 0.05, "kick_roll": 0.04, "recover": 18.0, "cycle": "",
		"reload_cues": [[0.0, "mag_out"], [0.55, "mag_in"], [0.85, "bolt"]], "inspect": "mag_check" },
	"rifle": { "tilt": 6.0, "hands": 1.0, "sway": 0.8, "bob": 1.0, "lag": 1.0, "equip": 0.55,
		"kick_back": 0.06, "kick_up": 0.01, "kick_rot": 0.08, "kick_roll": 0.05, "recover": 12.0, "cycle": "",
		"reload_cues": [[0.0, "mag_out"], [0.55, "mag_in"], [0.85, "bolt"]], "inspect": "check" },
	"shotgun": { "tilt": 8.0, "hands": 0.85, "sway": 0.9, "bob": 1.1, "lag": 1.15, "equip": 0.6,
		"kick_back": 0.12, "kick_up": 0.03, "kick_rot": 0.22, "kick_roll": 0.08, "recover": 7.0, "cycle": "pump",
		"reload_cues": [], "inspect": "shells" },
	"sniper": { "tilt": 10.0, "hands": 0.75, "sway": 0.45, "bob": 0.8, "lag": 1.2, "equip": 0.75,
		"kick_back": 0.14, "kick_up": 0.035, "kick_rot": 0.26, "kick_roll": 0.06, "recover": 6.0, "cycle": "bolt",
		"reload_cues": [[0.0, "mag_out"], [0.5, "mag_in"], [0.8, "bolt"]], "inspect": "scope" },
	"lmg": { "tilt": 7.0, "hands": 0.6, "sway": 1.25, "bob": 1.4, "lag": 1.45, "equip": 0.95,
		"kick_back": 0.05, "kick_up": 0.012, "kick_rot": 0.06, "kick_roll": 0.06, "recover": 10.0, "cycle": "",
		"reload_cues": [[0.1, "cover_open"], [0.3, "mag_out"], [0.6, "mag_in"], [0.72, "cover_close"],
			[0.88, "bolt"]], "inspect": "belt" },
	"knife": { "tilt": 0.0, "hands": 1.5, "sway": 0.5, "bob": 0.85, "lag": 0.7, "equip": 0.25,
		"kick_back": 0.0, "kick_up": 0.0, "kick_rot": 0.0, "kick_roll": 0.0, "recover": 12.0, "cycle": "",
		"reload_cues": [], "inspect": "flip" },
}


static func profile(weapon_id: String) -> Dictionary:
	return PROFILES.get(weapon_id, PROFILES.rifle)


## Seconds the bolt / pump takes after a shot (inside the fire interval).
static func cycle_time(data: WeaponData) -> float:
	return minf(60.0 / maxf(data.fire_rate, 1.0) * 0.85, 0.75)
