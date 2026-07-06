import re

with open("scripts/system/TooltipManager.gd", "r") as f:
    content = f.read()

target = """	var pos := mouse + Vector2(10, -ph - 8.0)
	if pos.x + pw > vp.x: pos.x = vp.x - pw - 4.0
	if pos.x < 4.0:       pos.x = 4.0
	if pos.y < 4.0:       pos.y = mouse.y + 14.0"""

replace = """	var pos := mouse + Vector2(10, -ph - 8.0)
	if pos.x + pw > vp.x:
		# Flip to the left of the mouse so it doesn't block clicks!
		pos.x = mouse.x - pw - 10.0
	if pos.x < 4.0:       pos.x = 4.0
	if pos.y < 4.0:       pos.y = mouse.y + 14.0"""

content = content.replace(target, replace)

# Now to add a sub_panel for the secondary tooltip
target2 = """var _sep:        Control
var _spacer:     Control
var _orbitron:   Font
var _visible:    bool  = false"""

replace2 = """var _sep:        Control
var _spacer:     Control
var _orbitron:   Font
var _visible:    bool  = false

var _sub_panel:  PanelContainer
var _sub_lbl:    RichTextLabel"""

content = content.replace(target2, replace2)

target3 = """	_cost_lbl.visible = false
	vbox.add_child(_cost_lbl)

	add_child(_panel)"""

replace3 = """	_cost_lbl.visible = false
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
	_sub_panel.visible = false
	
	_sub_lbl = RichTextLabel.new()
	_sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub_lbl.bbcode_enabled = true
	_sub_lbl.fit_content = true
	_sub_lbl.scroll_active = false
	_sub_lbl.add_theme_font_size_override("normal_font_size", 9)
	_sub_lbl.add_theme_color_override("default_color", Color(0.8, 0.85, 0.9))
	_sub_lbl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sub_panel.add_child(_sub_lbl)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_panel)
	hbox.add_child(_sub_panel)
	
	add_child(hbox)"""

content = content.replace(target3, replace3)

target4 = """	# get_combined_minimum_size() is synchronous — no frame delay needed
	var sz  := _panel.get_combined_minimum_size()
	var pw  := sz.x
	var ph  := sz.y"""

replace4 = """	# get_combined_minimum_size() is synchronous — no frame delay needed
	var root_node = _panel.get_parent()
	var sz  := root_node.get_combined_minimum_size()
	var pw  := sz.x
	var ph  := sz.y"""
content = content.replace(target4, replace4)

target5 = """	_panel.position = pos
	_panel.visible  = true"""

replace5 = """	var root_node = _panel.get_parent()
	root_node.position = pos
	_panel.visible  = true"""
content = content.replace(target5, replace5)

target6 = """	if _hide_timer <= 0.0:
			_panel.visible = false
			_visible       = false"""

replace6 = """	if _hide_timer <= 0.0:
			_panel.visible = false
			_sub_panel.visible = false
			_visible       = false"""
content = content.replace(target6, replace6)

target7 = """func show_tip(title: String, body = "", cost = "") -> void:"""

replace7 = """func show_tip(title: String, body = "", cost = "", sub_body = "") -> void:"""
content = content.replace(target7, replace7)

target8 = """	_panel.visible = false
	_hide_timer    = 0.0
	_visible       = true"""

replace8 = """	_panel.visible = false
	
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
	_visible       = true"""
content = content.replace(target8, replace8)

with open("scripts/system/TooltipManager.gd", "w") as f:
    f.write(content)

print("Patched TooltipManager")
