## ProductionManager — autoload singleton.
## Ticks every building on every colonized planet each _process frame.
extends Node

signal building_ticked(planet_seed: int, key: String)
signal building_progress_changed(planet_seed: int, key: String, progress: float)
signal building_constructed(planet_seed: int, key: String)
signal building_toggled(key: String, paused: bool)

## { pm_key -> float 0.0-1.0 }
var _progress:    Dictionary = {}
## { pm_key -> bool } true = auto-paused (resource/energy shortage)
var _paused:      Dictionary = {}
## { pm_key -> bool } true = user manually toggled off
var _user_paused: Dictionary = {}
## planet energy balance cache { planet_seed -> float }
var _energy:        Dictionary = {}
## energy throttle ratio cache { planet_seed -> float 0.0-1.0 }
var _energy_ratio:  Dictionary = {}
## { "construct:pm_key" -> float 0.0-1.0 }
var _construct:     Dictionary = {}

func _process(delta: float) -> void:
	_energy.clear()
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
	building_toggled.emit(key, _user_paused[key])

func is_user_paused(key: String) -> bool:
	return _user_paused.get(key, false)

## Returns 0.0–1.0: fraction of energy demand covered. < 1.0 = energy crisis.
func get_energy_ratio(planet_seed: int) -> float:
	return _energy_ratio.get(planet_seed, 1.0)

## Called by PlanetaryView after building is placed so UI can refresh immediately.
func invalidate(planet_seed: int) -> void:
	building_ticked.emit(planet_seed, "")

# ── Internal ──────────────────────────────────────────────────────────────────

func _tick_all(delta: float) -> void:
	for pp: PlanetProgress in _all_colonies():
		var planet_seed: int = pp.planet_seed
		_planet_energy(pp)  # refresh net energy cache for HUD

		# Throttle ratio: production-only (never negative) vs total demand.
		# energy_ratio < 1.0 → all consumers slow proportionally; 0 → pause.
		var total_production: float = 0.0
		var total_demand:     float = 0.0
		for i in pp.buildings.size():
			var eb: Dictionary = pp.buildings[i]
			if eb.get("constructing", false): continue
			var ekey: String = _key(planet_seed, eb.get("district_id", ""), i)
			if _paused.get(ekey, false) or _user_paused.get(ekey, false):
				continue
			var edef := BuildingDef.find(eb.get("building_id", ""))
			if edef == null: continue
			var eamt: int = eb.get("amount", 1)
			if edef.output_type == BuildingDef.OutputType.ENERGY:
				var emult: float = 1.0
				if edef.building_id == "solar_panel":
					emult = get_node("/root/SkillTree").get_solar_mult()
				elif edef.building_id == "generator":
					emult = get_node("/root/SkillTree").get_generator_output_mult()
					var in_min: String = eb.get("burning_mineral", "")
					if in_min != "":
						var rd: ResourceData = GameState.known_resources.get(in_min)
						if rd: emult *= float(rd.rarity)
					else:
						emult = 0.0 # No fuel, no production
				total_production += edef.output_amount * eamt * emult
			if edef.energy_per_tick > 0.0:
				total_production += edef.energy_per_tick * eamt
			elif edef.energy_per_tick < 0.0:
				total_demand += abs(edef.energy_per_tick) * eamt
		var energy_ratio: float = 1.0
		if total_demand > 0.0:
			energy_ratio = clampf(total_production / total_demand, 0.0, 1.0)
		_energy_ratio[planet_seed] = energy_ratio

		var mods := PlanetModifier.for_planet(_planet_type(planet_seed))

		# Collect entries to merge/remove after iteration (avoid modifying array mid-loop)
		var pending_merges: Array[Dictionary] = []

		# Iterate with explicit index so identical-content entries get unique keys
		for i in pp.buildings.size():
			var entry: Dictionary = pp.buildings[i]
			var poi_label: String  = entry.get("district_id", "")
			var bid: String        = entry.get("building_id", "")
			var amount: int        = entry.get("amount", 1)
			var key: String        = _key(planet_seed, poi_label, i)
			var def := BuildingDef.find(bid)
			if def == null or def.tick_duration <= 0.0:
				continue

			# ── Construction phase ────────────────────────────────────────────
			if entry.get("constructing", false):
				var ck: String = "construct:" + key
				var cp: float  = _construct.get(ck, 0.0) + delta / def.tick_duration
				if cp >= 1.0:
					_construct.erase(ck)
					entry["constructing"] = false
					var merge_idx: int = entry.get("merge_into", -1)
					if merge_idx >= 0:
						pending_merges.append(entry)
					# Spaceport starts paused after construction — player launches manually
					if def.building_id == "spaceport":
						_user_paused[key] = true
					building_constructed.emit(planet_seed, key)
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

					var required_amt := def.input_amount * amount
					if pp.stored_resources.get(intended_input, 0.0) < required_amt:
						if not _paused.get(key, false):
							_paused[key] = true
							building_ticked.emit(planet_seed, key)
						_emit_progress(planet_seed, key)
						continue   # can't start — wait for resource
					
					# Resource available: consume it immediately
					pp.stored_resources[intended_input] -= required_amt
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

			# ── Tick production bar ───────────────────────────────────────────
			var speed_mult: float = _deposit_speed(def, planet_seed, mods) * energy_speed * get_node("/root/SkillTree").get_global_speed_mult()
			if def.output_type == BuildingDef.OutputType.RAW_MINERAL:
				speed_mult *= get_node("/root/SkillTree").get_mine_speed_mult()
			var rate: float = delta / (def.tick_duration / speed_mult)
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
			pp.buildings.erase(entry)

