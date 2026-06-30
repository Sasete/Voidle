## Mission Builder — center-screen panel for composing task chains.
##
## Usage:
##   MissionBuilderPanel.open(parent_control, context, on_confirm)
##
## context dict keys:
##   planet_seed: int          — planet ships orbit
##   pp: PlanetProgress        — for cargo resource lists
##   font: Font                — Orbitron font (optional, fallback to theme)
##   entry: Dictionary         — spaceport config entry (read initial cargo etc.)
##   ships: Array[ShipData]    — current ships in orbit (for station list)
##
## on_confirm: Callable(tasks: Array, repeat_cycle: float)
##   tasks = [{type, ...params}, ...]
class_name MissionBuilderPanel
extends RefCounted

const START_STATUS := "on_pad"

# ── Factory ───────────────────────────────────────────────────────────────────

static func open(parent: Control, context: Dictionary, on_confirm: Callable) -> Control:
	var panel := MissionBuilderPanel.new()
	panel._context    = context
	panel._on_confirm = on_confirm
	panel._tasks      = context.get("initial_tasks", []).duplicate(true)
	panel._font       = context.get("font", null)

	# Dim overlay — full-screen, stops all input
	var overlay := ColorRect.new()
	overlay.color             = Color(0.0, 0.0, 0.0, 0.55)
	overlay.anchor_right      = 1.0
	overlay.anchor_bottom     = 1.0
	overlay.mouse_filter      = Control.MOUSE_FILTER_STOP
	overlay.z_index           = 200
	panel._overlay            = overlay
	# Keep panel alive via metadata so GC doesn't collect it
	overlay.set_meta("_mission_panel", panel)
	# Expose overlay to build_params_ui callables so they can host popups inside it
	panel._context["_overlay"] = overlay
	parent.add_child(overlay)

	# Centered container
	var center := CenterContainer.new()
	center.anchor_right   = 1.0
	center.anchor_bottom  = 1.0
	center.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	center.z_index        = 201
	overlay.add_child(center)

	# Main panel card
	var card          := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	var card_style    := StyleBoxFlat.new()
	card_style.bg_color     = Color(0.05, 0.07, 0.14, 0.97)
	card_style.border_color = Color(0.25, 0.45, 0.80, 0.55)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(6)
	card_style.content_margin_left   = 14
	card_style.content_margin_right  = 14
	card_style.content_margin_top    = 12
	card_style.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)
	panel._vbox = vbox

	panel._build_ui()
	return overlay  # caller keeps ref to free it


# ── State ─────────────────────────────────────────────────────────────────────

var _context:    Dictionary
var _on_confirm: Callable
var _tasks:      Array       # [{type, ...params}]
var _font:       Font
var _overlay:    Control
var _vbox:       VBoxContainer
var _task_list:  VBoxContainer
var _cost_lbl:   Label
var _confirm_btn: Button
var _add_popup:  Control     # dropdown for "+" button, or null


