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
var _energy:      Dictionary = {}
## { "construct:pm_key" -> float 0.0-1.0 }
var _construct:   Dictionary = {}

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

## Called by PlanetaryView after building is placed so UI can refresh immediately.
func invalidate(planet_seed: int) -> void:
	building_ticked.emit(planet_seed, "")

# ── Internal ──────────────────────────────────────────────────────────────────

func _tick_all(delta: float) -> void:
	for pp: PlanetProgress in _all_colonies():
		var planet_seed: int = pp.planet_seed
		var energy_avail: float = _planet_energy(pp)

		# Compute energy ratio for throttling: how much of demand is covered.
		# < 1.0 means deficit → energy-consumers slow down proportionally.
		var total_demand: float = 0.0
		for eb: Dictionary in pp.buildings:
			if eb.get("constructing", false): continue
			var edef := BuildingDef.find(eb.get("building_id", ""))
			if edef != null and edef.energy_per_tick < 0.0:
				total_demand += abs(edef.energy_per_tick) * eb.get("amount", 1)
		var energy_ratio: float = 1.0
		if total_demand > 0.0:
			energy_ratio = clampf(energy_avail / total_demand, 0.0, 1.0)

		var mods := PlanetModifier.for_planet(_planet_type(planet_seed))

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
					building_constructed.emit(planet_seed, key)
					building_ticked.emit(planet_seed, key)
				else:
					_construct[ck] = cp
					building_progress_changed.emit(planet_seed, key, cp)
				continue

			# ── User-toggled off ──────────────────────────────────────────────
			if _user_paused.get(key, false):
				continue

			# ── Auto-paused (waiting for resource): check if resource available ──
			# If the building was paused due to missing input resource, keep waiting
			# until the resource arrives. Energy-paused buildings fall through to
			# the energy_ratio check below.
			if _paused.get(key, false) and def.input_type != BuildingDef.OutputType.NONE:
				var rid2 := _resource_key(def.input_type, pp.planet_seed)
				if pp.stored_resources.get(rid2, 0.0) < def.input_amount * amount:
					_emit_progress(planet_seed, key)
					continue   # still not enough resource
				# Resource arrived — clear pause and let bar fill
				_paused[key] = false

			# ── Energy throttle ───────────────────────────────────────────────
			var needs_energy: bool = def.energy_per_tick < 0.0
			var energy_speed: float = 1.0
			if needs_energy:
				if energy_ratio <= 0.0:
					_paused[key] = true
					_emit_progress(planet_seed, key)
					continue
				energy_speed = energy_ratio  # slow to match available energy

			_paused[key] = false

			# ── Tick production bar ───────────────────────────────────────────
			var prev: float = _progress.get(key, 0.0)
			var speed_mult: float = _deposit_speed(def, planet_seed, mods) * energy_speed
			var rate: float = delta / (def.tick_duration / speed_mult)
			var next: float = prev + rate

			if next >= 1.0:
				# ── End-of-cycle resource check ───────────────────────────────
				# Bar is full. Check if the required input resource is available.
				# If not: pause the building and reset bar to 0 (waiting state).
				# Resource is consumed here (once) inside _on_tick_complete.
				if def.input_type != BuildingDef.OutputType.NONE:
					var rid := _resource_key(def.input_type, pp.planet_seed, entry)
					if pp.stored_resources.get(rid, 0.0) < def.input_amount * amount:
						_paused[key] = true
						_progress[key] = 0.0
						building_ticked.emit(planet_seed, key)
						_emit_progress(planet_seed, key)
						continue   # can't complete — wait for resource next frame
				# Resource available (or not needed): complete tick
				_on_tick_complete(pp, def, key, energy_avail, amount, entry)
				_progress[key] = 0.0
				building_ticked.emit(planet_seed, key)
			else:
				_progress[key] = next

			_emit_progress(planet_seed, key)

func _on_tick_complete(pp: PlanetProgress, def: BuildingDef,
		_key_str: String, _energy: float, amount: int,
		entry: Dictionary) -> void:
	# Consume input resource (scaled by amount)
	if def.input_type != BuildingDef.OutputType.NONE:
		var rid := _resource_key(def.input_type, pp.planet_seed, entry)
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
			var rid  := _resource_key(def.output_type, pp.planet_seed, entry)
			pp.add_resource(rid, def.output_amount * amount * mult)

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
			total += def.energy_per_tick * amt
		# Energy-output buildings (Solar Panel, Generator, Power Plant)
		if def.output_type == BuildingDef.OutputType.ENERGY:
			total += def.output_amount * amt
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
