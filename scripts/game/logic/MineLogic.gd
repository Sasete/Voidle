class_name MineLogic
extends BuildingLogic

func produce(pp: PlanetProgress, def: BuildingDef, amount: int, mods: Array, entry: Dictionary, skill_tree: Node) -> void:
	var mult: float = PlanetModifier.combined(mods, PlanetModifier.Effect.MINE_OUTPUT_MULT) * skill_tree.get_mine_output_mult()
	
	# Basic extractor -> Mix of all minerals based on PlanetData
	var pd: PlanetData = GameState.get_planet_data(pp.planet_seed)
	var raw_list := GameState.get_body_resources_for(pd).get_by_tag(ResourceData.Tag.RAW_MINERAL)
	var total_density: float = 0.0
	var densities: Array[float] = []
	var rng := RandomNumberGenerator.new()
	
	for rd in raw_list:
		var r_id := rd.resource_id()
		var d: float
		if pd.mineral_densities.has(r_id):
			d = float(pd.mineral_densities[r_id])
		else:
			rng.seed = pd.seed ^ (rd.rarity * 0x4E3D)
			d = pd.deposit_density * rng.randf_range(0.75, 1.25)
		densities.append(d)
		total_density += d
		
	var total_out := def.output_amount * amount * mult
	if total_density > 0.0:
		for i in raw_list.size():
			var share := total_out * (densities[i] / total_density)
			pp.add_resource((raw_list[i] as ResourceData).resource_id(), share)
