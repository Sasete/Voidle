## Developer console — toggle with Cmd+Shift+C (Mac) or Ctrl+Shift+C (Win/Linux).
## Type "help" for a list of commands.
extends CanvasLayer

var _panel:    Control
var _log:      RichTextLabel
var _field:    LineEdit
var _orbitron: Font
var _history:  Array[String] = []
var _hist_idx: int = -1
var _open:     bool = false

var show_planet_coords: bool = true

const MAX_LINES := 200

func _ready() -> void:
	layer = 200   # above everything
	_orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")
	_build_ui()
	_panel.visible = false

func _build_ui() -> void:
	_panel = PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color    = Color(0.04, 0.05, 0.08, 0.96)
	s.border_color = Color(0.25, 0.55, 0.35, 0.70)
	s.border_width_bottom = 2
	s.corner_radius_bottom_left  = 0
	s.corner_radius_bottom_right = 0
	_panel.add_theme_stylebox_override("panel", s)
	_panel.anchor_left   = 0.0
	_panel.anchor_right  = 1.0
	_panel.anchor_top    = 0.0
	_panel.anchor_bottom = 0.0
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	_panel.offset_bottom = 320.0
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	# Title bar
	var title := Label.new()
	title.text = "▸ VOIDLE DEV CONSOLE  —  type 'help' for commands"
	if _orbitron: title.add_theme_font_override("font", _orbitron)
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color(0.35, 0.75, 0.45))
	vbox.add_child(title)

	var sep := HSeparator.new()
	var sep_s := StyleBoxFlat.new()
	sep_s.bg_color = Color(0.20, 0.45, 0.28, 0.55)
	sep.add_theme_stylebox_override("separator", sep_s)
	vbox.add_child(sep)

	# Log area
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, 240)
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _orbitron: _log.add_theme_font_override("normal_font", _orbitron)
	_log.add_theme_font_size_override("normal_font_size", 9)
	_log.add_theme_color_override("default_color", Color(0.75, 0.85, 0.78))
	vbox.add_child(_log)

	# Input row
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	vbox.add_child(row)

	var prompt := Label.new()
	prompt.text = ">"
	if _orbitron: prompt.add_theme_font_override("font", _orbitron)
	prompt.add_theme_font_size_override("font_size", 10)
	prompt.add_theme_color_override("font_color", Color(0.35, 0.85, 0.50))
	row.add_child(prompt)

	_field = LineEdit.new()
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.placeholder_text = "enter command..."
	if _orbitron: _field.add_theme_font_override("font", _orbitron)
	_field.add_theme_font_size_override("font_size", 10)
	_field.add_theme_color_override("font_color", Color(0.90, 0.95, 0.85))
	_field.add_theme_stylebox_override("normal",  StyleBoxEmpty.new())
	_field.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())
	_field.text_submitted.connect(_on_submit)
	row.add_child(_field)

	_log_info("Console ready. Type [color=#55cc77]help[/color] for a list of commands.")

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_C \
				and ke.shift_pressed \
				and (ke.ctrl_pressed or ke.meta_pressed):
			_toggle()
			get_viewport().set_input_as_handled()
			return
		if _open and ke.pressed:
			match ke.keycode:
				KEY_UP:
					if _history.is_empty(): return
					_hist_idx = clampi(_hist_idx + 1, 0, _history.size() - 1)
					_field.text = _history[_history.size() - 1 - _hist_idx]
					_field.caret_column = _field.text.length()
					get_viewport().set_input_as_handled()
				KEY_DOWN:
					if _hist_idx <= 0:
						_hist_idx = -1
						_field.text = ""
					else:
						_hist_idx -= 1
						_field.text = _history[_history.size() - 1 - _hist_idx]
					_field.caret_column = _field.text.length()
					get_viewport().set_input_as_handled()
				KEY_TAB:
					_field.grab_focus()
					get_viewport().set_input_as_handled()
				KEY_ESCAPE:
					_toggle()
					get_viewport().set_input_as_handled()

func _toggle() -> void:
	_open = not _open
	_panel.visible = _open
	if _open:
		_field.grab_focus()
		_field.text = ""
		_hist_idx = -1

func _on_submit(raw: String) -> void:
	var line := raw.strip_edges()
	if line.is_empty():
		_field.grab_focus()
		return
	_history.append(line)
	_hist_idx = -1
	_field.text = ""
	_log_cmd(line)
	_exec(line)
	_field.call_deferred("grab_focus")

