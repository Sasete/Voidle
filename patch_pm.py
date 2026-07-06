import re

with open("scripts/game/ProductionManager.gd", "r") as f:
    content = f.read()

helpers = """
# ── Building Level & Buffs ────────────────────────────────────────────────────

func get_building_level_mult(level: int) -> float:
	return 1.0 + 0.5 * (log(max(1, level)) / log(2.0))

func get_building_consume_mult(level: int) -> float:
	return 1.0 + 0.25 * (log(max(1, level)) / log(2.0))

func get_district_buffs(pp: PlanetProgress, district_id: String) -> Dictionary:
	var buffs := {
		"solar_mult": 1.0,
		"geothermal_mult": 1.0,
		"clean_energy_mult": 1.0,
		"generator_duration_mult": 1.0
	}
	for b in pp.buildings_in_district(district_id):
		if b.get("constructing", false): continue
		var bid = b.get("building_id", "")
		var amt: int = b.get("amount", 1)
		var lv: int = b.get("level", 1)
		var lv_mult := get_building_level_mult(lv)
		
		if bid == "circuit_overloader":
			buffs.solar_mult += 0.03 * amt * lv_mult
		elif bid == "magma_resonator":
			buffs.geothermal_mult += 0.02 * amt * lv_mult
		elif bid == "grid_optimizer":
			buffs.clean_energy_mult += 0.01 * amt * lv_mult
		elif bid == "combustion_stabilizer":
			buffs.generator_duration_mult += 0.05 * amt * lv_mult
	return buffs

## Computes global energy balance and ratio across ALL colonized planets."""

content = content.replace("## Computes global energy balance and ratio across ALL colonized planets.", helpers)

# Update _tick_all consumption required_amt
tick_all_req_replace = """					var required_amt := def.input_amount * amount * get_building_consume_mult(entry.get("level", 1))"""
content = content.replace("var required_amt := def.input_amount * amount", tick_all_req_replace)

# Update _tick_all speed_mult and effective duration
tick_all_speed_target = """			var speed_mult: float = _deposit_speed(def, planet_seed, mods) * energy_speed * get_node("/root/SkillTree").get_global_speed_mult() * planet_speed_mult
			if def.output_type == BuildingDef.OutputType.RAW_MINERAL:
				speed_mult *= get_node("/root/SkillTree").get_mine_speed_mult()
			var eff_dur: float = entry.get("effective_duration", def.tick_duration)"""

tick_all_speed_replace = """			var speed_mult: float = _deposit_speed(def, planet_seed, mods) * energy_speed * get_node("/root/SkillTree").get_global_speed_mult() * planet_speed_mult
			if def.output_type == BuildingDef.OutputType.RAW_MINERAL:
				speed_mult *= get_node("/root/SkillTree").get_mine_speed_mult()
			var eff_dur: float = entry.get("effective_duration", def.tick_duration)
			var d_buffs := get_district_buffs(pp, poi_label)
			if def.input_type != BuildingDef.OutputType.NONE and def.output_type == BuildingDef.OutputType.ENERGY:
				eff_dur *= d_buffs.generator_duration_mult"""
content = content.replace(tick_all_speed_target, tick_all_speed_replace)

# Update _on_tick_complete to pass level mult
tick_complete_target = """	var display_val := def.output_amount * amount"""
tick_complete_replace = """	var display_val := def.output_amount * amount * get_building_level_mult(entry.get("level", 1))"""
content = content.replace(tick_complete_target, tick_complete_replace)


calc_energy_target = """			if def.energy_per_tick > 0.0:
				var mult: float = st.get_solar_mult() if def.building_id == "solar_panel" else 1.0
				var contrib := def.energy_per_tick * amt * mult
				total_prod += contrib
				net += contrib
			elif def.energy_per_tick < 0.0:
				var contrib := def.energy_per_tick * amt * (st.get_energy_consume_mult() as float) * planet_energy_mult
				total_demand += abs(contrib)
				net += contrib
			if def.output_type == BuildingDef.OutputType.ENERGY:
				var mult: float = 1.0
				if def.building_id == "solar_panel" or def.building_id == "solar_matrix":
					mult = st.get_solar_mult()
				elif def.building_id == "generator" or def.building_id == "power_plant" or def.building_id == "geothermal_plant":
					mult = st.get_generator_output_mult()
					if def.building_id != "geothermal_plant":
						var in_min: String = entry.get("burning_mineral", "")
						if in_min != "":
							var rd: ResourceData = GameState.known_resources.get(in_min)
							if rd: mult *= float(rd.rarity)
						else:
							mult = 0.0
				total_prod += def.output_amount * amt * mult
				net        += def.output_amount * amt * mult"""

