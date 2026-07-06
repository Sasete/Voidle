import re

with open("scripts/planetary/PlanetaryView.gd", "r") as f:
    content = f.read()

# Replace can_add cost check
target_can_add = "var can_add: bool    = slots_free >= def.slot_cost and GameState.credits >= def.base_cost"
replace_can_add = "var can_add: bool    = slots_free >= def.slot_cost and GameState.credits >= def.get_build_cost(entry.get(\"level\", 1))"
content = content.replace(target_can_add, replace_can_add)

# Replace add_btn tooltip
target_tip_add = """	var tip_add: String
	if not can_add and slots_free < def.slot_cost:
		tip_add = "No slots · Upgrade district"
	elif not can_add:
		tip_add = "Need %.0f cr" % def.base_cost
	else:
		tip_add = "Stack one more %s\\n%.0f cr · %d slot" % [def.display_name, def.base_cost, def.slot_cost]"""
replace_tip_add = """	var b_cost := def.get_build_cost(entry.get("level", 1))
	var tip_add: String
	if not can_add and slots_free < def.slot_cost:
		tip_add = "No slots · Upgrade district"
	elif not can_add:
		tip_add = "Need %.0f cr" % b_cost
	else:
		tip_add = "Stack one more %s\\n%.0f cr · %d slot" % [def.display_name, b_cost, def.slot_cost]"""
content = content.replace(target_tip_add, replace_tip_add)

# Replace add_btn press logic
target_add_press = """	add_btn.pressed.connect(func() -> void:
		if GameState.spend_credits(cap_def.base_cost):
			pp.stack_building_unchecked(cap_poi.label, cap_def.building_id)"""
replace_add_press = """	add_btn.pressed.connect(func() -> void:
		var c_cost := cap_def.get_build_cost(cap_entry.get("level", 1))
		if GameState.spend_credits(c_cost):
			pp.stack_building_unchecked(cap_poi.label, cap_def.building_id, cap_entry)"""
content = content.replace(target_add_press, replace_add_press)

# Add Upgrade and Split buttons
target_btns = """	btn_vbox.add_child(add_btn)
	btn_vbox.add_child(rem_btn)"""
replace_btns = """	btn_vbox.add_child(add_btn)
	btn_vbox.add_child(rem_btn)
	
	var up_btn := Button.new()
	up_btn.text = "⇪"
	_apply_orbitron(up_btn, 10)
	up_btn.custom_minimum_size = Vector2(30, 22)
	up_btn.add_theme_stylebox_override("normal", add_s)
	up_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	up_btn.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	var up_cost = def.get_upgrade_cost(entry.get("level", 1), count)
	up_btn.mouse_entered.connect(func():
		CursorManager.set_state(CursorManager.State.POINTER)
		TooltipManager.show_tip("Upgrade to Lv%d" % (entry.get("level", 1) + 1), "Cost: %.0f cr" % up_cost))
	up_btn.mouse_exited.connect(func():
		CursorManager.set_state(CursorManager.State.NORMAL)
		TooltipManager.hide_tip())
	up_btn.pressed.connect(func():
		if pp.upgrade_building(cap_entry):
			GameState.planet_progress_changed.emit(cap_planet.seed)
			_refresh_overview_energy()
			_build_district_panel(cap_poi, cap_planet))
	btn_vbox.add_child(up_btn)

	if count > 1:
		var split_btn := Button.new()
		split_btn.text = "➗"
		_apply_orbitron(split_btn, 10)
		split_btn.custom_minimum_size = Vector2(30, 22)
		split_btn.add_theme_stylebox_override("normal", rem_s)
		split_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		split_btn.add_theme_color_override("font_color", Color(0.4, 0.7, 0.9))
		split_btn.mouse_entered.connect(func():
			CursorManager.set_state(CursorManager.State.POINTER)
			TooltipManager.show_tip("Split", "Split into two stacks"))
		split_btn.mouse_exited.connect(func():
			CursorManager.set_state(CursorManager.State.NORMAL)
			TooltipManager.hide_tip())
		split_btn.pressed.connect(func():
			if pp.split_building(cap_entry, count / 2):
				GameState.planet_progress_changed.emit(cap_planet.seed)
				_build_district_panel(cap_poi, cap_planet))
		btn_vbox.add_child(split_btn)"""
content = content.replace(target_btns, replace_btns)

with open("scripts/planetary/PlanetaryView.gd", "w") as f:
    f.write(content)

print("PlanetaryView.gd patched with buttons.")
