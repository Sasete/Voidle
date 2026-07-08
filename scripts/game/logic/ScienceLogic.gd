class_name ScienceLogic
extends BuildingLogic

## Generates Science Points globally.

func produce(pp: PlanetProgress, def: BuildingDef, amount: int, mods: Array, entry: Dictionary, skill_tree: Node) -> void:
	var mult: float = 1.0
	
	if skill_tree.unlocked_skills.has("science_income_1"):
		mult += 0.15
	if skill_tree.unlocked_skills.has("science_income_2"):
		mult += 0.20
	if skill_tree.unlocked_skills.has("omega_core"):
		mult += 0.20
		
	var dbuffs := ProductionManager.get_district_buffs(pp, entry.get("district_id", ""))
	mult *= dbuffs.science_output_mult
		
	GameState.add_science(def.output_amount * amount * mult)
