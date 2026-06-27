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

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hbox)

	# Credit icon
	var icon := Label.new()
	icon.text = "◈"
	if _orbitron: icon.add_theme_font_override("font", _orbitron)
	icon.add_theme_font_size_override("font_size", 12)
	icon.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)

	_credits_lbl = Label.new()
	_credits_lbl.text = fmt_credits(GameState.credits)
	if _orbitron: _credits_lbl.add_theme_font_override("font", _orbitron)
	_credits_lbl.add_theme_font_size_override("font_size", 12)
	_credits_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_credits_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_credits_lbl)

	# Skill Tree Button
	var skill_btn := Button.new()
	skill_btn.text = "✦ Upgrade Tree"
	if _orbitron: skill_btn.add_theme_font_override("font", _orbitron)
	skill_btn.add_theme_font_size_override("font_size", 10)
	skill_btn.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	skill_btn.focus_mode = Control.FOCUS_NONE
	skill_btn.mouse_filter = Control.MOUSE_FILTER_STOP

	var skill_s := StyleBoxFlat.new()
	skill_s.bg_color = Color(0.08, 0.16, 0.3, 0.85)
	skill_s.border_color = Color(0.28, 0.42, 0.72, 0.6)
	skill_s.set_border_width_all(1)
	skill_s.corner_radius_top_left = 4
	skill_s.corner_radius_top_right = 4
	skill_s.corner_radius_bottom_left = 4
	skill_s.corner_radius_bottom_right = 4
	skill_s.content_margin_left = 12
	skill_s.content_margin_right = 12
	skill_s.content_margin_top = 4
	skill_s.content_margin_bottom = 4
	skill_btn.add_theme_stylebox_override("normal", skill_s)

	var skill_h := skill_s.duplicate() as StyleBoxFlat
	skill_h.bg_color = Color(0.12, 0.24, 0.45, 0.95)
	skill_h.border_color = Color(0.42, 0.62, 1.0, 0.85)
	skill_btn.add_theme_stylebox_override("hover", skill_h)

	skill_btn.pressed.connect(func() -> void:
		# Check if a SkillTreeView already exists in root using script path comparison
		var root := get_tree().root
		var existing = null
		for child in root.get_children():
			var script = child.get_script()
			if script != null and script.resource_path.ends_with("SkillTreeView.gd"):
				existing = child
				break
		
		if existing != null:
			CursorManager.set_state(CursorManager.State.NORMAL)
			existing.queue_free()
		else:
			var st_view = load("res://scripts/ui/SkillTreeView.gd").new()
			st_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			root.add_child(st_view))
		
	skill_btn.mouse_entered.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.POINTER)
		TooltipManager.show_tip("Upgrades & Tech Tree", "Open system upgrade matrix using credits."))
	skill_btn.mouse_exited.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.NORMAL)
		TooltipManager.hide_tip())
		
	vbox.add_child(skill_btn)

	# Anchor bottom-left
	panel.anchor_left   = 0.0
	panel.anchor_right  = 0.0
	panel.anchor_top    = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	panel.offset_left   = 12.0
	panel.offset_bottom = -12.0
	# Allow mouse clicks on HUD panel buttons
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.mouse_filter = Control.MOUSE_FILTER_STOP
	hbox.mouse_filter = Control.MOUSE_FILTER_STOP

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
