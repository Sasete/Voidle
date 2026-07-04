## Global HUD overlay — shows credits and other persistent info across all scenes.
extends CanvasLayer

var _credits_lbl: Label
var _science_lbl: Label
var _energy_hud_lbl: Label = null
var _energy_bar_left: ProgressBar = null
var _energy_bar_right: ProgressBar = null
var _energy_hud_poll: float = 0.0
var _energy_hud_node: Control = null
## Current displayed value (tweened, may lag behind GameState.credits)
var _credits_display: float = 0.0
var _credits_tween: Tween = null
var _orbitron: Font
## The credits panel node — exposed so PlanetaryView can read its screen height for toast offset.
var credits_panel: PanelContainer = null
var science_panel: PanelContainer = null
var _top_layer: CanvasLayer = null

func set_game_hud(visible_state: bool) -> void:
	visible = visible_state
	if is_instance_valid(_top_layer):
		_top_layer.visible = visible_state
static func fmt_credits(val: float) -> String:
	if val >= 1_000_000_000.0:
		return "%.2fb cr" % (val / 1_000_000_000.0)
	elif val >= 1_000_000.0:
		return "%.2fm cr" % (val / 1_000_000.0)
	elif val >= 1_000.0:
		return "%.1fk cr" % (val / 1_000.0)
	return "%.0f cr" % val

static func fmt_science(val: float) -> String:
	if val >= 1_000_000_000.0:
		return "%.2fB" % (val / 1_000_000_000.0)
	elif val >= 1_000_000.0:
		return "%.2fM" % (val / 1_000_000.0)
	elif val >= 1_000.0:
		return "%.1fK" % (val / 1_000.0)
	return "%.0f" % val

