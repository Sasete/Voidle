import re

with open("scripts/planetary/PlanetaryView.gd", "r") as f:
    content = f.read()

# Replace lines 4087-4104 with ProductionManager.get_building_output
target_ui = """	# Determine modified output label text
	var out_val := def.output_amount
	if def.output_type == BuildingDef.OutputType.CREDITS:
		out_val *= get_node("/root/SkillTree").get_credits_mult()
	elif def.output_type == BuildingDef.OutputType.ENERGY:
		if def.building_id == "solar_panel":
			out_val *= get_node("/root/SkillTree").get_solar_mult()
		elif def.building_id == "generator":
			out_val *= get_node("/root/SkillTree").get_generator_output_mult()
			var in_min: String = entry.get("burning_mineral", "")
			if in_min != "":
				var rd: ResourceData = GameState.known_resources.get(in_min)
				if rd: out_val *= float(rd.rarity)
			else:
				out_val = 0.0 # No fuel
	elif def.output_type == BuildingDef.OutputType.RAW_MINERAL or def.output_type == BuildingDef.OutputType.REFINED_MINERAL:
		out_val *= get_node("/root/SkillTree").get_mine_output_mult()"""

replace_ui = """	# Determine modified output label text
	var out_val := ProductionManager.get_building_output(pp, entry, def)"""

content = content.replace(target_ui, replace_ui)

# Update the display of amount and level
# In PlanetaryView.gd, the building name row has:
# var amt: int = entry.get("amount", 1)
# if amt > 1: name_lbl.text += " x%d" % amt
target_name = """		var amt: int = entry.get("amount", 1)
		if amt > 1:
			name_lbl.text += " x%d" % amt"""
replace_name = """		var amt: int = entry.get("amount", 1)
		var lv: int = entry.get("level", 1)
		if amt > 1:
			name_lbl.text += " x%d" % amt
		if lv > 1:
			name_lbl.text += " (Lv%d)" % lv"""
content = content.replace(target_name, replace_name)

# Make MineralSelector filter by input_tier
target_selector = """	if is_consumer:
		var br := GameState.get_body_resources_for(planet)
		var raw_list := br.get_by_tag(ResourceData.Tag.RAW_MINERAL)"""
replace_selector = """	if is_consumer:
		var br := GameState.get_body_resources_for(planet)
		var raw_list: Array[ResourceData] = []
		if def.input_type == BuildingDef.OutputType.RAW_MINERAL:
			raw_list = br.get_by_tag(ResourceData.Tag.RAW_MINERAL)
		elif def.input_type == BuildingDef.OutputType.REFINED_MINERAL:
			var all_ref = br.get_by_tag(ResourceData.Tag.REFINED_MINERAL)
			for r in all_ref:
				if r.tier == def.input_tier:
					raw_list.append(r)"""
content = content.replace(target_selector, replace_selector)

with open("scripts/planetary/PlanetaryView.gd", "w") as f:
    f.write(content)

print("UI patched for out_val, level display, and input_tier filtering")
