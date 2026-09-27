#include "opus_voice.h"

#include <opus.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>

using namespace godot;

static bool valid_rate(int p_rate) {
	return p_rate == 8000 || p_rate == 12000 || p_rate == 16000 || p_rate == 24000 || p_rate == 48000;
}

// ---------------------------------------------------------------------------
// Encoder
// ---------------------------------------------------------------------------

OpusVoiceEncoder::~OpusVoiceEncoder() {
	if (encoder) {
		opus_encoder_destroy(encoder);
	}
}

int OpusVoiceEncoder::setup(int p_sample_rate, int p_bitrate, int p_expected_loss_percent) {
	ERR_FAIL_COND_V_MSG(!valid_rate(p_sample_rate), FAILED, "Opus: unsupported sample rate.");
	if (encoder) {
		opus_encoder_destroy(encoder);
		encoder = nullptr;
	}
	int err = OPUS_OK;
	encoder = opus_encoder_create(p_sample_rate, 1, OPUS_APPLICATION_VOIP, &err);
	ERR_FAIL_COND_V_MSG(err != OPUS_OK || !encoder, FAILED, String("Opus encoder: ") + opus_strerror(err));
	sample_rate = p_sample_rate;
	set_bitrate(p_bitrate);
	opus_encoder_ctl(encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
	opus_encoder_ctl(encoder, OPUS_SET_COMPLEXITY(5)); // cheap enough for low-end CPUs
	opus_encoder_ctl(encoder, OPUS_SET_VBR(1));
	opus_encoder_ctl(encoder, OPUS_SET_DTX(0)); // silence is not sent at all anyway
	// In-band FEC: each packet also carries a low-bitrate copy of the previous one.
	opus_encoder_ctl(encoder, OPUS_SET_INBAND_FEC(p_expected_loss_percent > 0 ? 1 : 0));
	opus_encoder_ctl(encoder, OPUS_SET_PACKET_LOSS_PERC(CLAMP(p_expected_loss_percent, 0, 100)));
	return OK;
}

PackedByteArray OpusVoiceEncoder::encode(const PackedFloat32Array &p_pcm) {
	PackedByteArray out;
	ERR_FAIL_NULL_V_MSG(encoder, out, "Opus encoder: call setup() first.");
	const int frame = int(p_pcm.size());
	const int unit = sample_rate / 400; // 2.5 ms
	ERR_FAIL_COND_V_MSG(frame % unit != 0 || (frame / unit != 1 && frame / unit != 2 && frame / unit != 4 &&
			frame / unit != 8 && frame / unit != 16 && frame / unit != 24),
			out, "Opus encoder: frame must be 2.5/5/10/20/40/60 ms.");
	out.resize(1275); // max Opus packet
	const opus_int32 bytes = opus_encode_float(encoder, p_pcm.ptr(), frame, out.ptrw(), int(out.size()));
	if (bytes < 0) {
		ERR_PRINT(String("Opus encode: ") + opus_strerror(bytes));
		return PackedByteArray();
	}
	out.resize(bytes);
	return out;
}

void OpusVoiceEncoder::set_bitrate(int p_bitrate) {
	bitrate = CLAMP(p_bitrate, 6000, 64000);
	if (encoder) {
		opus_encoder_ctl(encoder, OPUS_SET_BITRATE(bitrate));
	}
}

void OpusVoiceEncoder::reset() {
	if (encoder) {
		opus_encoder_ctl(encoder, OPUS_RESET_STATE);
	}
}

String OpusVoiceEncoder::get_opus_version() {
	return String(opus_get_version_string());
}

void OpusVoiceEncoder::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "sample_rate", "bitrate", "expected_loss_percent"), &OpusVoiceEncoder::setup, DEFVAL(16000), DEFVAL(24000), DEFVAL(10));
	ClassDB::bind_method(D_METHOD("encode", "pcm"), &OpusVoiceEncoder::encode);
	ClassDB::bind_method(D_METHOD("set_bitrate", "bitrate"), &OpusVoiceEncoder::set_bitrate);
	ClassDB::bind_method(D_METHOD("get_bitrate"), &OpusVoiceEncoder::get_bitrate);
	ClassDB::bind_method(D_METHOD("reset"), &OpusVoiceEncoder::reset);
	ClassDB::bind_static_method("OpusVoiceEncoder", D_METHOD("get_opus_version"), &OpusVoiceEncoder::get_opus_version);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "bitrate"), "set_bitrate", "get_bitrate");
}