func _ready() -> void:
	layer = 226  # Energy above DevConsole (225), hidden when SkillTree opens
	_orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")

	var panel := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color    = Color(0.05, 0.06, 0.11, 0.92)
	s.border_width_right  = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.25, 0.32, 0.55, 0.45)
	s.corner_radius_bottom_right = 8
	s.content_margin_left   = 14
	s.content_margin_right  = 14
	s.content_margin_top    = 8
	s.content_margin_bottom = 8
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
		AudioManager.play("click")
		var root := get_tree().root
		var existing_layer: CanvasLayer = null
		for child in root.get_children():
			if child is CanvasLayer:
				for gc in child.get_children():
					var sc = gc.get_script()
					if sc != null and sc.resource_path.ends_with("SkillTreeView.gd"):
						existing_layer = child as CanvasLayer
						break
			if existing_layer != null:
				break
		if existing_layer != null:
			CursorManager.set_state(CursorManager.State.NORMAL)
			
			# Find SkillTreeView to update its static state
			for gc in existing_layer.get_children():
				if gc.get_script() != null and gc.get_script().resource_path.ends_with("SkillTreeView.gd"):
					gc.set("is_open", false)
					break
					
			existing_layer.queue_free()
			_energy_hud_node.visible = true
		else:
			var st_layer := CanvasLayer.new()
			st_layer.layer = 220
			var st_view = load("res://scripts/ui/SkillTreeView.gd").new()
			st_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			st_view.tree_opened.connect(func() -> void: _energy_hud_node.visible = false)
			st_view.tree_closed.connect(func() -> void: _energy_hud_node.visible = true)
			st_layer.add_child(st_view)
			root.add_child(st_layer))

		
	skill_btn.mouse_entered.connect(func() -> void:
		AudioManager.play("hover")
		CursorManager.set_state(CursorManager.State.POINTER)
		TooltipManager.show_tip("Upgrades & Tech Tree", "Open system upgrade matrix using credits."))
	skill_btn.mouse_exited.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.NORMAL)
		TooltipManager.hide_tip())
		
	# Anchor top-left
	panel.anchor_left   = 0.0
	panel.anchor_right  = 0.0
	panel.anchor_top    = 0.0
	panel.anchor_bottom = 0.0
	panel.grow_horizontal = Control.GROW_DIRECTION_END
	panel.grow_vertical   = Control.GROW_DIRECTION_END
	panel.offset_left   = 0.0
	panel.offset_top    = 0.0
	# Allow mouse clicks on HUD panel buttons
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.mouse_filter = Control.MOUSE_FILTER_STOP
	hbox.mouse_filter = Control.MOUSE_FILTER_STOP

	# Credits + Science go into a top layer (above SkillTree at 220)
	var top_layer := CanvasLayer.new()
	top_layer.layer = 230
	_top_layer = top_layer
	get_parent().call_deferred("add_child", top_layer)

	top_layer.call_deferred("add_child", panel)
	credits_panel = panel

	var settings_btn := Button.new()
	settings_btn.text = "⚙" # Cogwheel
	settings_btn.add_theme_font_size_override("font_size", 20)
	var sb_style := StyleBoxFlat.new()
	sb_style.bg_color = Color(0.05, 0.06, 0.11, 0.8)
	sb_style.border_color = Color(0.25, 0.32, 0.55, 0.45)
	sb_style.set_border_width_all(1)
	sb_style.corner_radius_bottom_left = 8
	sb_style.content_margin_left = 10
	sb_style.content_margin_right = 10
	sb_style.content_margin_top = 4
	sb_style.content_margin_bottom = 4
	settings_btn.add_theme_stylebox_override("normal", sb_style)
	var sb_hover := sb_style.duplicate() as StyleBoxFlat
	sb_hover.bg_color = Color(0.15, 0.16, 0.22, 0.9)
	settings_btn.add_theme_stylebox_override("hover", sb_hover)
	settings_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	
	settings_btn.anchor_left = 1.0
	settings_btn.anchor_right = 1.0
	settings_btn.anchor_top = 0.0
	settings_btn.anchor_bottom = 0.0
	settings_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	settings_btn.grow_vertical = Control.GROW_DIRECTION_END
	settings_btn.offset_right = 0
	settings_btn.offset_top = 0
	
	settings_btn.mouse_entered.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.POINTER)
		AudioManager.play("hover"))
	settings_btn.mouse_exited.connect(func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
	settings_btn.pressed.connect(show_pause_menu)
	
	top_layer.call_deferred("add_child", settings_btn)


	# Science + Upgrade Tree panel — bottom-left
	var sci_panel := PanelContainer.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color    = Color(0.05, 0.06, 0.11, 0.82)
	ss.border_width_top   = 1
	ss.border_width_right = 1
	ss.border_color = Color(0.25, 0.32, 0.55, 0.45)
	ss.corner_radius_top_right = 8
	ss.content_margin_left   = 14
	ss.content_margin_right  = 14
	ss.content_margin_top    = 8
	ss.content_margin_bottom = 8
	sci_panel.add_theme_stylebox_override("panel", ss)
	sci_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var sci_vbox := VBoxContainer.new()
	sci_vbox.add_theme_constant_override("separation", 6)
	sci_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sci_panel.add_child(sci_vbox)

	var sci_hbox := HBoxContainer.new()
	sci_hbox.add_theme_constant_override("separation", 6)
	sci_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	sci_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sci_vbox.add_child(sci_hbox)

	var sci_icon := Label.new()
	sci_icon.text = "⬡"
	if _orbitron: sci_icon.add_theme_font_override("font", _orbitron)
	sci_icon.add_theme_font_size_override("font_size", 12)
	sci_icon.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	sci_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sci_hbox.add_child(sci_icon)

	_science_lbl = Label.new()
	_science_lbl.text = "%s Science" % fmt_science(GameState.science_points)
	if _orbitron: _science_lbl.add_theme_font_override("font", _orbitron)
	_science_lbl.add_theme_font_size_override("font_size", 12)
	_science_lbl.add_theme_color_override("font_color", Color(0.65, 0.90, 1.0))
	_science_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sci_hbox.add_child(_science_lbl)

	sci_vbox.add_child(skill_btn)

	sci_panel.anchor_left   = 0.0
	sci_panel.anchor_right  = 0.0
	sci_panel.anchor_top    = 1.0
	sci_panel.anchor_bottom = 1.0
	sci_panel.grow_horizontal = Control.GROW_DIRECTION_END
	sci_panel.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	sci_panel.offset_left   = 0.0
	sci_panel.offset_bottom = 0.0
	science_panel = sci_panel
	top_layer.call_deferred("add_child", sci_panel)

	_credits_display = GameState.credits

	GameState.credits_changed.connect(_on_credits_changed)
	GameState.science_changed.connect(_on_science_changed)
	_setup_energy_hud()
	AchievementManager.achievement_unlocked.connect(_on_achievement_unlocked)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _top_layer.visible and not get_tree().paused:
			show_pause_menu()
			get_viewport().set_input_as_handled()

func show_pause_menu() -> void:
	AudioManager.play("ui_click")
	if get_tree().paused:
		return
	
	get_tree().paused = true
	
	var overlay := CanvasLayer.new()
	overlay.layer = 250
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	
	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.07, 0.12, 0.95)
	ps.border_color = Color(0.3, 0.4, 0.6, 0.5)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(12)
	ps.content_margin_left = 60
	ps.content_margin_right = 60
	ps.content_margin_top = 40
	ps.content_margin_bottom = 40
	panel.add_theme_stylebox_override("panel", ps)
	
	panel.anchor_left = 0.5; panel.anchor_right = 0.5
	panel.anchor_top = 0.5; panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)
	
	var title := Label.new()
	title.text = "PAUSED"
	if _orbitron: title.add_theme_font_override("font", _orbitron)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	vbox.add_child(HSeparator.new())
	
	var _make_btn = func(text: String, action: Callable) -> Button:
		var btn := Button.new()
		btn.text = text
		if _orbitron: btn.add_theme_font_override("font", _orbitron)
		btn.add_theme_font_size_override("font_size", 16)
		btn.custom_minimum_size = Vector2(240, 40)
		
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(0.12, 0.18, 0.28)
		bs.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", bs)
		
		var bsh := bs.duplicate() as StyleBoxFlat
		bsh.bg_color = Color(0.2, 0.35, 0.5)
		btn.add_theme_stylebox_override("hover", bsh)
		
		btn.pressed.connect(func():
			AudioManager.play("ui_click")
			action.call()
		)
		btn.mouse_entered.connect(func():
			CursorManager.set_state(CursorManager.State.POINTER)
			AudioManager.play("hover")
		)
		btn.mouse_exited.connect(func(): CursorManager.set_state(CursorManager.State.NORMAL))
		return btn

	vbox.add_child(_make_btn.call("RESUME", func():
		get_tree().paused = false
		overlay.queue_free()
	))
	
	vbox.add_child(_make_btn.call("SETTINGS", func():
		show_settings_popup()
	))
	
	vbox.add_child(_make_btn.call("SAVE GAME", func():
		GameState.save()
		title.text = "GAME SAVED"
		title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		var tw := create_tween()
		tw.tween_interval(1.5)
		tw.tween_callback(func():
			if is_instance_valid(title):
				title.text = "PAUSED"
				title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
		)
	))
	
	vbox.add_child(HSeparator.new())
	
	var mm_btn: Button = _make_btn.call("MAIN MENU", func():
		get_tree().paused = false
		overlay.queue_free()
		GameState.save()
		SceneTransition.go("res://scenes/MainMenu.tscn", null)
	)
	var mm_sb := mm_btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	mm_sb.bg_color = Color(0.4, 0.2, 0.2)
	mm_btn.add_theme_stylebox_override("normal", mm_sb)
	vbox.add_child(mm_btn)
	
	var quit_btn: Button = _make_btn.call("QUIT TO DESKTOP", func():
		GameState.save()
		get_tree().quit()
	)
	var quit_sb := quit_btn.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	quit_sb.bg_color = Color(0.5, 0.15, 0.15)
	quit_btn.add_theme_stylebox_override("normal", quit_sb)
	vbox.add_child(quit_btn)

	overlay.add_child(panel)
	get_tree().root.add_child(overlay)