func _exec(line: String) -> void:
	var parts := line.split(" ", false)
	if parts.is_empty():
		return
	var cmd := parts[0].to_lower()

	match cmd:
		# ── Help ────────────────────────────────────────────────────────────
		"help", "--help", "-h":
			_log_info("""[color=#55cc77]ECONOMY[/color]
  credits [b]<amount>[/b]          — add credits
  credits set [b]<amount>[/b]       — set credits to exact value
  credits clear                  — set to 0

[color=#55cc77]UNLOCKS[/color]
  unlock solar                   — unlock Solar View
  unlock galaxy                  — unlock Galaxy View
  unlock moon                    — unlock moons for current planet
  unlock all                     — unlock everything (incl. moons)
  lock solar / lock galaxy / lock moon  — re-lock

[color=#55cc77]COLONY[/color]
  colonize                       — colonize current home planet

[color=#55cc77]ASTEROID[/color]
  scan asteroid                  — discover 1 undiscovered asteroid belt
  scan asteroid all              — discover all asteroid belts in home system
  asteroids                      — list asteroid belt slots & discovery status

[color=#55cc77]DEBUG[/color]
  state                          — print current game state summary
  clear                          — clear console log
  debug coords                   — toggle planetary click coordinates""")

		# ── Credits ─────────────────────────────────────────────────────────
		"credits":
			if parts.size() == 1:
				_log_info("Credits: [b]%s[/b]" % HUDManager.fmt_credits(GameState.credits))
				return
			var sub := parts[1].to_lower() if parts.size() > 1 else ""
			match sub:
				"set":
					var v := _parse_float(parts, 2)
					if is_nan(v): return
					GameState.credits = v
					_log_ok("Credits set to %s" % HUDManager.fmt_credits(GameState.credits))
				"clear":
					GameState.credits = 0.0
					_log_ok("Credits cleared.")
				_:
					var v := _parse_float(parts, 1)
					if is_nan(v): return
					GameState.credits += v
					_log_ok("Added %s → total %s" % [
						HUDManager.fmt_credits(v),
						HUDManager.fmt_credits(GameState.credits)])

		# ── Unlocks ─────────────────────────────────────────────────────────
		"unlock":
			var target := parts[1].to_lower() if parts.size() > 1 else ""
			match target:
				"solar":
					GameState.moon_unlocked  = true
					GameState.solar_unlocked = true
					GameState.unlock_changed.emit("moon_unlocked", true)
					GameState.unlock_changed.emit("solar_unlocked", true)
					_log_ok("Solar View (and Moons) unlocked.")
				"galaxy":
					GameState.moon_unlocked   = true
					GameState.solar_unlocked  = true
					GameState.galaxy_unlocked = true
					GameState.unlock_changed.emit("moon_unlocked", true)
					GameState.unlock_changed.emit("solar_unlocked", true)
					GameState.unlock_changed.emit("galaxy_unlocked", true)
					_log_ok("Galaxy View (and Solar, Moons) unlocked.")
				"moon", "moons":
					GameState.moon_unlocked = true
					GameState.unlock_changed.emit("moon_unlocked", true)
					_log_ok("Moons globally unlocked.")
				"all":
					GameState.moon_unlocked   = true
					GameState.solar_unlocked  = true
					GameState.galaxy_unlocked = true
					GameState.unlock_changed.emit("moon_unlocked", true)
					GameState.unlock_changed.emit("solar_unlocked",  true)
					GameState.unlock_changed.emit("galaxy_unlocked", true)
					_log_ok("Everything unlocked.")
				_:
					_log_err("Unknown unlock target: '%s'. Try: solar, galaxy, moon, all" % target)

		# ── Debug ───────────────────────────────────────────────────────────
		"debug":
			var target := parts[1].to_lower() if parts.size() > 1 else ""
			match target:
				"coords":
					show_planet_coords = not show_planet_coords
					_log_ok("Planet click coordinates: [b]%s[/b]" % ("ON" if show_planet_coords else "OFF"))
				_:
					_log_err("Unknown debug target. Try: coords")

		"lock":
			var target := parts[1].to_lower() if parts.size() > 1 else ""
			match target:
				"solar":
					GameState.solar_unlocked = false
					GameState.galaxy_unlocked = false
					GameState.unlock_changed.emit("solar_unlocked", false)
					GameState.unlock_changed.emit("galaxy_unlocked", false)
					_log_ok("Solar View (and Galaxy) locked.")
				"galaxy":
					GameState.galaxy_unlocked = false
					GameState.unlock_changed.emit("galaxy_unlocked", false)
					_log_ok("Galaxy View locked.")
				"moon", "moons":
					GameState.moon_unlocked = false
					GameState.solar_unlocked = false
					GameState.galaxy_unlocked = false
					GameState.unlock_changed.emit("moon_unlocked", false)
					GameState.unlock_changed.emit("solar_unlocked", false)
					GameState.unlock_changed.emit("galaxy_unlocked", false)
					_log_ok("Moons (and Solar, Galaxy) locked.")
				_:
					_log_err("Unknown lock target: '%s'. Try: solar, galaxy, moon" % target)

		# ── Colony ──────────────────────────────────────────────────────────
		"colonize":
			var seed := GameState.active_planet_seed
			if seed < 0:
				_log_err("Not currently viewing a planet.")
				return
			var pp := GameState.get_planet(seed)
			pp.is_colonized = true
			GameState.planet_progress_changed.emit(seed)
			_log_ok("Planet (seed %d) colonized." % seed)

		# ── Asteroid ────────────────────────────────────────────────────────
		"scan":
			var target := parts[1].to_lower() if parts.size() > 1 else ""
			if target != "asteroid":
				_log_err("Unknown scan target: '%s'. Try: scan asteroid" % target)
				return
			var sd := GameState.get_home_solar()
			if sd.asteroid_belt_slots.is_empty():
				_log_err("No asteroid belts in the home system.")
				return
			var sub := parts[2].to_lower() if parts.size() >= 3 else ""
			if sub == "all":
				var total_added := 0
				for s in sd.asteroid_belt_slots:
					var cur: int = GameState.asteroid_scan_counts.get(s, 0)
					for _i in 3 - cur:
						GameState.discover_asteroid(s)
						total_added += 1
				if total_added == 0:
					_log_info("All asteroids already fully scanned.")
				else:
					_log_ok("Revealed %d asteroid(s) across %d belt(s)." % [total_added, sd.asteroid_belt_slots.size()])
			else:
				# find first slot that isn't fully scanned (count < 3)
				var target_slot := -1
				for s in sd.asteroid_belt_slots:
					if GameState.asteroid_scan_counts.get(s, 0) < 3:
						target_slot = s
						break
				if target_slot < 0:
					_log_info("All asteroids already fully scanned. Use [b]scan asteroid all[/b] to reset.")
					return
				GameState.discover_asteroid(target_slot)
				var new_count: int = GameState.asteroid_scan_counts.get(target_slot, 0)
				_log_ok("Asteroid scanned in belt slot %d — %d/3 revealed." % [target_slot, new_count])

		"asteroids":
			var sd := GameState.get_home_solar()
			if sd.asteroid_belt_slots.is_empty():
				_log_info("No asteroid belts in the home system.")
				return
			var lines := "[color=#aabbff]Asteroid Belts — Home System[/color]\n"
			for s in sd.asteroid_belt_slots:
				var cnt: int = GameState.asteroid_scan_counts.get(s, 0)
				var status: String
				if   cnt == 0: status = "[color=#ee5555]undiscovered[/color]"
				elif cnt < 3:  status = "[color=#ffcc55]%d/3 scanned[/color]" % cnt
				else:          status = "[color=#88ddaa]fully scanned (3/3)[/color]"
				lines += "  Slot %d — %s\n" % [s, status]
			_log_info(lines)

		# ── State ───────────────────────────────────────────────────────────
		"state":
			var pp := GameState.get_planet(GameState.home_planet_seed)
			_log_info("""[color=#aabbff]Game State[/color]
  Credits:        [b]%s[/b]
  Solar unlocked: [b]%s[/b]
  Galaxy unlocked:[b]%s[/b]
  Home colonized: [b]%s[/b]
  Home districts: [b]%d[/b]
  Home buildings: [b]%d[/b]""" % [
				HUDManager.fmt_credits(GameState.credits),
				str(GameState.solar_unlocked),
				str(GameState.galaxy_unlocked),
				str(pp.is_colonized),
				GameState.get_home_planet().custom_pois.size(),
				pp.buildings.size()])

		# ── Clear ───────────────────────────────────────────────────────────
		"clear":
			_log.clear()

		_:
			_log_err("Unknown command: '%s' — type 'help' for a list." % cmd)

# ── Logging helpers ───────────────────────────────────────────────────────────

func _log_cmd(text: String) -> void:
	_append("[color=#44aa66]> %s[/color]" % text)

func _log_ok(text: String) -> void:
	_append("[color=#88ddaa]✓ %s[/color]" % text)

func _log_err(text: String) -> void:
	_append("[color=#ee5555]✗ %s[/color]" % text)

func _log_info(text: String) -> void:
	_append(text)

func _append(bbcode: String) -> void:
	if _log.get_parsed_text().split("\n").size() > MAX_LINES:
		_log.clear()
	_log.append_text(bbcode + "\n")

# ── Helpers ──────────────────────────────────────────────────────────────────

func _parse_float(parts: Array, idx: int) -> float:
	if idx >= parts.size():
		_log_err("Missing numeric argument.")
		return NAN
	var s: String = parts[idx]
	# Support k/m suffix
	if s.ends_with("k") or s.ends_with("K"):
		return s.left(s.length() - 1).to_float() * 1_000.0
	if s.ends_with("m") or s.ends_with("M"):
		return s.left(s.length() - 1).to_float() * 1_000_000.0
	if not s.is_valid_float():
		_log_err("'%s' is not a valid number." % s)
		return NAN
	return s.to_float()
