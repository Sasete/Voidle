import re

with open("scripts/game/SkillTree.gd", "r") as f:
    content = f.read()

target = """	_add_node("dyson_swarm", "Dyson Swarm Blueprint", "Begin constructing orbital solar collectors around the sun.", 5000.0, Vector2(960, 320), ["unlock_fusion_reactor"], 5, "Massive global energy boost", 1)"""

new_nodes = """	_add_node("dyson_swarm", "Dyson Swarm Blueprint", "Begin constructing orbital solar collectors around the sun.", 5000.0, Vector2(960, 320), ["unlock_fusion_reactor"], 5, "Massive global energy boost", 1)

	# --- NEW ENERGY PROGRESSION ---
	_add_node("unlock_thermic_burner", "Thermic Burner", "Burns refined ingots for substantial energy.", 400.0, Vector2(240, 0), ["unlock_thermal_plant"], 3, "Unlocks Thermic Burner", 1)
	_add_node("thermic_mastery", "Thermic Mastery", "Optimizes ingot combustion.", 300.0, Vector2(480, 0), ["unlock_thermic_burner"], 3, "+5% Generator Output", 10, NodeShape.DIAMOND)
	
	_add_node("unlock_plasma_reactor", "Plasma Reactor", "Burns alloys using sustained magnetic plasma.", 1200.0, Vector2(240, -160), ["unlock_thermic_burner"], 4, "Unlocks Plasma Reactor", 1)
	_add_node("plasma_mastery", "Plasma Mastery", "Stabilizes plasma flow.", 800.0, Vector2(480, -160), ["unlock_plasma_reactor"], 4, "+5% Generator Output", 10, NodeShape.DIAMOND)
	
	_add_node("unlock_antimatter_chamber", "Antimatter Chamber", "Consumes complex components for staggering energy.", 4000.0, Vector2(240, -320), ["unlock_plasma_reactor"], 5, "Unlocks Antimatter Chamber", 1)
	_add_node("antimatter_mastery", "Antimatter Mastery", "Perfects containment fields.", 2500.0, Vector2(480, -320), ["unlock_antimatter_chamber"], 5, "+5% Generator Output", 10, NodeShape.DIAMOND)
	
	_add_node("unlock_singularity_core", "Singularity Core", "Harnesses a micro-black hole for godlike energy.", 10000.0, Vector2(240, -480), ["unlock_antimatter_chamber"], 6, "Unlocks Singularity Core", 1)
	_add_node("singularity_mastery", "Singularity Mastery", "Extracts hawking radiation.", 8000.0, Vector2(480, -480), ["unlock_singularity_core"], 6, "+5% Generator Output", 10, NodeShape.DIAMOND)

	_add_node("unlock_circuit_overloader", "Circuit Overloader", "A support building that boosts Solar Arrays in its district.", 600.0, Vector2(0, 480), ["solar_efficiency"], 3, "Unlocks Circuit Overloader", 1)
	_add_node("unlock_magma_resonator", "Magma Resonator", "A support building that boosts Geothermal Plants in its district.", 1200.0, Vector2(720, -160), ["unlock_geothermal_plant"], 4, "Unlocks Magma Resonator", 1)
	_add_node("unlock_grid_optimizer", "Grid Optimizer", "A support building that boosts all clean energy in its district.", 2000.0, Vector2(960, 480), ["unlock_fusion_reactor"], 5, "Unlocks Grid Optimizer", 1)
	_add_node("unlock_combustion_stabilizer", "Combustion Stabilizer", "A support building that extends burner fuel duration in its district.", 1500.0, Vector2(720, 0), ["unlock_thermic_burner"], 4, "Unlocks Combustion Stabilizer", 1)
"""
content = content.replace(target, new_nodes)

# Update get_generator_output_mult to include the new masteries
target_mult = """func get_generator_output_mult() -> float:
	var base := 1.0
	if "generator_efficiency" in unlocked_skills:
		base += 0.30
	if "supercharged_generators" in unlocked_skills:
		var lv := get_skill_level("supercharged_generators")
		base += 0.10 * lv
	return base"""
replace_mult = """func get_generator_output_mult() -> float:
	var base := 1.0
	if "generator_efficiency" in unlocked_skills:
		base += 0.30
	if "supercharged_generators" in unlocked_skills:
		var lv := get_skill_level("supercharged_generators")
		base += 0.10 * lv
	if "thermic_mastery" in unlocked_skills:
		base += 0.05 * get_skill_level("thermic_mastery")
	if "plasma_mastery" in unlocked_skills:
		base += 0.05 * get_skill_level("plasma_mastery")
	if "antimatter_mastery" in unlocked_skills:
		base += 0.05 * get_skill_level("antimatter_mastery")
	if "singularity_mastery" in unlocked_skills:
		base += 0.05 * get_skill_level("singularity_mastery")
	return base"""
content = content.replace(target_mult, replace_mult)

with open("scripts/game/SkillTree.gd", "w") as f:
    f.write(content)

print("SkillTree patched.")
