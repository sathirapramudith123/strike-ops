// Opus voice codec for Godot (GDExtension): mono float PCM <-> Opus packets.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>

struct OpusEncoder;
struct OpusDecoder;

namespace godot {

// Encoder for one speaker. Stateful: keep one per voice stream.
class OpusVoiceEncoder : public RefCounted {
	GDCLASS(OpusVoiceEncoder, RefCounted)

	OpusEncoder *encoder = nullptr;
	int sample_rate = 16000;
	int bitrate = 24000;

protected:
	static void _bind_methods();

public:
	OpusVoiceEncoder() = default;
	~OpusVoiceEncoder() override;

	// sample_rate: 8000, 12000, 16000, 24000 or 48000. Returns OK or FAILED.
	int setup(int p_sample_rate = 16000, int p_bitrate = 24000, int p_expected_loss_percent = 10);
	// `pcm` must be one Opus frame: 2.5, 5, 10, 20, 40 or 60 ms of samples.
	// Returns an empty array on error.
	PackedByteArray encode(const PackedFloat32Array &p_pcm);
	void set_bitrate(int p_bitrate);
	int get_bitrate() const { return bitrate; }
	void reset();

	static String get_opus_version();
};

// Decoder for one speaker. Stateful: keep one per remote player.
class OpusVoiceDecoder : public RefCounted {
	GDCLASS(OpusVoiceDecoder, RefCounted)

	OpusDecoder *decoder = nullptr;
	int sample_rate = 16000;
	PackedFloat32Array scratch;

	PackedFloat32Array _decode(const uint8_t *p_data, int p_size, int p_frame_size, bool p_fec);

protected:
	static void _bind_methods();

public:
	OpusVoiceDecoder() = default;
	~OpusVoiceDecoder() override;

	int setup(int p_sample_rate = 16000);
	PackedFloat32Array decode(const PackedByteArray &p_packet);
	// The packet before `p_next_packet` was lost: rebuild it from the
	// forward-error-correction data carried in the next one.
	PackedFloat32Array decode_fec(const PackedByteArray &p_next_packet, int p_frame_size);
	// Packet loss concealment: plausible audio for a lost frame.
	PackedFloat32Array decode_lost(int p_frame_size);
	void reset();
};

} // namespace godot
