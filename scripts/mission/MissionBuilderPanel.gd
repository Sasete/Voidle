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
var _add_popup:    Control   # dropdown for "+" button, or null
var _add_backdrop: Control   # transparent dismiss backdrop behind dropdown


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


## ── Pre-clamp ─────────────────────────────────────────────────────────────────

## Clamp pick_planet cargo amounts to ship capacity before state simulation runs,
## so state rows and downstream max calculations see correct values.
func _pre_clamp_tasks() -> void:
	var ship_type: String = (_context.get("entry", {}) as Dictionary).get("ship_type", "shuttle")
	const CAPS: Dictionary = {"shuttle": 5, "hauler": 20, "heavy_hauler": 60, "station": 60}
	var cap: int = CAPS.get(ship_type, 5)
	var used: int = 0
	for task: Dictionary in _tasks:
		if task.get("type", "") != "pick_planet": continue
		var cargo: Dictionary = task.get("cargo", {})
		for k: String in cargo.keys():
			var avail: int = cap - used
			var clamped: int = clampi(int(cargo[k]), 0, avail)
			cargo[k] = clamped
			used += clamped


## ── State simulation ──────────────────────────────────────────────────────────

## Returns Array of state dicts, one per task boundary: states[0] = initial,
## states[i] = state the ship is in BEFORE executing task[i-1],
## states[_tasks.size()] = final state after all tasks.
func _compute_states() -> Array:
	var states: Array = [{"status": "on_pad", "cargo": {}}]
	for task: Dictionary in _tasks:
		states.append(_apply_task_state(states.back(), task))
	return states


func _apply_task_state(state: Dictionary, task: Dictionary) -> Dictionary:
	var s := {"status": state["status"], "cargo": (state["cargo"] as Dictionary).duplicate()}
	match task.get("type", ""):
		"pick_planet":
			for k: String in (task.get("cargo", {}) as Dictionary).keys():
				s["cargo"][k] = s["cargo"].get(k, 0) + int((task["cargo"] as Dictionary)[k])
		"move_orbit":
			s["status"] = "in_orbit"
		"move_station":
			var tid: String = task.get("target_id", "")
			s["status"] = "at_station:" + tid if tid != "" else "at_station"
			for rt: Dictionary in task.get("rendezvous_tasks", []):
				match rt.get("type", ""):
					"pickup":
						var res: String = rt.get("transfer_resource", "")
						if res != "":
							s["cargo"][res] = s["cargo"].get(res, 0) + int(rt.get("transfer_amount", 0))
					"deliver":
						for k: String in (rt.get("cargo", {}) as Dictionary).keys():
							s["cargo"][k] = maxi(0, s["cargo"].get(k, 0) - int((rt["cargo"] as Dictionary)[k]))
		"land":
			s["status"] = "on_pad"
		"deploy":
			s["status"] = "deployed"
	return s


func _status_label(status: String) -> String:
	if status == "on_pad":    return "Launch Pad"
	if status == "in_orbit":  return "In Orbit"
	if status == "deployed":  return "Deployed"
	if status.begins_with("at_station"):
		var sid: String = status.substr("at_station:".length())
		if sid != "":
			for sh in _context.get("ships", []):
				if (sh as ShipData).ship_id == sid:
					return "At " + (sh as ShipData).ship_name
		return "At Station"
	return status


## Small connector row between tasks showing ship location + cargo.
func _build_state_row(state: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var status: String = state.get("status", "on_pad")
	var dot_col: Color = Color(0.40, 0.80, 0.55) if status == "on_pad" \
		else Color(0.45, 0.65, 1.0) if status == "in_orbit" \
		else Color(0.85, 0.72, 0.30)
	var dot := Label.new()
	dot.text = "●"
	_font_apply(dot, 6)
	dot.add_theme_color_override("font_color", dot_col)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)

	var status_lbl := Label.new()
	status_lbl.text = _status_label(status)
	_font_apply(status_lbl, 6)
	status_lbl.add_theme_color_override("font_color", Color(0.55, 0.70, 0.90, 0.65))
	status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(status_lbl)

	var cargo: Dictionary = state.get("cargo", {})
	var has_cargo: bool = false
	for res_id: String in cargo.keys():
		var amt: int = int(cargo[res_id])
		if amt <= 0: continue
		var rd: ResourceData = GameState.known_resources.get(res_id, null)
		if rd == null: continue
		has_cargo = true
		var tex := MineralIcon.make(rd.tier, rd.display_color)
		var icon := TextureRect.new()
		icon.texture              = tex
		icon.custom_minimum_size  = Vector2(14, 14)
		icon.stretch_mode         = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var amt_lbl := Label.new()
		amt_lbl.text = "×%d" % amt
		_font_apply(amt_lbl, 6)
		amt_lbl.add_theme_color_override("font_color", Color(0.82, 0.90, 1.0, 0.75))
		amt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(amt_lbl)

	if not has_cargo:
		var empty_lbl := Label.new()
		empty_lbl.text = "· empty"
		_font_apply(empty_lbl, 6)
		empty_lbl.add_theme_color_override("font_color", Color(0.40, 0.45, 0.58, 0.50))
		empty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(empty_lbl)

	return row


