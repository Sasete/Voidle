## Developer console — toggle with Cmd+Shift+C (Mac) or Ctrl+Shift+C (Win/Linux).
## Type "help" for a list of commands.
extends CanvasLayer

var _panel:        Control
var _top_spacer:   Control
var _log:          RichTextLabel
var _field:        LineEdit
var _input_row:    Control
var _orbitron:     Font
var _history:  Array[String] = []
var _hist_idx: int = -1
var _open:     bool = false
var _booting:  bool = false

# Output typewriter state
var _out_lines: Array[String] = []   # collected by _log_* during _exec
var _out_gen:   int = 0              # increment to cancel in-progress drain

var show_planet_coords: bool = true

const MAX_LINES    := 200
const PANEL_H      := 300.0
const RIGHT_MARGIN_FRAC := 0.31   # right panel is anchored at 0.70 of vp; leave 31% gap
const FONT_SIZE    := 9

# Retro boot lines: [pre_delay_sec, bbcode_text, sec_per_char]
const BOOT_LINES: Array = [
	[0.00, "[color=#1e5c2a]╔══════════════════════════════════════╗[/color]",      0.010],
	[0.02, "[color=#1e5c2a]║[/color]  [color=#33aa55]VOIDLE/OS[/color]  [color=#2e7a3e]kernel 4.7.1-void[/color]       [color=#1e5c2a]║[/color]", 0.010],
	[0.02, "[color=#1e5c2a]╚══════════════════════════════════════╝[/color]",      0.010],
	[0.10, "[color=#2e7a3e]>[/color] [color=#33cc55]BOOT[/color]   neural_interface.sys   [color=#1a6630]......[/color] [color=#44ff77]OK[/color]", 0.016],
	[0.06, "[color=#2e7a3e]>[/color] [color=#33cc55]INIT[/color]   quantum_entropy_pool   [color=#1a6630]......[/color] [color=#44ff77]OK[/color]", 0.016],
	[0.06, "[color=#2e7a3e]>[/color] [color=#33cc55]LOAD[/color]   dev_console v3.9.2     [color=#1a6630]......[/color] [color=#44ff77]OK[/color]", 0.016],
	[0.06, "[color=#2e7a3e]>[/color] [color=#33cc55]SYNC[/color]   game_state_bridge      [color=#1a6630]......[/color] [color=#44ff77]OK[/color]", 0.016],
	[0.12, "",                                                                     0.0],
	[0.00, "[color=#55ff88]▸ ACCESS GRANTED  —  type help for commands[/color]",   0.022],
	[0.04, "",                                                                     0.0],
]

