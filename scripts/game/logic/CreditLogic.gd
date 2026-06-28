class_name CreditLogic
extends BuildingLogic

func produce(pp: PlanetProgress, def: BuildingDef, amount: int, mods: Array, entry: Dictionary, skill_tree: Node) -> void:
	var mult: float = skill_tree.get_credits_mult()
	GameState.earn_credits(def.output_amount * amount * mult)
