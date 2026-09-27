class_name ProceduralSfx
extends RefCounted
## Tiny generated placeholder sounds so the prototype has audio before real
## assets exist. Replace with .ogg/.wav files from assets/audio/sfx/ later.

const MIX_RATE := 22050


## Noise burst with exponential decay — works as a gunshot / impact placeholder.
static func noise_burst(duration: float, decay: float, low_pass: float = 0.5, volume: float = 0.9) -> AudioStreamWAV:
	var frames := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var prev := 0.0
	for i in frames:
		var t := float(i) / MIX_RATE
		var sample := rng.randf_range(-1.0, 1.0)
		prev = lerpf(prev, sample, low_pass) # one-pole low-pass
		var env := exp(-t * decay)
		data.encode_s16(i * 2, int(clampf(prev * env * volume, -1.0, 1.0) * 32767.0))
	return _make_stream(data)


## Short sine "click" — dry fire / UI placeholder.
static func click(freq: float = 1800.0, duration: float = 0.04) -> AudioStreamWAV:
	var frames := int(duration * MIX_RATE)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var t := float(i) / MIX_RATE
		var env := 1.0 - float(i) / frames
		data.encode_s16(i * 2, int(sin(TAU * freq * t) * env * 0.5 * 32767.0))
	return _make_stream(data)


static func _make_stream(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