func show_settings_popup() -> void:
	AudioManager.play("ui_click")
	var overlay := CanvasLayer.new()
	overlay.layer = 300 # Above pause menu
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	
	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.10, 0.16, 0.98)
	ps.border_color = Color(0.4, 0.5, 0.7, 0.5)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(12)
	ps.content_margin_left = 40; ps.content_margin_right = 40
	ps.content_margin_top = 30; ps.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", ps)
	
	panel.anchor_left = 0.5; panel.anchor_right = 0.5
	panel.anchor_top = 0.5; panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)
	
	var title := Label.new()
	title.text = "SETTINGS"
	if _orbitron: title.add_theme_font_override("font", _orbitron)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	vbox.add_child(HSeparator.new())
	
	var mv_lbl := Label.new()
	mv_lbl.text = "Master Volume"
	if _orbitron: mv_lbl.add_theme_font_override("font", _orbitron)
	mv_lbl.add_theme_font_size_override("font_size", 14)
	mv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(mv_lbl)
	
	var mv_slider := HSlider.new()
	mv_slider.custom_minimum_size = Vector2(240, 0)
	mv_slider.min_value = 0.0
	mv_slider.max_value = 1.0
	mv_slider.step = 0.05
	mv_slider.value = SettingsManager.master_volume
	mv_slider.value_changed.connect(func(v: float): SettingsManager.set_master_volume(v))
	vbox.add_child(mv_slider)
	
	vbox.add_child(HSeparator.new())
	
	var fs_hbox := HBoxContainer.new()
	fs_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	fs_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(fs_hbox)
	
	var fs_lbl := Label.new()
	fs_lbl.text = "Fullscreen"
	if _orbitron: fs_lbl.add_theme_font_override("font", _orbitron)
	fs_lbl.add_theme_font_size_override("font_size", 14)
	fs_hbox.add_child(fs_lbl)
	
	var fs_chk := CheckButton.new()
	fs_chk.button_pressed = SettingsManager.is_fullscreen
	fs_chk.toggled.connect(func(on: bool): SettingsManager.set_fullscreen(on))
	fs_chk.mouse_entered.connect(func(): CursorManager.set_state(CursorManager.State.POINTER))
	fs_chk.mouse_exited.connect(func(): CursorManager.set_state(CursorManager.State.NORMAL))
	fs_hbox.add_child(fs_chk)
	
	vbox.add_child(HSeparator.new())
	
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	if _orbitron: close_btn.add_theme_font_override("font", _orbitron)
	close_btn.add_theme_font_size_override("font_size", 16)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.2, 0.25, 0.35)
	bs.set_corner_radius_all(6)
	bs.content_margin_top = 10; bs.content_margin_bottom = 10
	close_btn.add_theme_stylebox_override("normal", bs)
	var bsh := bs.duplicate() as StyleBoxFlat
	bsh.bg_color = Color(0.3, 0.4, 0.5)
	close_btn.add_theme_stylebox_override("hover", bsh)
	
	close_btn.pressed.connect(func():
		AudioManager.play("ui_click")
		overlay.queue_free()
	)
	close_btn.mouse_entered.connect(func():
		CursorManager.set_state(CursorManager.State.POINTER)
		AudioManager.play("hover")
	)
	close_btn.mouse_exited.connect(func(): CursorManager.set_state(CursorManager.State.NORMAL))
	
	vbox.add_child(close_btn)
	overlay.add_child(panel)
	get_tree().root.add_child(overlay)

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

