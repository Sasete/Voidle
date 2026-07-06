import re

with open("scripts/ui/SkillTreeView.gd", "r") as f:
    content = f.read()

target = """		# Show title. If it is leveled, we will put the level info at the top right inside body
		var tip_title: String = node.name
		var tip_body := ""
		var tip_cost := ""
		
		# Root is a dummy central core - format clean
		if id == "root":
			tip_body = node.description
		else:
			# Format level information to show at the right top of the tooltip body
			if max_lv > 1:
				if cur_lv >= max_lv:
					tip_body += "[right][color=#55f58c]MAX LEVEL[/color][/right]\\n"
				else:
					tip_body += "[right][color=#e5c24b]Level %d/%d[/color][/right]\\n" % [cur_lv, max_lv]
				
			# Normal nodes
			if max_lv > 1:
				# Leveled Upgrades
				tip_body = node.description
				if cur_lv > 0:
					tip_body += "\\n\\n[color=#55f58c]Current Level: %d/%d[/color]" % [cur_lv, max_lv]
				if cur_lv < max_lv:
					tip_body += "\\n[color=#55aaff]Effect: %s[/color]" % node.effect_desc
				else:
					tip_body += "\\n\\n[color=#55f58c]✦ MAX LEVEL ✦[/color]"
			else:
				# Single purchase upgrades
				tip_body = node.description + "\\n\\n[color=#55aaff]Effect: " + node.effect_desc + "[/color]"
				if unlocked:
					tip_body += "\\n\\n[color=#55f58c]✦ UNLOCKED ✦[/color]"
			
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
					tip_body += "\\n\\n[color=#ff5544]Requires: " + ", ".join(missing_parents) + "[/color]"

		# Pivot offset at center for clean scaling"""

replace = """		# Show title. If it is leveled, we will put the level info at the top right inside body
		var tip_title: String = node.name
		var tip_body: Array = []
		var tip_cost := ""
		
		# Root is a dummy central core - format clean
		if id == "root":
			tip_body.append(node.description)
		else:
			var body_str := ""
			# Format level information to show at the right top of the tooltip body
			if max_lv > 1:
				if cur_lv >= max_lv:
					body_str += "[right][color=#55f58c]MAX LEVEL[/color][/right]\\n"
				else:
					body_str += "[right][color=#e5c24b]Level %d/%d[/color][/right]\\n" % [cur_lv, max_lv]
				
			# Normal nodes
			if max_lv > 1:
				# Leveled Upgrades
				body_str += node.description
				if cur_lv > 0:
					body_str += "\\n\\n[color=#55f58c]Current Level: %d/%d[/color]" % [cur_lv, max_lv]
				if cur_lv < max_lv:
					body_str += "\\n[color=#55aaff]Effect: %s[/color]" % node.effect_desc
				else:
					body_str += "\\n\\n[color=#55f58c]✦ MAX LEVEL ✦[/color]"
			else:
				# Single purchase upgrades
				body_str += node.description + "\\n\\n[color=#55aaff]Effect: "
				
				if id.begins_with("unlock_"):
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

		# Pivot offset at center for clean scaling"""

content = content.replace(target, replace)

with open("scripts/ui/SkillTreeView.gd", "w") as f:
    f.write(content)

print("SkillTreeView patched.")
