## ProductionManager — autoload singleton.
## Ticks every building on every colonized planet each _process frame.
extends Node

signal building_ticked(planet_seed: int, key: String)
signal building_progress_changed(planet_seed: int, key: String, progress: float)

## { "planet_seed:poi_label:idx" -> float 0.0-1.0 }
var _progress:  Dictionary = {}
## { "planet_seed:poi_label:idx" -> bool } true = waiting for resources
var _paused:    Dictionary = {}
## planet energy balance cache, rebuilt each frame { planet_seed -> float }
var _energy:    Dictionary = {}

func _process(delta: float) -> void:
	_energy.clear()
	_tick_all(delta)

func get_progress(key: String) -> float:
	return _progress.get(key, 0.0)

func is_paused(key: String) -> bool:
	return _paused.get(key, false)

## Called by PlanetaryView after building is placed so UI can refresh immediately.
func invalidate(planet_seed: int) -> void:
	building_ticked.emit(planet_seed, "")

# ── Internal ──────────────────────────────────────────────────────────────────

func _tick_all(delta: float) -> void:
	for pp: PlanetProgress in _all_colonies():
		var planet_seed: int = pp.planet_seed
		var energy_avail: float = _planet_energy(pp)

		var mods := PlanetModifier.for_planet(_planet_type(planet_seed))

		for entry: Dictionary in pp.buildings:
			var poi_label: String  = entry.get("district_id", "")
			var bid: String        = entry.get("building_id", "")
			var amount: int        = entry.get("amount", 1)
			var idx: int           = _entry_index(pp, entry)
			var key: String        = _key(planet_seed, poi_label, idx)
			var def := BuildingDef.find(bid)
			if def == null or def.tick_duration <= 0.0:
				continue

			# Energy consumed scales with amount
			var energy_needed: float = abs(def.energy_per_tick) * amount
			var needs_energy: bool   = def.energy_per_tick < 0.0
			var energy_mult := PlanetModifier.combined(mods, PlanetModifier.Effect.ENERGY_COST_MULT)
			energy_needed *= energy_mult

			if needs_energy and energy_avail < energy_needed and energy_avail > 0.0:
				_paused[key] = true
				_emit_progress(planet_seed, key)
				continue

			# Check input resources (scaled by amount)
			if def.input_type != BuildingDef.OutputType.NONE:
				var rid := _resource_key(def.input_type, pp.planet_seed)
				var have: float = pp.stored_resources.get(rid, 0.0)
				if have < def.input_amount * amount and _progress.get(key, 0.0) == 0.0:
					_paused[key] = true
					_emit_progress(planet_seed, key)
					continue

			_paused[key] = false

			# Speed — mines also use PlanetModifier mine speed
			var speed_mult: float = _deposit_speed(def, planet_seed, mods)
			var rate: float = delta / (def.tick_duration / speed_mult)
			var prev: float = _progress.get(key, 0.0)
			var next: float = prev + rate

			if next >= 1.0:
				_on_tick_complete(pp, def, key, energy_avail, amount)
				_progress[key] = 0.0
				if needs_energy:
					energy_avail -= energy_needed
				building_ticked.emit(planet_seed, key)
			else:
				_progress[key] = next

			_emit_progress(planet_seed, key)

func _on_tick_complete(pp: PlanetProgress, def: BuildingDef,
		_key_str: String, _energy: float, amount: int) -> void:
	# Consume input (scaled by amount)
	if def.input_type != BuildingDef.OutputType.NONE:
		var rid := _resource_key(def.input_type, pp.planet_seed)
		pp.stored_resources[rid] = maxf(0.0,
			pp.stored_resources.get(rid, 0.0) - def.input_amount * amount)

	# Produce output (scaled by amount)
	var mods := PlanetModifier.for_planet(_planet_type(pp.planet_seed))
	match def.output_type:
		BuildingDef.OutputType.CREDITS:
			GameState.earn_credits(def.output_amount * amount)
		BuildingDef.OutputType.ENERGY:
			pass   # energy is a flow
		BuildingDef.OutputType.RAW_MINERAL, BuildingDef.OutputType.REFINED_MINERAL:
			var mult := PlanetModifier.combined(mods, PlanetModifier.Effect.MINE_OUTPUT_MULT)
			var rid  := _resource_key(def.output_type, pp.planet_seed)
			pp.add_resource(rid, def.output_amount * amount * mult)

func _planet_energy(pp: PlanetProgress) -> float:
	if _energy.has(pp.planet_seed):
		return _energy[pp.planet_seed]
	var total: float = 0.0
	for entry: Dictionary in pp.buildings:
		var def := BuildingDef.find(entry.get("building_id", ""))
		if def != null and def.energy_per_tick > 0.0:
			total += def.energy_per_tick
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
	var br := GameState.get_body_resources(planet_seed, 1, 3)
	var avg_tier: float = 1.0
	var arr := br.as_array()
	if not arr.is_empty():
		var sum: float = 0.0
		for rd: ResourceData in arr:
			sum += float(rd.tier)
		avg_tier = sum / float(arr.size())
	var base: float = clampf(avg_tier * 0.5, 0.5, 3.0)
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

func _resource_key(out_type: BuildingDef.OutputType, planet_seed: int) -> String:
	match out_type:
		BuildingDef.OutputType.RAW_MINERAL:    return "raw_%d" % planet_seed
		BuildingDef.OutputType.REFINED_MINERAL: return "ref_%d" % planet_seed
	return ""

func _emit_progress(planet_seed: int, key: String) -> void:
	building_progress_changed.emit(planet_seed, key, _progress.get(key, 0.0))
