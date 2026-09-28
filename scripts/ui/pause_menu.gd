class_name PauseMenu
extends CanvasLayer
## In-game menu (Esc). The game keeps running underneath — this is a
## multiplayer shooter — only the local player's input is disabled.

var player: PlayerController

@onready var _panel: Control = %Panel
@onready var _box: Control = $Panel/Center
@onready var _settings: SettingsMenu = %SettingsMenu


func _ready() -> void:
	_panel.visible = false
	%SettingsButton.pressed.connect(func() -> void:
		_box.visible = false
		_settings.open())
	_settings.closed.connect(func() -> void:
		_box.visible = true
		%SettingsButton.grab_focus())
	%MainMenuButton.text = "Disconnect" if NetworkManager.is_online() else "Main menu"
	%ResumeButton.pressed.connect(close)
	%BugButton.pressed.connect(BugReport.open)
	%MainMenuButton.pressed.connect(_go_to_main_menu)
	%QuitButton.pressed.connect(get_tree().quit)
	%MuteAllCheck.toggled.connect(func(on: bool) -> void: VoiceChat.mute_all = on)
	for id: String in GameConfig.PRIMARY_WEAPONS:
		%LoadoutOption.add_item(GameConfig.PRIMARY_NAMES[id])
	%LoadoutOption.item_selected.connect(func(i: int) -> void:
		Match.request_loadout(GameConfig.PRIMARY_WEAPONS[i]))
	%TeamButton.pressed.connect(func() -> void:
		Match.request_team_switch()
		close())
	_build_bots_row()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if _settings.visible:
			_settings.close() # Esc backs out of the settings first
		elif _panel.visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif _panel.visible and not _settings.visible and event.is_action_pressed(&"ui_cancel") \
			and GamepadInput.is_pad_event(event):
		close() # controller B resumes
		get_viewport().set_input_as_handled()


func open() -> void:
	_panel.visible = true
	if Match.mode == GameConfig.Mode.BOMB:
		Match.bomb.request_interact(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player:
		player.input_enabled = false
	_build_mute_list()
	%LoadoutOption.select(maxi(GameConfig.PRIMARY_WEAPONS.find(SettingsManager.preferred_primary), 0))
	# Bomb Defusal guns are bought (X), not picked.
	%LoadoutOption.get_parent().visible = Match.mode != GameConfig.Mode.BOMB
	%TeamButton.visible = Match.is_team_mode()
	_bots_row.visible = multiplayer.is_server()
	_update_bots_label()
	%ResumeButton.grab_focus()


## One "Mute <name>" checkbox per other player in the match.
func _build_mute_list() -> void:
	%MuteAllCheck.set_pressed_no_signal(VoiceChat.mute_all)
	var list: VBoxContainer = %MuteList
	for child in list.get_children():
		child.queue_free()
	var level := get_parent() as Level
	if level == null:
		return
	for p: PlayerController in level.get_players():
		if p.is_local:
			continue
		var cb := CheckBox.new()
		cb.text = "Mute %s" % p.player_name
		cb.button_pressed = VoiceChat.muted.has(p.peer_id)
		var id := p.peer_id
		cb.toggled.connect(func(on: bool) -> void: VoiceChat.set_muted(id, on))
		list.add_child(cb)
	%MuteAllCheck.visible = NetworkManager.is_online()
	$Panel/Center/Box/VoiceTitle.visible = NetworkManager.is_online()


func close() -> void:
	if _settings.visible:
		_settings.close()
	_box.visible = true
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if player:
		player.input_enabled = true
	SettingsManager.save()


func _go_to_main_menu() -> void:
	SettingsManager.save()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkManager.leave()


# -----------------------------------------------------------------------------
# Training bots (the server / offline player): add or remove one at a time.
# -----------------------------------------------------------------------------

var _bots_row: HBoxContainer
var _bots_label: Label


func _build_bots_row() -> void:
	_bots_row = HBoxContainer.new()
	_bots_row.name = "BotsRow"
	_bots_label = Label.new()
	_bots_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bots_row.add_child(_bots_label)
	for step: int in [-1, 1]:
		var b := Button.new()
		b.text = "−" if step < 0 else "+"
		b.custom_minimum_size.x = 44
		b.pressed.connect(func() -> void:
			Match.bots.set_count(Match.bots.count() + step)
			_update_bots_label())
		_bots_row.add_child(b)
	var team_row: Node = %TeamButton
	team_row.get_parent().add_child(_bots_row)
	team_row.get_parent().move_child(_bots_row, team_row.get_index() + 1)


func _update_bots_label() -> void:
	if _bots_label:
		_bots_label.text = "Bots: %d (%s)" % [Match.bots.count(), BotManager.DIFFICULTY_NAMES[Match.bots.difficulty]]
