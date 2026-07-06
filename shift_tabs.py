import re

with open("scripts/planetary/PlanetaryView.gd", "r") as f:
    content = f.read()

target = """	# Single row: [Surface group] [spacer] [Orbital group]
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
		slots_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var filled: int = slot_info[1]; var total: int = slot_info[2]
		for idx in total:
			var slot_pc := PanelContainer.new()
			slot_pc.custom_minimum_size = Vector2(14, 10)
			var slot_s := StyleBoxFlat.new()
			if idx < filled:
				slot_s.bg_color    = Color(0.90, 0.75, 0.18, 0.85)
				slot_s.border_color = Color(0.95, 0.82, 0.25, 0.90)
			else:
				slot_s.bg_color    = Color(0.10, 0.12, 0.22, 0.70)
				slot_s.border_color = Color(0.28, 0.33, 0.52, 0.55)
			slot_s.set_border_width_all(1)
			slot_s.set_corner_radius_all(2)
			slot_pc.add_theme_stylebox_override("panel", slot_s)
			slot_pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slots_hbox.add_child(slot_pc)
		group_vbox.add_child(slots_hbox)
		var si_lbl := Label.new(); si_lbl.text = slot_info[0]
		_apply_orbitron(si_lbl, 9)
		si_lbl.add_theme_color_override("font_color", Color(0.50, 0.55, 0.70))
		si_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		si_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		si_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group_vbox.add_child(si_lbl)
		limits_row.add_child(group_vbox)
	root.add_child(limits_row)"""

replacement = """	var _build_slot_indicator = func(filled: int, total: int) -> Control:
		var slots_hbox := HBoxContainer.new()
		slots_hbox.add_theme_constant_override("separation", 3)
		slots_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for idx in total:
			var slot_pc := PanelContainer.new()
			slot_pc.custom_minimum_size = Vector2(14, 10)
			var slot_s := StyleBoxFlat.new()
			if idx < filled:
				slot_s.bg_color    = Color(0.90, 0.75, 0.18, 0.85)
				slot_s.border_color = Color(0.95, 0.82, 0.25, 0.90)
			else:
				slot_s.bg_color    = Color(0.10, 0.12, 0.22, 0.70)
				slot_s.border_color = Color(0.28, 0.33, 0.52, 0.55)
			slot_s.set_border_width_all(1)
			slot_s.set_corner_radius_all(2)
			slot_pc.add_theme_stylebox_override("panel", slot_s)
			slot_pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slots_hbox.add_child(slot_pc)
		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_bottom", 4)
		m.add_child(slots_hbox)
		return m"""

content = content.replace(target, replacement)

target2 = """	var districts_page := VBoxContainer.new()
	districts_page.add_theme_constant_override("separation", 8)
	districts_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dist_scroll.add_child(districts_page)

	_poi_overview_cards.clear()
	_stop_tut_panel_pulse()
	for poi: POIData in surface_pois:"""

replacement2 = """	var districts_page := VBoxContainer.new()
	districts_page.add_theme_constant_override("separation", 8)
	districts_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dist_scroll.add_child(districts_page)
	
	districts_page.add_child(_build_slot_indicator.call(surface_pois.size(), pp.max_districts))

	_poi_overview_cards.clear()
	_stop_tut_panel_pulse()
	for poi: POIData in surface_pois:"""

content = content.replace(target2, replacement2)

target3 = """	var orbital_page := VBoxContainer.new()
	orbital_page.add_theme_constant_override("separation", 8)
	orbital_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orb_scroll.add_child(orbital_page)

	for poi: POIData in orbital_pois:"""

replacement3 = """	var orbital_page := VBoxContainer.new()
	orbital_page.add_theme_constant_override("separation", 8)
	orbital_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orb_scroll.add_child(orbital_page)
	
	if has_orbital_unlocked:
		orbital_page.add_child(_build_slot_indicator.call(orbital_pois.size(), max(1, p_max_orbital)))

	for poi: POIData in orbital_pois:"""

content = content.replace(target3, replacement3)

with open("scripts/planetary/PlanetaryView.gd", "w") as f:
    f.write(content)

print("Done")