# ── UI Build ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Title row: "Mission Builder" label + name field
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	_vbox.add_child(title_row)

	var title := Label.new()
	title.text = "Mission Builder"
	_font_apply(title, 10)
	title.add_theme_color_override("font_color", Color(0.70, 0.88, 1.0))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(title)

	var name_edit := LineEdit.new()
	var entry_ref: Dictionary = _context.get("entry", {})
	name_edit.text = entry_ref.get("ship_name", _context.get("default_name", "Pioneer"))
	name_edit.placeholder_text = "Mission name…"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_lineedit(name_edit)
	name_edit.text_changed.connect(func(t: String) -> void:
		entry_ref["ship_name"] = t)
	title_row.add_child(name_edit)

	# Ship type selector row
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 5)
	_vbox.add_child(type_row)

	var type_lbl := Label.new()
	type_lbl.text = "Ship"
	_font_apply(type_lbl, 7)
	type_lbl.add_theme_color_override("font_color", Color(0.50, 0.62, 0.82, 0.70))
	type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_lbl.custom_minimum_size = Vector2(36, 0)
	type_row.add_child(type_lbl)

	var station_count: int = 0
	var ships_arr: Array = _context.get("ships", [])
	for s in ships_arr:
		if (s as ShipData).ship_type == "station":
			station_count += 1
	var station_locked: bool = station_count >= 1

	const SHIP_LABELS: Dictionary = {
		"shuttle": "Shuttle (5)",
		"hauler": "Hauler (20)",
		"heavy_hauler": "Heavy (60)",
		"station": "Station",
	}
	for ttype: String in ["shuttle", "hauler", "heavy_hauler", "station"]:
		var cap_t: String = ttype
		var is_locked: bool = (ttype == "station" and station_locked)
		var tb := Button.new()
		tb.text = SHIP_LABELS.get(ttype, ttype.capitalize())
		_font_apply(tb, 7)
		var is_sel: bool = _context.get("entry", {}).get("ship_type", "shuttle") == ttype
		var tbg := Color(0.10, 0.28, 0.50, 0.95) if is_sel else (Color(0.08, 0.08, 0.12, 0.60) if is_locked else Color(0.05, 0.07, 0.15, 0.75))
		var tbc := Color(0.35, 0.65, 1.0, 0.65 if is_sel else (0.12 if is_locked else 0.28))
		var tbs := _btn_style(tbg, tbc)
		tb.add_theme_stylebox_override("normal", tbs)
		tb.add_theme_stylebox_override("hover",  tbs)
		tb.add_theme_color_override("font_color",
			Color(0.75, 0.92, 1.0) if is_sel else (Color(0.30, 0.32, 0.40) if is_locked else Color(0.45, 0.60, 0.80)))
		tb.custom_minimum_size = Vector2(70, 0)
		tb.disabled = is_locked
		if not is_locked:
			tb.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
			tb.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
		tb.pressed.connect(func() -> void:
			_context.get("entry", {})["ship_type"] = cap_t
			_tasks.clear()
			# Rebuild whole UI so type buttons reflect new selection
			for ch in _vbox.get_children(): ch.queue_free()
			_build_ui())
		type_row.add_child(tb)

	if station_locked:
		var lock_lbl := Label.new()
		lock_lbl.text = "(limit 1)"
		_font_apply(lock_lbl, 6)
		lock_lbl.add_theme_color_override("font_color", Color(0.55, 0.35, 0.35, 0.70))
		lock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		type_row.add_child(lock_lbl)

	# Starting position chip
	var start_row := HBoxContainer.new()
	start_row.add_theme_constant_override("separation", 5)
	_vbox.add_child(start_row)

	var start_dot := Label.new()
	start_dot.text = "●"
	_font_apply(start_dot, 7)
	start_dot.add_theme_color_override("font_color", Color(0.40, 0.80, 0.55))
	start_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_row.add_child(start_dot)

	var start_lbl := Label.new()
	start_lbl.text = "Launch Pad"
	_font_apply(start_lbl, 7)
	start_lbl.add_theme_color_override("font_color", Color(0.55, 0.70, 0.90, 0.80))
	start_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_row.add_child(start_lbl)

	_add_sep()

	# Task list (rebuilt on changes)
	_task_list = VBoxContainer.new()
	_task_list.add_theme_constant_override("separation", 4)
	_vbox.add_child(_task_list)

	_rebuild_task_list()

	_add_sep()

	# Repeat cycle row
	var rep_row := HBoxContainer.new()
	rep_row.add_theme_constant_override("separation", 6)
	_vbox.add_child(rep_row)

	var rep_lbl := Label.new()
	rep_lbl.text = "Repeat"
	_font_apply(rep_lbl, 7)
	rep_lbl.add_theme_color_override("font_color", Color(0.50, 0.62, 0.82, 0.70))
	rep_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rep_lbl.custom_minimum_size = Vector2(46, 0)
	rep_row.add_child(rep_lbl)

	var rep_edit := LineEdit.new()
	rep_edit.text              = "-"
	rep_edit.custom_minimum_size = Vector2(56, 0)
	rep_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_style_lineedit(rep_edit)
	rep_edit.text_changed.connect(func(t: String) -> void:
		_context["repeat_cycle"] = _parse_repeat(t))
	rep_row.add_child(rep_edit)

	var rep_hint := Label.new()
	rep_hint.text = "sec  (- = no repeat)"
	_font_apply(rep_hint, 6)
	rep_hint.add_theme_color_override("font_color", Color(0.40, 0.50, 0.65, 0.60))
	rep_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rep_row.add_child(rep_hint)

	_add_sep()

	# Bottom row: cost + cancel + confirm
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	_vbox.add_child(bottom)

	_cost_lbl = Label.new()
	_font_apply(_cost_lbl, 7)
	_cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_cost_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(spacer)

	var cancel_btn := _make_btn("Cancel",
		Color(0.10, 0.07, 0.12, 0.80), Color(0.48, 0.28, 0.32, 0.55),
		Color(0.80, 0.50, 0.52))
	cancel_btn.pressed.connect(_close)
	bottom.add_child(cancel_btn)

	_confirm_btn = _make_btn("Confirm",
		Color(0.07, 0.28, 0.16, 0.92), Color(0.22, 0.78, 0.42, 0.75),
		Color(0.35, 0.95, 0.58))
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	bottom.add_child(_confirm_btn)

	_refresh_cost()


