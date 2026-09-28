class_name CharacterLook
extends RefCounted
## A player's appearance (Character screen in the main menu): body, face,
## eyes, mouth, ears, voice, outfit and each kit piece. Stored in the
## settings as a Dictionary, sent over the network as a small Array[int]
## (pack / unpack; the server sanitizes it into the roster "look"), built
## into meshes by CharacterMesh. Bots get a random look.
##
## Every option is an index into the lists below; picking an outfit in the
## editor also sets its kit pieces (OUTFITS[i].kit), which can then be
## changed one by one.

const KEYS: PackedStringArray = ["body", "face", "eyes", "mouth", "ears", "voice", "outfit",
	"headwear", "torso", "backpack", "gloves", "pants", "boots"]
const LABELS := {
	"body": "Body", "face": "Face", "eyes": "Eyes", "mouth": "Mouth", "ears": "Ears", "voice": "Voice",
	"outfit": "Outfit", "headwear": "Headwear", "torso": "Torso / armour", "backpack": "Backpack",
	"gloves": "Gloves", "pants": "Pants", "boots": "Boots",
}

const BODIES: PackedStringArray = ["Male", "Female"]

## Faces: skin tone, hair colour, hair style (see CharacterMesh), beard
## (0 none, 1 stubble, 2 full, 3 moustache).
const MALE_FACES: Array[Dictionary] = [
	{ "name": "Cole", "skin": Color(0.80, 0.62, 0.50), "hair": Color(0.12, 0.09, 0.07), "style": 1, "beard": 1 },
	{ "name": "Mason", "skin": Color(0.84, 0.67, 0.55), "hair": Color(0.25, 0.17, 0.10), "style": 2, "beard": 0 },
	{ "name": "Rico", "skin": Color(0.66, 0.48, 0.36), "hair": Color(0.08, 0.06, 0.05), "style": 3, "beard": 2 },
	{ "name": "Nuwan", "skin": Color(0.55, 0.38, 0.27), "hair": Color(0.06, 0.05, 0.05), "style": 1, "beard": 3 },
	{ "name": "Viktor", "skin": Color(0.86, 0.70, 0.60), "hair": Color(0.45, 0.38, 0.30), "style": 0, "beard": 2 },
	{ "name": "Kofi", "skin": Color(0.36, 0.24, 0.17), "hair": Color(0.05, 0.04, 0.04), "style": 0, "beard": 1 },
	{ "name": "Diego", "skin": Color(0.72, 0.53, 0.40), "hair": Color(0.10, 0.07, 0.05), "style": 4, "beard": 1 },
	{ "name": "Hiro", "skin": Color(0.82, 0.66, 0.52), "hair": Color(0.04, 0.04, 0.05), "style": 2, "beard": 0 },
]
const FEMALE_FACES: Array[Dictionary] = [
	{ "name": "Ava", "skin": Color(0.82, 0.64, 0.53), "hair": Color(0.14, 0.10, 0.07), "style": 5, "beard": 0 },
	{ "name": "Freya", "skin": Color(0.88, 0.73, 0.63), "hair": Color(0.78, 0.66, 0.44), "style": 7, "beard": 0 },
	{ "name": "Mira", "skin": Color(0.62, 0.45, 0.34), "hair": Color(0.05, 0.04, 0.04), "style": 6, "beard": 0 },
	{ "name": "Rose", "skin": Color(0.87, 0.70, 0.60), "hair": Color(0.55, 0.20, 0.10), "style": 8, "beard": 0 },
	{ "name": "Nimali", "skin": Color(0.56, 0.39, 0.28), "hair": Color(0.06, 0.05, 0.05), "style": 5, "beard": 0 },
	{ "name": "Lena", "skin": Color(0.80, 0.63, 0.52), "hair": Color(0.32, 0.22, 0.14), "style": 9, "beard": 0 },
	{ "name": "Yuki", "skin": Color(0.84, 0.69, 0.57), "hair": Color(0.03, 0.03, 0.04), "style": 7, "beard": 0 },
]

