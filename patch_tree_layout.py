import re

with open("scripts/game/SkillTree.gd", "r") as f:
    content = f.read()

trade_target = """	# --- BRANCH 5: TRADE/LOGISTICS (Mid-Right-Down) ---
	_add_node("unlock_trade_hub", "Interplanetary Trade Hub", "Massive logistics center that prints credits.", 1500.0, Vector2(120, 240), ["root"], 2, "Unlocks Trade Hub", 1)
	_add_node("global_logistics", "Global Logistics", "Optimizes supply chains for all colonized worlds.", 2000.0, Vector2(240, 240), ["unlock_trade_hub"], 3, "+5% global production speed", 10, NodeShape.DIAMOND)
	_add_node("unlock_commercial_hub", "Mega Commercial Hub", "Massive commercial hubs processing refined minerals.", 2000.0, Vector2(240, 480), ["unlock_trade_hub"], 3, "Unlocks Commercial Hub", 1)
	_add_node("planetary_architecture", "Planetary Architecture", "Increases maximum districts available on all planets.", 2500.0, Vector2(360, 480), ["unlock_commercial_hub"], 4, "+1 Max District", 3, NodeShape.DIAMOND)
	_add_node("unlock_logistics_center", "Planetary Logistics", "Blueprints for planet-wide logistics centers.", 5000.0, Vector2(120, 720), ["unlock_commercial_hub"], 4, "Unlocks Logistics Center", 1)
	_add_node("unlock_command_center", "Planetary Command", "Blueprints for planet-wide command centers.", 5000.0, Vector2(360, 720), ["unlock_commercial_hub"], 4, "Unlocks Command Center", 1)"""

trade_replace = """	# --- BRANCH 5: TRADE/LOGISTICS (Mid-Right-Down) ---
	_add_node("unlock_trade_hub", "Interplanetary Trade Hub", "Massive logistics center that prints credits.", 1500.0, Vector2(240, 240), ["root"], 2, "Unlocks Trade Hub", 1)
	_add_node("global_logistics", "Global Logistics", "Optimizes supply chains for all colonized worlds.", 2000.0, Vector2(240, 360), ["unlock_trade_hub"], 3, "+5% global production speed", 10, NodeShape.DIAMOND)
	_add_node("unlock_commercial_hub", "Mega Commercial Hub", "Massive commercial hubs processing refined minerals.", 2000.0, Vector2(240, 480), ["unlock_trade_hub"], 3, "Unlocks Commercial Hub", 1)
	_add_node("planetary_architecture", "Planetary Architecture", "Increases maximum districts available on all planets.", 2500.0, Vector2(360, 480), ["unlock_commercial_hub"], 4, "+1 Max District", 3, NodeShape.DIAMOND)
	_add_node("unlock_logistics_center", "Planetary Logistics", "Blueprints for planet-wide logistics centers.", 5000.0, Vector2(240, 600), ["unlock_commercial_hub"], 4, "Unlocks Logistics Center", 1)
	_add_node("unlock_command_center", "Planetary Command", "Blueprints for planet-wide command centers.", 5000.0, Vector2(360, 600), ["unlock_commercial_hub"], 4, "Unlocks Command Center", 1)"""

content = content.replace(trade_target, trade_replace)

energy_target = """	# --- BRANCH 6: ENERGY (Right-Down) ---
	_add_node("unlock_thermal_plant", "Thermal Plant", "Unlocks the standard mineral-burning Thermal Generator.", 100.0, Vector2(240, 160), ["root"], 2, "Unlocks Thermal Generator", 1)
	_add_node("solar_efficiency", "Solar Arrays", "Improves basic solar cell design to absorb more stellar energy.", 50.0, Vector2(240, 320), ["unlock_thermal_plant"], 2, "+25% Solar Array output", 5, NodeShape.DIAMOND)
	_add_node("generator_efficiency", "Heat Capture Loops", "Adds heat capture loops to standard Generators.", 250.0, Vector2(480, 160), ["unlock_thermal_plant"], 3, "+30% Generator Energy output", 5, NodeShape.DIAMOND)
	_add_node("power_transmission", "Superconducting Grid", "Reduces losses inside energy lines.", 400.0, Vector2(480, 320), ["unlock_thermal_plant"], 3, "-15% Energy consumption on all buildings", 1, NodeShape.DIAMOND)
	_add_node("supercharged_generators", "Plasma Ignition", "Drastically increases output of all generators.", 800.0, Vector2(720, 160), ["generator_efficiency"], 4, "+10% Generator Energy output", 10, NodeShape.DIAMOND)
	_add_node("energy_efficiency", "Zero-Point Regulators", "Reduces overall energy consumption via quantum stabilization.", 800.0, Vector2(480, 480), ["power_transmission"], 4, "-5% global energy consumption", 5, NodeShape.DIAMOND)
	_add_node("unlock_fusion_reactor", "Fusion Reactor", "Unlocks massive industrial Fusion Reactors.", 1000.0, Vector2(720, 320), ["power_transmission", "generator_efficiency"], 4, "Unlocks Fusion Reactor", 1)
	_add_node("dyson_swarm", "Dyson Swarm Blueprint", "Begin constructing orbital solar collectors around the sun.", 5000.0, Vector2(960, 320), ["unlock_fusion_reactor"], 5, "Massive global energy boost", 1)

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
	_add_node("unlock_combustion_stabilizer", "Combustion Stabilizer", "A support building that extends burner fuel duration in its district.", 1500.0, Vector2(720, 0), ["unlock_thermic_burner"], 4, "Unlocks Combustion Stabilizer", 1)"""

