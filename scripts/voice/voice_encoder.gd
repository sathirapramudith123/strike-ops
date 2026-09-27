class_name VoiceEncoder
extends RefCounted
## Encodes one speaker's voice into packets: [codec byte][payload].
## Stateful (Opus keeps history between packets) — one per sender.

## Samples per packet (VoiceChat.FRAMES_PER_PACKET × 20 ms).
const PACKET_SAMPLES := 640

## Send Opus (true) or ADPCM. May change between packets.
var use_opus: bool = false

var _opus: Object # OpusVoiceEncoder (GDExtension), created on first use


func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	if use_opus and VoiceCodec.opus_available():
		if _opus == null:
			_opus = ClassDB.instantiate(&"OpusVoiceEncoder")
			_opus.setup(VoiceCodec.SAMPLE_RATE, VoiceCodec.OPUS_BITRATE, VoiceCodec.OPUS_EXPECTED_LOSS)
		# Opus needs whole frames: pad the tail of a sentence with silence.
		var frame := samples
		if frame.size() != PACKET_SAMPLES:
			frame = samples.slice(0, PACKET_SAMPLES)
			frame.resize(PACKET_SAMPLES)
		var payload: PackedByteArray = _opus.encode(frame)
		if not payload.is_empty():
			out.append(VoiceCodec.CODEC_OPUS)
			out.append_array(payload)
			return out
	out.append(VoiceCodec.CODEC_ADPCM)
	out.append_array(VoiceCodec.encode(samples))
	return out
