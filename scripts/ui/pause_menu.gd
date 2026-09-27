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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if _settings.visible:
			_settings.close() # Esc backs out of the settings first
		elif _panel.visible:
			close()
		else:
			open()
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
	%TeamButton.visible = Match.is_team_mode()
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