func _rebuild_task_list() -> void:
	for ch in _task_list.get_children():
		ch.queue_free()

	for i: int in _tasks.size():
		_task_list.add_child(_build_task_row(i))

	# "+" add button
	var add_btn := _make_btn("+ Add Step",
		Color(0.06, 0.14, 0.28, 0.85), Color(0.22, 0.45, 0.75, 0.45),
		Color(0.50, 0.75, 1.0))
	add_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_btn.pressed.connect(func() -> void: _show_add_dropdown(add_btn))
	_task_list.add_child(add_btn)

	# Disable add if no tasks available at current tail
	var tail: String = MissionTaskRegistry.chain_tail_status(_tasks, START_STATUS)
	var available: Array = MissionTaskRegistry.get_available(tail, _context.get("entry", {}).get("ship_type", "shuttle"))
	add_btn.disabled = available.is_empty()

	_refresh_cost()


func _build_task_row(index: int) -> Control:
	var entry: Dictionary = _tasks[index]
	var def: MissionTaskDef = MissionTaskRegistry.get_def(entry.get("type", ""))

	var card := PanelContainer.new()
	var cs   := StyleBoxFlat.new()
	cs.bg_color     = Color(0.08, 0.12, 0.24, 0.80)
	cs.border_color = Color(0.22, 0.38, 0.65, 0.40)
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(4)
	cs.content_margin_left   = 8
	cs.content_margin_right  = 6
	cs.content_margin_top    = 5
	cs.content_margin_bottom = 5
	card.add_theme_stylebox_override("panel", cs)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	card.add_child(row)

	# Task name
	var name_lbl := Label.new()
	name_lbl.text = def.display_name if def != null else entry.get("type", "?")
	_font_apply(name_lbl, 7)
	name_lbl.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.custom_minimum_size = Vector2(72, 0)
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(name_lbl)

	# Params container
	var params_cont := HBoxContainer.new()
	params_cont.add_theme_constant_override("separation", 4)
	params_cont.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(params_cont)

	if def != null and def.build_params_ui.is_valid():
		def.build_params_ui.call(params_cont, entry, func() -> void: _refresh_cost(), _context)

	# × remove button
	var remove_btn := Button.new()
	remove_btn.text = "×"
	_font_apply(remove_btn, 9)
	var rbs := StyleBoxFlat.new()
	rbs.bg_color     = Color(0.0, 0.0, 0.0, 0.0)
	rbs.border_color = Color(0.0, 0.0, 0.0, 0.0)
	rbs.set_border_width_all(0)
	remove_btn.add_theme_stylebox_override("normal", rbs)
	remove_btn.add_theme_stylebox_override("hover",  rbs)
	remove_btn.add_theme_color_override("font_color", Color(0.70, 0.35, 0.35, 0.80))
	remove_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	remove_btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	remove_btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
	remove_btn.pressed.connect(func() -> void:
		# Remove this task and all subsequent (chain may be broken)
		_tasks.resize(index)
		_rebuild_task_list())
	row.add_child(remove_btn)

	return card


# ── Add Dropdown ──────────────────────────────────────────────────────────────

func _show_add_dropdown(anchor: Control) -> void:
	if _add_popup != null and is_instance_valid(_add_popup):
		_add_popup.queue_free()
		_add_popup = null
		return

	var tail: String = MissionTaskRegistry.chain_tail_status(_tasks, START_STATUS)
	var available: Array = MissionTaskRegistry.get_available(tail, _context.get("entry", {}).get("ship_type", "shuttle"))
	if available.is_empty():
		return

	var popup := PanelContainer.new()
	var ps    := StyleBoxFlat.new()
	ps.bg_color     = Color(0.06, 0.09, 0.18, 0.97)
	ps.border_color = Color(0.25, 0.45, 0.80, 0.55)
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(5)
	ps.content_margin_left = 6; ps.content_margin_right = 6
	ps.content_margin_top  = 6; ps.content_margin_bottom = 6
	popup.add_theme_stylebox_override("panel", ps)
	popup.z_index = 210

	var pvbox := VBoxContainer.new()
	pvbox.add_theme_constant_override("separation", 3)
	popup.add_child(pvbox)

	for def: MissionTaskDef in available:
		var cap_def: MissionTaskDef = def
		var item_btn := Button.new()
		item_btn.text = cap_def.display_name
		_font_apply(item_btn, 7)
		var ibs := StyleBoxFlat.new()
		ibs.bg_color     = Color(0.0, 0.0, 0.0, 0.0)
		ibs.border_color = Color(0.0, 0.0, 0.0, 0.0)
		ibs.set_border_width_all(0)
		ibs.content_margin_left = 6; ibs.content_margin_right = 6
		ibs.content_margin_top  = 3; ibs.content_margin_bottom = 3
		item_btn.add_theme_stylebox_override("normal", ibs)
		var ibs_h := ibs.duplicate()
		(ibs_h as StyleBoxFlat).bg_color = Color(0.12, 0.22, 0.45, 0.80)
		item_btn.add_theme_stylebox_override("hover", ibs_h)
		item_btn.add_theme_color_override("font_color", Color(0.80, 0.92, 1.0))
		item_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item_btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
		item_btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
		item_btn.pressed.connect(func() -> void:
			_tasks.append({"type": cap_def.task_type})
			if _add_popup != null and is_instance_valid(_add_popup):
				_add_popup.queue_free()
				_add_popup = null
			_rebuild_task_list())
		pvbox.add_child(item_btn)

	# Position below anchor, added to overlay so coordinates are consistent
	var anchor_global: Vector2 = anchor.get_global_rect().position + Vector2(0, anchor.size.y + 2)
	if _overlay != null and is_instance_valid(_overlay):
		var overlay_rect: Vector2 = _overlay.get_global_rect().position
		popup.position = anchor_global - overlay_rect
		_overlay.add_child(popup)
	else:
		popup.global_position = anchor_global
		anchor.get_viewport().add_child(popup)
	_add_popup = popup