# ── Build ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 225
	_orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")
	_build_ui()
	_panel.visible = false
	# Tab always cycles back to the field (must be set after node is in tree)
	await get_tree().process_frame
	if is_instance_valid(_field):
		_field.focus_next     = _field.get_path()
		_field.focus_previous = _field.get_path()

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.clip_contents = true
	var s := StyleBoxFlat.new()
	s.bg_color             = Color(0.03, 0.05, 0.07, 0.97)
	s.border_color         = Color(0.20, 0.55, 0.30, 0.80)
	s.border_width_bottom  = 2
	s.border_width_right   = 1
	s.corner_radius_bottom_right = 6
	_panel.add_theme_stylebox_override("panel", s)
	# anchor_right = 0 → width set dynamically at open time from viewport
	_panel.anchor_left   = 0.0
	_panel.anchor_right  = 0.0
	_panel.anchor_top    = 0.0
	_panel.anchor_bottom = 0.0
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	_panel.offset_left   = 0.0
	_panel.offset_right  = 800.0   # placeholder; overwritten at open time
	_panel.offset_top    = -PANEL_H
	_panel.offset_bottom = 0.0
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	_top_spacer = Control.new()
	_top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_top_spacer)

	_log = RichTextLabel.new()
	_log.bbcode_enabled  = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, 250)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _orbitron:
		_log.add_theme_font_override("normal_font",   _orbitron)
		_log.add_theme_font_override("bold_font",     _orbitron)
		_log.add_theme_font_override("italics_font",  _orbitron)
	_log.add_theme_font_size_override("normal_font_size",   FONT_SIZE)
	_log.add_theme_font_size_override("bold_font_size",     FONT_SIZE)
	_log.add_theme_font_size_override("italics_font_size",  FONT_SIZE)
	_log.add_theme_color_override("default_color", Color(0.70, 0.82, 0.72))
	_log.focus_mode = Control.FOCUS_NONE
	vbox.add_child(_log)

	# Separator above input
	var sep := HSeparator.new()
	var sep_s := StyleBoxFlat.new()
	sep_s.bg_color = Color(0.18, 0.40, 0.24, 0.55)
	sep.add_theme_stylebox_override("separator", sep_s)
	vbox.add_child(sep)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_input_row = row
	vbox.add_child(row)

	var prompt := Label.new()
	prompt.text = ">"
	if _orbitron: prompt.add_theme_font_override("font", _orbitron)
	prompt.add_theme_font_size_override("font_size", FONT_SIZE)
	prompt.add_theme_color_override("font_color", Color(0.35, 0.85, 0.50))
	row.add_child(prompt)

	_field = LineEdit.new()
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.placeholder_text      = "enter command..."
	if _orbitron: _field.add_theme_font_override("font", _orbitron)
	_field.add_theme_font_size_override("font_size", FONT_SIZE)
	_field.add_theme_color_override("font_color",               Color(0.90, 0.95, 0.85))
	_field.add_theme_color_override("placeholder_color",        Color(0.35, 0.50, 0.38, 0.6))
	_field.add_theme_color_override("caret_color",              Color(0.45, 0.95, 0.60))
	_field.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_field.add_theme_stylebox_override("focus",  StyleBoxEmpty.new())
	_field.focus_mode = Control.FOCUS_ALL
	_field.text_submitted.connect(_on_submit)
	_field.text_changed.connect(func(_t: String) -> void: AudioManager.play("tick", -10.0))
	_field.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.IBEAM))
	_field.mouse_exited.connect(func()  -> void: CursorManager.set_state(CursorManager.State.NORMAL))
	row.add_child(_field)

# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke := event as InputEventKey
	if ke.pressed and ke.keycode == KEY_TAB and _open and not _booting:
		_field.grab_focus()
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke := event as InputEventKey
	# Toggle shortcut — always active
	if ke.pressed and ke.keycode == KEY_C \
			and ke.shift_pressed \
			and (ke.ctrl_pressed or ke.meta_pressed):
		_toggle()
		get_viewport().set_input_as_handled()
		return
	if not _open or not ke.pressed:
		return
	match ke.keycode:
		KEY_ESCAPE:
			_toggle()
			get_viewport().set_input_as_handled()
		KEY_UP:
			if _booting or _history.is_empty(): return
			_hist_idx = clampi(_hist_idx + 1, 0, _history.size() - 1)
			_field.text = _history[_history.size() - 1 - _hist_idx]
			_field.caret_column = _field.text.length()
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			if _booting: return
			if _hist_idx <= 0:
				_hist_idx = -1; _field.text = ""
			else:
				_hist_idx -= 1
				_field.text = _history[_history.size() - 1 - _hist_idx]
			_field.caret_column = _field.text.length()
			get_viewport().set_input_as_handled()

# ── Toggle / slide ────────────────────────────────────────────────────────────

func _toggle() -> void:
	_open = not _open
	if _open:
		# Set panel width: leave the right 31% for the game side panel
		var vp_w := get_viewport().get_visible_rect().size.x
		_panel.offset_right = vp_w * (1.0 - RIGHT_MARGIN_FRAC)

		var hud: Node = get_node_or_null("/root/HUDManager")
		var top_pad: float = 4.0
		if hud and hud.get("credits_panel") and is_instance_valid(hud.credits_panel):
			top_pad = hud.credits_panel.size.y + 2.0
		_top_spacer.custom_minimum_size = Vector2(0, top_pad)

		_field.text   = ""
		_hist_idx     = -1
		_input_row.visible = false   # hidden until boot finishes

		_panel.visible   = true
		_panel.offset_top    = -PANEL_H
		_panel.offset_bottom = 0.0
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
		tw.tween_property(_panel, "offset_top",    0.0,     0.22)
		tw.parallel().tween_property(_panel, "offset_bottom", PANEL_H, 0.22)
		tw.tween_callback(_play_boot_sequence)
	else:
		_out_gen += 1   # cancel any pending output animation
		_log.clear()
		var tw := create_tween()
		tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
		tw.tween_property(_panel, "offset_top",    -PANEL_H, 0.18)
		tw.parallel().tween_property(_panel, "offset_bottom", 0.0, 0.18)
		tw.tween_callback(func() -> void: _panel.visible = false)

