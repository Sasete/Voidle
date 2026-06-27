## Global HUD overlay — shows credits and other persistent info across all scenes.
extends CanvasLayer

var _credits_lbl: Label
var _orbitron: Font

static func fmt_credits(val: float) -> String:
	if val >= 1_000_000_000.0:
		return "%.2fb cr" % (val / 1_000_000_000.0)
	elif val >= 1_000_000.0:
		return "%.2fm cr" % (val / 1_000_000.0)
	elif val >= 1_000.0:
		return "%.1fk cr" % (val / 1_000.0)
	return "%.0f cr" % val

func _ready() -> void:
	layer = 120
	_orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")

	var panel := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color    = Color(0.05, 0.06, 0.11, 0.82)
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_color = Color(0.25, 0.32, 0.55, 0.35)
	s.corner_radius_top_left  = 6
	s.corner_radius_top_right = 6
	s.content_margin_left   = 12
	s.content_margin_right  = 12
	s.content_margin_top    = 4
	s.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", s)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	# Credit icon
	var icon := Label.new()
	icon.text = "◈"
	if _orbitron: icon.add_theme_font_override("font", _orbitron)
	icon.add_theme_font_size_override("font_size", 11)
	icon.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)

	_credits_lbl = Label.new()
	_credits_lbl.text = fmt_credits(GameState.credits)
	if _orbitron: _credits_lbl.add_theme_font_override("font", _orbitron)
	_credits_lbl.add_theme_font_size_override("font_size", 11)
	_credits_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_credits_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_credits_lbl)

	# Anchor bottom-left
	panel.anchor_left   = 0.0
	panel.anchor_right  = 0.0
	panel.anchor_top    = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	panel.offset_left   = 12.0
	panel.offset_bottom = -12.0

	add_child(panel)

	GameState.credits_changed.connect(_on_credits_changed)

func _on_credits_changed(val: float) -> void:
	if _credits_lbl:
		_credits_lbl.text = fmt_credits(val)
