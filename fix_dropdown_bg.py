import re

with open("scripts/planetary/PlanetaryView.gd", "r") as f:
    content = f.read()

target1 = """	_dd_layer.add_child(outer)
	# CanvasLayer children use screen-space coordinates directly
	await get_tree().process_frame"""

replacement1 = """	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			if is_instance_valid(_dd_layer):
				_dd_layer.queue_free()
				_dd_layer = null
			_active_slot_dropdown = null
			# Tutorial: restore slot card highlight when dropdown is closed
			var tut_bid := TutorialManager.get_action_building_target()
			if tut_bid != "" and is_instance_valid(card):
				_tut_highlight_node = card as Control
				_start_tut_node_pulse(_tut_highlight_node)
	)
	_dd_layer.add_child(bg)
	_dd_layer.add_child(outer)
	# CanvasLayer children use screen-space coordinates directly
	await get_tree().process_frame"""

content = content.replace(target1, replacement1)

target2 = """	_dd_layer.add_child(outer)
	await get_tree().process_frame
	if not is_instance_valid(outer):"""

replacement2 = """	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			if is_instance_valid(_dd_layer):
				_dd_layer.queue_free()
				_dd_layer = null
			_active_slot_dropdown = null
	)
	_dd_layer.add_child(bg)
	_dd_layer.add_child(outer)
	await get_tree().process_frame
	if not is_instance_valid(outer):"""

content = content.replace(target2, replacement2)

with open("scripts/planetary/PlanetaryView.gd", "w") as f:
    f.write(content)

print("Done")