# ── Boot animation ────────────────────────────────────────────────────────────

func _play_boot_sequence() -> void:
	if _booting: return
	_booting = true
	_log.clear()
	var completed: Array[String] = []

	for entry in BOOT_LINES:
		var pre_delay: float  = entry[0]
		var bbcode:    String = entry[1]
		var char_spd:  float  = entry[2]

		if pre_delay > 0.0:
			await get_tree().create_timer(pre_delay).timeout
		if not _open: break

		if bbcode == "":
			completed.append("")
			_redraw_log(completed, "")
			continue

		var plain := _strip_bbcode(bbcode)
		for i in plain.length():
			if not _open: break
			_redraw_log(completed, plain.substr(0, i + 1) + "▌")
			AudioManager.play("tick", -12.0)
			await get_tree().create_timer(char_spd).timeout

		completed.append(bbcode)
		_redraw_log(completed, "")

	_booting = false
	_input_row.visible = true
	_field.grab_focus()

func _redraw_log(lines: Array[String], current: String) -> void:
	_log.clear()
	for l in lines:
		_log.append_text(l + "\n")
	if current != "":
		_log.append_text("[color=#44cc66]" + current + "[/color]\n")

func _strip_bbcode(s: String) -> String:
	var out := ""; var in_tag := false
	for ch in s:
		if ch == "[": in_tag = true;  continue
		if ch == "]": in_tag = false; continue
		if not in_tag: out += ch
	return out

# ── Submit / exec ─────────────────────────────────────────────────────────────

func _on_submit(raw: String) -> void:
	var line := raw.strip_edges()
	if line.is_empty():
		_field.grab_focus(); return
	_history.append(line)
	_hist_idx = -1
	_field.text = ""
	_out_lines.clear()
	_raw_append("[color=#44aa66]> %s[/color]" % line)   # command echoes instantly
	_exec(line)
	# Animate the collected response lines
	_out_gen += 1
	_drain_output(_out_lines.duplicate(), _out_gen)
	# Wait one frame so Godot's focus system finishes processing Enter, then re-grab
	await get_tree().process_frame
	if _open and is_instance_valid(_field):
		_field.grab_focus()

func _drain_output(lines: Array, gen: int) -> void:
	for ln in lines:
		if _out_gen != gen or not _open: return
		_raw_append(ln)
		AudioManager.play("tick", -14.0)
		await get_tree().create_timer(0.018).timeout