calc_energy_replace = """			var lv: int = entry.get("level", 1)
			var lv_mult := get_building_level_mult(lv)
			var consume_mult := get_building_consume_mult(lv)
			var dbuffs := get_district_buffs(pp, entry.get("district_id", ""))
			
			if def.energy_per_tick > 0.0:
				var mult: float = lv_mult
				if def.building_id == "solar_panel" or def.building_id == "solar_matrix":
					mult *= st.get_solar_mult() * dbuffs.clean_energy_mult * dbuffs.solar_mult
				elif def.building_id == "geothermal_plant":
					mult *= dbuffs.clean_energy_mult * dbuffs.geothermal_mult
				var contrib := def.energy_per_tick * amt * mult
				total_prod += contrib
				net += contrib
			elif def.energy_per_tick < 0.0:
				var contrib := def.energy_per_tick * amt * consume_mult * (st.get_energy_consume_mult() as float) * planet_energy_mult
				total_demand += abs(contrib)
				net += contrib
				
			if def.output_type == BuildingDef.OutputType.ENERGY:
				var mult: float = lv_mult
				if def.building_id == "solar_panel" or def.building_id == "solar_matrix":
					mult *= st.get_solar_mult() * dbuffs.clean_energy_mult * dbuffs.solar_mult
				elif def.building_id == "geothermal_plant":
					mult *= st.get_generator_output_mult() * dbuffs.clean_energy_mult * dbuffs.geothermal_mult
				elif def.input_type != BuildingDef.OutputType.NONE:
					# Burners
					mult *= st.get_generator_output_mult()
					var in_min: String = entry.get("burning_mineral", "")
					if in_min != "":
						var rd: ResourceData = GameState.known_resources.get(in_min)
						if rd: mult *= float(rd.rarity)
					else:
						mult = 0.0
				total_prod += def.output_amount * amt * mult
				net        += def.output_amount * amt * mult"""

content = content.replace(calc_energy_target, calc_energy_replace)

planet_energy_target = """		if def.energy_per_tick > 0.0:
			var mult: float = st.get_solar_mult() if def.building_id == "solar_panel" else 1.0
			total += def.energy_per_tick * amt * mult
		elif def.energy_per_tick < 0.0:
			total += def.energy_per_tick * amt * (st.get_energy_consume_mult() as float)
		if def.output_type == BuildingDef.OutputType.ENERGY:
			var mult: float = 1.0
			if def.building_id == "solar_panel":
				mult = st.get_solar_mult()
			elif def.building_id == "generator":
				mult = st.get_generator_output_mult()
				var in_min: String = entry.get("burning_mineral", "")
				if in_min != "":
					var rd: ResourceData = GameState.known_resources.get(in_min)
					if rd: mult *= float(rd.rarity)
				else:
					mult = 0.0
			total += def.output_amount * amt * mult"""

planet_energy_replace = """		var lv: int = entry.get("level", 1)
		var lv_mult := get_building_level_mult(lv)
		var consume_mult := get_building_consume_mult(lv)
		var dbuffs := get_district_buffs(pp, entry.get("district_id", ""))
		
		if def.energy_per_tick > 0.0:
			var mult: float = lv_mult
			if def.building_id == "solar_panel" or def.building_id == "solar_matrix":
				mult *= st.get_solar_mult() * dbuffs.clean_energy_mult * dbuffs.solar_mult
			elif def.building_id == "geothermal_plant":
				mult *= dbuffs.clean_energy_mult * dbuffs.geothermal_mult
			total += def.energy_per_tick * amt * mult
		elif def.energy_per_tick < 0.0:
			total += def.energy_per_tick * amt * consume_mult * (st.get_energy_consume_mult() as float)
			
		if def.output_type == BuildingDef.OutputType.ENERGY:
			var mult: float = lv_mult
			if def.building_id == "solar_panel" or def.building_id == "solar_matrix":
				mult *= st.get_solar_mult() * dbuffs.clean_energy_mult * dbuffs.solar_mult
			elif def.building_id == "geothermal_plant":
				mult *= st.get_generator_output_mult() * dbuffs.clean_energy_mult * dbuffs.geothermal_mult
			elif def.input_type != BuildingDef.OutputType.NONE:
				mult *= st.get_generator_output_mult()
				var in_min: String = entry.get("burning_mineral", "")
				if in_min != "":
					var rd: ResourceData = GameState.known_resources.get(in_min)
					if rd: mult *= float(rd.rarity)
				else:
					mult = 0.0
			total += def.output_amount * amt * mult"""

content = content.replace(planet_energy_target, planet_energy_replace)

with open("scripts/game/ProductionManager.gd", "w") as f:
    f.write(content)

print("Patch applied to ProductionManager.gd")
