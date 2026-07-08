## ProductionManager — autoload singleton.
## Ticks every building on every colonized planet each _process frame.
extends Node

signal building_ticked(planet_seed: int, key: String)
signal building_progress_changed(planet_seed: int, key: String, progress: float)
signal resource_produced(planet_seed: int, poi_label: String, text: String, color: Color, icon: Texture2D)
signal building_constructed(planet_seed: int, key: String, building_id: String)
signal building_toggled(key: String, paused: bool)
signal building_queued(planet_seed: int, building_id: String)

## { pm_key -> float 0.0-1.0 }
var _progress:    Dictionary = {}
## { pm_key -> bool } true = auto-paused (resource/energy shortage)
var _paused:      Dictionary = {}
## { pm_key -> bool } true = user manually toggled off
var _user_paused: Dictionary = {}
## global energy balance (sum across all colonies, updated each frame)
var _global_energy:       float = 0.0
## global energy throttle ratio (0.0-1.0)
var _global_energy_ratio: float = 1.0
## { "construct:pm_key" -> float 0.0-1.0 }
var _construct:     Dictionary = {}

func _process(delta: float) -> void:
	_calc_global_energy()
	_tick_all(delta)

func get_progress(key: String) -> float:
	return _progress.get(key, 0.0)

func is_paused(key: String) -> bool:
	return _paused.get(key, false)

func get_construct_progress(key: String) -> float:
	return _construct.get("construct:" + key, 0.0)

func is_constructing(key: String) -> bool:
	return _construct.has("construct:" + key)

func toggle_user_pause(key: String) -> void:
	_user_paused[key] = not _user_paused.get(key, false)
	_calc_global_energy()
	building_toggled.emit(key, _user_paused[key])

func is_user_paused(key: String) -> bool:
	return _user_paused.get(key, false)

## Returns 0.0–1.0: global energy coverage ratio. < 1.0 = energy crisis.
func get_energy_ratio(_planet_seed: int = 0) -> float:
	return _global_energy_ratio

## Returns the global net energy balance (positive = surplus, negative = deficit).
func get_global_energy() -> float:
	return _global_energy

## Called by PlanetaryView after building is placed so UI can refresh immediately.
func invalidate(planet_seed: int) -> void:
	building_ticked.emit(planet_seed, "")

# ── Internal ──────────────────────────────────────────────────────────────────