const EYES: Array[Dictionary] = [
	{ "name": "Brown", "color": Color(0.36, 0.2, 0.1) },
	{ "name": "Blue", "color": Color(0.2, 0.45, 0.8) },
	{ "name": "Green", "color": Color(0.3, 0.55, 0.25) },
	{ "name": "Hazel", "color": Color(0.5, 0.4, 0.18) },
	{ "name": "Grey", "color": Color(0.5, 0.56, 0.6) },
	{ "name": "Amber", "color": Color(0.7, 0.45, 0.12) },
	{ "name": "Teal", "color": Color(0.1, 0.6, 0.62) },
	{ "name": "Violet", "color": Color(0.5, 0.35, 0.8) },
	{ "name": "Dark", "color": Color(0.12, 0.07, 0.05) },
]
const MOUTHS: PackedStringArray = ["Normal", "Smirk", "Grim", "Open (talk)", "Shout", "Clench", "Neutral", "Smile"]
const EARS: PackedStringArray = ["Small", "Standard", "Large", "Pointed", "Rounded", "Folded", "Scarred", "Earring"]

## Voice: pitch of the grunts and cries (pain, death) — times the body's
## base pitch — and whether it is the rough variant.
const VOICES: Array[Dictionary] = [
	{ "name": "Normal", "pitch": 1.0, "rough": false },
	{ "name": "Deep", "pitch": 0.8, "rough": false },
	{ "name": "Rough", "pitch": 0.92, "rough": true },
	{ "name": "Calm", "pitch": 0.96, "rough": false },
	{ "name": "High", "pitch": 1.22, "rough": false },
	{ "name": "Soft", "pitch": 1.1, "rough": false },
	{ "name": "Angry", "pitch": 1.05, "rough": true },
	{ "name": "Young", "pitch": 1.32, "rough": false },
]
const FEMALE_PITCH := 1.55

## Outfits: the shirt (colour + camouflage pattern, see model.gdshader) and
## the kit pieces they come with.
const OUTFITS: Array[Dictionary] = [
	{ "name": "Tactical", "shirt": Color(0.13, 0.13, 0.13), "pattern": 0,
		"kit": { "headwear": 7, "torso": 0, "backpack": 1, "gloves": 0, "pants": 0, "boots": 0 } },
	{ "name": "Military", "shirt": Color(0.34, 0.36, 0.24), "pattern": 5,
		"kit": { "headwear": 2, "torso": 1, "backpack": 2, "gloves": 2, "pants": 1, "boots": 1 } },
	{ "name": "Urban", "shirt": Color(0.36, 0.37, 0.39), "pattern": 0,
		"kit": { "headwear": 1, "torso": 5, "backpack": 3, "gloves": 3, "pants": 5, "boots": 5 } },
	{ "name": "Desert", "shirt": Color(0.62, 0.52, 0.36), "pattern": 2,
		"kit": { "headwear": 3, "torso": 3, "backpack": 4, "gloves": 1, "pants": 4, "boots": 2 } },
	{ "name": "Winter", "shirt": Color(0.86, 0.87, 0.88), "pattern": 4,
		"kit": { "headwear": 4, "torso": 6, "backpack": 6, "gloves": 5, "pants": 6, "boots": 4 } },
	{ "name": "Stealth", "shirt": Color(0.07, 0.07, 0.08), "pattern": 0,
		"kit": { "headwear": 5, "torso": 0, "backpack": 0, "gloves": 0, "pants": 0, "boots": 3 } },
	{ "name": "Casual", "shirt": Color(0.55, 0.56, 0.58), "pattern": 0,
		"kit": { "headwear": 0, "torso": 2, "backpack": 5, "gloves": 3, "pants": 3, "boots": 5 } },
]

const HEADWEAR: PackedStringArray = ["None", "Cap", "Helmet", "Boonie hat", "Beanie", "Balaclava", "Headset",
	"Tactical helmet"]
