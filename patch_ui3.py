import re

with open("scripts/planetary/PlanetaryView.gd", "r") as f:
    content = f.read()

target = """		if ProductionManager.is_user_paused(pm_key):
			continue
		total += b.get("amount", 1)
	return total"""

replace = """		if ProductionManager.is_user_paused(pm_key):
			continue
		total += b.get("amount", 1) * b.get("level", 1)
	return total"""

content = content.replace(target, replace)

with open("scripts/planetary/PlanetaryView.gd", "w") as f:
    f.write(content)

print("Patched _district_night_size")