func _tick_all(delta: float) -> void:
	for pp: PlanetProgress in GameState._planet_progress.values():
		if pp.is_colonizing:
			pp.colonize_progress += delta / max(0.1, pp.colonize_duration)
			if pp.colonize_progress >= 1.0:
				GameState.finish_colonization(pp.planet_seed)
			else:
				building_progress_changed.emit(pp.planet_seed, "colonize", pp.colonize_progress)

	for pp: PlanetProgress in _all_colonies():
		var planet_seed: int = pp.planet_seed
		var pd: PlanetData = GameState.get_planet_data(planet_seed)
		if pd:
			var district_changed := false
			
			if pp.is_upgrading:
				pp.upgrade_progress += delta / max(0.1, pp.upgrade_duration)
				if pp.upgrade_progress >= 1.0:
					pp.is_upgrading = false
					pp.upgrade_progress = 0.0
					pp.level += 1
					pp.recalculate_limits()
					GameState.planet_progress_changed.emit(planet_seed)

			# District upgrades (independent of planet upgrade state)
			for dlabel in pp.district_upgrading.keys():
				var target_lv: int = pp.district_levels.get(dlabel, 1) + 1
				var dur: float = PlanetProgress.district_upgrade_duration(target_lv)
				pp.district_upgrading[dlabel] += delta / max(0.1, dur)
				if pp.district_upgrading[dlabel] >= 1.0:
					pp.district_upgrading.erase(dlabel)
					pp.district_levels[dlabel] = target_lv
					GameState.planet_progress_changed.emit(planet_seed)
					break  # dict modified — next frame handles remaining

			for poi in pd.custom_pois:
				if poi.constructing:
					if poi.is_orbital():
						continue  # Orbital progress is driven by rocket animation in PlanetaryView
					poi.construct_progress += delta / max(0.1, poi.construct_duration)
					if poi.construct_progress >= 1.0:
						poi.constructing = false
						poi.construct_progress = 1.0
						district_changed = true
					building_progress_changed.emit(planet_seed, poi.label, poi.construct_progress)
			if district_changed:
				GameState.planet_progress_changed.emit(planet_seed)

		var energy_ratio: float = _global_energy_ratio

		var mods := PlanetModifier.for_planet(_planet_type(planet_seed))

		# Collect entries to merge/remove after iteration (avoid modifying array mid-loop)
		var pending_merges: Array[Dictionary] = []
		var completed_buildings: Array[Dictionary] = []

		# Iterate with explicit index so identical-content entries get unique keys
		for i in pp.buildings.size():
			var entry: Dictionary = pp.buildings[i]
			var poi_label: String  = entry.get("district_id", "")
			var bid: String        = entry.get("building_id", "")
			var amount: int        = entry.get("amount", 1)
			if not entry.has("uid"):
				entry["uid"] = str(randi())
			var key: String        = _key(planet_seed, poi_label, entry["uid"])
			var def := BuildingDef.find(bid)
			if def == null or def.tick_duration <= 0.0:
				continue

			# ── Construction phase ────────────────────────────────────────────
			if entry.get("constructing", false):
				var ck: String = "construct:" + key
				var cdur: float = def.construct_duration if def.construct_duration > 0.0 else def.tick_duration
				var cp: float  = _construct.get(ck, 0.0) + delta / cdur
				if cp >= 1.0:
					_construct.erase(ck)
					entry["constructing"] = false
					var merge_idx: int = entry.get("merge_into", -1)
					if merge_idx >= 0:
						pending_merges.append(entry)
					# Spaceport starts paused after construction — player launches manually
					if def.building_id == "spaceport":
						_user_paused[key] = true
					completed_buildings.append({ "key": key, "bid": bid })
					building_ticked.emit(planet_seed, key)
				else:
					_construct[ck] = cp
					building_progress_changed.emit(planet_seed, key, cp)
				continue

			# ── User-toggled off ──────────────────────────────────────────────
			if _user_paused.get(key, false):
				continue

			# ── Start of cycle resource consumption ───────────────────────────
			var prev: float = _progress.get(key, 0.0)
			if prev <= 0.0:
				if def.input_type != BuildingDef.OutputType.NONE:
					# Find what the user selected to burn
					var intended_input: String = entry.get("input_mineral", "")
					if intended_input == "":
						intended_input = _resource_key(def.input_type, pp.planet_seed, entry)

					var required_amt := def.input_amount * amount * get_building_consume_mult(entry.get("level", 1))
					if GameState.global_resources.get(intended_input, 0.0) < required_amt:
						if not _paused.get(key, false):
							_paused[key] = true
							building_ticked.emit(planet_seed, key)
						_emit_progress(planet_seed, key)
						continue   # can't start — wait for resource

					# Resource available: consume it immediately from global pool
					GameState.global_resources[intended_input] = \
						GameState.global_resources.get(intended_input, 0.0) - required_amt
					# Lock this resource as the one currently burning for this cycle
					var old_burning: String = entry.get("burning_mineral", "")
					entry["burning_mineral"] = intended_input
					if old_burning != intended_input:
						building_ticked.emit(planet_seed, key)

				# Clear pause if we successfully started the cycle
				if _paused.get(key, false):
					_paused[key] = false
					building_ticked.emit(planet_seed, key)

			# ── Energy throttle ───────────────────────────────────────────────
			var needs_energy: bool = def.energy_per_tick < 0.0
			var energy_speed: float = 1.0
			if needs_energy:
				if energy_ratio <= 0.0:
					# Don't pause physical input failure, just stall progress due to power outage
					# Note: the input is already consumed, it just sits in the machine!
					_emit_progress(planet_seed, key)
					continue
				energy_speed = energy_ratio

			# Planet-wide passive buffs
			var planet_speed_mult := 1.0
			var planet_energy_mult := 1.0
			if pp.has_building("logistics_center"):
				planet_speed_mult *= 1.20
			if pp.has_building("command_center"):
				planet_energy_mult *= 0.85

			# ── Tick production bar ───────────────────────────────────────────
			var speed_mult: float = _deposit_speed(def, planet_seed, mods) * energy_speed * get_node("/root/SkillTree").get_global_speed_mult() * planet_speed_mult
			var d_buffs := get_district_buffs(pp, poi_label)
			if def.output_type == BuildingDef.OutputType.RAW_MINERAL:
				speed_mult *= get_node("/root/SkillTree").get_mine_speed_mult() * d_buffs.mine_speed_mult
				if def.building_id == "atmospheric_siphon":
					speed_mult *= d_buffs.gas_mining_speed_mult
			elif def.output_type == BuildingDef.OutputType.REFINED_MINERAL:
				speed_mult *= d_buffs.refinery_speed_mult * get_node("/root/SkillTree").get_refinery_speed_mult()
				if def.building_id == "aerosol_refinery":
					speed_mult *= d_buffs.gas_mining_speed_mult
					
			var eff_dur: float = entry.get("effective_duration", def.tick_duration)
			if def.input_type != BuildingDef.OutputType.NONE and def.output_type == BuildingDef.OutputType.ENERGY:
				eff_dur *= d_buffs.generator_duration_mult
				var in_min: String = entry.get("burning_mineral", "")
				if in_min != "":
					var rd: ResourceData = GameState.known_resources.get(in_min)
					if rd: eff_dur *= float(rd.rarity)
			var rate: float = delta / (eff_dur / speed_mult)
			var next: float = prev + rate

			if next >= 1.0:
				# ── End-of-cycle production ───────────────────────────────────
				_on_tick_complete(pp, def, key, 0.0, amount, entry)
				_progress[key] = 0.0
				# Spaceport: re-pause after each launch cycle so player must trigger manually
				if def.building_id == "spaceport":
					_user_paused[key] = true
				building_ticked.emit(planet_seed, key)
			else:
				_progress[key] = next

			_emit_progress(planet_seed, key)

		# Apply stacked-build merges now that iteration is complete
		for entry: Dictionary in pending_merges:
			var merge_idx: int = entry.get("merge_into", -1)
			if merge_idx >= 0 and merge_idx < pp.buildings.size():
				pp.buildings[merge_idx]["amount"] = pp.buildings[merge_idx].get("amount", 1) + 1
			pp.remove_building_stack(entry)

		for c in completed_buildings:
			building_constructed.emit(planet_seed, c.key, c.bid)