func _on_science_changed(new_val: float) -> void:
	if not is_instance_valid(_science_lbl):
		return
	_science_lbl.text = "%s Science" % fmt_science(new_val)

func _process(delta: float) -> void:
	_energy_hud_poll += delta
	if _energy_hud_poll < 0.25 or not is_instance_valid(_energy_hud_lbl):
		return
	_energy_hud_poll = 0.0
	var pm: Node = get_node_or_null("/root/ProductionManager")
	if pm == null:
		return
	var bal: float   = pm.get_global_energy()
	var ratio: float = pm.get_energy_ratio()
	var sign_s := "+" if bal > 0.0 else ""
	_energy_hud_lbl.text = sign_s + "%.0f ⚡" % bal
	var ecol: Color
	if ratio >= 0.95:
		ecol = Color(0.90, 0.82, 0.25)
	elif ratio >= 0.5:
		ecol = Color(0.80, 0.65, 0.20)
	else:
		ecol = Color(0.90, 0.38, 0.25)
	_energy_hud_lbl.add_theme_color_override("font_color", ecol)
	var pct := ratio * 100.0
	var bl_fill2 := StyleBoxFlat.new()
	bl_fill2.bg_color = ecol
	bl_fill2.corner_radius_bottom_left = 3
	var br_fill2 := StyleBoxFlat.new()
	br_fill2.bg_color = ecol
	br_fill2.corner_radius_bottom_right = 3
	_energy_bar_left.value  = pct
	_energy_bar_right.value = pct
	_energy_bar_left.add_theme_stylebox_override("fill", bl_fill2)
	_energy_bar_right.add_theme_stylebox_override("fill", br_fill2)

