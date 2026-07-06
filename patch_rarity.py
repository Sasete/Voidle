import re

with open("scripts/game/ProductionManager.gd", "r") as f:
    content = f.read()

# 1. Update _calc_global_energy
target_calc = """				elif def.input_type != BuildingDef.OutputType.NONE:
					# Burners
					mult *= st.get_generator_output_mult()
					var in_min: String = entry.get("burning_mineral", "")
					if in_min != "":
						var rd: ResourceData = GameState.known_resources.get(in_min)
						if rd: mult *= float(rd.rarity)
					else:
						mult = 0.0"""
replace_calc = """				elif def.input_type != BuildingDef.OutputType.NONE:
					# Burners
					mult *= st.get_generator_output_mult()
					var in_min: String = entry.get("burning_mineral", "")
					if in_min == "":
						mult = 0.0"""
content = content.replace(target_calc, replace_calc)

# 2. Update planet_energy_net
target_planet = """			elif def.input_type != BuildingDef.OutputType.NONE:
				mult *= st.get_generator_output_mult()
				var in_min: String = entry.get("burning_mineral", "")
				if in_min != "":
					var rd: ResourceData = GameState.known_resources.get(in_min)
					if rd: mult *= float(rd.rarity)
				else:
					mult = 0.0"""
replace_planet = """			elif def.input_type != BuildingDef.OutputType.NONE:
				mult *= st.get_generator_output_mult()
				var in_min: String = entry.get("burning_mineral", "")
				if in_min == "":
					mult = 0.0"""
content = content.replace(target_planet, replace_planet)

# 3. Update get_building_output
target_out = """		elif def.input_type != BuildingDef.OutputType.NONE:
			out_val *= st.get_generator_output_mult()
			var in_min: String = entry.get("burning_mineral", "")
			if in_min != "":
				var rd: ResourceData = GameState.known_resources.get(in_min)
				if rd: out_val *= float(rd.rarity)
			else:
				out_val = 0.0 # No fuel"""
replace_out = """		elif def.input_type != BuildingDef.OutputType.NONE:
			out_val *= st.get_generator_output_mult()
			var in_min: String = entry.get("burning_mineral", "")
			if in_min == "":
				out_val = 0.0 # No fuel"""
content = content.replace(target_out, replace_out)

# 4. Update _tick_all to apply rarity to eff_dur
target_tick = """			var d_buffs := get_district_buffs(pp, poi_label)
			if def.input_type != BuildingDef.OutputType.NONE and def.output_type == BuildingDef.OutputType.ENERGY:
				eff_dur *= d_buffs.generator_duration_mult"""
replace_tick = """			var d_buffs := get_district_buffs(pp, poi_label)
			if def.input_type != BuildingDef.OutputType.NONE and def.output_type == BuildingDef.OutputType.ENERGY:
				eff_dur *= d_buffs.generator_duration_mult
				var in_min: String = entry.get("burning_mineral", "")
				if in_min != "":
					var rd: ResourceData = GameState.known_resources.get(in_min)
					if rd: eff_dur *= float(rd.rarity)"""
content = content.replace(target_tick, replace_tick)

with open("scripts/game/ProductionManager.gd", "w") as f:
    f.write(content)

print("Rarity patched in ProductionManager")
