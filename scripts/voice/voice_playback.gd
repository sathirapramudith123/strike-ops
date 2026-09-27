class_name VoicePlayback
extends Node
## Plays one remote speaker's voice. Decoded packets go into a small jitter
## buffer; playback starts once PREBUFFER is queued and the buffer is trimmed
## if it grows too long, so latency stays low.
##
## Team / all-chat plays through a 2D player; proximity chat through a 3D
## player attached to the speaker's head (distance falloff + direction).

const PREBUFFER := 0.06 # seconds queued before playback starts
const MAX_BUFFER := 0.3 # drop the oldest audio above this
const SPEAKING_HOLD := 0.3 # "is speaking" stays true this long after the last packet
const PROXIMITY_UNIT_SIZE := 6.0
const PROXIMITY_MAX_DISTANCE := 35.0

var peer_id: int = 0
## Stats (used by tests and the debug overlay).
var packets_received: int = 0
var samples_decoded: int = 0
var last_packet_time: float = -100.0
## Last decoded samples (kept small; used by tests to verify the signal).
var last_decoded := PackedFloat32Array()
var bytes_received: int = 0
## Codec of the last packet (VoiceCodec.CODEC_*), -1 = none yet.
var last_codec: int:
	get: return _decoder.last_codec
## Lost packets rebuilt by Opus FEC / concealment.
var concealed: int:
	get: return _decoder.concealed

var _queue := PackedFloat32Array()
var _started: bool = false
var _player_2d: AudioStreamPlayer
var _player_3d: AudioStreamPlayer3D
var _proximity: bool = false
var _last_seq: int = -1
var _decoder := VoiceDecoder.new()


func _ready() -> void:
	_player_2d = _make_2d()
	add_child(_player_2d)


func is_speaking() -> bool:
	return Time.get_ticks_msec() / 1000.0 - last_packet_time < SPEAKING_HOLD


func push_packet(seq: int, channel: int, packet: PackedByteArray, sample_count: int) -> void:
	# Drop duplicates / late packets (unreliable_ordered can still skip).
	var now := Time.get_ticks_msec() / 1000.0
	var lost := 0
	if _last_seq >= 0:
		var delta := _seq_delta(seq, _last_seq)
		if delta <= 0:
			return
		# A gap while talking = lost packets (a gap between sentences is silence).
		if now - last_packet_time < 0.25:
			lost = delta - 1
	_last_seq = seq
	var samples := _decoder.decode(packet, sample_count, lost)
	packets_received += 1
	bytes_received += packet.size()
	samples_decoded += samples.size()
	last_packet_time = Time.get_ticks_msec() / 1000.0
	# The packet's own audio (without any concealed audio before it).
	last_decoded = samples.slice(maxi(samples.size() - sample_count, 0))
	_set_proximity(channel == VoiceChat.Channel.PROXIMITY)
	_queue.append_array(samples)
	var max_samples := int(MAX_BUFFER * VoiceCodec.SAMPLE_RATE)
	if _queue.size() > max_samples:
		_queue = _queue.slice(_queue.size() - max_samples)


## Re-attaches the 3D player when the speaker's player node changes (respawn/spawn).
func attach_to(head: Node3D) -> void:
	if _player_3d and _player_3d.get_parent() != head:
		_player_3d.get_parent().remove_child(_player_3d)
		_player_3d.queue_free()
		_player_3d = null
	if head and _player_3d == null:
		_player_3d = _make_3d()
		head.add_child(_player_3d)


func _process(_delta: float) -> void:
	if not _started:
		if _queue.size() < int(PREBUFFER * VoiceCodec.SAMPLE_RATE):
			return
		_started = true
	var active: Node = _player_3d if _proximity and _player_3d else _player_2d
	if not active.playing:
		active.play()
	var playback := active.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var n := mini(playback.get_frames_available(), _queue.size())
	if n > 0:
		var frames := PackedVector2Array()
		frames.resize(n)
		for i in n:
			frames[i] = Vector2(_queue[i], _queue[i])
		playback.push_buffer(frames)
		_queue = _queue.slice(n)
	if _queue.is_empty() and not is_speaking():
		_started = false # re-prebuffer on the next burst


func _exit_tree() -> void:
	if _player_3d and is_instance_valid(_player_3d):
		_player_3d.queue_free()


func _set_proximity(on: bool) -> void:
	if on == _proximity:
		return
	_proximity = on
	_player_2d.stop()
	if _player_3d:
		_player_3d.stop()


func _make_stream() -> AudioStreamGenerator:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = VoiceCodec.SAMPLE_RATE
	gen.buffer_length = 0.5
	return gen


func _make_2d() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _make_stream()
	p.bus = &"Voice"
	return p


func _make_3d() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _make_stream()
	p.bus = &"Voice"
	p.unit_size = PROXIMITY_UNIT_SIZE
	p.max_distance = PROXIMITY_MAX_DISTANCE
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	return p


## Signed difference for 16-bit wrapping sequence numbers.
static func _seq_delta(a: int, b: int) -> int:
	var d := (a - b) & 0xFFFF
	return d - 0x10000 if d > 0x7FFF else d
