class_name CreditLogic
extends BuildingLogic

func produce(pp: PlanetProgress, def: BuildingDef, amount: int, mods: Array, entry: Dictionary, skill_tree: Node) -> void:
	var dist_id: String = entry.get("district_id", "")
	var d_buffs := ProductionManager.get_district_buffs(pp, dist_id)
	var out_mult := 1.0
	
	if def.building_id == "residential":
		out_mult *= d_buffs.get("residential_mult", 1.0)
	elif def.building_id == "apartments":
		out_mult *= d_buffs.get("apartments_mult", 1.0)
	elif def.building_id == "luxury_complex":
		out_mult *= d_buffs.get("luxury_complex_mult", 1.0)
	else:
		# Assume it's a trade building if it uses CreditLogic and isn't housing
		out_mult *= d_buffs.get("trade_output_mult", 1.0)
		if skill_tree.has_method("get_trade_output_mult"):
			out_mult *= skill_tree.get_trade_output_mult()
		
	var mult: float = skill_tree.get_credits_mult() * out_mult
	GameState.earn_credits(def.output_amount * amount * mult)

func requires_mineral_selector() -> bool:
	return true
