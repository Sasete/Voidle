extends CanvasLayer

var _panel:      PanelContainer
var _title_lbl:  Label
var _body_lbl:   RichTextLabel
var _cost_lbl:   Label
var _sep:        Control
var _spacer:     Control
var _orbitron:   Font
var _visible:    bool  = false

var _sub_panel:  PanelContainer
var _sub_lbl:    RichTextLabel
var _hide_timer: float = 0.0

func _ready() -> void:
	layer = 300
	_orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")

	_panel = PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.13, 0.96)
	s.border_width_left  = 1; s.border_width_right  = 1
	s.border_width_top   = 1; s.border_width_bottom = 1
	s.border_color       = Color(0.28, 0.35, 0.60, 0.55)
	s.corner_radius_top_left     = 5; s.corner_radius_top_right    = 5
	s.corner_radius_bottom_left  = 5; s.corner_radius_bottom_right = 5
	s.content_margin_left   = 12; s.content_margin_right  = 12
	s.content_margin_top    = 8;  s.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", s)
	_panel.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_panel.custom_minimum_size   = Vector2(0, 0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
	_panel.visible = false

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel.add_child(vbox)

	_title_lbl = Label.new()
	_title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _orbitron: _title_lbl.add_theme_font_override("font", _orbitron)
	_title_lbl.add_theme_font_size_override("font_size", 11)
	_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_title_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	vbox.add_child(_title_lbl)

	_body_lbl = RichTextLabel.new()
	_body_lbl.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	_body_lbl.bbcode_enabled = true
	_body_lbl.fit_content    = true
	_body_lbl.scroll_active  = false
	_body_lbl.add_theme_font_size_override("normal_font_size", 9)
	_body_lbl.add_theme_color_override("default_color", Color(0.72, 0.78, 0.92))
	_body_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_body_lbl.custom_minimum_size = Vector2(0, 0)
	_body_lbl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	vbox.add_child(_body_lbl)

	# Spacer pushes cost to the bottom
	_spacer = Control.new()
	_spacer.custom_minimum_size = Vector2(0, 4)
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spacer.visible = false
	vbox.add_child(_spacer)

	# Cost header row: "COST ————"
	_sep = HBoxContainer.new()
	_sep.add_theme_constant_override("separation", 6)
	_sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sep.visible = false
	var cost_hdr := Label.new()
	cost_hdr.text = "COST"
	if _orbitron: cost_hdr.add_theme_font_override("font", _orbitron)
	cost_hdr.add_theme_font_size_override("font_size", 7)
	cost_hdr.add_theme_color_override("font_color", Color(0.45, 0.50, 0.70))
	cost_hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sep.add_child(cost_hdr)
	vbox.add_child(_sep)

	_cost_lbl = Label.new()
	_cost_lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	if _orbitron: _cost_lbl.add_theme_font_override("font", _orbitron)
	_cost_lbl.add_theme_font_size_override("font_size", 11)
	_cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	_cost_lbl.autowrap_mode         = TextServer.AUTOWRAP_OFF
	_cost_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	_cost_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_cost_lbl.visible = false
	vbox.add_child(_cost_lbl)

	# --- Secondary Tooltip Panel ---
	_sub_panel = PanelContainer.new()
	var sub_s := StyleBoxFlat.new()
	sub_s.bg_color = Color(0.12, 0.14, 0.20, 0.95)
	sub_s.border_width_left = 1; sub_s.border_width_right = 1
	sub_s.border_width_top = 1; sub_s.border_width_bottom = 1
	sub_s.border_color = Color(0.4, 0.45, 0.6, 0.6)
	sub_s.corner_radius_top_left = 4; sub_s.corner_radius_top_right = 4
	sub_s.corner_radius_bottom_left = 4; sub_s.corner_radius_bottom_right = 4
	sub_s.content_margin_left = 8; sub_s.content_margin_right = 8
	sub_s.content_margin_top = 6; sub_s.content_margin_bottom = 6
	_sub_panel.add_theme_stylebox_override("panel", sub_s)
	_sub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_sub_panel.visible = false
	
	_sub_lbl = RichTextLabel.new()
	_sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_lbl.bbcode_enabled = true
	_sub_lbl.fit_content = true
	_sub_lbl.scroll_active = false
	_sub_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_sub_lbl.add_theme_font_size_override("normal_font_size", 9)
	_sub_lbl.add_theme_color_override("default_color", Color(0.8, 0.85, 0.9))
	_sub_lbl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sub_panel.add_child(_sub_lbl)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_panel)
	hbox.add_child(_sub_panel)
	
	add_child(hbox)

