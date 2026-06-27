## Global HUD overlay — shows credits and other persistent info across all scenes.
extends CanvasLayer

var _credits_lbl: Label
## Current displayed value (tweened, may lag behind GameState.credits)
var _credits_display: float = 0.0
var _credits_tween: Tween = null
var _orbitron: Font
## The credits panel node — exposed so PlanetaryView can read its screen height for toast offset.
var credits_panel: PanelContainer = null

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
	credits_panel = panel

	_credits_display = GameState.credits

	GameState.credits_changed.connect(_on_credits_changed)

func _on_credits_changed(new_val: float) -> void:
	if not is_instance_valid(_credits_lbl):
		return

	var old_val := _credits_display
	var gained  := new_val > old_val

	# Kill any running tween so we start fresh from the current displayed value
	if _credits_tween and _credits_tween.is_valid():
		_credits_tween.kill()

	_credits_tween = create_tween()

	# Briefly flash the label colour to signal gain / loss
	var flash_col := Color(0.55, 1.0, 0.35) if gained else Color(1.0, 0.55, 0.25)
	_credits_tween.tween_property(_credits_lbl, "theme_override_colors/font_color",
		flash_col, 0.12).set_ease(Tween.EASE_OUT)
	_credits_tween.parallel().tween_method(
		func(v: float) -> void:
			_credits_display = v
			if is_instance_valid(_credits_lbl):
				_credits_lbl.text = fmt_credits(v),
		old_val, new_val, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_credits_tween.tween_property(_credits_lbl, "theme_override_colors/font_color",
		Color(1.0, 0.92, 0.55), 0.3).set_ease(Tween.EASE_IN)