## Torso: vest style (0 plate carrier, 1 chest rig, 2 light vest, 3 heavy
## armour), colour, pattern.
const TORSO: Array[Dictionary] = [
	{ "name": "Black plate carrier", "style": 0, "color": Color(0.1, 0.1, 0.1), "pattern": 0 },
	{ "name": "Woodland chest rig", "style": 1, "color": Color(0.3, 0.33, 0.2), "pattern": 1 },
	{ "name": "Light vest", "style": 2, "color": Color(0.24, 0.26, 0.2), "pattern": 0 },
	{ "name": "Coyote heavy armour", "style": 3, "color": Color(0.5, 0.41, 0.28), "pattern": 0 },
	{ "name": "Ranger carrier", "style": 0, "color": Color(0.26, 0.3, 0.2), "pattern": 0 },
	{ "name": "Urban carrier", "style": 0, "color": Color(0.3, 0.31, 0.33), "pattern": 3 },
	{ "name": "Winter carrier", "style": 0, "color": Color(0.82, 0.83, 0.85), "pattern": 4 },
]
const BACKPACKS: Array[Dictionary] = [
	{ "name": "None", "style": 0, "color": Color.BLACK, "pattern": 0 },
	{ "name": "Assault pack", "style": 1, "color": Color(0.1, 0.1, 0.1), "pattern": 0 },
	{ "name": "Woodland ruck", "style": 2, "color": Color(0.3, 0.33, 0.2), "pattern": 1 },
	{ "name": "Black daypack", "style": 1, "color": Color(0.16, 0.16, 0.17), "pattern": 0 },
	{ "name": "Desert ruck", "style": 2, "color": Color(0.58, 0.48, 0.32), "pattern": 2 },
	{ "name": "Sling bag", "style": 3, "color": Color(0.22, 0.22, 0.24), "pattern": 0 },
	{ "name": "Winter pack", "style": 1, "color": Color(0.82, 0.83, 0.85), "pattern": 4 },
]
## Gloves (fingerless: skin fingers).
const GLOVES: Array[Dictionary] = [
	{ "name": "Black tactical", "color": Color(0.08, 0.08, 0.08), "fingerless": false },
	{ "name": "Tan", "color": Color(0.55, 0.45, 0.3), "fingerless": false },
	{ "name": "Olive", "color": Color(0.28, 0.3, 0.2), "fingerless": false },
	{ "name": "Fingerless", "color": Color(0.1, 0.1, 0.1), "fingerless": true },
	{ "name": "Leather", "color": Color(0.3, 0.18, 0.1), "fingerless": false },
	{ "name": "Grey knuckle", "color": Color(0.5, 0.51, 0.52), "fingerless": false },
	{ "name": "None", "color": Color(-1, 0, 0), "fingerless": true },
]
const PANTS: Array[Dictionary] = [
	{ "name": "Black cargo", "color": Color(0.1, 0.1, 0.11), "pattern": 0 },
	{ "name": "Woodland", "color": Color(0.3, 0.33, 0.21), "pattern": 1 },
	{ "name": "Khaki", "color": Color(0.58, 0.5, 0.36), "pattern": 0 },
	{ "name": "Jeans", "color": Color(0.16, 0.22, 0.34), "pattern": 0 },
	{ "name": "Desert camo", "color": Color(0.6, 0.5, 0.33), "pattern": 2 },
	{ "name": "Urban camo", "color": Color(0.33, 0.34, 0.36), "pattern": 3 },
	{ "name": "Winter camo", "color": Color(0.84, 0.85, 0.87), "pattern": 4 },
]
const BOOTS: Array[Dictionary] = [
	{ "name": "Black combat", "color": Color(0.07, 0.07, 0.07), "tall": false },
	{ "name": "Brown", "color": Color(0.3, 0.19, 0.1), "tall": false },
	{ "name": "Desert tan", "color": Color(0.55, 0.44, 0.28), "tall": false },
	{ "name": "Black tall", "color": Color(0.06, 0.06, 0.06), "tall": true },
	{ "name": "Winter white", "color": Color(0.8, 0.81, 0.82), "tall": true },
	{ "name": "Grey trainers", "color": Color(0.45, 0.46, 0.48), "tall": false },
]


static func default_look() -> Dictionary:
	var look := { "body": 0, "face": 0, "eyes": 0, "mouth": 0, "ears": 1, "voice": 0, "outfit": 0 }
	look.merge(OUTFITS[0].kit)
	return look


