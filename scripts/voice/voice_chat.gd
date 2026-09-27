extends Node
## In-game voice chat (autoload: VoiceChat).
##
## Capture:  AudioStreamMicrophone → "MicCapture" bus (muted, AudioEffectCapture)
##           → VoiceProcessor (resample 16 kHz, high-pass, gate, AGC) → 20 ms frames
## Send:     push-to-talk (V = team, B = proximity) or voice activation;
##           2 frames per packet, VoiceCodec (ADPCM), ENet channel 2, via the server
## Relay:    the server forwards each packet only to eligible listeners
##           (team / all / players within PROXIMITY_RANGE)
## Receive:  one VoicePlayback per speaker (jitter buffer, 2D or 3D positional)
##
## Privacy: voice is only ever held in memory for playback — never recorded or
## stored — and can be switched off completely in Settings.

signal speaking_changed(peer_id: int, speaking: bool)
signal transmitting_changed(transmitting: bool, channel: Channel)

enum Channel { TEAM, PROXIMITY, ALL }

const FRAMES_PER_PACKET := 2 # 2 × 20 ms = 40 ms per packet
const PROXIMITY_RANGE := 35.0
const VAD_HANGOVER := 0.4 # keep transmitting this long after the voice drops
const MAX_PACKET_BYTES := 1024
const MAX_PACKETS_PER_SECOND := 40

## True while this client is sending voice.
var is_transmitting: bool = false
var transmit_channel: Channel = Channel.TEAM
## Microphone level 0..1 after processing (settings meter).
var input_level: float = 0.0
## Plays your own processed voice back to you (mic test in Settings).
var loopback: bool = false:
	set(value):
		loopback = value
		_update_capture_state()
## Keep the microphone running outside a match (Settings panel open).
var monitoring: bool = false:
	set(value):
		monitoring = value
		_update_capture_state()
## peer_id -> true for players you muted locally.
var muted: Dictionary = {}
var mute_all: bool = false

var processor := VoiceProcessor.new()
var packets_sent: int = 0

var _mic_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _frame := PackedFloat32Array()
var _pending := PackedFloat32Array() # processed samples waiting to fill a packet
var _test_input := PackedFloat32Array() # injected samples (tests)
var _vad_timer: float = 0.0
var _seq: int = 0
var _playbacks: Dictionary = {} # peer_id -> VoicePlayback
var _speaking: Dictionary = {} # peer_id -> bool (last emitted state)
var _rate_counters: Dictionary = {} # server: peer_id -> [window_start, count]
var _state_timer: float = 0.0


func _ready() -> void:
	var bus := AudioServer.get_bus_index(&"MicCapture")
	if bus >= 0:
		_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = &"MicCapture"
	add_child(_mic_player)
	SettingsManager.voice_changed.connect(_update_capture_state)
	_update_capture_state()


func _process(delta: float) -> void:
	# Cheap poll: start/stop the mic when entering/leaving a match.
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = 0.5
		_update_capture_state()
	_read_microphone()
	_update_transmit_state(delta)
	_update_speaking_flags()


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

func is_speaking(peer_id: int) -> bool:
	if peer_id == multiplayer.get_unique_id():
		return is_transmitting
	var pb: VoicePlayback = _playbacks.get(peer_id)
	return pb != null and pb.is_speaking()


func set_muted(peer_id: int, value: bool) -> void:
	if value:
		muted[peer_id] = true
	else:
		muted.erase(peer_id)


func get_playback(peer_id: int) -> VoicePlayback:
	return _playbacks.get(peer_id)


## Tests: feed 16 kHz samples through the pipeline as if they came from the mic.
func inject_test_audio(samples: PackedFloat32Array) -> void:
	_test_input.append_array(samples)


## Server-side relay rules. Returns the peer ids that should hear `sender_id`.
static func recipients_for(sender_id: int, channel: Channel, players: Array, teams: Dictionary = {}) -> Array[int]:
	var result: Array[int] = []
	var sender: PlayerController = null
	for p: PlayerController in players:
		if p.peer_id == sender_id:
			sender = p
	for p: PlayerController in players:
		if p.peer_id == sender_id:
			continue
		match channel:
			Channel.PROXIMITY:
				if sender and p.global_position.distance_to(sender.global_position) <= PROXIMITY_RANGE:
					result.append(p.peer_id)
			Channel.TEAM:
				# In free-for-all everyone has team -1, so "team" reaches everyone.
				if teams.get(p.peer_id, -1) == teams.get(sender_id, -1):
					result.append(p.peer_id)
			_:
				result.append(p.peer_id)
	return result


# -----------------------------------------------------------------------------
# Capture & send
# -----------------------------------------------------------------------------

func _in_match() -> bool:
	return get_tree().current_scene is Level


func _update_capture_state() -> void:
	if _mic_player == null:
		return
	var want := SettingsManager.voice_enabled and (monitoring or loopback or \
		(_in_match() and NetworkManager.is_online() and not NetworkManager.is_dedicated()))
	if want and not _mic_player.playing:
		_mic_player.play()
		if _capture:
			_capture.clear_buffer()
	elif not want and _mic_player.playing:
		_mic_player.stop()
	processor.mic_gain = SettingsManager.mic_volume
	processor.processing_enabled = SettingsManager.voice_processing