energy_replace = """	# --- BRANCH 6: ENERGY (Right-Down) ---
	_add_node("unlock_thermal_plant", "Thermal Plant", "Unlocks the standard mineral-burning Thermal Generator.", 100.0, Vector2(480, 160), ["root"], 2, "Unlocks Thermal Generator (+5 E)", 1)
	_add_node("solar_efficiency", "Solar Arrays", "Improves basic solar cell design to absorb more stellar energy.", 50.0, Vector2(480, 280), ["unlock_thermal_plant"], 2, "+25% Solar Array output", 5, NodeShape.DIAMOND)
	_add_node("generator_efficiency", "Heat Capture Loops", "Adds heat capture loops to standard Generators.", 250.0, Vector2(600, 160), ["unlock_thermal_plant"], 3, "+30% Generator Energy output", 5, NodeShape.DIAMOND)
	_add_node("power_transmission", "Superconducting Grid", "Reduces losses inside energy lines.", 400.0, Vector2(600, 280), ["unlock_thermal_plant"], 3, "-15% Energy consumption on all buildings", 1, NodeShape.DIAMOND)
	_add_node("supercharged_generators", "Plasma Ignition", "Drastically increases output of all generators.", 800.0, Vector2(720, 160), ["generator_efficiency"], 4, "+10% Generator Energy output", 10, NodeShape.DIAMOND)
	_add_node("energy_efficiency", "Zero-Point Regulators", "Reduces overall energy consumption via quantum stabilization.", 800.0, Vector2(720, 280), ["power_transmission"], 4, "-5% global energy consumption", 5, NodeShape.DIAMOND)
	_add_node("unlock_fusion_reactor", "Fusion Reactor", "Unlocks massive industrial Fusion Reactors.", 1000.0, Vector2(840, 220), ["power_transmission", "generator_efficiency"], 4, "Unlocks Fusion Reactor (+100 E)", 1)
	_add_node("dyson_swarm", "Dyson Swarm Blueprint", "Begin constructing orbital solar collectors around the sun.", 5000.0, Vector2(960, 220), ["unlock_fusion_reactor"], 5, "Massive global energy boost", 1)

	# --- NEW ENERGY PROGRESSION ---
	_add_node("unlock_thermic_burner", "Thermic Burner", "Burns refined ingots for substantial energy.", 400.0, Vector2(480, 40), ["unlock_thermal_plant"], 3, "Unlocks Thermic Burner (+15 E)", 1)
	_add_node("thermic_mastery", "Thermic Mastery", "Optimizes ingot combustion.", 300.0, Vector2(600, 40), ["unlock_thermic_burner"], 3, "+5% Generator Output", 10, NodeShape.DIAMOND)
	
	_add_node("unlock_plasma_reactor", "Plasma Reactor", "Burns alloys using sustained magnetic plasma.", 1200.0, Vector2(480, -80), ["unlock_thermic_burner"], 4, "Unlocks Plasma Reactor (+45 E)", 1)
	_add_node("plasma_mastery", "Plasma Mastery", "Stabilizes plasma flow.", 800.0, Vector2(600, -80), ["unlock_plasma_reactor"], 4, "+5% Generator Output", 10, NodeShape.DIAMOND)
	
	_add_node("unlock_antimatter_chamber", "Antimatter Chamber", "Consumes complex components for staggering energy.", 4000.0, Vector2(480, -200), ["unlock_plasma_reactor"], 5, "Unlocks Antimatter Chamber (+120 E)", 1)
	_add_node("antimatter_mastery", "Antimatter Mastery", "Perfects containment fields.", 2500.0, Vector2(600, -200), ["unlock_antimatter_chamber"], 5, "+5% Generator Output", 10, NodeShape.DIAMOND)
	
	_add_node("unlock_singularity_core", "Singularity Core", "Harnesses a micro-black hole for godlike energy.", 10000.0, Vector2(480, -320), ["unlock_antimatter_chamber"], 6, "Unlocks Singularity Core (+350 E)", 1)
	_add_node("singularity_mastery", "Singularity Mastery", "Extracts hawking radiation.", 8000.0, Vector2(600, -320), ["unlock_singularity_core"], 6, "+5% Generator Output", 10, NodeShape.DIAMOND)

	_add_node("unlock_circuit_overloader", "Circuit Overloader", "A support building that boosts Solar Arrays in its district.", 600.0, Vector2(480, 400), ["solar_efficiency"], 3, "Unlocks Circuit Overloader (+3% Solar)", 1)
	_add_node("unlock_magma_resonator", "Magma Resonator", "A support building that boosts Geothermal Plants in its district.", 1200.0, Vector2(720, 40), ["supercharged_generators"], 4, "Unlocks Magma Resonator (+2% Geo)", 1)
	_add_node("unlock_grid_optimizer", "Grid Optimizer", "A support building that boosts all clean energy in its district.", 2000.0, Vector2(840, 400), ["unlock_fusion_reactor"], 5, "Unlocks Grid Optimizer (+1% Clean)", 1)
	_add_node("unlock_combustion_stabilizer", "Combustion Stabilizer", "A support building that extends burner fuel duration in its district.", 1500.0, Vector2(720, -80), ["plasma_mastery"], 4, "Unlocks Combustion Stabilizer (+5% Duration)", 1)"""

content = content.replace(energy_target, energy_replace)

with open("scripts/game/SkillTree.gd", "w") as f:
    f.write(content)

print("SkillTree coordinates and descriptions updated")