func _setup_energy_hud() -> void:
	var anchor := Control.new()
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.set_anchors_preset(Control.PRESET_TOP_WIDE)
	anchor.offset_top    = 0
	anchor.offset_bottom = 48
	add_child(anchor)
	_energy_hud_node = anchor

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	hbox.alignment    = BoxContainer.ALIGNMENT_BEGIN
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(hbox)

	var bg_col       := Color(0.04, 0.06, 0.14, 0.84)
	var border_col   := Color(0.28, 0.36, 0.62, 0.45)
	var bar_bg_col   := Color(0.07, 0.09, 0.18, 0.90)
	var bar_fill_col := Color(0.92, 0.80, 0.22)

	# Left bar
	var left_pc := PanelContainer.new()
	var ls := StyleBoxFlat.new()
	ls.bg_color = bg_col; ls.border_color = border_col
	ls.border_width_left = 1; ls.border_width_top = 1; ls.border_width_bottom = 1; ls.border_width_right = 0
	ls.corner_radius_bottom_left = 6
	ls.content_margin_left = 10; ls.content_margin_right = 10; ls.content_margin_top = 5; ls.content_margin_bottom = 5
	left_pc.add_theme_stylebox_override("panel", ls)
	left_pc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	left_pc.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_energy_bar_left = ProgressBar.new()
	_energy_bar_left.custom_minimum_size = Vector2(90, 7)
	_energy_bar_left.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_energy_bar_left.max_value = 100.0; _energy_bar_left.value = 100.0
	_energy_bar_left.show_percentage = false
	_energy_bar_left.fill_mode = ProgressBar.FILL_END_TO_BEGIN
	_energy_bar_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bl_bg := StyleBoxFlat.new(); bl_bg.bg_color = bar_bg_col; bl_bg.corner_radius_bottom_left = 3
	var bl_fill := StyleBoxFlat.new(); bl_fill.bg_color = bar_fill_col; bl_fill.corner_radius_bottom_left = 3
	_energy_bar_left.add_theme_stylebox_override("background", bl_bg)
	_energy_bar_left.add_theme_stylebox_override("fill", bl_fill)
	left_pc.add_child(_energy_bar_left)
	hbox.add_child(left_pc)

	# Center
	var center_pc := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.05, 0.07, 0.16, 0.95); cs.border_color = border_col
	cs.border_width_left = 1; cs.border_width_top = 1; cs.border_width_right = 1; cs.border_width_bottom = 1
	cs.corner_radius_bottom_left = 8; cs.corner_radius_bottom_right = 8
	cs.content_margin_left = 16; cs.content_margin_right = 16; cs.content_margin_top = 7; cs.content_margin_bottom = 10
	center_pc.add_theme_stylebox_override("panel", cs)
	center_pc.mouse_filter = Control.MOUSE_FILTER_STOP
	center_pc.mouse_entered.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.POINTER)
		TooltipManager.show_tip("⚡ Energy Breakdown", _energy_breakdown_text()))
	center_pc.mouse_exited.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.NORMAL)
		TooltipManager.hide_tip())

	_energy_hud_lbl = Label.new()
	_energy_hud_lbl.text = "0 ⚡"
	if _orbitron: _energy_hud_lbl.add_theme_font_override("font", _orbitron)
	_energy_hud_lbl.add_theme_font_size_override("font_size", 12)
	_energy_hud_lbl.add_theme_color_override("font_color", Color(0.92, 0.82, 0.22))
	_energy_hud_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_energy_hud_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_energy_hud_lbl.custom_minimum_size   = Vector2(92, 0)
	_energy_hud_lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	center_pc.add_child(_energy_hud_lbl)
	hbox.add_child(center_pc)

	# Right bar
	var right_pc := PanelContainer.new()
	var rs := StyleBoxFlat.new()
	rs.bg_color = bg_col; rs.border_color = border_col
	rs.border_width_left = 0; rs.border_width_top = 1; rs.border_width_bottom = 1; rs.border_width_right = 1
	rs.corner_radius_bottom_right = 6
	rs.content_margin_left = 10; rs.content_margin_right = 10; rs.content_margin_top = 5; rs.content_margin_bottom = 5
	right_pc.add_theme_stylebox_override("panel", rs)
	right_pc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right_pc.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_energy_bar_right = ProgressBar.new()
	_energy_bar_right.custom_minimum_size = Vector2(90, 7)
	_energy_bar_right.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_energy_bar_right.max_value = 100.0; _energy_bar_right.value = 100.0
	_energy_bar_right.show_percentage = false
	_energy_bar_right.fill_mode = ProgressBar.FILL_BEGIN_TO_END
	_energy_bar_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var br_bg := StyleBoxFlat.new(); br_bg.bg_color = bar_bg_col; br_bg.corner_radius_bottom_right = 3
	var br_fill := StyleBoxFlat.new(); br_fill.bg_color = bar_fill_col; br_fill.corner_radius_bottom_right = 3
	_energy_bar_right.add_theme_stylebox_override("background", br_bg)
	_energy_bar_right.add_theme_stylebox_override("fill", br_fill)
	right_pc.add_child(_energy_bar_right)
	hbox.add_child(right_pc)

	call_deferred("_center_energy_hud", hbox)