// ---------------------------------------------------------------------------
// Decoder
// ---------------------------------------------------------------------------

OpusVoiceDecoder::~OpusVoiceDecoder() {
	if (decoder) {
		opus_decoder_destroy(decoder);
	}
}

int OpusVoiceDecoder::setup(int p_sample_rate) {
	ERR_FAIL_COND_V_MSG(!valid_rate(p_sample_rate), FAILED, "Opus: unsupported sample rate.");
	if (decoder) {
		opus_decoder_destroy(decoder);
		decoder = nullptr;
	}
	int err = OPUS_OK;
	decoder = opus_decoder_create(p_sample_rate, 1, &err);
	ERR_FAIL_COND_V_MSG(err != OPUS_OK || !decoder, FAILED, String("Opus decoder: ") + opus_strerror(err));
	sample_rate = p_sample_rate;
	scratch.resize(sample_rate * 120 / 1000); // longest Opus packet: 120 ms
	return OK;
}

PackedFloat32Array OpusVoiceDecoder::_decode(const uint8_t *p_data, int p_size, int p_frame_size, bool p_fec) {
	PackedFloat32Array out;
	ERR_FAIL_NULL_V_MSG(decoder, out, "Opus decoder: call setup() first.");
	const int max_frame = int(scratch.size());
	const int frame = p_frame_size > 0 ? MIN(p_frame_size, max_frame) : max_frame;
	const int n = opus_decode_float(decoder, p_data, p_size, scratch.ptrw(), frame, p_fec ? 1 : 0);
	if (n < 0) {
		// Corrupt packet (or a malicious one): drop it, never crash.
		return out;
	}
	out.resize(n);
	memcpy(out.ptrw(), scratch.ptr(), sizeof(float) * n);
	return out;
}

PackedFloat32Array OpusVoiceDecoder::decode(const PackedByteArray &p_packet) {
	if (p_packet.is_empty()) {
		return PackedFloat32Array();
	}
	return _decode(p_packet.ptr(), int(p_packet.size()), 0, false);
}

PackedFloat32Array OpusVoiceDecoder::decode_fec(const PackedByteArray &p_next_packet, int p_frame_size) {
	if (p_next_packet.is_empty() || p_frame_size <= 0) {
		return decode_lost(p_frame_size);
	}
	return _decode(p_next_packet.ptr(), int(p_next_packet.size()), p_frame_size, true);
}

PackedFloat32Array OpusVoiceDecoder::decode_lost(int p_frame_size) {
	if (p_frame_size <= 0) {
		return PackedFloat32Array();
	}
	return _decode(nullptr, 0, p_frame_size, false);
}

void OpusVoiceDecoder::reset() {
	if (decoder) {
		opus_decoder_ctl(decoder, OPUS_RESET_STATE);
	}
}

void OpusVoiceDecoder::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "sample_rate"), &OpusVoiceDecoder::setup, DEFVAL(16000));
	ClassDB::bind_method(D_METHOD("decode", "packet"), &OpusVoiceDecoder::decode);
	ClassDB::bind_method(D_METHOD("decode_fec", "next_packet", "frame_size"), &OpusVoiceDecoder::decode_fec);
	ClassDB::bind_method(D_METHOD("decode_lost", "frame_size"), &OpusVoiceDecoder::decode_lost);
	ClassDB::bind_method(D_METHOD("reset"), &OpusVoiceDecoder::reset);
}
