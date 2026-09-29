class_name LobbyLogo
extends HBoxContainer
## The STRIKE OPS word mark: "STRIKE" in white, "OPS" in the accent yellow.

const ACCENT := Color(0.98, 0.78, 0.18)


static func make(font_size: int = 32) -> LobbyLogo:
	var logo := LobbyLogo.new()
	logo.add_theme_constant_override(&"separation", int(font_size * 0.3))
	for part: Array in [["STRIKE", Color.WHITE], ["OPS", ACCENT]]:
		var l := Label.new()
		l.text = part[0]
		l.add_theme_font_size_override(&"font_size", font_size)
		l.add_theme_color_override(&"font_color", part[1])
		l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.5))
		l.add_theme_constant_override(&"outline_size", maxi(2, int(font_size / 10.0)))
		logo.add_child(l)
	return logo
