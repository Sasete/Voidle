## Defines one step type in a mission chain.
## Register instances via MissionTaskRegistry.register().
## The actual UI and cost logic live here as Callables — no subclassing needed.
class_name MissionTaskDef
extends RefCounted

## Unique identifier, e.g. "move_station", "pickup".
var task_type: String = ""

## Human-readable name shown in the "+" dropdown and task rows.
var display_name: String = ""

## Status strings that the chain must be in for this task to appear.
## Supports exact match ("in_orbit") and prefix wildcard ("at_station:*").
## Special value "*" matches any status.
var required_status: Array = []

## Ship types this task requires. Empty = available for all types.
## e.g. ["station"] to restrict to station ships only.
var required_ship_types: Array = []

## Status produced when this task completes. Use "{key}" to embed entry values,
## e.g. "at_station:{target_id}" resolves to "at_station:SHIP_XYZ".
var produced_status: String = ""

## func(container: Control, entry: Dictionary, on_change: Callable) -> void
## Builds the inline parameter UI for this task into `container`.
## Must call on_change() whenever a param changes so cost/validity updates.
var build_params_ui: Callable

## func(entry: Dictionary, context: Dictionary) -> float
## Returns the credit cost contribution of this task given its params.
## context = { planet_seed, ships: Array[ShipData] }
var estimate_cost: Callable