## ── Task list ─────────────────────────────────────────────────────────────────

func _rebuild_task_list() -> void:
	for ch in _task_list.get_children():
		ch.queue_free()

	_pre_clamp_tasks()
	var states: Array = _compute_states()

	# Launch Pad card — groups all pick_planet tasks
	_task_list.add_child(_build_launch_pad_card(states[0]))

	var has_land    := false
	var has_dest    := false

	for i: int in _tasks.size():
		var ttype: String = (_tasks[i] as Dictionary).get("type", "")
		match ttype:
			"move_station":
				has_dest = true
				_task_list.add_child(_build_chain_arrow())
				_task_list.add_child(_build_destination_card(i, states[i]))
			"land":
				has_land = true
				_task_list.add_child(_build_chain_arrow())
				_task_list.add_child(_build_land_row(i))
			"pick_planet", "move_orbit":
				pass  # rendered inside launch pad card

	# Bottom action buttons
	if not has_land:
		var btns := HBoxContainer.new()
		btns.add_theme_constant_override("separation", 6)
		_task_list.add_child(btns)

		var dest_btn := _make_btn("+ Add Destination",
			Color(0.05, 0.10, 0.22, 0.80), Color(0.22, 0.42, 0.70, 0.45),
			Color(0.55, 0.78, 1.0))
		dest_btn.pressed.connect(func() -> void:
			# Insert after all existing move_station tasks, before land
			var pos: int = _tasks.size()
			for j: int in _tasks.size():
				if (_tasks[j] as Dictionary).get("type", "") in ["pick_planet", "move_orbit", "move_station"]:
					pos = j + 1
				else:
					break
			_tasks.insert(pos, {"type": "move_station"})
			_rebuild_task_list())
		btns.add_child(dest_btn)

		if has_dest:
			var land_btn := _make_btn("+ Land",
				Color(0.05, 0.08, 0.16, 0.80), Color(0.22, 0.35, 0.55, 0.40),
				Color(0.50, 0.68, 0.90))
			land_btn.pressed.connect(func() -> void:
				_tasks.append({"type": "land"})
				_rebuild_task_list())
			btns.add_child(land_btn)

	_refresh_cost()


func _build_launch_pad_card(state_before: Dictionary) -> Control:
	var card := PanelContainer.new()
	var cs := _card_style(Color(0.25, 0.55, 0.38, 0.40))
	card.add_theme_stylebox_override("panel", cs)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	# Header
	var hdr_row := HBoxContainer.new()
	hdr_row.add_theme_constant_override("separation", 5)
	hdr_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hdr_row)
	var dot := Label.new(); dot.text = "●"
	_font_apply(dot, 7)
	dot.add_theme_color_override("font_color", Color(0.40, 0.80, 0.55))
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr_row.add_child(dot)
	var hdr_lbl := Label.new(); hdr_lbl.text = "Launch Pad"
	_font_apply(hdr_lbl, 7)
	hdr_lbl.add_theme_color_override("font_color", Color(0.65, 0.82, 0.96, 0.90))
	hdr_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr_row.add_child(hdr_lbl)

	# pick_planet task rows (in order, with sequential state)
	var running := state_before.duplicate(true)
	var has_pick := false
	for i: int in _tasks.size():
		var task: Dictionary = _tasks[i]
		if task.get("type", "") != "pick_planet": continue
		has_pick = true
		vbox.add_child(_build_pick_planet_row(i, running.duplicate(true)))
		running = _apply_task_state(running, task)

	if not has_pick:
		var empty := Label.new(); empty.text = "No pre-launch cargo"
		_font_apply(empty, 6)
		empty.add_theme_color_override("font_color", Color(0.38, 0.44, 0.58, 0.55))
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(empty)

	# Insert position: after last pick_planet/move_orbit, before first move_station
	var insert_pos := 0
	for j: int in _tasks.size():
		if (_tasks[j] as Dictionary).get("type", "") in ["pick_planet", "move_orbit"]:
			insert_pos = j + 1
		else:
			break
	var cap_pos := insert_pos
	var add_btn := _make_btn("+ Take from Storage",
		Color(0.0, 0.0, 0.0, 0.0), Color(0.18, 0.35, 0.58, 0.35),
		Color(0.48, 0.68, 0.92, 0.85))
	add_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_btn.pressed.connect(func() -> void:
		_tasks.insert(cap_pos, {"type": "pick_planet", "cargo": {}})
		_rebuild_task_list())
	vbox.add_child(add_btn)

	return card


