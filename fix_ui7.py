import re

with open("scripts/ui/SkillTreeView.gd", "r") as f:
    content = f.read()

# We need to extract the building logic into a sub_body array.
target = """				if id.begins_with("unlock_"):
					var bid := id.trim_prefix("unlock_")
					var def := BuildingDef.find(bid)
					if def:
						body_str += node.effect_desc.replace(def.display_name, "[color=#fce205]" + def.display_name + "[/color]") + "[/color]"
						var cycle := " / %ds" % def.tick_duration
						var details := "\\n[color=#99aab5]"
						if def.output_type == BuildingDef.OutputType.ENERGY:
							details += "Produces +%.0f ⚡%s\\n" % [def.output_amount, cycle]
						
						if def.input_type != BuildingDef.OutputType.NONE:
							details += "Consumes -%.0f " % def.input_amount
							var t_col := Color(0.6, 0.6, 0.6)
							if def.input_tier == 2: t_col = Color(0.8, 0.8, 0.9)
							elif def.input_tier == 3: t_col = Color(0.4, 0.7, 0.4)
							elif def.input_tier == 4: t_col = Color(0.5, 0.5, 0.9)
							elif def.input_tier == 5: t_col = Color(0.9, 0.4, 0.4)
							
							tip_body.append(body_str + details + "[/color]")
							tip_body.append(MineralIcon.make(def.input_tier, t_col))
							body_str = "[color=#99aab5]%s[/color]" % cycle
						else:
							body_str += details + "[/color]"
					else:
						body_str += node.effect_desc + "[/color]"
				else:
					body_str += node.effect_desc + "[/color]"
					
				if unlocked:
					body_str += "\\n\\n[color=#55f58c]✦ UNLOCKED ✦[/color]"
			
			# Cost handling
			if cur_lv < max_lv:
				var next_cost: float = st.call("get_next_cost", id)
				tip_cost = "%.0f Science" % next_cost
			
			# Requirements checking
			if cur_lv == 0:
				var missing_parents: Array[String] = []
				for p in node.parents:
					if st.call("get_skill_level", p) == 0:
						missing_parents.append(st.get("nodes")[p].name)
				
				if missing_parents.size() > 0:
					body_str += "\\n\\n[color=#ff5544]Requires: " + ", ".join(missing_parents) + "[/color]"
			
			tip_body.append(body_str)

		# Pivot offset at center for clean scaling
		card.pivot_offset = Vector2(24, 24)

		var cap_cost := tip_cost
		card.mouse_entered.connect(func() -> void:
			AudioManager.play("hover")
			if unlocked or purchasable:
				CursorManager.set_state(CursorManager.State.POINTER)
			else:
				CursorManager.set_state(CursorManager.State.NORMAL)

			# Smooth scale up animation (Juicy Hover)
			var tween := create_tween()
			tween.tween_property(card, "scale", Vector2(1.15, 1.15), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

			TooltipManager.show_tip(tip_title, tip_body, cap_cost))"""


