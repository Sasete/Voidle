import re

with open("scripts/planetary/PlanetaryView.gd", "r") as f:
    content = f.read()

# 1. Add var _inventory_tab_btn: Button = null
if "var _inventory_tab_btn" not in content:
    content = content.replace("var _planet_upgrade_pbar: ProgressBar = null", "var _planet_upgrade_pbar: ProgressBar = null\nvar _inventory_tab_btn: Button = null")

# 2. Update _build_planet_overview to assign it
target_btn = """	var inventory_tab_btn: Button = _make_overview_tab_btn("INVENTORY", _top_tab_active == "INVENTORY")"""
replacement_btn = """	var inventory_tab_btn: Button = _make_overview_tab_btn("INVENTORY", _top_tab_active == "INVENTORY")
	_inventory_tab_btn = inventory_tab_btn"""
content = content.replace(target_btn, replacement_btn)

# 3. Update _spawn_fly_icon to use _inventory_tab_btn
content = content.replace("inventory_tab_btn ==", "_inventory_tab_btn ==")
content = content.replace("inventory_tab_btn.global_position", "_inventory_tab_btn.global_position")
content = content.replace("inventory_tab_btn.size", "_inventory_tab_btn.size")
content = content.replace("inventory_tab_btn, \"scale\"", "_inventory_tab_btn, \"scale\"")

with open("scripts/planetary/PlanetaryView.gd", "w") as f:
    f.write(content)

print("Done")