# ── Cost & Confirm ────────────────────────────────────────────────────────────

func _refresh_cost() -> void:
	var total: float = 0.0
	var ctx: Dictionary = _context
	for t: Dictionary in _tasks:
		var def: MissionTaskDef = MissionTaskRegistry.get_def(t.get("type", ""))
		if def != null and def.estimate_cost.is_valid():
			total += def.estimate_cost.call(t, ctx)

	var tail: String = MissionTaskRegistry.chain_tail_status(_tasks, START_STATUS)
	var valid: bool  = _tasks.size() > 0

	if _cost_lbl != null and is_instance_valid(_cost_lbl):
		_cost_lbl.text = "%.0f cr" % total
		_cost_lbl.add_theme_color_override("font_color",
			Color(0.90, 0.75, 0.20) if valid else Color(0.65, 0.40, 0.40))

	if _confirm_btn != null and is_instance_valid(_confirm_btn):
		_confirm_btn.disabled = not valid
		var fbs_col := Color(0.07, 0.28, 0.16, 0.92) if valid else Color(0.18, 0.12, 0.12, 0.85)
		var fbs_brd := Color(0.22, 0.78, 0.42, 0.75) if valid else Color(0.48, 0.28, 0.28, 0.55)
		var fbs     := _btn_style(fbs_col, fbs_brd)
		_confirm_btn.add_theme_stylebox_override("normal", fbs)
		_confirm_btn.add_theme_stylebox_override("hover",  fbs)
		_confirm_btn.add_theme_color_override("font_color",
			Color(0.35, 0.95, 0.58) if valid else Color(0.55, 0.40, 0.40))


func _on_confirm_pressed() -> void:
	var repeat: float = _context.get("repeat_cycle", 0.0)
	_on_confirm.call(_tasks.duplicate(true), repeat)
	_close()


func _close() -> void:
	if _add_popup != null and is_instance_valid(_add_popup):
		_add_popup.queue_free()
		_add_popup = null
	var on_close: Callable = _context.get("on_close", Callable())
	if on_close.is_valid():
		on_close.call()
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
		_overlay = null


# ── Helpers ───────────────────────────────────────────────────────────────────

func _add_sep() -> void:
	var sep := HSeparator.new()
	var ss  := StyleBoxFlat.new()
	ss.bg_color = Color(0.22, 0.38, 0.65, 0.25)
	ss.content_margin_top    = 0
	ss.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", ss)
	_vbox.add_child(sep)


func _font_apply(node: CanvasItem, size: int) -> void:
	if _font != null:
		node.add_theme_font_override("font", _font)
	node.add_theme_font_size_override("font_size", size)


func _style_lineedit(le: LineEdit) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.07, 0.09, 0.18, 0.90)
	s.border_color = Color(0.22, 0.42, 0.75, 0.55)
	s.set_border_width_all(1); s.set_corner_radius_all(3)
	s.content_margin_left = 5; s.content_margin_right = 5
	s.content_margin_top  = 3; s.content_margin_bottom = 3
	le.add_theme_stylebox_override("normal", s)
	le.add_theme_stylebox_override("focus",  s)
	_font_apply(le, 8)
	le.add_theme_color_override("font_color", Color(0.90, 0.92, 1.0))


func _make_btn(text_val: String, bg: Color, border: Color, font_color: Color) -> Button:
	var btn := Button.new()
	btn.text = text_val
	_font_apply(btn, 7)
	var s := _btn_style(bg, border)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover",  s)
	btn.add_theme_color_override("font_color", font_color)
	btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
	return btn


func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left   = 10
	s.content_margin_right  = 10
	s.content_margin_top    = 4
	s.content_margin_bottom = 4
	return s


func _parse_repeat(text: String) -> float:
	var t := text.strip_edges()
	if t == "" or t == "-":
		return 0.0
	if t.is_valid_float():
		return float(t)
	return 0.0