func _on_tick_complete(pp: PlanetProgress, def: BuildingDef,
		_key_str: String, _energy: float, amount: int,
		entry: Dictionary) -> void:
	# Produce output (scaled by amount)
	var mods := PlanetModifier.for_planet(_planet_type(pp.planet_seed))
	if def.logic != null:
		var st := get_node("/root/SkillTree")
		def.logic.produce(pp, def, amount, mods, entry, st)

func _planet_energy(pp: PlanetProgress) -> float:
	if _energy.has(pp.planet_seed):
		return _energy[pp.planet_seed]
	var total: float = 0.0
	for i in pp.buildings.size():
		var entry: Dictionary = pp.buildings[i]
		if entry.get("constructing", false):
			continue
		var def := BuildingDef.find(entry.get("building_id", ""))
		if def == null:
			continue
		var amt: int        = entry.get("amount", 1)
		var poi_lbl: String = entry.get("district_id", "")
		var ekey: String    = _key(pp.planet_seed, poi_lbl, i)
		# Skip paused (waiting for fuel/resource) and user-paused buildings
		if _paused.get(ekey, false) or _user_paused.get(ekey, false):
			continue
		
		# Direct energy flow (positive energy_per_tick = passive producer)
		if def.energy_per_tick > 0.0:
			var mult: float = get_node("/root/SkillTree").get_solar_mult() if def.building_id == "solar_panel" else 1.0
			total += def.energy_per_tick * amt * mult
		elif def.energy_per_tick < 0.0:
			# Apply energy consumption reducer skill
			total += def.energy_per_tick * amt * (get_node("/root/SkillTree").get_energy_consume_mult() as float)
			
		# Energy-output buildings (Solar Panel, Generator, Power Plant)
		if def.output_type == BuildingDef.OutputType.ENERGY:
			var mult: float = 1.0
			if def.building_id == "solar_panel":
				mult = get_node("/root/SkillTree").get_solar_mult()
			elif def.building_id == "generator":
				mult = get_node("/root/SkillTree").get_generator_output_mult()
				var in_min: String = entry.get("burning_mineral", "")
				if in_min != "":
					var rd: ResourceData = GameState.known_resources.get(in_min)
					if rd: mult *= float(rd.rarity)
			total += def.output_amount * amt * mult
	_energy[pp.planet_seed] = total
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
		if pp.is_colonized and not pp.buildings.is_empty():
			result.append(pp)
	return result

func _entry_index(pp: PlanetProgress, entry: Dictionary) -> int:
	for i in pp.buildings.size():
		if pp.buildings[i] == entry:
			return i
	return 0

func _key(planet_seed: int, poi_label: String, idx: int) -> String:
	return "%d:%s:%d" % [planet_seed, poi_label, idx]

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