func _build_pick_planet_row(index: int, state_before: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var params := HBoxContainer.new()
	params.add_theme_constant_override("separation", 4)
	params.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(params)

	var entry: Dictionary = _tasks[index]
	var def: MissionTaskDef = MissionTaskRegistry.get_def("pick_planet")
	if def != null and def.build_params_ui.is_valid():
		var task_ctx := _context.duplicate()
		task_ctx["state_before"] = state_before
		def.build_params_ui.call(params, entry, func() -> void: _refresh_cost(), task_ctx)

	var cap_i := index
	row.add_child(_make_x_btn(func() -> void:
		_tasks.remove_at(cap_i)
		_rebuild_task_list()))
	return row


func _build_destination_card(index: int, state_before: Dictionary) -> Control:
	var card := PanelContainer.new()
	var cs := _card_style(Color(0.20, 0.52, 0.38, 0.35))
	card.add_theme_stylebox_override("panel", cs)

	# Outer row: content fills left, × button on right
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	card.add_child(outer)

	var content := HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(content)

	var entry: Dictionary = _tasks[index]
	var def: MissionTaskDef = MissionTaskRegistry.get_def("move_station")
	if def != null and def.build_params_ui.is_valid():
		var task_ctx := _context.duplicate()
		task_ctx["state_before"] = state_before
		def.build_params_ui.call(content, entry, func() -> void: _refresh_cost(), task_ctx)

	var cap_i := index
	outer.add_child(_make_x_btn(func() -> void:
		_tasks.resize(cap_i)
		_rebuild_task_list()))

	return card


func _build_land_row(index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var dot := Label.new(); dot.text = "●"
	_font_apply(dot, 7)
	dot.add_theme_color_override("font_color", Color(0.75, 0.55, 0.30))
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)

	var lbl := Label.new(); lbl.text = "Land"
	_font_apply(lbl, 7)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.90, 0.85))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	var cap_i := index
	row.add_child(_make_x_btn(func() -> void:
		_tasks.resize(cap_i)
		_rebuild_task_list()))
	return row


func _build_chain_arrow() -> Control:
	var lbl := Label.new()
	lbl.text = "    │"
	_font_apply(lbl, 7)
	lbl.add_theme_color_override("font_color", Color(0.28, 0.42, 0.65, 0.40))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _card_style(border_color: Color) -> StyleBoxFlat:
	var cs := StyleBoxFlat.new()
	cs.bg_color     = Color(0.07, 0.10, 0.20, 0.88)
	cs.border_color = border_color
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(5)
	cs.content_margin_left   = 10
	cs.content_margin_right  = 8
	cs.content_margin_top    = 8
	cs.content_margin_bottom = 8
	return cs


func _make_x_btn(on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = "×"
	_font_apply(btn, 9)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0); s.set_border_width_all(0)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover",  s)
	btn.add_theme_color_override("font_color", Color(0.70, 0.35, 0.35, 0.75))
	btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
	btn.pressed.connect(on_press)
	return btn


# ── Add Dropdown ──────────────────────────────────────────────────────────────

func _dismiss_add_popup() -> void:
	if _add_popup != null and is_instance_valid(_add_popup):
		_add_popup.queue_free()
	_add_popup = null
	if _add_backdrop != null and is_instance_valid(_add_backdrop):
		_add_backdrop.queue_free()
	_add_backdrop = null


func _show_add_dropdown(anchor: Control) -> void:
	if _add_popup != null and is_instance_valid(_add_popup):
		_dismiss_add_popup()
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
			_dismiss_add_popup()
			_rebuild_task_list())
		pvbox.add_child(item_btn)

	# Position below anchor, added to overlay so coordinates are consistent
	var anchor_global: Vector2 = anchor.get_global_rect().position + Vector2(0, anchor.size.y + 2)
	if _overlay != null and is_instance_valid(_overlay):
		# Transparent backdrop — added first (below popup), catches outside clicks to dismiss
		var backdrop := ColorRect.new()
		backdrop.color = Color(0, 0, 0, 0)
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		backdrop.z_index = 209
		backdrop.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
				_dismiss_add_popup())
		_overlay.add_child(backdrop)
		_add_backdrop = backdrop

		var overlay_rect: Vector2 = _overlay.get_global_rect().position
		popup.position = anchor_global - overlay_rect
		_overlay.add_child(popup)  # added after backdrop → higher input priority
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
	_dismiss_add_popup()
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