func _process(delta: float) -> void:
	if _hide_timer > 0.0:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			_panel.get_parent().visible = false
			_panel.visible = false
			_sub_panel.visible = false
			_visible       = false
		return
	if not _visible:
		return
	# get_combined_minimum_size() is synchronous — no frame delay needed
	var root_node := _panel.get_parent() as Control
	# Make sure _panel is visible so it contributes to size
	_panel.visible = true
	var sz: Vector2 = root_node.get_combined_minimum_size()
	var pw: float = sz.x
	var ph: float = sz.y
	if pw <= 1.0 or ph <= 1.0:
		return
	var mouse := get_viewport().get_mouse_position()
	var vp    := get_viewport().get_visible_rect().size
	var pos := mouse + Vector2(10, -ph - 8.0)
	if pos.x + pw > vp.x:
		# Flip to the left of the mouse so it doesn't block clicks!
		pos.x = mouse.x - pw - 10.0
	if pos.x < 4.0:       pos.x = 4.0
	if pos.y < 4.0:       pos.y = mouse.y + 14.0
	root_node.position = pos
	root_node.visible  = true

## Show a tooltip.
## body: String or Array — Array elements may be String or ImageTexture (rendered inline).
## cost: String, Array[String], or Array[Variant] mixing strings and textures.
func show_tip(title: String, body = "", cost = "", sub_body = "") -> void:
	_title_lbl.text = title

	# ── Body ────────────────────────────────────────────────────────
	_body_lbl.clear()
	if body is String:
		_body_lbl.append_text(body as String)
		_body_lbl.visible = not (body as String).is_empty()
	elif body is Array:
		var arr := body as Array
		for part in arr:
			if part is String:
				_body_lbl.append_text(part as String)
			elif part is ImageTexture or part is Texture2D:
				_body_lbl.add_image(part as Texture2D, 13, 13)
		_body_lbl.visible = not arr.is_empty()
	else:
		_body_lbl.visible = false

	# ── Cost ────────────────────────────────────────────────────────
	var cost_lines: Array[String] = []
	if cost is String and (cost as String) != "":
		cost_lines.append(cost as String)
	elif cost is Array:
		for item in (cost as Array):
			if item is String and (item as String) != "":
				cost_lines.append(item as String)

	var has_cost := not cost_lines.is_empty()
	_spacer.visible   = has_cost
	_sep.visible      = has_cost
	_cost_lbl.visible = has_cost
	if has_cost:
		_cost_lbl.text = "\n".join(cost_lines)

	_panel.visible = true
	_panel.get_parent().visible = false
	
	# ── Sub Body ────────────────────────────────────────────────────
	_sub_lbl.clear()
	if sub_body is String:
		_sub_lbl.append_text(sub_body as String)
		_sub_panel.visible = not (sub_body as String).is_empty()
	elif sub_body is Array:
		var arr := sub_body as Array
		for part in arr:
			if part is String:
				_sub_lbl.append_text(part as String)
			elif part is ImageTexture or part is Texture2D:
				_sub_lbl.add_image(part as Texture2D, 13, 13)
		_sub_panel.visible = not arr.is_empty()
	else:
		_sub_panel.visible = false

	_hide_timer    = 0.0
	_visible       = true

func set_cost_color(c: Color) -> void:
	_cost_lbl.add_theme_color_override("font_color", c)

func hide_tip() -> void:
	_cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))  # reset to default gold
	_hide_timer = 0.18   # 180 ms grace period before actually hiding
