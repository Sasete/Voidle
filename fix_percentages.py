import re

with open("scripts/planetary/PlanetaryView.gd", "r") as f:
    content = f.read()

# Fix for line 2518+ in _build_planet_overview
target1 = """		var dep_rng := RandomNumberGenerator.new()
		for rd: ResourceData in p_br.as_array():
			var rid := rd.resource_id()
			var p_density: float
			if data.mineral_densities.has(rid):
				p_density = float(data.mineral_densities[rid])
			else:
				dep_rng.seed = data.seed ^ (rd.rarity * 0x4E3D)
				p_density = data.deposit_density * dep_rng.randf_range(0.75, 1.25)
			dep_grid.add_child(_mineral_grid_card(rd, 0.0, false, "%d%%" % int(round(p_density * 100.0))))"""

replacement1 = """		var dep_rng := RandomNumberGenerator.new()
		var total_dens: float = 0.0
		for rd: ResourceData in p_br.as_array():
			var rid := rd.resource_id()
			var d: float = 0.0
			if data.mineral_densities.has(rid):
				d = float(data.mineral_densities[rid])
			else:
				dep_rng.seed = data.seed ^ (rd.rarity * 0x4E3D)
				d = data.deposit_density * dep_rng.randf_range(0.75, 1.25)
			total_dens += d
		for rd: ResourceData in p_br.as_array():
			var rid := rd.resource_id()
			var p_density: float
			if data.mineral_densities.has(rid):
				p_density = float(data.mineral_densities[rid])
			else:
				dep_rng.seed = data.seed ^ (rd.rarity * 0x4E3D)
				p_density = data.deposit_density * dep_rng.randf_range(0.75, 1.25)
			var pct := 0
			if total_dens > 0: pct = int(round((p_density / total_dens) * 100.0))
			dep_grid.add_child(_mineral_grid_card(rd, 0.0, false, "%d%%" % pct))"""

content = content.replace(target1, replacement1)

# Do the same for line 1139+
target2 = """	_details_section(vbox, "DEPOSITS")
	var dep_grid := HFlowContainer.new()
	dep_grid.add_theme_constant_override("h_separation", 4)
	dep_grid.add_theme_constant_override("v_separation", 4)
	var rng := RandomNumberGenerator.new()
	for rd: ResourceData in br.as_array():
		var rid := rd.resource_id()
		var mineral_density: float
		if data.mineral_densities.has(rid):
			mineral_density = float(data.mineral_densities[rid])
		else:
			rng.seed = data.seed ^ (rd.rarity * 0x4E3D)
			mineral_density = data.deposit_density * rng.randf_range(0.75, 1.25)
		dep_grid.add_child(_mineral_grid_card(rd, 0.0, false, "%d%%" % int(round(mineral_density * 100.0))))
	vbox.add_child(dep_grid)"""

replacement2 = """	_details_section(vbox, "DEPOSITS")
	var dep_grid := HFlowContainer.new()
	dep_grid.add_theme_constant_override("h_separation", 4)
	dep_grid.add_theme_constant_override("v_separation", 4)
	var rng := RandomNumberGenerator.new()
	var total_dens: float = 0.0
	for rd: ResourceData in br.as_array():
		var rid := rd.resource_id()
		var d: float = 0.0
		if data.mineral_densities.has(rid):
			d = float(data.mineral_densities[rid])
		else:
			rng.seed = data.seed ^ (rd.rarity * 0x4E3D)
			d = data.deposit_density * rng.randf_range(0.75, 1.25)
		total_dens += d
	for rd: ResourceData in br.as_array():
		var rid := rd.resource_id()
		var mineral_density: float
		if data.mineral_densities.has(rid):
			mineral_density = float(data.mineral_densities[rid])
		else:
			rng.seed = data.seed ^ (rd.rarity * 0x4E3D)
			mineral_density = data.deposit_density * rng.randf_range(0.75, 1.25)
		var pct := 0
		if total_dens > 0: pct = int(round((mineral_density / total_dens) * 100.0))
		dep_grid.add_child(_mineral_grid_card(rd, 0.0, false, "%d%%" % pct))
	vbox.add_child(dep_grid)"""

content = content.replace(target2, replacement2)

with open("scripts/planetary/PlanetaryView.gd", "w") as f:
    f.write(content)
