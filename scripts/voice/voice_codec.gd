class_name VoiceCodec
extends RefCounted
## Voice codecs. Every voice packet starts with a codec byte:
##
##   CODEC_OPUS  — Opus (GDExtension in addons/opus_voice, libopus 1.5):
##                 24 kbps, in-band FEC + loss concealment. Used when every
##                 player in the match has the extension.
##   CODEC_ADPCM — IMA-ADPCM (4 bits/sample) in pure GDScript: 64 kbps, works
##                 everywhere; the fallback when someone lacks Opus.
##
## Both run at 16 kHz mono, and only while talking. VoiceEncoder / VoiceDecoder
## pick the codec; this class holds the shared constants and the ADPCM code.
##
## ADPCM packet: [int16 predictor][u8 step index][4-bit samples, low nibble first]
## Each ADPCM packet carries its own state, so a lost packet never corrupts
## the following ones.

const SAMPLE_RATE := 16000
const HEADER_SIZE := 3

const CODEC_ADPCM := 0
const CODEC_OPUS := 1
const OPUS_BITRATE := 24000
## Expected packet loss the Opus encoder protects against with FEC.
const OPUS_EXPECTED_LOSS := 10

static var _opus_checked: bool = false
static var _opus_ok: bool = false


## True when the Opus extension is loaded (and not disabled with `-- --no-opus`).
static func opus_available() -> bool:
	if not _opus_checked:
		_opus_checked = true
		_opus_ok = ClassDB.class_exists(&"OpusVoiceEncoder") \
			and not "--no-opus" in OS.get_cmdline_user_args()
	return _opus_ok


## "libopus 1.5.2" or "" when Opus isn't available.
static func opus_version() -> String:
	if not opus_available():
		return ""
	return ClassDB.class_call_static(&"OpusVoiceEncoder", &"get_opus_version")


static func codec_name(codec: int) -> String:
	return "Opus" if codec == CODEC_OPUS else "ADPCM"

const _INDEX_TABLE: PackedInt32Array = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]
const _STEP_TABLE: PackedInt32Array = [
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
	50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230,
	253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963,
	1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327,
	3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487,
	12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]


## Encodes mono samples in [-1, 1] into one packet.
static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var n := samples.size()
	var out := PackedByteArray()
	out.resize(HEADER_SIZE + (n + 1) / 2)
	var predictor := int(clampf(samples[0] if n > 0 else 0.0, -1.0, 1.0) * 32767.0)
	var index := _initial_index(samples)
	out.encode_s16(0, predictor)
	out[2] = index
	var step := _STEP_TABLE[index]
	for i in n:
		var sample := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		var diff := sample - predictor
		var nibble := 0
		if diff < 0:
			nibble = 8
			diff = -diff
		var temp_step := step
		if diff >= temp_step:
			nibble |= 4
			diff -= temp_step
		temp_step >>= 1
		if diff >= temp_step:
			nibble |= 2
			diff -= temp_step
		temp_step >>= 1
		if diff >= temp_step:
			nibble |= 1
		# Decode the nibble we just produced so encoder and decoder stay in sync.
		var diffq := step >> 3
		if nibble & 4: diffq += step
		if nibble & 2: diffq += step >> 1
		if nibble & 1: diffq += step >> 2
		predictor = clampi(predictor - diffq if nibble & 8 else predictor + diffq, -32768, 32767)
		index = clampi(index + _INDEX_TABLE[nibble], 0, 88)
		step = _STEP_TABLE[index]
		var byte_i := HEADER_SIZE + (i >> 1)
		if i & 1:
			out[byte_i] |= nibble << 4
		else:
			out[byte_i] = nibble
	return out


## Starting step size matched to the packet's first samples, so the encoder
## doesn't spend the start of every packet ramping up (packets are independent).
static func _initial_index(samples: PackedFloat32Array) -> int:
	var count := mini(samples.size() - 1, 16)
	if count <= 0:
		return 0
	var mean_diff := 0.0
	for i in count:
		mean_diff += absf(samples[i + 1] - samples[i])
	mean_diff = mean_diff / count * 32767.0
	var index := 0
	while index < 88 and _STEP_TABLE[index] < mean_diff:
		index += 1
	return index


## Decodes one packet back to mono samples in [-1, 1].
## `sample_count` limits the output (odd-length packets); -1 = all.
static func decode(packet: PackedByteArray, sample_count: int = -1) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if packet.size() < HEADER_SIZE:
		return out
	var n := (packet.size() - HEADER_SIZE) * 2
	if sample_count >= 0:
		n = mini(n, sample_count)
	out.resize(n)
	var predictor := packet.decode_s16(0)
	var index := clampi(packet[2], 0, 88)
	var step := _STEP_TABLE[index]
	for i in n:
		var byte := packet[HEADER_SIZE + (i >> 1)]
		var nibble := (byte >> 4) & 0xF if i & 1 else byte & 0xF
		var diffq := step >> 3
		if nibble & 4: diffq += step
		if nibble & 2: diffq += step >> 1
		if nibble & 1: diffq += step >> 2
		predictor = clampi(predictor - diffq if nibble & 8 else predictor + diffq, -32768, 32767)
		index = clampi(index + _INDEX_TABLE[nibble], 0, 88)
		step = _STEP_TABLE[index]
		out[i] = predictor / 32768.0
	return out