func _on_tick_complete(pp: PlanetProgress, def: BuildingDef,
		_key_str: String, _energy: float, amount: int,
		entry: Dictionary) -> void:
	# Skip if building was scrapped before tick completed
	if not pp.buildings.has(entry):
		return
	# Produce output (scaled by amount)
	var mods := PlanetModifier.for_planet(_planet_type(pp.planet_seed))
	var st := get_node("/root/SkillTree")
	if def.logic != null:
		def.logic.produce(pp, def, amount, mods, entry, st)

	var poi_lbl: String = entry.get("district_id", "")

	# For mines: emit one notification per resource with its actual color/icon
	if def.output_type == BuildingDef.OutputType.RAW_MINERAL or def.output_type == BuildingDef.OutputType.REFINED_MINERAL:
		if poi_lbl != "":
			var pd: PlanetData = GameState.get_planet_data(pp.planet_seed)
			var tag := ResourceData.Tag.RAW_MINERAL if def.output_type == BuildingDef.OutputType.RAW_MINERAL else ResourceData.Tag.REFINED_MINERAL
			var res_list := GameState.get_body_resources_for(pd).get_by_tag(tag)
			var dbuffs := get_district_buffs(pp, poi_lbl)
			var mult: float = get_building_level_mult(entry.get("level", 1)) * st.get_mine_output_mult() * dbuffs.mine_output_mult
			if def.building_id == "magma_dredge":
				mult *= dbuffs.magma_dredge_output_mult
			var total_density: float = 0.0
			var densities: Array[float] = []
			var rng := RandomNumberGenerator.new()
			for rd in res_list:
				var r_id := (rd as ResourceData).resource_id()
				var d: float
				if pd.mineral_densities.has(r_id):
					d = float(pd.mineral_densities[r_id])
				else:
					rng.seed = pd.seed ^ ((rd as ResourceData).rarity * 0x4E3D)
					d = pd.deposit_density * rng.randf_range(0.75, 1.25)
				densities.append(d)
				total_density += d
			var total_out := def.output_amount * amount * mult
			if total_density > 0.0:
				for i in res_list.size():
					var share := total_out * (densities[i] / total_density)
					if share < 0.05:
						continue
					var rd := res_list[i] as ResourceData
					var icon_tex := MineralIcon.make(rd.tier, rd.display_color)
					var txt := "+%.1f" % share if share < 1.0 else "+%.0f" % share
					resource_produced.emit(pp.planet_seed, poi_lbl, txt, rd.display_color, icon_tex)
		return

	var display_val := def.output_amount * amount * get_building_level_mult(entry.get("level", 1))
	var suffix := ""
	var icon_tex: Texture2D = null
	match def.output_type:
		BuildingDef.OutputType.CREDITS:
			display_val *= st.get_credits_mult()
			suffix = " cr"
		BuildingDef.OutputType.SCIENCE:
			suffix = " sci"
		BuildingDef.OutputType.ENERGY:
			display_val = 0.0

	if display_val > 0.0 and poi_lbl != "":
		var txt := "+%.0f%s" % [display_val, suffix]
		resource_produced.emit(pp.planet_seed, poi_lbl, txt, def.output_color(), icon_tex)


