class_name ProceduralSfx
extends RefCounted
## Tiny synthesiser for the placeholder sounds and music, so the game has
## audio without any sound files. Sounds are built in float buffers (mono,
## `rate` Hz) with add_noise() / add_tone() / add_wave(), then converted to a
## 16-bit AudioStreamWAV with to_stream(). Real files in assets/audio/
## replace the generated sounds (see SfxLibrary and MusicSynth).

const MIX_RATE := 22050

enum Shape { SINE, SOFT_SQUARE }


## An empty (silent) buffer of `duration` seconds.
static func buffer(duration: float, rate: int = MIX_RATE) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(maxi(int(duration * rate), 1))
	return buf


## Adds filtered noise starting at `start` s. low_pass / high_pass are
## one-pole coefficients 0..1 (1 = no filtering / 0 = no high-pass).
## Envelope: linear attack, then exponential decay (per second).
static func add_noise(buf: PackedFloat32Array, start: float, duration: float, gain: float,
		low_pass: float, high_pass: float = 0.0, decay: float = 10.0, attack: float = 0.002,
		seed: int = 1, rate: int = MIX_RATE) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var first := int(start * rate)
	var frames := mini(int(duration * rate), buf.size() - first)
	var lp := 0.0
	var hp := 0.0
	for i in frames:
		var t := float(i) / rate
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), low_pass)
		hp = lerpf(hp, lp, high_pass)
		buf[first + i] += (lp - hp) * gain * _envelope(t, duration, attack, decay)


## Adds a tone that sweeps exponentially from f0 to f1 Hz (f1 <= 0: steady).
static func add_tone(buf: PackedFloat32Array, start: float, duration: float, gain: float,
		f0: float, f1: float = -1.0, decay: float = 8.0, attack: float = 0.002,
		shape: Shape = Shape.SINE, rate: int = MIX_RATE) -> void:
	var first := int(start * rate)
	var frames := mini(int(duration * rate), buf.size() - first)
	var ratio := (f1 / f0) if f1 > 0.0 else 1.0
	var phase := 0.0
	for i in frames:
		var t := float(i) / rate
		var f := f0 * pow(ratio, t / duration) if ratio != 1.0 else f0
		phase += TAU * f / rate
		var s := sin(phase)
		if shape == Shape.SOFT_SQUARE:
			s = tanh(s * 3.0) * 0.8
		buf[first + i] += s * gain * _envelope(t, duration, attack, decay)


## One period of a waveform made of harmonics (weights for 1×, 2×, 3× …),
## used by add_wave() for cheap rich tones (music pads, plucks).
static func wavetable(harmonics: PackedFloat32Array, size: int = 1024) -> PackedFloat32Array:
	var table := PackedFloat32Array()
	table.resize(size)
	var peak := 0.0
	for i in size:
		var s := 0.0
		for h in harmonics.size():
			s += sin(TAU * (h + 1) * i / size) * harmonics[h]
		table[i] = s
		peak = maxf(peak, absf(s))
	for i in size:
		table[i] /= maxf(peak, 0.0001)
	return table


## Adds a note played from `table`: attack, sustain, `release` s fade-out at
## the end, optional exponential decay. With `wrap`, samples past the end of
## the buffer wrap to the start (seamless music loops).
static func add_wave(buf: PackedFloat32Array, table: PackedFloat32Array, start: float, duration: float,
		gain: float, freq: float, attack: float = 0.01, release: float = 0.05, decay: float = 0.0,
		rate: int = MIX_RATE, wrap: bool = false) -> void:
	var size := table.size()
	var n := buf.size()
	var first := int(start * rate)
	var frames := int(duration * rate)
	if not wrap:
		frames = mini(frames, n - first)
	var step := freq * size / rate
	var phase := 0.0
	var attack_frames := maxf(attack * rate, 1.0)
	var release_frames := maxf(release * rate, 1.0)
	var decay_per_frame := exp(-decay / rate)
	var level := 1.0
	for i in frames:
		var env := minf(i / attack_frames, 1.0) * minf((frames - i) / release_frames, 1.0) * level
		level *= decay_per_frame
		var idx := first + i
		if wrap:
			idx %= n
		buf[idx] += table[int(phase) % size] * gain * env
		phase += step


## Scales the buffer so its loudest sample is `peak`.
static func normalize(buf: PackedFloat32Array, peak: float = 0.9) -> void:
	var top := 0.0
	for s in buf:
		top = maxf(top, absf(s))
	if top <= 0.0:
		return
	var k := peak / top
	for i in buf.size():
		buf[i] *= k


static func to_stream(buf: PackedFloat32Array, rate: int = MIX_RATE, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = buf.size()
	return stream


## Frequency of a MIDI note (69 = A4 = 440 Hz).
static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## Noise burst with exponential decay (gunshot / impact placeholder).
static func noise_burst(duration: float, decay: float, low_pass: float = 0.5, volume: float = 0.9) -> AudioStreamWAV:
	var buf := buffer(duration)
	add_noise(buf, 0.0, duration, volume, low_pass, 0.0, decay, 0.0, 1234)
	return to_stream(buf)


## Short sine "click" (dry fire / UI placeholder).
static func click(freq: float = 1800.0, duration: float = 0.04) -> AudioStreamWAV:
	var buf := buffer(duration)
	add_tone(buf, 0.0, duration, 0.5, freq, -1.0, 1.0 / duration)
	return to_stream(buf)


## Attack ramp, exponential decay, and a 4 ms fade at the very end (no clicks).
static func _envelope(t: float, duration: float, attack: float, decay: float) -> float:
	var env := minf(t / attack, 1.0) if attack > 0.0 else 1.0
	env *= exp(-maxf(t - attack, 0.0) * decay)
	return env * clampf((duration - t) / 0.004, 0.0, 1.0)
