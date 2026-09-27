class_name VoiceDecoder
extends RefCounted
## Decodes one speaker's packets (see VoiceEncoder). Stateful — one per sender.
##
## Lost Opus packets are rebuilt: the one just before a packet from the FEC
## data it carries, older ones by Opus packet-loss concealment. ADPCM packets
## are independent, so a lost one is simply skipped.

## Most lost packets in a row that get concealed (longer gaps = silence).
const MAX_CONCEALED := 3

## Codec of the last packet (VoiceCodec.CODEC_*), -1 = none yet.
var last_codec: int = -1
## Packets rebuilt by FEC / concealment (stats, tests).
var concealed: int = 0

var _opus: Object # OpusVoiceDecoder (GDExtension)


## `lost`: packets missing right before this one (0 = none).
func decode(packet: PackedByteArray, sample_count: int, lost: int = 0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if packet.size() < 2:
		return out
	var codec := packet[0]
	var payload := packet.slice(1)
	sample_count = clampi(sample_count, 0, VoiceEncoder.PACKET_SAMPLES)
	match codec:
		VoiceCodec.CODEC_ADPCM:
			out = VoiceCodec.decode(payload, sample_count)
		VoiceCodec.CODEC_OPUS:
			if not VoiceCodec.opus_available():
				return out # can't happen when codec negotiation works
			if _opus == null:
				_opus = ClassDB.instantiate(&"OpusVoiceDecoder")
				_opus.setup(VoiceCodec.SAMPLE_RATE)
			if last_codec == VoiceCodec.CODEC_OPUS and lost > 0 and lost <= MAX_CONCEALED:
				for i in lost - 1:
					out.append_array(_opus.decode_lost(VoiceEncoder.PACKET_SAMPLES))
				out.append_array(_opus.decode_fec(payload, VoiceEncoder.PACKET_SAMPLES))
				concealed += lost
			var frame: PackedFloat32Array = _opus.decode(payload)
			out.append_array(frame.slice(0, sample_count))
		_:
			return out
	last_codec = codec
	return out
