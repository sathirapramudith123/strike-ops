class_name BuyMenu
extends Control
## Bomb Defusal buy menu (X): guns, armour and grenades with their prices.
## Open near your team's spawn during the freeze time and the first
## Economy.BUY_TIME seconds of a round; it closes by itself when that ends.
## Click an item (or pick it with a controller) to buy it — the server checks
## money, time and place (see Economy). X or Esc closes it.

const BUY_ACTION := &"buy_menu"

var player: PlayerController

var _title: Label
var _status: Label
var _buttons: Dictionary = {} # item id -> Button
var _refresh_timer := 0.0


func _ready() -> void:
	name = "BuyMenu"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.08, 0.92)
	style.border_color = Color(1, 0.85, 0.4, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override(&"panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	panel.add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override(&"font_size", 24)
	_title.add_theme_color_override(&"font_color", Color(1, 0.9, 0.55))
	box.add_child(_title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 16)
	box.add_child(columns)
	for c in Economy.MENU.size():
		var col := VBoxContainer.new()
		col.custom_minimum_size.x = 250
		col.add_theme_constant_override(&"separation", 6)
		columns.add_child(col)
		var head := Label.new()
		head.text = Economy.MENU_TITLES[c]
		head.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.6))
		col.add_child(head)
		for item: String in Economy.MENU[c]:
			var b := Button.new()
			b.name = "Buy_" + item
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size.y = 38
			b.pressed.connect(_buy.bind(item))
			col.add_child(b)
			_buttons[item] = b

	_status = Label.new()
	_status.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.7))
	box.add_child(_status)


func _process(delta: float) -> void:
	if not visible:
		return
	# Buy time over, walked out of the buy zone, died, round ended…
	if player == null or Economy.buy_block_reason(player) != "":
		close()
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = 0.2
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(BUY_ACTION):
		if visible:
			close()
		else:
			try_open()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Esc / controller B close the menu (before the pause menu sees them).
	if visible and (event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


## Opens the menu if the local player may buy now; returns whether it did.
## Otherwise tells them why not.
func try_open() -> bool:
	if player == null or not player.input_enabled or not Economy.is_active():
		return false
	var reason := Economy.buy_block_reason(player)
	if reason != "":
		Match.economy.buy_refused.emit(reason)
		return false
	visible = true
	player.input_enabled = false
	if Match.mode == GameConfig.Mode.BOMB:
		Match.bomb.request_interact(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = "Click to buy · %s or Esc to close" % SettingsManager.prompt_text(BUY_ACTION)
	refresh()
	var first := _first_enabled()
	if first and GamepadInput.using_pad:
		first.grab_focus()
	return true


func close() -> void:
	if not visible:
		return
	visible = false
	if player:
		player.input_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Prices, money and which items can be bought.
func refresh() -> void:
	if player == null:
		return
	var money := Economy.money_of(player.peer_id)
	_title.text = "Buy   $%d   ·   %ds left" % [money, ceili(Economy.buy_time_left())]
	for item: String in _buttons:
		var b: Button = _buttons[item]
		var price := Economy.price_of(item, player)
		var why := Economy.item_block_reason(item, player)
		if why == "" and price > money:
			why = "Not enough money"
		b.text = "%s   $%d" % [Economy.ITEMS[item].name, price]
		b.disabled = why != ""
		b.tooltip_text = why


func _buy(item: String) -> void:
	Match.economy.request_buy(item)
	# The server's answer (money, gear) arrives shortly; refresh then.
	_refresh_timer = 0.1


func _first_enabled() -> Button:
	for item: String in _buttons:
		if not (_buttons[item] as Button).disabled:
			return _buttons[item]
	return null
