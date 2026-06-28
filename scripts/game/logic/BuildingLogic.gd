class_name BuildingLogic
extends Resource

## The logic that runs when a building cycle completes.
func produce(pp: PlanetProgress, def: BuildingDef, amount: int, mods: Array, entry: Dictionary, skill_tree: Node) -> void:
	pass

## Does this logic require the user to select an input mineral?
func requires_mineral_selector() -> bool:
	return false

## Custom output label formatter (can be empty to use default logic).
func format_output_label(def: BuildingDef) -> String:
	return ""
