class_name MusicSynth
extends RefCounted
## Generated placeholder music: seamless loops built from wavetable notes.
## A real file res://assets/audio/music/<track>.ogg (or .mp3/.wav) replaces
## a track automatically — loop it in the import settings.
##
##   menu  — calm A-minor pad + bass + arpeggio (96 BPM, 20 s loop)
##   match — low tense drone with a soft pulse (120 BPM, 16 s loop), played quietly
##
## Generation takes a moment, so AudioManager runs it on a worker thread.

const TRACKS: Array[StringName] = [&"menu", &"match"]
const RATE := 16000
const DIR := "res://assets/audio/music/"

const PS := preload("res://scripts/audio/procedural_sfx.gd")


static func get_track(track: StringName) -> AudioStream:
	for ext in ["ogg", "mp3", "wav"]:
		var path := "%s%s.%s" % [DIR, track, ext]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return generate(track)


static func generate(track: StringName) -> AudioStreamWAV:
	match track:
		&"menu":
			return _menu()
		&"match":
			return _match()
	push_warning("MusicSynth: unknown track '%s'" % track)
	return PS.to_stream(PS.buffer(1.0, RATE), RATE, true)


static func _menu() -> AudioStreamWAV:
	var beat := 60.0 / 96.0
	var bar := beat * 4.0
	var chord_len := bar * 2.0
	# Am – F – C – G, two bars each (MIDI notes).
	var chords := [[57, 60, 64], [53, 57, 60], [60, 64, 67], [55, 59, 62]]
	var buf := PS.buffer(chord_len * chords.size(), RATE)
	var pad := PS.wavetable(PackedFloat32Array([1.0, 0.35, 0.18, 0.08]))
	var pluck := PS.wavetable(PackedFloat32Array([1.0, 0.5, 0.2, 0.25, 0.1]))
	var bass := PS.wavetable(PackedFloat32Array([1.0, 0.25]))
	for c in chords.size():
		var t0: float = c * chord_len
		var notes: Array = chords[c]
		# Pad: slow attack, long release overlapping the next chord.
		for n: int in notes:
			PS.add_wave(buf, pad, t0, chord_len + 1.2, 0.09, PS.midi_hz(n), 1.2, 1.4, 0.0, RATE, true)
			PS.add_wave(buf, pad, t0, chord_len + 1.2, 0.05, PS.midi_hz(n) * 1.004, 1.2, 1.4, 0.0, RATE, true)
		# Bass: root, one note per bar.
		for b in 2:
			PS.add_wave(buf, bass, t0 + b * bar, bar, 0.22, PS.midi_hz(notes[0] - 12), 0.02, 0.3, 0.6, RATE, true)
		# Arpeggio: eighth notes one octave up.
		var pattern := [0, 1, 2, 1, 0, 2, 1, 2]
		for i in 16:
			var note: int = notes[pattern[i % 8]] + 12
			PS.add_wave(buf, pluck, t0 + i * beat * 0.5, 0.6, 0.07, PS.midi_hz(note), 0.004, 0.1, 5.0, RATE, true)
	PS.normalize(buf, 0.6)
	return PS.to_stream(buf, RATE, true)


static func _match() -> AudioStreamWAV:
	var beat := 60.0 / 120.0
	var bars := 8
	var length := beat * 4.0 * bars
	var buf := PS.buffer(length, RATE)
	var drone := PS.wavetable(PackedFloat32Array([1.0, 0.6, 0.3, 0.2, 0.1]))
	# Low D drone + fifth, swelling in two halves; the upper voice moves D → C → Bb → C.
	for half in 2:
		var t0 := half * length * 0.5
		PS.add_wave(buf, drone, t0, length * 0.5 + 1.5, 0.16, PS.midi_hz(38), 1.5, 1.5, 0.0, RATE, true)
		PS.add_wave(buf, drone, t0, length * 0.5 + 1.5, 0.08, PS.midi_hz(45), 1.5, 1.5, 0.0, RATE, true)
	var upper := [62, 60, 58, 60]
	for i in upper.size():
		PS.add_wave(buf, drone, i * length / 4.0, length / 4.0 + 1.0, 0.035, PS.midi_hz(upper[i]), 0.8, 1.0, 0.0, RATE, true)
	# Soft pulse on every beat, a tick on the off-beats.
	var thump := PS.wavetable(PackedFloat32Array([1.0]))
	for i in bars * 4:
		PS.add_wave(buf, thump, i * beat, 0.25, 0.25, 55.0, 0.003, 0.05, 14.0, RATE, true)
	var tick := PS.buffer(0.03, RATE)
	PS.add_noise(tick, 0.0, 0.03, 0.05, 1.0, 0.6, 120.0, 0.001, 7, RATE)
	for i in bars * 4:
		var at := int((i + 0.5) * beat * RATE)
		for j in tick.size():
			buf[(at + j) % buf.size()] += tick[j]
	PS.normalize(buf, 0.6)
	return PS.to_stream(buf, RATE, true)