## Number of choices for `key` (faces depend on the body).
static func count(key: String, look: Dictionary = {}) -> int:
	match key:
		"body": return BODIES.size()
		"face": return (FEMALE_FACES if int(look.get("body", 0)) == 1 else MALE_FACES).size()
		"eyes": return EYES.size()
		"mouth": return MOUTHS.size()
		"ears": return EARS.size()
		"voice": return VOICES.size()
		"outfit": return OUTFITS.size()
		"headwear": return HEADWEAR.size()
		"torso": return TORSO.size()
		"backpack": return BACKPACKS.size()
		"gloves": return GLOVES.size()
		"pants": return PANTS.size()
		"boots": return BOOTS.size()
	return 1


## Name of choice `i` for `key`.
static func option_name(key: String, i: int, look: Dictionary = {}) -> String:
	match key:
		"body": return BODIES[i]
		"face": return (FEMALE_FACES if int(look.get("body", 0)) == 1 else MALE_FACES)[i].name
		"eyes": return EYES[i].name
		"mouth": return MOUTHS[i]
		"ears": return EARS[i]
		"voice": return VOICES[i].name
		"outfit": return OUTFITS[i].name
		"headwear": return HEADWEAR[i]
		"torso": return TORSO[i].name
		"backpack": return BACKPACKS[i].name
		"gloves": return GLOVES[i].name
		"pants": return PANTS[i].name
		"boots": return BOOTS[i].name
	return ""


## A complete, valid look from anything (saved settings, the network).
static func sanitize(raw: Variant) -> Dictionary:
	var look := default_look()
	if raw is Dictionary:
		for key in KEYS:
			var v: Variant = (raw as Dictionary).get(key)
			if v is int or v is float:
				look[key] = int(v)
	for key in KEYS: # body first, so the face range is right
		look[key] = clampi(int(look[key]), 0, count(key, look) - 1)
	return look


## Picking an outfit sets its kit pieces.
static func with_outfit(look: Dictionary, outfit: int) -> Dictionary:
	var out := look.duplicate()
	out.outfit = clampi(outfit, 0, OUTFITS.size() - 1)
	out.merge(OUTFITS[out.outfit].kit, true)
	return out


## A random look (bots, the Random button), repeatable with `seed_value`.
static func random(seed_value: int, body: int = -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var look := { "body": body if body >= 0 else rng.randi_range(0, 1) }
	look = with_outfit(look, rng.randi_range(0, OUTFITS.size() - 1))
	for key in ["face", "eyes", "mouth", "ears", "voice"]:
		look[key] = rng.randi_range(0, count(key, look) - 1)
	# Mostly the outfit's own kit, a piece or two swapped.
	for key in ["headwear", "backpack", "gloves"]:
		if rng.randf() < 0.3:
			look[key] = rng.randi_range(0, count(key, look) - 1)
	return sanitize(look)


static func pack(look: Dictionary) -> Array[int]:
	var clean := sanitize(look)
	var out: Array[int] = []
	for key in KEYS:
		out.append(int(clean[key]))
	return out


static func unpack(data: Variant) -> Dictionary:
	var look := {}
	if data is Array or data is PackedInt32Array or data is PackedByteArray:
		for i in mini(data.size(), KEYS.size()):
			look[KEYS[i]] = data[i]
	return sanitize(look)


## Cache key: identical looks share their meshes.
static func key_of(look: Dictionary) -> String:
	var parts := PackedStringArray()
	for v in pack(look):
		parts.append(str(v))
	return ",".join(parts)


static func face_of(look: Dictionary) -> Dictionary:
	return (FEMALE_FACES if int(look.body) == 1 else MALE_FACES)[int(look.face)]


## Pitch for this look's voice (grunts, cries) and whether it is rough.
static func voice_pitch(look: Dictionary) -> float:
	var v: Dictionary = VOICES[int(look.get("voice", 0))]
	return float(v.pitch) * (FEMALE_PITCH if int(look.get("body", 0)) == 1 else 1.0)


static func voice_rough(look: Dictionary) -> bool:
	return bool(VOICES[int(look.get("voice", 0))].rough)
