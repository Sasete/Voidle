import re

with open("scripts/planetary/PlanetaryView.gd", "r") as f:
    content = f.read()

# Fix 1: MarginContainer for Empty Slot
target_empty_slot = """	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size   = Vector2(0, 56)

	var lbl := Label.new()
	lbl.text = "+ Empty Slot"
	_apply_orbitron(lbl, 11)"""

replacement_empty_slot = """	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size   = Vector2(0, 56)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 24)
	card.add_child(margin)

	var lbl := Label.new()
	lbl.text = "+ Empty Slot"
	_apply_orbitron(lbl, 11)"""

content = content.replace(target_empty_slot, replacement_empty_slot)
content = content.replace("card.add_child(lbl)", "margin.add_child(lbl)")

# Fix 2: Debug Spam - Wait, debug spam was in PlanetaryView.gd?
# "Bu bir mahalle ismi, bina barı aramana gerek yok" -> Wait, that was fixed in PlanetaryView.gd `_on_production_update`.
# Let's check where `_on_production_update` prints an error.
target_debug = """	if not _bar_meta.has(key):
		push_warning("Key not in `_bar_meta`: " + key)
		return"""

replacement_debug = """	if not _bar_meta.has(key):
		return"""
content = content.replace(target_debug, replacement_debug)

# Fix 3: Slowed label visibility with is_user_paused
target_slowed = """		if is_instance_valid(slowed_lbl):
			var er := ProductionManager.get_energy_ratio(m.get("planet_seed", -1))
			slowed_lbl.text    = "⚡ Slowed %d%% — Energy Crisis" % [int((1.0 - er) * 100)]
			slowed_lbl.visible = not paused and er < 0.999"""

replacement_slowed = """		if is_instance_valid(slowed_lbl):
			var er := ProductionManager.get_energy_ratio(m.get("planet_seed", -1))
			slowed_lbl.text    = "⚡ Slowed %d%% — Energy Crisis" % [int((1.0 - er) * 100)]
			var is_user_paused := ProductionManager.is_user_paused(key)
			slowed_lbl.visible = not paused and not is_user_paused and er < 0.999"""
content = content.replace(target_slowed, replacement_slowed)


# Fix 4: root.add_child instead of planet_page.add_child for limits_row and below
content = content.replace("planet_page.add_child(limits_row)", "root.add_child(limits_row)")
content = content.replace("planet_page.add_child(tab_sep)", "root.add_child(tab_sep)")
content = content.replace("planet_page.add_child(tab_row)", "root.add_child(tab_row)")
content = content.replace("planet_page.add_child(dist_scroll)", "root.add_child(dist_scroll)")
content = content.replace("planet_page.add_child(orb_scroll)", "root.add_child(orb_scroll)")
content = content.replace("planet_page.add_child(lvl_sep)", "root.add_child(lvl_sep)")
content = content.replace("planet_page.add_child(up_lbl)", "root.add_child(up_lbl)")
content = content.replace("planet_page.add_child(_planet_upgrade_pbar)", "root.add_child(_planet_upgrade_pbar)")
content = content.replace("planet_page.add_child(up_btn)", "root.add_child(up_btn)")

# Fix 5: The layout of limits_row based on user's new request:
target_limits = """	var p_max_orbital := 0
	for p_def: DistrictDef in DistrictDef.all():
		if p_def.is_orbital and p_def.max_per_planet > 0:
			p_max_orbital += p_def.max_per_planet

	# Single row: [Surface group] [spacer] [Orbital group]
	# Each group is a VBox: slots on top, label below.
	var limits_row := HBoxContainer.new()
	limits_row.add_theme_constant_override("separation", 0)
	limits_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for slot_info: Array in [
		["Surface", surface_pois.size(), pp.max_districts],
		["Orbital", orbital_pois.size(), max(1, p_max_orbital)]
	]:
		var group_vbox := VBoxContainer.new()
		group_vbox.add_theme_constant_override("separation", 3)
		group_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slots_hbox := HBoxContainer.new()
		slots_hbox.add_theme_constant_override("separation", 3)
		slots_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slots_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE"""

