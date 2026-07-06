import re

with open("scripts/system/TooltipManager.gd", "r") as f:
    content = f.read()

target1 = """	add_child(_panel)"""
replace1 = """	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_panel)
	add_child(hbox)"""
content = content.replace(target1, replace1)

# I need to create _sub_panel and _sub_body_lbl.
# Actually it's easier to just append a PanelContainer inside the VBoxContainer of _panel itself, with a distinct style!
