class_name SfxLibrary
extends RefCounted
## Every named game sound. A real file named after the sound in
## res://assets/audio/sfx/ or res://assets/audio/ui/ (.ogg, .wav or .mp3)
## replaces the generated placeholder automatically — e.g. drop in
## assets/audio/sfx/fire_rifle.ogg and the AR-7 uses it.
##
## Thread-safe: AudioManager prewarms the whole library on a worker thread.

const NAMES: Array[StringName] = [
	# Weapons (fire_<weapon_id>)
	&"fire_rifle", &"fire_smg", &"fire_shotgun", &"fire_sniper", &"fire_pistol",
	&"dry_fire", &"mag_out", &"mag_in", &"bolt", &"equip",
	# Movement
	&"step1", &"step2", &"step3", &"step4", &"land", &"jump", &"slide",
	# Bullets
	&"impact", &"whiz",
	# Grenades
	&"throw", &"grenade_bounce", &"glass_break", &"fire", &"flash_bang", &"flash_ring", &"smoke_hiss",
	# Feedback (UI bus)
	&"hitmarker", &"headshot", &"kill", &"hurt", &"ui_click", &"ui_hover",
	# Bomb Defusal + match
	&"bomb_beep", &"explosion", &"bomb_planted", &"bomb_defused",
	&"round_start", &"round_win", &"round_lose", &"match_win", &"match_lose",
]
const FILE_DIRS: PackedStringArray = ["res://assets/audio/sfx/", "res://assets/audio/ui/"]
const FILE_EXTENSIONS: PackedStringArray = ["ogg", "wav", "mp3"]

const PS := preload("res://scripts/audio/procedural_sfx.gd")

static var _cache: Dictionary = {}
static var _mutex := Mutex.new()


static func get_sound(sound: StringName) -> AudioStream:
	_mutex.lock()
	var cached: AudioStream = _cache.get(sound)
	_mutex.unlock()
	if cached:
		return cached
	var stream := _load_file(sound)
	if stream == null:
		stream = generate(sound)
	_mutex.lock()
	_cache[sound] = stream
	_mutex.unlock()
	return stream


## Builds every sound once (called on a worker thread at startup).
static func prewarm() -> void:
	for sound in NAMES:
		get_sound(sound)


static func is_cached(sound: StringName) -> bool:
	_mutex.lock()
	var ok := _cache.has(sound)
	_mutex.unlock()
	return ok


## Path of a replacement file for `sound`, or "" if there is none.
static func file_for(sound: StringName) -> String:
	for dir in FILE_DIRS:
		for ext in FILE_EXTENSIONS:
			var path := "%s%s.%s" % [dir, sound, ext]
			if ResourceLoader.exists(path):
				return path
	return ""


static func _load_file(sound: StringName) -> AudioStream:
	var path := file_for(sound)
	return load(path) as AudioStream if path != "" else null