func _read_microphone() -> void:
	var input := PackedFloat32Array()
	if _capture and _mic_player.playing:
		var available := _capture.get_frames_available()
		if available > 0:
			var stereo := _capture.get_buffer(available)
			input.resize(stereo.size())
			for i in stereo.size():
				input[i] = (stereo[i].x + stereo[i].y) * 0.5
			processor.set_input_rate(AudioServer.get_mix_rate())
			input = processor.resample(input)
	if not _test_input.is_empty():
		input.append_array(_test_input)
		_test_input.clear()
	if input.is_empty():
		return

	_frame.append_array(input)
	while _frame.size() >= VoiceProcessor.FRAME_SIZE:
		var frame := _frame.slice(0, VoiceProcessor.FRAME_SIZE)
		_frame = _frame.slice(VoiceProcessor.FRAME_SIZE)
		processor.process_frame(frame)
		input_level = processor.level
		if processor.level > SettingsManager.voice_activation_threshold:
			_vad_timer = VAD_HANGOVER
		if is_transmitting or loopback:
			_pending.append_array(frame)
		if _pending.size() >= VoiceProcessor.FRAME_SIZE * FRAMES_PER_PACKET:
			_flush_packet()


func _update_transmit_state(delta: float) -> void:
	_vad_timer = maxf(_vad_timer - delta, 0.0)
	var channel := Channel.TEAM
	var talk := false
	# Offline there is nobody to talk to — only the mic test (loopback) transmits.
	if SettingsManager.voice_enabled and ((_in_match() and NetworkManager.is_online()) or loopback):
		if Input.is_action_pressed(&"push_to_talk_proximity") and SettingsManager.proximity_chat_enabled:
			talk = true
			channel = Channel.PROXIMITY
		elif Input.is_action_pressed(&"push_to_talk_team"):
			talk = true
		elif SettingsManager.voice_mode == SettingsManager.VoiceMode.VOICE_ACTIVATION and _vad_timer > 0.0:
			talk = true
	if talk != is_transmitting or channel != transmit_channel:
		if not talk and not _pending.is_empty():
			_flush_packet() # send the tail of the sentence
		is_transmitting = talk
		transmit_channel = channel
		transmitting_changed.emit(talk, channel)


func _flush_packet() -> void:
	var samples := _pending
	_pending = PackedFloat32Array()
	var packet := VoiceCodec.encode(samples)
	_seq = (_seq + 1) & 0xFFFF
	if loopback:
		_receive(multiplayer.get_unique_id(), _seq, Channel.ALL, packet, samples.size())
	if not is_transmitting or not NetworkManager.is_online():
		return
	packets_sent += 1
	if multiplayer.is_server():
		_relay(multiplayer.get_unique_id(), _seq, transmit_channel, packet, samples.size())
	else:
		_voice_up.rpc_id(1, _seq, transmit_channel, packet, samples.size())


# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered", 2) # channel 2 = NetworkManager.CHANNEL_VOICE
func _voice_up(seq: int, channel: int, packet: PackedByteArray, sample_count: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if packet.size() > MAX_PACKET_BYTES or channel < 0 or channel > Channel.ALL or not _rate_ok(sender):
		return
	_relay(sender, seq, channel, packet, clampi(sample_count, 0, packet.size() * 2))


@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _voice_down(sender_id: int, seq: int, channel: int, packet: PackedByteArray, sample_count: int) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	_receive(sender_id, seq, channel, packet, sample_count)


## Server: forward a packet to everyone who should hear it.
func _relay(sender_id: int, seq: int, channel: int, packet: PackedByteArray, sample_count: int) -> void:
	var level := get_tree().current_scene as Level
	if level == null:
		return
	var ready_ids := NetworkManager.ready_peer_ids()
	for id: int in recipients_for(sender_id, channel as Channel, level.get_players(), Match.team_map()):
		if id == 1:
			if not NetworkManager.is_dedicated():
				_receive(sender_id, seq, channel, packet, sample_count)
		elif id in ready_ids:
			_voice_down.rpc_id(id, sender_id, seq, channel, packet, sample_count)


func _receive(sender_id: int, seq: int, channel: int, packet: PackedByteArray, sample_count: int) -> void:
	if not SettingsManager.voice_enabled or mute_all or muted.has(sender_id):
		return
	var pb: VoicePlayback = _playbacks.get(sender_id)
	if pb == null or not is_instance_valid(pb):
		pb = VoicePlayback.new()
		pb.peer_id = sender_id
		pb.name = "Voice_%d" % sender_id
		add_child(pb)
		_playbacks[sender_id] = pb
	var level := get_tree().current_scene as Level
	var speaker := level.get_player(sender_id) if level else null
	pb.attach_to(speaker.head if speaker else null)
	pb.push_packet(seq, channel, packet, sample_count)


func _rate_ok(peer_id: int) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var c: Array = _rate_counters.get(peer_id, [now, 0])
	if now - c[0] >= 1.0:
		c = [now, 0]
	c[1] += 1
	_rate_counters[peer_id] = c
	return c[1] <= MAX_PACKETS_PER_SECOND


func _update_speaking_flags() -> void:
	for id: int in _playbacks.keys():
		var pb: VoicePlayback = _playbacks[id]
		if not is_instance_valid(pb):
			_playbacks.erase(id)
			continue
		var now_speaking := pb.is_speaking()
		if _speaking.get(id, false) != now_speaking:
			_speaking[id] = now_speaking
			speaking_changed.emit(id, now_speaking)
		# Forget speakers that left the match.
		var level := get_tree().current_scene as Level
		if not now_speaking and (level == null or level.get_player(id) == null) \
				and id != multiplayer.get_unique_id():
			pb.queue_free()
			_playbacks.erase(id)
			_speaking.erase(id)
