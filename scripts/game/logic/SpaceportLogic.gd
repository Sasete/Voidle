class_name SpaceportLogic
extends BuildingLogic

## Emitted when a ship successfully launches. PlanetaryView connects to this
## to play the rocket animation and re-pause the building.
signal ship_launched(planet_seed: int, ship: ShipData)

func produce(pp: PlanetProgress, _def: BuildingDef, _amount: int,
		_mods: Array, entry: Dictionary, _skill_tree: Node) -> void:
	pp.has_spaceport = true
	# If entry["cooldown_only"] is set, this cycle was just a recharge — don't launch.
	if entry.get("cooldown_only", false):
		entry["cooldown_only"] = false
		return
	var ship := ShipManager.launch(pp.planet_seed, "Shuttle")
	ship.ship_type = "station"
	ship_launched.emit(pp.planet_seed, ship)

func format_output_label(_def: BuildingDef) -> String:
	return ""
