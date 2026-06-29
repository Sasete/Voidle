class_name SpaceportLogic
extends BuildingLogic

## Emitted when a ship successfully enters orbit after launch animation.
signal ship_launched(planet_seed: int, ship: ShipData)
## Emitted when preparation cycle finishes — card should rebuild to show Launch button.
signal preparation_complete(planet_seed: int)

func produce(pp: PlanetProgress, _def: BuildingDef, _amount: int,
		_mods: Array, entry: Dictionary, _skill_tree: Node) -> void:
	pp.has_spaceport = true
	var phase: String = entry.get("phase", "idle")

	if phase == "preparing":
		# Preparation done — unlock the Launch button.
		entry["phase"] = "launch_ready"
		entry.erase("effective_duration")
		preparation_complete.emit(pp.planet_seed)
		return

	if entry.get("cooldown_only", false):
		# Post-launch cooldown finished — back to idle.
		entry["cooldown_only"] = false
		entry["phase"] = "idle"
		return

	# Fallback: shouldn't be reached in normal new flow.
	var ship := ShipManager.launch(pp.planet_seed, entry.get("ship_name", "Shuttle"))
	ship.ship_type = entry.get("ship_type", "shuttle")
	ship_launched.emit(pp.planet_seed, ship)

func format_output_label(_def: BuildingDef) -> String:
	return ""
