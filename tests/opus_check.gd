extends SceneTree
## Quick check that the Opus extension loads and works on this platform
## (CI runs it on Windows and macOS; the full tests run on Linux).
##   godot --headless --path . -s res://tests/opus_check.gd
## Exit code 0 = OK.

func _init() -> void:
	var ok := VoiceCodec.opus_available()
	print("Opus: %s (%s / %s)" % [VoiceCodec.opus_version() if ok else "NOT LOADED", OS.get_name(), Engine.get_architecture_name()])
	if ok:
		var enc := VoiceEncoder.new()
		enc.use_opus = true
		var dec := VoiceDecoder.new()
		var frame := PackedFloat32Array()
		frame.resize(VoiceEncoder.PACKET_SAMPLES)
		var bytes := 0
		var out := PackedFloat32Array()
		for k in 25:
			for i in frame.size():
				frame[i] = 0.5 * sin(TAU * 440.0 * (k * frame.size() + i) / 16000.0)
			var p := enc.encode(frame)
			bytes += p.size()
			out = dec.decode(p, frame.size())
		var rms := 0.0
		for v in out:
			rms += v * v
		rms = sqrt(rms / maxf(out.size(), 1))
		print("25 packets: %.0f kbps, last frame %d samples, RMS %.2f" % [bytes * 8.0 / 1000.0, out.size(), rms])
		ok = bytes * 8.0 / 1000.0 < 40.0 and out.size() == frame.size() and absf(rms - 0.354) < 0.1
	print("PASSED" if ok else "FAILED")
	quit(0 if ok else 1)
