class_name SpaceportLogic
extends BuildingLogic

## Emitted when a ship successfully launches. PlanetaryView connects to this
## to play the rocket animation and re-pause the building.
signal ship_launched(planet_seed: int, ship: ShipData)

## When true, the next produce() call is a cooldown completion — skip ship launch.
## PlanetaryView sets this before unpausing PM after a button-triggered animation.
var skip_next_launch: bool = false

func produce(pp: PlanetProgress, _def: BuildingDef, _amount: int,
		_mods: Array, _entry: Dictionary, _skill_tree: Node) -> void:
	pp.has_spaceport = true
	if skip_next_launch:
		skip_next_launch = false
		return
	var ship := ShipManager.launch(pp.planet_seed, "Shuttle")
	ship.ship_type = "station"
	ship_launched.emit(pp.planet_seed, ship)

func format_output_label(_def: BuildingDef) -> String:
	return ""
