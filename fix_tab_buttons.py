import re

with open("scripts/planetary/PlanetaryView.gd", "r") as f:
    content = f.read()

target1 = """	planet_tab_btn.toggled.connect(func(on: bool) -> void:
		if on:
			_top_tab_active = "DETAILS"
			inventory_tab_btn.button_pressed = false
			planet_page.visible  = true
			inv_scroll.visible   = false)
	inventory_tab_btn.toggled.connect(func(on: bool) -> void:
		if on:
			_top_tab_active = "INVENTORY"
			planet_tab_btn.button_pressed = false
			planet_page.visible  = false
			inv_scroll.visible   = true
			_build_inv_grid.call())"""

replacement1 = """	planet_tab_btn.toggled.connect(func(on: bool) -> void:
		if on:
			_top_tab_active = "DETAILS"
			inventory_tab_btn.button_pressed = false
			planet_page.visible  = true
			inv_scroll.visible   = false
		else:
			if _top_tab_active == "DETAILS":
				planet_tab_btn.set_pressed_no_signal(true))
	inventory_tab_btn.toggled.connect(func(on: bool) -> void:
		if on:
			_top_tab_active = "INVENTORY"
			planet_tab_btn.button_pressed = false
			planet_page.visible  = false
			inv_scroll.visible   = true
			_build_inv_grid.call()
		else:
			if _top_tab_active == "INVENTORY":
				inventory_tab_btn.set_pressed_no_signal(true))"""
content = content.replace(target1, replacement1)


target2 = """	dist_btn.toggled.connect(func(on: bool) -> void:
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
			orb_scroll.visible  = true)"""

replacement2 = """	dist_btn.toggled.connect(func(on: bool) -> void:
		if on:
			_inner_tab_active = "SURFACE"
			orbital_btn.button_pressed = false
			dist_scroll.visible = true
			orb_scroll.visible  = false
		else:
			if _inner_tab_active == "SURFACE":
				dist_btn.set_pressed_no_signal(true))
	orbital_btn.toggled.connect(func(on: bool) -> void:
		if on:
			_inner_tab_active = "ORBITAL"
			dist_btn.button_pressed = false
			dist_scroll.visible = false
			orb_scroll.visible  = true
		else:
			if _inner_tab_active == "ORBITAL":
				orbital_btn.set_pressed_no_signal(true))"""
content = content.replace(target2, replacement2)

with open("scripts/planetary/PlanetaryView.gd", "w") as f:
    f.write(content)

print("Done")
