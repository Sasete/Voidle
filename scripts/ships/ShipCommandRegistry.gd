## ShipCommandRegistry — autoload singleton.
##
## Holds all ShipCommandDef resources and the Callable that runs each one.
## PlanetaryView (or any scene) injects callables via register_callable().
## New commands = add a .tres + call register_callable(), no other changes needed.
extends Node

## All registered command definitions (loaded from .tres files).
var _commands: Array[ShipCommandDef] = []

## { command_id -> Callable }
## Ship command callable signature:   func(ship: ShipData, layer: OrbitalLayer) -> void
## Planet command callable signature: func() -> void
var _callables: Dictionary = {}

# ── Loading ───────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_commands_from_dir("res://resources/ships/commands/")

func _load_commands_from_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res: Resource = load(path + fname)
			if res is ShipCommandDef:
				_commands.append(res as ShipCommandDef)
		fname = dir.get_next()

# ── Callable injection (DI) ───────────────────────────────────────────────────

## Inject the implementation for a command id.
## Ship:   register_callable("deselect", func(ship, layer): layer.deselect())
## Planet: register_callable("solar_view", func(): _go_back())
func register_callable(command_id: String, callable: Callable) -> void:
	_callables[command_id] = callable

# ── Queries ───────────────────────────────────────────────────────────────────

func get_ship_commands(ship_type: String) -> Array[ShipCommandDef]:
	var result: Array[ShipCommandDef] = []
	for cmd: ShipCommandDef in _commands:
		if cmd.context == ShipCommandDef.Context.SHIP:
			if cmd.ship_types.is_empty() or ship_type in cmd.ship_types:
				result.append(cmd)
	return result

func get_planet_commands() -> Array[ShipCommandDef]:
	var result: Array[ShipCommandDef] = []
	for cmd: ShipCommandDef in _commands:
		if cmd.context == ShipCommandDef.Context.PLANET:
			result.append(cmd)
	return result

func get_callable(command_id: String) -> Callable:
	return _callables.get(command_id, Callable())

func has_callable(command_id: String) -> bool:
	return _callables.has(command_id)
