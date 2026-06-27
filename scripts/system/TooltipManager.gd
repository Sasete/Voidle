extends CanvasLayer

var _panel:     PanelContainer
var _title_lbl: Label
var _body_lbl:  Label
var _orbitron:  Font
var _visible:   bool = false

func _ready() -> void:
	layer = 150
	_orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")

	_panel = PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.13, 0.96)
	s.border_width_left  = 1; s.border_width_right  = 1
	s.border_width_top   = 1; s.border_width_bottom = 1
	s.border_color       = Color(0.28, 0.35, 0.60, 0.55)
	s.corner_radius_top_left     = 5
	s.corner_radius_top_right    = 5
	s.corner_radius_bottom_left  = 5
	s.corner_radius_bottom_right = 5
	s.content_margin_left   = 10
	s.content_margin_right  = 10
	s.content_margin_top    = 7
	s.content_margin_bottom = 7
	_panel.add_theme_stylebox_override("panel", s)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size = Vector2(120, 0)
	_panel.visible = false

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	_title_lbl = Label.new()
	_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _orbitron: _title_lbl.add_theme_font_override("font", _orbitron)
	_title_lbl.add_theme_font_size_override("font_size", 10)
	_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_title_lbl)

	_body_lbl = Label.new()
	_body_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _orbitron: _body_lbl.add_theme_font_override("font", _orbitron)
	_body_lbl.add_theme_font_size_override("font_size", 8)
	_body_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.92))
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_body_lbl)

	add_child(_panel)

func _process(_delta: float) -> void:
	if not _visible:
		return
	var mouse := get_viewport().get_mouse_position()
	var vp    := get_viewport().get_visible_rect().size
	var pw: float = _panel.size.x if _panel.size.x > 10 else 160.0
	var ph: float = _panel.size.y if _panel.size.y > 10 else 48.0
	var pos := mouse + Vector2(10, -ph - 8.0)   # appear above cursor
	if pos.x + pw > vp.x:
		pos.x = vp.x - pw - 4.0
	if pos.x < 4.0:
		pos.x = 4.0
	if pos.y < 4.0:
		pos.y = mouse.y + 14.0   # flip below if too close to top
	_panel.position = pos

func show_tip(title: String, body: String) -> void:
	_title_lbl.text = title
	_body_lbl.text  = body
	_body_lbl.visible = not body.is_empty()
	_panel.visible  = true
	_visible        = true

func hide_tip() -> void:
	_panel.visible = false
	_visible       = false