replacement_limits = """	var p_max_orbital := 0
	var st := get_node_or_null("/root/SkillTree")
	var has_orbital_unlocked := false
	for p_def: DistrictDef in DistrictDef.all():
		if p_def.is_orbital and p_def.max_per_planet > 0:
			if p_def.unlock_skill == "" or (st != null and st.is_unlocked(p_def.unlock_skill)):
				has_orbital_unlocked = true
				p_max_orbital += p_def.max_per_planet

	# Single row: [Surface group] [spacer] [Orbital group]
	# Each group is a VBox: slots on top, label below.
	var limits_row := HBoxContainer.new()
	limits_row.add_theme_constant_override("separation", 0)
	limits_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slot_info_arr: Array = [ ["Surface", surface_pois.size(), pp.max_districts] ]
	if has_orbital_unlocked:
		slot_info_arr.append(["Orbital", orbital_pois.size(), max(1, p_max_orbital)])
		
	for slot_info: Array in slot_info_arr:
		var group_vbox := VBoxContainer.new()
		group_vbox.add_theme_constant_override("separation", 3)
		group_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slots_hbox := HBoxContainer.new()
		slots_hbox.add_theme_constant_override("separation", 3)
		slots_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not has_orbital_unlocked:
			slots_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		slots_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE"""

content = content.replace(target_limits, replacement_limits)

# Tab buttons conditional addition
target_tabs = """	var dist_btn:    Button = _make_overview_tab_btn("SURFACE", _inner_tab_active == "SURFACE")
	var orbital_btn: Button = _make_overview_tab_btn("ORBITAL", _inner_tab_active == "ORBITAL")
	tab_row.add_child(dist_btn)
	tab_row.add_child(orbital_btn)"""

replacement_tabs = """	var dist_btn:    Button = _make_overview_tab_btn("SURFACE", _inner_tab_active == "SURFACE")
	var orbital_btn: Button = _make_overview_tab_btn("ORBITAL", _inner_tab_active == "ORBITAL")
	tab_row.add_child(dist_btn)
	if has_orbital_unlocked:
		tab_row.add_child(orbital_btn)"""
content = content.replace(target_tabs, replacement_tabs)

# Orbital scrolling visibility
target_vis = """	# ── Tab switching ─────────────────────────────────────────────────────────
	dist_btn.toggled.connect(func(on: bool) -> void:
		if on:
			_inner_tab_active = "SURFACE"
			orbital_btn.button_pressed = false
			dist_scroll.visible = true
			orb_scroll.visible  = false)
	orbital_btn.toggled.connect(func(on: bool) -> void:
		if on:
			_inner_tab_active = "ORBITAL"
			dist_btn.button_pressed = false
			dist_scroll.visible = false
			orb_scroll.visible  = true)
	# Restore correct visibility based on saved state
	dist_scroll.visible = (_inner_tab_active == "SURFACE")
	orb_scroll.visible  = (_inner_tab_active == "ORBITAL")"""

replacement_vis = """	# ── Tab switching ─────────────────────────────────────────────────────────
	if not has_orbital_unlocked and _inner_tab_active == "ORBITAL":
		_inner_tab_active = "SURFACE"

	dist_btn.toggled.connect(func(on: bool) -> void:
		if on:
			_inner_tab_active = "SURFACE"
			orbital_btn.button_pressed = false
			dist_scroll.visible = true
			orb_scroll.visible  = false)
	orbital_btn.toggled.connect(func(on: bool) -> void:
		if on:
			_inner_tab_active = "ORBITAL"
			dist_btn.button_pressed = false
			dist_scroll.visible = false
			orb_scroll.visible  = true)
	# Restore correct visibility based on saved state
	dist_scroll.visible = (_inner_tab_active == "SURFACE")
	orb_scroll.visible  = (_inner_tab_active == "ORBITAL") and has_orbital_unlocked"""
content = content.replace(target_vis, replacement_vis)

with open("scripts/planetary/PlanetaryView.gd", "w") as f:
    f.write(content)

print("Done reapplying")