replace = """				var sub_body: Array = []
				if id.begins_with("unlock_"):
					var bid := id.trim_prefix("unlock_")
					var def := BuildingDef.find(bid)
					if def:
						body_str += node.effect_desc.replace(def.display_name, "[color=#fce205]" + def.display_name + "[/color]") + "[/color]"
						
						var cycle := " / %ds" % def.tick_duration
						var details := "[color=#99aab5]"
						sub_body.append("[color=#fce205]" + def.display_name + " Blueprint[/color]\\n\\n")
						if def.output_type == BuildingDef.OutputType.ENERGY:
							details += "Produces +%.0f ⚡%s\\n" % [def.output_amount, cycle]
						
						if def.input_type != BuildingDef.OutputType.NONE:
							details += "Consumes -%.0f " % def.input_amount
							var t_col := Color(0.6, 0.6, 0.6)
							if def.input_tier == 2: t_col = Color(0.8, 0.8, 0.9)
							elif def.input_tier == 3: t_col = Color(0.4, 0.7, 0.4)
							elif def.input_tier == 4: t_col = Color(0.5, 0.5, 0.9)
							elif def.input_tier == 5: t_col = Color(0.9, 0.4, 0.4)
							
							sub_body.append(details + "[/color]")
							sub_body.append(MineralIcon.make(def.input_tier, t_col))
							sub_body.append("[color=#99aab5]%s[/color]" % cycle)
						else:
							sub_body.append(details + "[/color]")
					else:
						body_str += node.effect_desc + "[/color]"
				else:
					body_str += node.effect_desc + "[/color]"
					
				if unlocked:
					body_str += "\\n\\n[color=#55f58c]✦ UNLOCKED ✦[/color]"
			
			# Cost handling
			if cur_lv < max_lv:
				var next_cost: float = st.call("get_next_cost", id)
				tip_cost = "%.0f Science" % next_cost
			
			# Requirements checking
			if cur_lv == 0:
				var missing_parents: Array[String] = []
				for p in node.parents:
					if st.call("get_skill_level", p) == 0:
						missing_parents.append(st.get("nodes")[p].name)
				
				if missing_parents.size() > 0:
					body_str += "\\n\\n[color=#ff5544]Requires: " + ", ".join(missing_parents) + "[/color]"
			
			tip_body.append(body_str)

		# Pivot offset at center for clean scaling
		card.pivot_offset = Vector2(24, 24)

		var cap_cost := tip_cost
		# WE NEED TO CAPTURE SUB BODY AS WELL
		var sub_body_cap = null
		# To avoid undeclared identifier error if sub_body is not in scope for leveled nodes:
		# Wait, sub_body is declared inside `if max_lv > 1: else:` branch!
		# I should declare it outside. Let's fix that below."""

content = content.replace(target, replace)

# I need to declare sub_body at the top of the block
target2 = """		var tip_body: Array = []
		var tip_cost := """"
replace2 = """		var tip_body: Array = []
		var sub_body: Array = []
		var tip_cost := """"
content = content.replace(target2, replace2)

# Now remove the duplicate `var sub_body: Array = []` I added inside the else branch
target3 = """			else:
				# Single purchase upgrades
				body_str += node.description + "\\n\\n[color=#55aaff]Effect: "
				
				var sub_body: Array = []"""
replace3 = """			else:
				# Single purchase upgrades
				body_str += node.description + "\\n\\n[color=#55aaff]Effect: "
				"""
content = content.replace(target3, replace3)

# Pass sub_body_cap
target4 = """		var cap_cost := tip_cost
		# WE NEED TO CAPTURE SUB BODY AS WELL
		var sub_body_cap = null
		# To avoid undeclared identifier error if sub_body is not in scope for leveled nodes:
		# Wait, sub_body is declared inside `if max_lv > 1: else:` branch!
		# I should declare it outside. Let's fix that below.
		card.mouse_entered.connect(func() -> void:
			AudioManager.play("hover")
			if unlocked or purchasable:
				CursorManager.set_state(CursorManager.State.POINTER)
			else:
				CursorManager.set_state(CursorManager.State.NORMAL)

			# Smooth scale up animation (Juicy Hover)
			var tween := create_tween()
			tween.tween_property(card, "scale", Vector2(1.15, 1.15), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

			TooltipManager.show_tip(tip_title, tip_body, cap_cost))"""
replace4 = """		var cap_cost := tip_cost
		var cap_sub := sub_body.duplicate()
		card.mouse_entered.connect(func() -> void:
			AudioManager.play("hover")
			if unlocked or purchasable:
				CursorManager.set_state(CursorManager.State.POINTER)
			else:
				CursorManager.set_state(CursorManager.State.NORMAL)

			# Smooth scale up animation (Juicy Hover)
			var tween := create_tween()
			tween.tween_property(card, "scale", Vector2(1.15, 1.15), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

			TooltipManager.show_tip(tip_title, tip_body, cap_cost, cap_sub))"""
content = content.replace(target4, replace4)

with open("scripts/ui/SkillTreeView.gd", "w") as f:
    f.write(content)

print("SkillTreeView Tooltip Fixed")
