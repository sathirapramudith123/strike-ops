class_name VoiceProcessor
extends RefCounted
## Microphone signal chain, run on 20 ms frames at 16 kHz:
##   resample → high-pass (removes rumble/DC) → mic gain →
##   [noise gate + automatic gain control] → level meter.
## Echo cancellation is not implemented — players should use headphones.

const FRAME_SIZE := 320 # 20 ms @ 16 kHz

var mic_gain: float = 1.0
var processing_enabled: bool = true

## Last frame's peak level (0..1) — for the settings meter and voice activation.
var level: float = 0.0

var _hp_x1: float = 0.0
var _hp_y1: float = 0.0
var _noise_floor: float = 0.002
var _gate_gain: float = 1.0
var _agc_gain: float = 1.0

# Streaming linear resampler state.
var _in_rate: float = 16000.0
var _res_pos: float = 0.0
var _res_buf := PackedFloat32Array()


func set_input_rate(rate: float) -> void:
	if not is_equal_approx(rate, _in_rate):
		_in_rate = rate
		_res_pos = 0.0
		_res_buf.clear()


## Streams input-rate samples in, returns whatever 16 kHz samples are ready.
func resample(input: PackedFloat32Array) -> PackedFloat32Array:
	if is_equal_approx(_in_rate, VoiceCodec.SAMPLE_RATE):
		return input
	_res_buf.append_array(input)
	var ratio := _in_rate / VoiceCodec.SAMPLE_RATE
	var out := PackedFloat32Array()
	var last := _res_buf.size() - 1
	while _res_pos < last:
		var i := int(_res_pos)
		var f := _res_pos - i
		out.append(lerpf(_res_buf[i], _res_buf[i + 1], f))
		_res_pos += ratio
	var consumed := int(_res_pos)
	_res_buf = _res_buf.slice(consumed)
	_res_pos -= consumed
	return out


## Processes one frame in place and updates `level`.
func process_frame(frame: PackedFloat32Array) -> void:
	var n := frame.size()
	var sum_sq := 0.0
	var peak := 0.0
	for i in n:
		# One-pole high-pass at ~80 Hz.
		var x := frame[i] * mic_gain
		var y := x - _hp_x1 + 0.969 * _hp_y1
		_hp_x1 = x
		_hp_y1 = y
		frame[i] = y
		sum_sq += y * y
	var rms := sqrt(sum_sq / maxf(n, 1))

	if processing_enabled:
		# Noise floor: drops instantly, rises slowly; capped so speech is never gated.
		_noise_floor = minf(minf(rms, _noise_floor * 1.01 + 0.00001), 0.03)
		var open := rms > _noise_floor * 2.5
		_gate_gain = move_toward(_gate_gain, 1.0 if open else 0.05, 0.25)
		# AGC towards ~0.12 RMS while the gate is open.
		if open and rms > 0.0001:
			_agc_gain = lerpf(_agc_gain, clampf(0.12 / rms, 0.5, 4.0), 0.05)
		var g := _gate_gain * _agc_gain
		for i in n:
			frame[i] = clampf(frame[i] * g, -1.0, 1.0)

	for i in n:
		peak = maxf(peak, absf(frame[i]))
	level = peak
