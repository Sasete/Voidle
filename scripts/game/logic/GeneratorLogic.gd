class_name GeneratorLogic
extends BuildingLogic

func requires_mineral_selector() -> bool:
	return true

func produce(pp: PlanetProgress, def: BuildingDef, amount: int, mods: Array, entry: Dictionary, skill_tree: Node) -> void:
	pass # Energy is handled as flow.
