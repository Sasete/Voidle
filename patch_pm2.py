import re

with open("scripts/game/ProductionManager.gd", "r") as f:
    content = f.read()

helpers = """
func get_building_output(pp: PlanetProgress, entry: Dictionary, def: BuildingDef) -> float:
	var amt: int = entry.get("amount", 1)
	var lv: int = entry.get("level", 1)
	var lv_mult := get_building_level_mult(lv)
	var dbuffs := get_district_buffs(pp, entry.get("district_id", ""))
	var st := get_node("/root/SkillTree")
	var out_val := def.output_amount * amt * lv_mult
	
	if def.output_type == BuildingDef.OutputType.CREDITS:
		out_val *= st.get_credits_mult()
	elif def.output_type == BuildingDef.OutputType.ENERGY:
		if def.building_id == "solar_panel" or def.building_id == "solar_matrix":
			out_val *= st.get_solar_mult() * dbuffs.clean_energy_mult * dbuffs.solar_mult
		elif def.building_id == "geothermal_plant":
			out_val *= st.get_generator_output_mult() * dbuffs.clean_energy_mult * dbuffs.geothermal_mult
		elif def.input_type != BuildingDef.OutputType.NONE:
			out_val *= st.get_generator_output_mult()
			var in_min: String = entry.get("burning_mineral", "")
			if in_min != "":
				var rd: ResourceData = GameState.known_resources.get(in_min)
				if rd: out_val *= float(rd.rarity)
			else:
				out_val = 0.0 # No fuel
	elif def.output_type == BuildingDef.OutputType.RAW_MINERAL or def.output_type == BuildingDef.OutputType.REFINED_MINERAL:
		out_val *= st.get_mine_output_mult()
	return out_val
"""

content = content.replace("func get_building_consume_mult(level: int) -> float:\n\treturn 1.0 + 0.25 * (log(max(1, level)) / log(2.0))", 
"""func get_building_consume_mult(level: int) -> float:
\treturn 1.0 + 0.25 * (log(max(1, level)) / log(2.0))
""" + helpers)

with open("scripts/game/ProductionManager.gd", "w") as f:
    f.write(content)

print("Added get_building_output to ProductionManager.")