## The generated placeholder for `sound`.
static func generate(sound: StringName) -> AudioStreamWAV:
	var b: PackedFloat32Array
	match sound:
		# --- Guns: a low "thump" sweep + a bright crack + a filtered tail ---
		&"fire_rifle":
			b = PS.buffer(0.55)
			PS.add_tone(b, 0.0, 0.2, 0.9, 130.0, 45.0, 22.0)
			PS.add_noise(b, 0.0, 0.12, 0.8, 0.75, 0.02, 40.0, 0.001, 11)
			PS.add_noise(b, 0.01, 0.54, 0.35, 0.12, 0.0, 7.0, 0.01, 12)
		&"fire_smg":
			b = PS.buffer(0.35)
			PS.add_tone(b, 0.0, 0.12, 0.7, 170.0, 70.0, 35.0)
			PS.add_noise(b, 0.0, 0.08, 0.8, 0.85, 0.03, 55.0, 0.001, 21)
			PS.add_noise(b, 0.01, 0.34, 0.25, 0.15, 0.0, 12.0, 0.01, 22)
		&"fire_shotgun":
			b = PS.buffer(0.9)
			PS.add_tone(b, 0.0, 0.35, 1.0, 95.0, 32.0, 12.0)
			PS.add_noise(b, 0.0, 0.25, 0.9, 0.55, 0.01, 20.0, 0.001, 31)
			PS.add_noise(b, 0.02, 0.88, 0.45, 0.08, 0.0, 4.5, 0.02, 32)
		&"fire_sniper":
			b = PS.buffer(1.3)
			PS.add_noise(b, 0.0, 0.06, 1.0, 0.95, 0.1, 70.0, 0.0005, 41)
			PS.add_tone(b, 0.0, 0.5, 1.0, 85.0, 28.0, 8.0)
			PS.add_noise(b, 0.0, 0.3, 0.6, 0.35, 0.0, 18.0, 0.001, 42)
			PS.add_noise(b, 0.03, 1.27, 0.5, 0.06, 0.0, 3.0, 0.03, 43)
		&"fire_pistol":
			b = PS.buffer(0.4)
			PS.add_tone(b, 0.0, 0.14, 0.7, 210.0, 85.0, 30.0)
			PS.add_noise(b, 0.0, 0.1, 0.8, 0.8, 0.03, 45.0, 0.001, 51)
			PS.add_noise(b, 0.01, 0.39, 0.25, 0.15, 0.0, 10.0, 0.01, 52)
		# --- Weapon handling: metallic clicks ---
		&"dry_fire":
			b = PS.buffer(0.07)
			PS.add_tone(b, 0.0, 0.07, 0.5, 1400.0, -1.0, 80.0)
			PS.add_noise(b, 0.0, 0.05, 0.3, 0.9, 0.3, 120.0, 0.0005, 61)
		&"mag_out":
			b = PS.buffer(0.16)
			PS.add_noise(b, 0.0, 0.1, 0.5, 0.9, 0.2, 60.0, 0.001, 62)
			PS.add_tone(b, 0.0, 0.08, 0.3, 2300.0, -1.0, 70.0)
			PS.add_tone(b, 0.03, 0.12, 0.3, 900.0, -1.0, 50.0)
		&"mag_in":
			b = PS.buffer(0.2)
			PS.add_noise(b, 0.0, 0.12, 0.6, 0.4, 0.0, 40.0, 0.001, 63)
			PS.add_tone(b, 0.0, 0.1, 0.4, 700.0, -1.0, 45.0)
			PS.add_tone(b, 0.03, 0.12, 0.3, 2600.0, -1.0, 90.0)
		&"bolt":
			b = PS.buffer(0.26)
			for t: float in [0.0, 0.1]:
				PS.add_tone(b, t, 0.1, 0.4, 1800.0 - t * 3000.0, -1.0, 90.0)
				PS.add_noise(b, t, 0.1, 0.4, 0.9, 0.3, 90.0, 0.0005, 64 + int(t * 10))
		&"equip":
			b = PS.buffer(0.24)
			PS.add_noise(b, 0.0, 0.2, 0.35, 0.3, 0.02, 18.0, 0.03, 65)
			PS.add_tone(b, 0.12, 0.1, 0.3, 1600.0, -1.0, 80.0)
		# --- Movement ---
		&"step1", &"step2", &"step3", &"step4":
			var v := int(String(sound).right(1))
			b = PS.buffer(0.15)
			PS.add_noise(b, 0.0, 0.15, 0.8, 0.18 + v * 0.03, 0.01, 38.0, 0.004, 70 + v)
			PS.add_tone(b, 0.0, 0.1, 0.5, 70.0 + v * 6.0, 50.0, 40.0, 0.003)
		&"land":
			b = PS.buffer(0.3)
			PS.add_noise(b, 0.0, 0.3, 0.9, 0.2, 0.0, 18.0, 0.003, 75)
			PS.add_tone(b, 0.0, 0.2, 0.8, 65.0, 40.0, 20.0, 0.003)
		&"jump":
			b = PS.buffer(0.14)
			PS.add_noise(b, 0.0, 0.14, 0.4, 0.35, 0.05, 30.0, 0.02, 76)
		&"slide":
			b = PS.buffer(0.7)
			PS.add_noise(b, 0.0, 0.7, 0.6, 0.3, 0.02, 3.5, 0.05, 77)
		# --- Bullets ---
		&"impact":
			b = PS.buffer(0.12)
			PS.add_noise(b, 0.0, 0.12, 0.8, 0.8, 0.15, 60.0, 0.0005, 81)
			PS.add_tone(b, 0.0, 0.08, 0.3, 420.0, 300.0, 45.0)
		&"whiz":
			b = PS.buffer(0.3)
			PS.add_noise(b, 0.0, 0.3, 0.5, 0.5, 0.25, 22.0, 0.1, 82)
			PS.add_tone(b, 0.0, 0.3, 0.35, 1100.0, 500.0, 20.0, 0.1)
		# --- Grenades ---
		&"throw":
			b = PS.buffer(0.25)
			PS.add_noise(b, 0.0, 0.25, 0.5, 0.3, 0.05, 14.0, 0.06, 83)
		&"grenade_bounce":
			b = PS.buffer(0.12)
			PS.add_tone(b, 0.0, 0.1, 0.5, 950.0, 700.0, 45.0)
			PS.add_noise(b, 0.0, 0.06, 0.4, 0.7, 0.1, 70.0, 0.0005, 84)
		&"glass_break":
			b = PS.buffer(0.6)
			PS.add_noise(b, 0.0, 0.5, 0.8, 0.95, 0.4, 9.0, 0.0005, 85)
			for i in 6:
				PS.add_tone(b, i * 0.035, 0.2, 0.25, 2800.0 + i * 530.0, -1.0, 25.0)
			PS.add_noise(b, 0.0, 0.6, 0.6, 0.25, 0.0, 5.0, 0.01, 86) # the whoosh of the fuel
		&"fire":
			# Crackling roar for the whole burn (FireZone.DURATION), fading at the end.
			b = PS.buffer(7.5)
			PS.add_noise(b, 0.0, 7.5, 0.5, 0.12, 0.0, 0.25, 0.3, 87)
			var rng := RandomNumberGenerator.new()
			rng.seed = 88
			for i in 90:
				PS.add_noise(b, rng.randf_range(0.0, 7.0), 0.03, rng.randf_range(0.3, 0.7), 0.9, 0.5, 90.0, 0.0005, 200 + i)
		&"flash_bang":
			# A sharp, bright crack — higher and shorter than the HE.
			b = PS.buffer(1.0)
			PS.add_noise(b, 0.0, 0.08, 1.0, 0.98, 0.2, 60.0, 0.0003, 89)
			PS.add_tone(b, 0.0, 0.3, 0.7, 180.0, 60.0, 14.0)
			PS.add_noise(b, 0.0, 1.0, 0.45, 0.3, 0.0, 4.0, 0.005, 90)
		&"flash_ring":
			# Ears ringing after a flash: a high whine fading out.
			b = PS.buffer(3.5)
			PS.add_tone(b, 0.0, 3.5, 0.5, 3600.0, -1.0, 0.9, 0.05)
			PS.add_tone(b, 0.0, 3.5, 0.15, 3615.0, -1.0, 0.9, 0.05)
		&"smoke_hiss":
			b = PS.buffer(3.0)
			PS.add_noise(b, 0.0, 3.0, 0.6, 0.85, 0.3, 0.8, 0.05, 93)
		# --- Feedback ---
		&"hitmarker":
			b = PS.buffer(0.05)
			PS.add_tone(b, 0.0, 0.05, 0.6, 2600.0, -1.0, 90.0)
			PS.add_noise(b, 0.0, 0.03, 0.2, 1.0, 0.5, 150.0, 0.0005, 91)
		&"headshot":
			b = PS.buffer(0.35)
			PS.add_tone(b, 0.0, 0.35, 0.5, 1800.0, -1.0, 12.0)
			PS.add_tone(b, 0.0, 0.35, 0.35, 2700.0, -1.0, 14.0)
		&"kill":
			b = PS.buffer(0.3)
			PS.add_tone(b, 0.0, 0.1, 0.5, 1250.0, -1.0, 30.0)
			PS.add_tone(b, 0.07, 0.23, 0.5, 1680.0, -1.0, 18.0)
		&"hurt":
			b = PS.buffer(0.3)
			PS.add_tone(b, 0.0, 0.3, 0.9, 80.0, 45.0, 14.0)
			PS.add_noise(b, 0.0, 0.25, 0.5, 0.12, 0.0, 16.0, 0.002, 92)
		&"ui_click":
			b = PS.buffer(0.05)
			PS.add_tone(b, 0.0, 0.05, 0.5, 1150.0, -1.0, 70.0)
		&"ui_hover":
			b = PS.buffer(0.035)
			PS.add_tone(b, 0.0, 0.035, 0.25, 1700.0, -1.0, 110.0)
		# --- Bomb Defusal & match stings ---
		&"bomb_beep":
			b = PS.buffer(0.07)
			PS.add_tone(b, 0.0, 0.07, 0.5, 2200.0, -1.0, 15.0)
		&"explosion":
			b = PS.buffer(2.0)
			PS.add_tone(b, 0.0, 1.2, 1.0, 70.0, 24.0, 3.0)
			PS.add_noise(b, 0.0, 2.0, 0.9, 0.18, 0.0, 2.5, 0.005, 101)
			PS.add_noise(b, 0.0, 0.2, 0.6, 0.6, 0.0, 25.0, 0.001, 102)
		&"bomb_planted":
			b = PS.buffer(0.9)
			for i in 4:
				PS.add_tone(b, i * 0.2, 0.18, 0.4, 880.0 if i % 2 == 0 else 660.0, -1.0, 6.0, 0.005, PS.Shape.SOFT_SQUARE)
		&"bomb_defused":
			b = PS.buffer(0.7)
			_arpeggio(b, [76.0, 81.0, 88.0], 0.13, 0.4, 0.4)
		&"round_start":
			b = PS.buffer(0.75)
			_arpeggio(b, [72.0, 76.0, 79.0], 0.12, 0.45, 0.4)
		&"round_win":
			b = PS.buffer(1.1)
			_arpeggio(b, [72.0, 76.0, 79.0, 84.0], 0.1, 0.7, 0.35)
		&"round_lose":
			b = PS.buffer(1.1)
			_arpeggio(b, [76.0, 72.0, 69.0, 64.0], 0.14, 0.6, 0.35)
		&"match_win":
			b = PS.buffer(2.2)
			_arpeggio(b, [60.0, 64.0, 67.0, 72.0], 0.12, 0.5, 0.3)
			for n: float in [72.0, 76.0, 79.0]:
				PS.add_tone(b, 0.5, 1.7, 0.25, PS.midi_hz(n), -1.0, 1.5, 0.02)
		&"match_lose":
			b = PS.buffer(2.2)
			_arpeggio(b, [69.0, 67.0, 65.0, 64.0], 0.16, 0.5, 0.3)
			for n: float in [57.0, 60.0, 64.0]:
				PS.add_tone(b, 0.64, 1.56, 0.28, PS.midi_hz(n), -1.0, 1.5, 0.02)
		_:
			push_warning("SfxLibrary: unknown sound '%s'" % sound)
			b = PS.buffer(0.05)
			PS.add_tone(b, 0.0, 0.05, 0.3, 1000.0)
	PS.normalize(b, 0.9)
	return PS.to_stream(b)


## Notes (MIDI) one after another, each ringing out.
static func _arpeggio(b: PackedFloat32Array, notes: Array, spacing: float, length: float, gain: float) -> void:
	for i in notes.size():
		PS.add_tone(b, i * spacing, minf(length, b.size() / float(PS.MIX_RATE) - i * spacing),
			gain, PS.midi_hz(notes[i]), -1.0, 5.0, 0.005)
		PS.add_tone(b, i * spacing, minf(length, b.size() / float(PS.MIX_RATE) - i * spacing),
			gain * 0.3, PS.midi_hz(notes[i] + 12.0), -1.0, 8.0, 0.005)