# ── Building Level & Buffs ────────────────────────────────────────────────────

func get_building_level_mult(level: int) -> float:
	return 1.0 + 0.5 * (log(max(1, level)) / log(2.0))

func get_building_consume_mult(level: int) -> float:
	return 1.0 + 0.25 * (log(max(1, level)) / log(2.0))

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
			if in_min == "":
				out_val = 0.0 # No fuel
	elif def.output_type == BuildingDef.OutputType.RAW_MINERAL or def.output_type == BuildingDef.OutputType.REFINED_MINERAL:
		out_val *= st.get_mine_output_mult() * dbuffs.mine_output_mult
		if def.building_id == "magma_dredge":
			out_val *= dbuffs.magma_dredge_output_mult
	return out_val


func get_district_buffs(pp: PlanetProgress, district_id: String) -> Dictionary:
	var buffs := {
		"solar_mult": 1.0,
		"geothermal_mult": 1.0,
		"clean_energy_mult": 1.0,
		"generator_duration_mult": 1.0,
		"mine_output_mult": 1.0,
		"mine_speed_mult": 1.0,
		"refinery_speed_mult": 1.0,
		"mining_energy_cost_mult": 1.0,
		"magma_dredge_output_mult": 1.0,
		"gas_mining_speed_mult": 1.0,
		"residential_mult": 1.0,
		"apartments_mult": 1.0,
		"luxury_complex_mult": 1.0
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
		elif bid == "extraction_optimizer":
			buffs.mine_output_mult += 0.05 * amt * lv_mult
		elif bid == "sonic_resonator":
			buffs.mine_speed_mult += 0.05 * amt * lv_mult
		elif bid == "thermal_crusher":
			buffs.refinery_speed_mult += 0.05 * amt * lv_mult
		elif bid == "logistics_hub":
			buffs.mining_energy_cost_mult -= 0.05 * amt * lv_mult
		elif bid == "tectonic_stabilizer":
			buffs.magma_dredge_output_mult += 0.50 * amt * lv_mult
		elif bid == "pressure_funnel":
			buffs.gas_mining_speed_mult += 0.50 * amt * lv_mult
		elif bid == "zero_g_sorter":
			buffs.mine_speed_mult += 0.20 * amt * lv_mult
		elif bid == "culture_center":
			buffs.residential_mult += 0.20 * amt * lv_mult
		elif bid == "recreation_center":
			buffs.apartments_mult += 0.25 * amt * lv_mult
		elif bid == "opera_house":
			buffs.luxury_complex_mult += 0.30 * amt * lv_mult
	return buffs

## Computes global energy balance and ratio across ALL colonized planets.
## Called once per frame before _tick_all.
func _calc_global_energy() -> void:
	var total_prod: float = 0.0
	var total_demand: float = 0.0
	var net: float = 0.0
	var st := get_node("/root/SkillTree")
	for pp: PlanetProgress in _all_colonies():
		for i in pp.buildings.size():
			var entry: Dictionary = pp.buildings[i]
			if entry.get("constructing", false):
				continue
			var def := BuildingDef.find(entry.get("building_id", ""))
			if def == null:
				continue
			var amt: int     = entry.get("amount", 1)
			if not entry.has("uid"):
				entry["uid"] = str(randi())
			var ekey: String = _key(pp.planet_seed, entry.get("district_id", ""), entry["uid"])
			if _paused.get(ekey, false) or _user_paused.get(ekey, false):
				continue
			var planet_energy_mult := 1.0
			if pp.has_building("command_center"):
				planet_energy_mult *= 0.85
				
			var lv: int = entry.get("level", 1)
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
				var building_consume: float = consume_mult
				if def.output_type == BuildingDef.OutputType.RAW_MINERAL or def.output_type == BuildingDef.OutputType.REFINED_MINERAL:
					building_consume *= max(0.1, dbuffs.mining_energy_cost_mult as float) * st.get_mining_energy_mult()
				
				var st_energy_mult: float = st.get_energy_consume_mult()
				if POIData.POIType.CITY in def.allowed_poi_types and st.is_unlocked("housing_maintenance"):
					st_energy_mult -= 0.10
					
				var contrib := def.energy_per_tick * amt * building_consume * st_energy_mult * planet_energy_mult
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
					if in_min == "":
						mult = 0.0
				total_prod += def.output_amount * amt * mult
				net        += def.output_amount * amt * mult
	_global_energy = net
	_global_energy_ratio = 1.0 if total_demand <= 0.0 else clampf(total_prod / total_demand, 0.0, 1.0)

## Per-planet energy contribution (used by PlanetaryView for breakdown display).
func planet_energy_net(pp: PlanetProgress) -> float:
	var st := get_node("/root/SkillTree")
	var total: float = 0.0
	for i in pp.buildings.size():
		var entry: Dictionary = pp.buildings[i]
		if entry.get("constructing", false):
			continue
		var def := BuildingDef.find(entry.get("building_id", ""))
		if def == null:
			continue
		var amt: int     = entry.get("amount", 1)
		if not entry.has("uid"):
			entry["uid"] = str(randi())
		var ekey: String = _key(pp.planet_seed, entry.get("district_id", ""), entry["uid"])
		if _paused.get(ekey, false) or _user_paused.get(ekey, false):
			continue
		var lv: int = entry.get("level", 1)
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
			var building_consume: float = consume_mult
			if def.output_type == BuildingDef.OutputType.RAW_MINERAL or def.output_type == BuildingDef.OutputType.REFINED_MINERAL:
				building_consume *= max(0.1, dbuffs.mining_energy_cost_mult as float) * st.get_mining_energy_mult()
			total += def.energy_per_tick * amt * building_consume * (st.get_energy_consume_mult() as float)
			
		if def.output_type == BuildingDef.OutputType.ENERGY:
			var mult: float = lv_mult
			if def.building_id == "solar_panel" or def.building_id == "solar_matrix":
				mult *= st.get_solar_mult() * dbuffs.clean_energy_mult * dbuffs.solar_mult
			elif def.building_id == "geothermal_plant":
				mult *= st.get_generator_output_mult() * dbuffs.clean_energy_mult * dbuffs.geothermal_mult
			elif def.input_type != BuildingDef.OutputType.NONE:
				mult *= st.get_generator_output_mult()
				var in_min: String = entry.get("burning_mineral", "")
				if in_min == "":
					mult = 0.0
			total += def.output_amount * amt * mult
	return total

func _planet_type(planet_seed: int) -> PlanetData.Type:
	var pd := GameState.get_planet_data(planet_seed)
	if pd != null:
		return pd.planet_type
	return PlanetData.Type.TERRAN

func _deposit_speed(def: BuildingDef, planet_seed: int,
		mods: Array[PlanetModifier]) -> float:
	if def.output_type != BuildingDef.OutputType.RAW_MINERAL:
		return 1.0
	var pd := GameState.get_planet_data(planet_seed)
	var br := GameState.get_body_resources_for(pd) if pd != null \
		else GameState.get_body_resources(planet_seed)
	var base: float = clampf(br.avg_power() * 0.4, 0.5, 3.0)
	var planet_mult: float = PlanetModifier.combined(mods, PlanetModifier.Effect.MINE_SPEED_MULT)
	return base * planet_mult

func _all_colonies() -> Array[PlanetProgress]:
	var result: Array[PlanetProgress] = []
	for pp: PlanetProgress in GameState._planet_progress.values():
		if pp.is_colonized:
			result.append(pp)
	return result

func _entry_index(pp: PlanetProgress, entry: Dictionary) -> int:
	for i in pp.buildings.size():
		if pp.buildings[i] == entry:
			return i
	return 0

func _key(planet_seed: int, poi_label: String, uid: String) -> String:
	return "%d:%s:%s" % [planet_seed, poi_label, uid]

func _resource_key(out_type: BuildingDef.OutputType, planet_seed: int,
		entry: Dictionary = {}) -> String:
	match out_type:
		BuildingDef.OutputType.RAW_MINERAL:
			# If this is an input checking situation, check input_mineral first, else target_mineral
			var tgt: String = entry.get("input_mineral", "")
			if tgt == "":
				tgt = entry.get("target_mineral", "")
			if tgt != "":
				return tgt
			# Auto-assign: pick the first raw mineral on this planet and persist it
			var _pd := GameState.get_planet_data(planet_seed)
			var br := GameState.get_body_resources_for(_pd) if _pd != null \
				else GameState.get_body_resources(planet_seed)
			var raw := br.get_by_tag(ResourceData.Tag.RAW_MINERAL)
			if not raw.is_empty():
				var rid: String = (raw[0] as ResourceData).resource_id()
				if not entry.is_empty():
					entry["target_mineral"] = rid   # persist default for outputs
				return rid
			return "raw_%d" % planet_seed   # last-resort generic fallback
		BuildingDef.OutputType.REFINED_MINERAL:
			return "ref_%d" % planet_seed
	return ""

func _emit_progress(planet_seed: int, key: String) -> void:
	building_progress_changed.emit(planet_seed, key, _progress.get(key, 0.0))
