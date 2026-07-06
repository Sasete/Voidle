with open("scripts/game/PlanetProgress.gd", "r") as f:
    content = f.read()

target = """	var cur_lv: int = b.get("level", 1)
	var amt: int = b.get("amount", 1)
	var cost := def.get_upgrade_cost(cur_lv, amt)
	
	if GameState.spend_credits(cost):
		b["level"] = cur_lv + 1
		return true
	return false"""

replacement = """	var cur_lv: int = b.get("level", 1)
	var amt: int = b.get("amount", 1)
	var cost := def.get_upgrade_cost(cur_lv, amt)
	
	if GameState.spend_credits(cost):
		b["level"] = cur_lv + 1
		return true
	return false"""

if target in content:
    print("Already handles amt and cost correctly via get_upgrade_cost!")
else:
    print("Could not find target block.")
