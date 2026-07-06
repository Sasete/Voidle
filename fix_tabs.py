import re

with open("scripts/planetary/PlanetaryView.gd", "r") as f:
    content = f.read()

# Replace planet_page.add_child with root.add_child for limits_row and later
content = content.replace("planet_page.add_child(limits_row)", "root.add_child(limits_row)")
content = content.replace("planet_page.add_child(tab_sep)", "root.add_child(tab_sep)")
content = content.replace("planet_page.add_child(tab_row)", "root.add_child(tab_row)")
content = content.replace("planet_page.add_child(dist_scroll)", "root.add_child(dist_scroll)")
content = content.replace("planet_page.add_child(orb_scroll)", "root.add_child(orb_scroll)")
content = content.replace("planet_page.add_child(lvl_sep)", "root.add_child(lvl_sep)")
content = content.replace("planet_page.add_child(up_lbl)", "root.add_child(up_lbl)")
content = content.replace("planet_page.add_child(_planet_upgrade_pbar)", "root.add_child(_planet_upgrade_pbar)")
content = content.replace("planet_page.add_child(up_btn)", "root.add_child(up_btn)")

# Add has_orbital_unlocked logic
target1 = """	var p_max_orbital := 0
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
	]:"""

replacement1 = """	var p_max_orbital := 0
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

	for slot_info: Array in slot_info_arr:"""
content = content.replace(target1, replacement1)

# Tab buttons conditional addition
target2 = """	var dist_btn:    Button = _make_overview_tab_btn("SURFACE", _inner_tab_active == "SURFACE")
	var orbital_btn: Button = _make_overview_tab_btn("ORBITAL", _inner_tab_active == "ORBITAL")
	tab_row.add_child(dist_btn)
	tab_row.add_child(orbital_btn)"""

replacement2 = """	var dist_btn:    Button = _make_overview_tab_btn("SURFACE", _inner_tab_active == "SURFACE")
	var orbital_btn: Button = _make_overview_tab_btn("ORBITAL", _inner_tab_active == "ORBITAL")
	tab_row.add_child(dist_btn)
	if has_orbital_unlocked:
		tab_row.add_child(orbital_btn)"""
content = content.replace(target2, replacement2)

# Orbital scrolling visibility
target3 = """	# ── Tab switching ─────────────────────────────────────────────────────────
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

replacement3 = """	# ── Tab switching ─────────────────────────────────────────────────────────
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
content = content.replace(target3, replacement3)

with open("scripts/planetary/PlanetaryView.gd", "w") as f:
    f.write(content)

print("Done")
