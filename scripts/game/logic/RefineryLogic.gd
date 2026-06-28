class_name RefineryLogic
extends BuildingLogic

func requires_mineral_selector() -> bool:
	return true

func produce(pp: PlanetProgress, def: BuildingDef, amount: int, mods: Array, entry: Dictionary, skill_tree: Node) -> void:
	var mult: float = PlanetModifier.combined(mods, PlanetModifier.Effect.MINE_OUTPUT_MULT) * skill_tree.get_mine_output_mult()
	var rid: String = entry.get("input_mineral", "")
	
	if rid != "":
		var rd := GameState.known_resources.get(rid) as ResourceData
		if rd:
			var raw_list := GameState.get_body_resources(pp.planet_seed).get_by_tag(ResourceData.Tag.REFINED_MINERAL)
			for refined in raw_list:
				if refined.mineral_name == rd.mineral_name and refined.tier == rd.tier + 1:
					rid = refined.resource_id()
					break
	else:
		# Fallback if somehow not selected
		var pd := GameState.get_planet_data(pp.planet_seed)
		var raw_list := GameState.get_body_resources_for(pd).get_by_tag(ResourceData.Tag.RAW_MINERAL)
		if not raw_list.is_empty():
			rid = raw_list[0].resource_id()
			# Transform to refined
			var rd := GameState.known_resources.get(rid) as ResourceData
			if rd:
				var ref_list := GameState.get_body_resources(pp.planet_seed).get_by_tag(ResourceData.Tag.REFINED_MINERAL)
				for refined in ref_list:
					if refined.mineral_name == rd.mineral_name and refined.tier == rd.tier + 1:
						rid = refined.resource_id()
						break
			
	if rid != "":
		pp.add_resource(rid, def.output_amount * amount * mult)