func _exec(line: String) -> void:
	var parts := line.split(" ", false)
	if parts.is_empty(): return
	var cmd := parts[0].to_lower()

	match cmd:
		# ── Help ────────────────────────────────────────────────────────────
		"help", "--help", "-h":
			_log_info("[color=#33cc55]── ECONOMY ──────────────────────────────[/color]")
			_log_info("  [color=#88ddcc]credits[/color] [color=#aaaaaa]<amount>[/color]          — add credits")
			_log_info("  [color=#88ddcc]credits set[/color] [color=#aaaaaa]<amount>[/color]      — set exact")
			_log_info("  [color=#88ddcc]credits clear[/color]               — reset to 0")
			_log_info("[color=#33cc55]── UNLOCKS ──────────────────────────────[/color]")
			_log_info("  [color=#88ddcc]unlock solar / galaxy / moon / all[/color]")
			_log_info("  [color=#88ddcc]lock solar / galaxy / moon[/color]")
			_log_info("[color=#33cc55]── SCIENCE ──────────────────────────────[/color]")
			_log_info("  [color=#88ddcc]science[/color] [color=#aaaaaa][amount][/color]           — show or add")
			_log_info("  [color=#88ddcc]science set[/color] [color=#aaaaaa]<amount>[/color]       — set exact")
			_log_info("  [color=#88ddcc]science clear[/color]")
			_log_info("[color=#33cc55]── COLONY / ASTEROID ────────────────────[/color]")
			_log_info("  [color=#88ddcc]colonize[/color]  [color=#88ddcc]scan asteroid[/color] [color=#aaaaaa][all][/color]")
			_log_info("  [color=#88ddcc]asteroids[/color]")
			_log_info("[color=#33cc55]── SKILL TREE ───────────────────────────[/color]")
			_log_info("  [color=#88ddcc]skilltree unhide -all[/color]  [color=#88ddcc]hide -all[/color]")
			_log_info("[color=#33cc55]── DEBUG ─────────────────────────────────[/color]")
			_log_info("  [color=#88ddcc]state[/color]  [color=#88ddcc]clear[/color]  [color=#88ddcc]debug coords[/color]")

		# ── Credits ─────────────────────────────────────────────────────────
		"credits":
			if parts.size() == 1:
				_log_info("[color=#aaaaaa]credits[/color]  [color=#ffdd66]%s[/color]" % HUDManager.fmt_credits(GameState.credits))
				return
			var sub := parts[1].to_lower() if parts.size() > 1 else ""
			match sub:
				"set":
					var v := _parse_float(parts, 2); if is_nan(v): return
					GameState.credits = v
					_log_ok("Credits → [color=#ffdd66]%s[/color]" % HUDManager.fmt_credits(GameState.credits))
				"clear":
					GameState.credits = 0.0; _log_ok("Credits cleared.")
				_:
					var v := _parse_float(parts, 1); if is_nan(v): return
					GameState.credits += v
					_log_ok("+[color=#ffdd66]%s[/color]  total [color=#ffdd66]%s[/color]" % [
						HUDManager.fmt_credits(v), HUDManager.fmt_credits(GameState.credits)])

		# ── Science ─────────────────────────────────────────────────────────
		"science":
			if parts.size() == 1:
				_log_info("[color=#aaaaaa]science[/color]  [color=#66ccff]%.0f[/color]" % GameState.science_points)
				return
			var sub := parts[1].to_lower() if parts.size() > 1 else ""
			match sub:
				"set":
					var v := _parse_float(parts, 2); if is_nan(v): return
					GameState.science_points = v
					GameState.science_changed.emit(GameState.science_points)
					_log_ok("Science → [color=#66ccff]%.0f[/color]" % GameState.science_points)
				"clear":
					GameState.science_points = 0.0
					GameState.science_changed.emit(0.0)
					_log_ok("Science cleared.")
				_:
					var v := _parse_float(parts, 1); if is_nan(v): return
					GameState.add_science(v)
					_log_ok("+[color=#66ccff]%.0f[/color]  total [color=#66ccff]%.0f[/color]" % [v, GameState.science_points])

		# ── Skill Tree ────────────────────────────────────────────────────────
		"skilltree":
			var sub := parts[1].to_lower() if parts.size() > 1 else ""
			var opt := parts[2].to_lower() if parts.size() > 2 else ""
			if sub == "unhide" and opt == "-all":
				var st = get_tree().root.get_node("SkillTree")
				st.set_meta("debug_reveal_all", true)
				st.skill_unlocked.emit("debug")
				_log_ok("SkillTree nodes [color=#55ff88]revealed[/color] (visual only).")
			elif sub == "hide" and opt == "-all":
				var st = get_tree().root.get_node("SkillTree")
				st.set_meta("debug_reveal_all", false)
				st.skill_unlocked.emit("debug")
				_log_ok("SkillTree nodes [color=#ee5555]hidden[/color].")
			else:
				_log_err("Usage: skilltree unhide -all | skilltree hide -all")

		# ── Unlocks ─────────────────────────────────────────────────────────
		"unlock":
			var target := parts[1].to_lower() if parts.size() > 1 else ""
			match target:
				"solar":
					GameState.moon_unlocked = true; GameState.solar_unlocked = true
					GameState.unlock_changed.emit("moon_unlocked", true)
					GameState.unlock_changed.emit("solar_unlocked", true)
					_log_ok("[color=#55ff88]Solar[/color] (+ Moons) unlocked.")
				"galaxy":
					GameState.moon_unlocked = true; GameState.solar_unlocked = true; GameState.galaxy_unlocked = true
					GameState.unlock_changed.emit("moon_unlocked", true)
					GameState.unlock_changed.emit("solar_unlocked", true)
					GameState.unlock_changed.emit("galaxy_unlocked", true)
					_log_ok("[color=#55ff88]Galaxy[/color] (+ Solar, Moons) unlocked.")
				"moon", "moons":
					GameState.moon_unlocked = true
					GameState.unlock_changed.emit("moon_unlocked", true)
					_log_ok("[color=#55ff88]Moons[/color] unlocked.")
				"all":
					GameState.moon_unlocked = true; GameState.solar_unlocked = true; GameState.galaxy_unlocked = true
					GameState.unlock_changed.emit("moon_unlocked", true)
					GameState.unlock_changed.emit("solar_unlocked", true)
					GameState.unlock_changed.emit("galaxy_unlocked", true)
					_log_ok("[color=#55ff88]Everything[/color] unlocked.")
				_:
					_log_err("Unknown target: '%s'" % target)

		"lock":
			var target := parts[1].to_lower() if parts.size() > 1 else ""
			match target:
				"solar":
					GameState.solar_unlocked = false; GameState.galaxy_unlocked = false
					GameState.unlock_changed.emit("solar_unlocked", false)
					GameState.unlock_changed.emit("galaxy_unlocked", false)
					_log_ok("[color=#ee5555]Solar[/color] (+ Galaxy) locked.")
				"galaxy":
					GameState.galaxy_unlocked = false
					GameState.unlock_changed.emit("galaxy_unlocked", false)
					_log_ok("[color=#ee5555]Galaxy[/color] locked.")
				"moon", "moons":
					GameState.moon_unlocked = false; GameState.solar_unlocked = false; GameState.galaxy_unlocked = false
					GameState.unlock_changed.emit("moon_unlocked", false)
					GameState.unlock_changed.emit("solar_unlocked", false)
					GameState.unlock_changed.emit("galaxy_unlocked", false)
					_log_ok("[color=#ee5555]Moons[/color] (+ Solar, Galaxy) locked.")
				_:
					_log_err("Unknown target: '%s'" % target)

		# ── Debug ───────────────────────────────────────────────────────────
		"debug":
			var target := parts[1].to_lower() if parts.size() > 1 else ""
			match target:
				"coords":
					show_planet_coords = not show_planet_coords
					var s := "[color=#55ff88]ON[/color]" if show_planet_coords else "[color=#ee5555]OFF[/color]"
					_log_ok("Planet coords: %s" % s)
				_:
					_log_err("Unknown debug target. Try: coords")

		# ── Colony ──────────────────────────────────────────────────────────
		"colonize":
			var seed := GameState.active_planet_seed
			if seed < 0: _log_err("Not viewing a planet."); return
			var pp := GameState.get_planet(seed)
			pp.is_colonized = true
			GameState.planet_progress_changed.emit(seed)
			_log_ok("Planet [color=#aabbff]#%d[/color] colonized." % seed)

		# ── Asteroid ────────────────────────────────────────────────────────
		"scan":
			var target := parts[1].to_lower() if parts.size() > 1 else ""
			if target != "asteroid": _log_err("Try: scan asteroid"); return
			var sd := GameState.get_home_solar()
			if sd.asteroid_belt_slots.is_empty(): _log_err("No asteroid belts."); return
			var sub := parts[2].to_lower() if parts.size() >= 3 else ""
			if sub == "all":
				var total := 0
				for sl in sd.asteroid_belt_slots:
					for _i in 3 - GameState.asteroid_scan_counts.get(sl, 0):
						GameState.discover_asteroid(sl); total += 1
				if total == 0: _log_info("All already scanned.")
				else: _log_ok("Revealed [color=#ffcc55]%d[/color] asteroid(s)." % total)
			else:
				var slot := -1
				for sl in sd.asteroid_belt_slots:
					if GameState.asteroid_scan_counts.get(sl, 0) < 3: slot = sl; break
				if slot < 0: _log_info("All scanned."); return
				GameState.discover_asteroid(slot)
				var cnt: int = GameState.asteroid_scan_counts.get(slot, 0)
				_log_ok("Belt [color=#aabbff]%d[/color] — [color=#ffcc55]%d/3[/color] revealed." % [slot, cnt])

		"asteroids":
			var sd := GameState.get_home_solar()
			if sd.asteroid_belt_slots.is_empty(): _log_info("No belts."); return
			_log_info("[color=#aabbff]Asteroid Belts[/color]")
			for sl in sd.asteroid_belt_slots:
				var cnt: int = GameState.asteroid_scan_counts.get(sl, 0)
				var status: String
				if   cnt == 0: status = "[color=#ee5555]undiscovered[/color]"
				elif cnt < 3:  status = "[color=#ffcc55]%d/3 scanned[/color]" % cnt
				else:          status = "[color=#88ddaa]fully scanned[/color]"
				_log_info("  [color=#aaaaaa]slot %d[/color] — %s" % [sl, status])

		# ── State ───────────────────────────────────────────────────────────
		"state":
			var pp := GameState.get_planet(GameState.home_planet_seed)
			var yn := func(b: bool) -> String:
				return "[color=#55ff88]yes[/color]" if b else "[color=#ee5555]no[/color]"
			_log_info("[color=#aabbff]─── Game State ───────────────────────[/color]")
			_log_info("  [color=#aaaaaa]Credits[/color]         [color=#ffdd66]%s[/color]" % HUDManager.fmt_credits(GameState.credits))
			_log_info("  [color=#aaaaaa]Science[/color]         [color=#66ccff]%s[/color]" % HUDManager.fmt_science(GameState.science_points))
			_log_info("  [color=#aaaaaa]Solar unlocked[/color]  %s" % yn.call(GameState.solar_unlocked))
			_log_info("  [color=#aaaaaa]Galaxy unlocked[/color] %s" % yn.call(GameState.galaxy_unlocked))
			_log_info("  [color=#aaaaaa]Home colonized[/color]  %s" % yn.call(pp.is_colonized))
			_log_info("  [color=#aaaaaa]Districts[/color]       [color=#ccddff]%d[/color]" % GameState.get_home_planet().custom_pois.size())
			_log_info("  [color=#aaaaaa]Buildings[/color]       [color=#ccddff]%d[/color]" % pp.buildings.size())

		# ── Clear ───────────────────────────────────────────────────────────
		"clear":
			_out_gen += 1   # cancel pending drain
			_log.clear()

		_:
			_log_err("Unknown: '[color=#ffcc55]%s[/color]' — type help" % cmd)

# ── Logging helpers ───────────────────────────────────────────────────────────

# Queued (animated) output — used by most commands
func _log_ok(text: String) -> void:
	_out_lines.append("[color=#88ddaa]✓ %s[/color]" % text)

func _log_err(text: String) -> void:
	_out_lines.append("[color=#ee5555]✗ %s[/color]" % text)

func _log_info(text: String) -> void:
	_out_lines.append(text)

# Immediate write (boot sequence and command echo)
func _raw_append(bbcode: String) -> void:
	if _log.get_parsed_text().split("\n").size() > MAX_LINES:
		_log.clear()
	_log.append_text(bbcode + "\n")

# ── Helpers ──────────────────────────────────────────────────────────────────

func _parse_float(parts: Array, idx: int) -> float:
	if idx >= parts.size(): _log_err("Missing number."); return NAN
	var s: String = parts[idx]
	if s.ends_with("k") or s.ends_with("K"): return s.left(s.length()-1).to_float() * 1_000.0
	if s.ends_with("m") or s.ends_with("M"): return s.left(s.length()-1).to_float() * 1_000_000.0
	if not s.is_valid_float(): _log_err("'%s' is not a number." % s); return NAN
	return s.to_float()