func _center_energy_hud(hbox: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(hbox):
		return
	var area_w := get_viewport().get_visible_rect().size.x * 0.7
	var pw := hbox.size.x
	if pw <= 0.0:
		return
	hbox.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hbox.offset_left   = (area_w - pw) * 0.5
	hbox.offset_top    = 0.0
	hbox.offset_right  = hbox.offset_left + pw
	hbox.offset_bottom = hbox.size.y

func _on_achievement_unlocked(def) -> void:
	AudioManager.play("achievement", 2.0)
	# Build a gold-bordered achievement popup anchored bottom-right
	var overlay := CanvasLayer.new()
	overlay.layer = 240
	get_tree().root.add_child(overlay)

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.05, 0.02, 0.96)
	ps.border_color = Color(0.95, 0.78, 0.15, 0.9)
	ps.set_border_width_all(2)
	ps.corner_radius_top_left     = 8
	ps.corner_radius_top_right    = 8
	ps.corner_radius_bottom_left  = 8
	ps.corner_radius_bottom_right = 8
	ps.content_margin_left   = 16
	ps.content_margin_right  = 16
	ps.content_margin_top    = 10
	ps.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", ps)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	var icon_lbl := Label.new()
	icon_lbl.text = def.icon if def.icon != "" else "★"
	if _orbitron: icon_lbl.add_theme_font_override("font", _orbitron)
	icon_lbl.add_theme_font_size_override("font_size", 24)
	icon_lbl.add_theme_color_override("font_color", Color(0.95, 0.78, 0.15))
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_lbl)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(vbox)

	var header := Label.new()
	header.text = "Achievement Unlocked"
	if _orbitron: header.add_theme_font_override("font", _orbitron)
	header.add_theme_font_size_override("font_size", 9)
	header.add_theme_color_override("font_color", Color(0.95, 0.78, 0.15, 0.75))
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = def.title
	if _orbitron: title_lbl.add_theme_font_override("font", _orbitron)
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title_lbl)

	if def.description != "":
		var desc_lbl := Label.new()
		desc_lbl.text = def.description
		if _orbitron: desc_lbl.add_theme_font_override("font", _orbitron)
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.72, 0.60, 0.85))
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(desc_lbl)

	panel.anchor_right  = 1.0
	panel.anchor_bottom = 1.0
	panel.anchor_left   = 1.0
	panel.anchor_top    = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	panel.offset_right  = -12.0
	panel.offset_bottom = -12.0
	overlay.add_child(panel)

	await get_tree().process_frame
	await get_tree().process_frame
	var h := panel.size.y
	panel.offset_bottom = -12.0
	panel.offset_top    = panel.offset_bottom - h

	# Slide in, hold, fade out
	panel.modulate = Color(1, 1, 1, 0)
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate", Color(1, 1, 1, 1), 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.5)
	tw.tween_property(panel, "modulate", Color(1, 1, 1, 0), 0.6).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: overlay.queue_free())

func _energy_breakdown_text() -> String:
	var pm: Node = get_node_or_null("/root/ProductionManager")
	if pm == null:
		return "No data"
	var lines: Array[String] = []
	var total: float = 0.0
	for pp: PlanetProgress in GameState._planet_progress.values():
		if not pp.is_colonized:
			continue
		var net: float = pm.planet_energy_net(pp)
		if net == 0.0:
			continue
		var pd: PlanetData = GameState.get_planet_data(pp.planet_seed)
		var name_str: String = pd.planet_name if pd != null else "Colony"
		var sign_s := "+" if net > 0.0 else ""
		lines.append("%s  %s%.0f" % [name_str, sign_s, net])
		total += net
	if lines.is_empty():
		return "No active colonies"
	lines.sort()
	var sign_t := "+" if total > 0.0 else ""
	lines.append("─────────────────")
	lines.append("Net  %s%.0f" % [sign_t, total])
	return "\n".join(lines)
