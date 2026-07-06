## SkillTree — Autoload singleton or script helper for management of incremental upgrades.
## Tracks unlocked skill IDs, levels, calculates modifiers, and defines node graph info.
extends Node

signal skill_unlocked(id: String)

# Global set of purchased/unlocked skill IDs
var unlocked_skills: Array[String] = ["root", "unlock_solar_panel", "unlock_residential", "unlock_lab"]

# Dictionary for upgrade levels (for multi-level upgrades)
# format: { skill_id: current_level_int }
var skill_levels: Dictionary = {
	"unlock_solar_panel": 1,

	"unlock_residential": 1,
	"unlock_lab": 1
}

enum NodeShape { HEXAGON, DIAMOND, CIRCLE }

# Definitions of all nodes in the skill tree graph
class SkillNode:
	var id: String
	var name: String
	var description: String
	var cost: float
	var pos: Vector2
	var parents: Array[String]
	var tier: int
	var effect_desc: String
	var max_level: int # 1 = single purchase, >1 = leveled upgrade
	var shape: NodeShape

	func _init(p_id: String, p_name: String, p_desc: String, p_cost: float, p_pos: Vector2, p_parents: Array[String], p_tier: int, p_eff: String, p_max_lv: int = 1, p_shape: NodeShape = NodeShape.HEXAGON) -> void:
		id = p_id
		name = p_name
		description = p_desc
		cost = p_cost
		pos = p_pos
		parents = p_parents
		tier = p_tier
		effect_desc = p_eff
		max_level = p_max_lv
		shape = p_shape

# The upgrade graph structure
var nodes: Dictionary = {}

func _init() -> void:
	# --- Core ---
	_add_node("root", "Central Core", "The heart of your colony. Grants basic Low-Density Housing, Solar Panels, and a University.", 0.0, Vector2(0, 0), [], 1, "Unlocks basic structures", 1, NodeShape.CIRCLE)

	# --- BRANCH 1: EXPLORATION (UP) ---
	_add_node("unlock_space_station", "Orbital Facilities", "Launches basic structural components into Low Orbit.", 300.0, Vector2(0, -160), ["root"], 2, "Unlocks Space Station District", 10)
	_add_node("unlock_orbital_shipyard", "Orbital Shipyard", "Constructs huge orbital vessels to boost local logistics.", 1000.0, Vector2(160, -160), ["unlock_space_station"], 3, "Unlocks Orbital Shipyard", 10)
	
	_add_node("unlock_moon", "Moon Outpost", "Provides orbital mechanics calculations required to establish lunar outposts.", 500.0, Vector2(0, -320), ["unlock_space_station"], 3, "Unlocks Moon Outpost", 1)
	_add_node("unlock_lunar_observatory", "Lunar Observatory", "Zero-atmosphere deep space observation for massive Science generation.", 1500.0, Vector2(-160, -320), ["unlock_moon"], 4, "Unlocks Lunar Observatory", 1)
	
	_add_node("unlock_asteroids", "Deep Space Tracking", "Allows tracking and mining of resource-rich Asteroids.", 1200.0, Vector2(0, -480), ["unlock_moon"], 4, "Unlocks Asteroid Mining", 1)
	_add_node("unlock_asteroid_harvester", "Asteroid Harvester", "Colossal mining rig tailored for zero-G asteroid cracking.", 3000.0, Vector2(160, -480), ["unlock_asteroids"], 5, "Unlocks Asteroid Harvester", 1)
	
	_add_node("colonize_ice", "Cryo-Habitation", "Thermal insulation tech for Ice Worlds.", 2500.0, Vector2(-360, -640), ["unlock_asteroids"], 5, "Unlocks Ice Planet Colonization", 1)
	_add_node("unlock_cryo_vault", "Cryo-Vault Architecture", "Blueprints for massive underground cryo-vaults.", 4000.0, Vector2(-480, -800), ["colonize_ice"], 6, "Unlocks Cryo-Vault", 10)

	_add_node("colonize_desert", "Arid Habitation", "Water reclamation for Desert Worlds.", 2500.0, Vector2(-120, -640), ["unlock_asteroids"], 5, "Unlocks Desert Planet Colonization", 1)
	_add_node("unlock_solar_matrix", "Solar Matrix", "Blueprints for colossal solar arrays.", 4000.0, Vector2(-160, -800), ["colonize_desert"], 6, "Unlocks Solar Matrix", 10)

	_add_node("colonize_gas", "Atmospheric Harvesters", "Floating platforms for Gas Giants.", 2500.0, Vector2(120, -640), ["unlock_asteroids"], 5, "Unlocks Gas Planet Colonization", 1)
	_add_node("unlock_atmospheric_siphon", "Atmospheric Siphon", "Blueprints for massive gas siphons.", 4000.0, Vector2(160, -800), ["colonize_gas"], 6, "Unlocks Atmospheric Siphon", 10)

	_add_node("colonize_volcanic", "Thermal Shielding", "Extreme heat resistance for Volcanic Worlds.", 2500.0, Vector2(360, -640), ["unlock_asteroids"], 5, "Unlocks Volcanic Planet Colonization", 1)
	_add_node("unlock_geothermal_plant", "Geothermal Plant", "Blueprints for extreme geothermal energy extraction.", 4000.0, Vector2(480, -800), ["colonize_volcanic"], 6, "Unlocks Geothermal Plant", 10)
	
	_add_node("unlock_interstellar", "Interstellar Travel", "Bend spacetime to discover entirely new Star Systems.", 10000.0, Vector2(0, -960), ["colonize_ice", "colonize_desert", "colonize_gas", "colonize_volcanic"], 7, "Discovers 1 New Star System per level", 999, NodeShape.CIRCLE)

	# --- BRANCH 2: SCIENCE (Mid-Left-Down) ---
	_add_node("unlock_advanced_lab", "Advanced Research", "Upgrades the basic University into a dedicated high-yield Research Lab.", 150.0, Vector2(-120, 240), ["unlock_lab"], 2, "Unlocks Advanced Lab", 10)
	_add_node("unlock_research_academy", "Research Academy", "Large-scale science academy to generate passive Science.", 800.0, Vector2(-240, 480), ["unlock_advanced_lab"], 3, "Unlocks Research Academy", 10)

	# --- BRANCH 3: MINING (Left-Down) ---
	_add_node("unlock_mining", "Mining Operations", "Establishes the geological survey programs needed to locate and extract raw minerals from planetary crust.\nUpgrade to increase Mine max level.", 20.0, Vector2(-240, 0), ["root"], 1, "Unlocks Mining District & Mine & +1 Max Level", 10, NodeShape.HEXAGON)
	_add_node("unlock_deep_drill", "Deep Drill", "Unlocks high-yield Deep Drills to penetrate bedrock.", 200.0, Vector2(-240, 160), ["unlock_mining"], 2, "Unlocks Deep Drill", 10)
	_add_node("mine_speed", "Excavation Drills", "Equips mining facilities with high-torque diamond drills.", 50.0, Vector2(-240, 320), ["unlock_deep_drill"], 2, "+5% Mining production speed per level", 10, NodeShape.DIAMOND)
	_add_node("unlock_refinery", "Refinery", "Unlocks ore-to-mineral Refineries.", 400.0, Vector2(-480, 320), ["unlock_deep_drill"], 3, "Unlocks Refinery", 10)
	_add_node("deep_mining", "Seismic Sensors", "Deep scans tectonic plates to output higher yields.", 350.0, Vector2(-480, 160), ["unlock_refinery"], 3, "+25% Mine & Deep Drill output amount", 5, NodeShape.DIAMOND)
	_add_node("core_extractor", "Core Extractor", "Extracts hyper-dense minerals directly from the planet's mantle.", 1200.0, Vector2(-720, 480), ["unlock_refinery"], 4, "Unlocks Core Extractor", 1)
	_add_node("mineral_compression", "Matter Compression", "Condenses raw minerals, vastly increasing storage efficiency.", 900.0, Vector2(-480, 480), ["core_extractor"], 4, "+100% Mineral Storage", 5, NodeShape.DIAMOND)
	_add_node("deep_core_drilling", "Planetary Fracture", "Taps into the core to maximize global mineral yield.", 1500.0, Vector2(-720, 640), ["core_extractor"], 5, "+10% Mine output multiplier", 10, NodeShape.DIAMOND)
	_add_node("omega_drill", "Omega Drill", "The ultimate planetary mining solution. Consumes huge energy.", 3000.0, Vector2(-960, 640), ["core_extractor"], 5, "Unlocks Omega Drill", 1)

	# --- BRANCH 4: URBANIZATION (Down) ---
	_add_node("unlock_commercial", "Commercial Hubs", "Transitions from simple trade to high-density commercial centers.", 150.0, Vector2(0, 320), ["unlock_residential"], 2, "Unlocks Commercial Center", 10)
	_add_node("unlock_luxury_complex", "Luxury Complex", "Unlocks premium housing for elites.", 600.0, Vector2(0, 640), ["unlock_commercial"], 3, "Unlocks Luxury Complex", 10)
	_add_node("credit_boost", "Market Integration", "Integrates residential areas with local credit exchanges.", 400.0, Vector2(-160, 480), ["unlock_commercial"], 2, "+25% Residential credit payout", 5, NodeShape.DIAMOND)

	# --- BRANCH 5: TRADE/LOGISTICS (Mid-Right-Down) ---
	_add_node("unlock_trade_hub", "Interplanetary Trade Hub", "Massive logistics center that prints credits.", 1500.0, Vector2(240, 240), ["root"], 2, "Unlocks Trade Hub", 1)
	_add_node("global_logistics", "Global Logistics", "Optimizes supply chains for all colonized worlds.", 2000.0, Vector2(240, 360), ["unlock_trade_hub"], 3, "+5% global production speed", 10, NodeShape.DIAMOND)
	_add_node("unlock_commercial_hub", "Mega Commercial Hub", "Massive commercial hubs processing refined minerals.", 2000.0, Vector2(240, 480), ["unlock_trade_hub"], 3, "Unlocks Commercial Hub", 10)
	_add_node("planetary_architecture", "Planetary Architecture", "Increases maximum districts available on all planets.", 2500.0, Vector2(360, 480), ["unlock_commercial_hub"], 4, "+1 Max District", 3, NodeShape.DIAMOND)
	_add_node("unlock_logistics_center", "Planetary Logistics", "Blueprints for planet-wide logistics centers.", 5000.0, Vector2(240, 600), ["unlock_commercial_hub"], 4, "Unlocks Logistics Center", 1)
	_add_node("unlock_command_center", "Planetary Command", "Blueprints for planet-wide command centers.", 5000.0, Vector2(360, 600), ["unlock_commercial_hub"], 4, "Unlocks Command Center", 1)

	# --- BRANCH 6: ENERGY (Right-Down) ---
	_add_node("unlock_thermal_plant", "Thermal Plant", "Unlocks the standard mineral-burning Thermal Generator.", 100.0, Vector2(480, 160), ["unlock_solar_panel"], 2, "Unlocks Thermal Generator.", 10)
	_add_node("solar_efficiency", "Solar Arrays", "Improves basic solar cell design to absorb more stellar energy.", 50.0, Vector2(480, 280), ["unlock_thermal_plant"], 2, "+10% Solar Array output", 5, NodeShape.DIAMOND)
	_add_node("generator_efficiency", "Heat Capture Loops", "Adds heat capture loops to standard Generators.", 250.0, Vector2(600, 160), ["unlock_thermal_plant"], 3, "+5% Generator Energy output", 5, NodeShape.DIAMOND)
	_add_node("power_transmission", "Superconducting Grid", "Reduces losses inside energy lines.", 400.0, Vector2(600, 280), ["unlock_thermal_plant"], 3, "-5% Energy consumption on all buildings", 1, NodeShape.DIAMOND)
	_add_node("supercharged_generators", "Plasma Ignition", "Drastically increases output of all generators.", 800.0, Vector2(720, 160), ["generator_efficiency"], 4, "+2% Generator Energy output", 10, NodeShape.DIAMOND)
	_add_node("energy_efficiency", "Zero-Point Regulators", "Reduces overall energy consumption via quantum stabilization.", 800.0, Vector2(720, 280), ["power_transmission"], 4, "-2% global energy consumption", 5, NodeShape.DIAMOND)
	_add_node("unlock_fusion_reactor", "Fusion Reactor", "Unlocks massive industrial Fusion Reactors.", 1000.0, Vector2(840, 220), ["power_transmission", "generator_efficiency"], 4, "Unlocks Fusion Reactor.", 10)
	
	_add_node("find_available_star", "Find Available Star", "Locate a stable G-type main-sequence star for megastructure construction.", 9999999.0, Vector2(1080, 220), ["dyson_swarm_dummy"], 6, "Required for Dyson Swarm.", 1)
	_add_node("dyson_swarm", "Dyson Swarm Blueprint", "Begin constructing orbital solar collectors around the sun.\n[color=#ffbb55]Megastructure Project[/color]", 50000.0, Vector2(960, 220), ["unlock_fusion_reactor", "find_available_star"], 5, "+100% Solar Array output", 1, NodeShape.CIRCLE)

	# --- NEW ENERGY PROGRESSION ---
	_add_node("unlock_thermic_burner", "Thermic Burner", "Burns refined ingots for substantial energy.", 400.0, Vector2(480, 40), ["unlock_thermal_plant"], 3, "Unlocks Thermic Burner.", 10)
	_add_node("thermic_mastery", "Thermic Mastery", "Optimizes ingot combustion.", 300.0, Vector2(600, 40), ["unlock_thermic_burner"], 3, "+2% Generator Output", 10, NodeShape.DIAMOND)
	
	_add_node("unlock_plasma_reactor", "Plasma Reactor", "Burns alloys using sustained magnetic plasma.", 1200.0, Vector2(480, -80), ["unlock_thermic_burner"], 4, "Unlocks Plasma Reactor.", 10)
	_add_node("plasma_mastery", "Plasma Mastery", "Stabilizes plasma flow.", 800.0, Vector2(600, -80), ["unlock_plasma_reactor"], 4, "+2% Generator Output", 10, NodeShape.DIAMOND)
	
	_add_node("unlock_antimatter_chamber", "Antimatter Chamber", "Consumes complex components for staggering energy.", 4000.0, Vector2(480, -200), ["unlock_plasma_reactor"], 5, "Unlocks Antimatter Chamber.", 10)
	_add_node("antimatter_mastery", "Antimatter Mastery", "Perfects containment fields.", 2500.0, Vector2(600, -200), ["unlock_antimatter_chamber"], 5, "+2% Generator Output", 10, NodeShape.DIAMOND)
	
	_add_node("unlock_singularity_core", "Singularity Core", "Harnesses a micro-black hole for godlike energy.", 10000.0, Vector2(480, -320), ["unlock_antimatter_chamber"], 6, "Unlocks Singularity Core.", 10)
	_add_node("singularity_mastery", "Singularity Mastery", "Extracts hawking radiation.", 8000.0, Vector2(600, -320), ["unlock_singularity_core"], 6, "+2% Generator Output", 10, NodeShape.DIAMOND)

	_add_node("unlock_circuit_overloader", "Circuit Overloader", "A support building that boosts Solar Arrays in its district.", 600.0, Vector2(480, 400), ["solar_efficiency"], 3, "Unlocks Circuit Overloader.\nBoosts district Solar output by +3%.", 10)
	_add_node("unlock_magma_resonator", "Magma Resonator", "A support building that boosts Geothermal Plants in its district.", 1200.0, Vector2(720, 40), ["supercharged_generators"], 4, "Unlocks Magma Resonator.\nBoosts district Geothermal output by +2%.", 10)
	_add_node("unlock_grid_optimizer", "Grid Optimizer", "A support building that boosts all clean energy in its district.", 2000.0, Vector2(840, 400), ["unlock_fusion_reactor"], 5, "Unlocks Grid Optimizer.\nBoosts all district clean energy by +1%.", 10)
	_add_node("unlock_combustion_stabilizer", "Combustion Stabilizer", "A support building that extends burner fuel duration in its district.", 1500.0, Vector2(720, -80), ["plasma_mastery"], 4, "Unlocks Combustion Stabilizer.\nExtends district burner fuel duration by +5%.", 10)



# Get the maximum allowed level for a building (based on skill upgrades)
	# --- DEFAULT BUILDING UNLOCKS & UPGRADES ---
	_add_node("unlock_solar_panel", "Energy Operations", "Unlocks Energy Districts and Solar Panels.\nUpgrade to increase Solar Panel max level.", 50.0, Vector2(240, 0), ["root"], 1, "Unlocks Solar Panel & +1 Max Level", 10, NodeShape.HEXAGON)
	_add_node("unlock_residential", "Habitation Operations", "Unlocks Urban Districts and Residential blocks.\nUpgrade to increase Habitation max level.", 50.0, Vector2(0, 160), ["root"], 1, "Unlocks Residential & +1 Max Level", 10, NodeShape.HEXAGON)
	_add_node("unlock_lab", "Research Operations", "Unlocks University facilities.\nUpgrade to increase University max level.", 100.0, Vector2(-120, 120), ["root"], 1, "Unlocks University & +1 Max Level", 10, NodeShape.HEXAGON)
func get_building_max_level(building_id: String) -> int:
	# Default level is 1. Upgrades increase this.
	var max_lv = 1
	
	# If there's an upgrade node for default buildings
	if is_unlocked("upgrade_" + building_id):
		max_lv = get_skill_level("upgrade_" + building_id)
		
	# specific check for mine since Claude named it unlock_mining
	if building_id == "mine" and is_unlocked("unlock_mining"):
		max_lv = get_skill_level("unlock_mining")
		
	# If the building itself is unlocked via a node, its node dictates max level
	elif is_unlocked("unlock_" + building_id):
		max_lv = get_skill_level("unlock_" + building_id)
		
	return max_lv



func _add_node(id: String, name: String, desc: String, cost: float, pos: Vector2, parents: Array[String], tier: int, eff: String, max_lv: int = 1, shape: NodeShape = NodeShape.HEXAGON) -> void:
	nodes[id] = SkillNode.new(id, name, desc, cost, pos, parents, tier, eff, max_lv, shape)

# Get current level of a node (returns 0 if locked/not started)
func is_unlocked(id: String) -> bool:
	if id == "root": return true
	return id in unlocked_skills

func get_skill_level(id: String) -> int:
	if id == "root":
		return 1
	if id not in unlocked_skills:
		return 0
	return skill_levels.get(id, 1)

# Get cost of next level
func get_next_cost(id: String) -> float:
	var node: SkillNode = nodes.get(id, null)
	if node == null:
		return 0.0
	var cur_lv := get_skill_level(id)
	if cur_lv >= node.max_level:
		return 0.0
	# Linear cost scaling: Base cost * (1 + current_level)
	return node.cost * (1.0 + cur_lv)

# Check if a skill can be purchased / upgraded
func can_purchase(id: String) -> bool:
	var node: SkillNode = nodes.get(id, null)
	if node == null:
		return false
		
	var cur_lv := get_skill_level(id)
	if cur_lv >= node.max_level:
		return false

	# If first purchase, check parents
	if cur_lv == 0:
		var parent_ok := false
		for p in node.parents:
			if p in unlocked_skills:
				parent_ok = true
				break
		if not parent_ok and not node.parents.is_empty():
			return false

	var next_cost := get_next_cost(id)
	return GameState.science_points >= next_cost

# Buy or upgrade a skill node
func purchase_skill(id: String) -> bool:
	if not can_purchase(id):
		return false
	var next_cost := get_next_cost(id)
	if GameState.spend_science(next_cost):
		var cur_lv := get_skill_level(id)
		if cur_lv == 0:
			unlocked_skills.append(id)
			skill_levels[id] = 1
			
			if id == "unlock_space_station":
				GameState.solar_unlocked = true
				GameState.unlock_changed.emit("solar_unlocked", true)
			elif id == "unlock_moon":
				GameState.moon_unlocked = true
				GameState.unlock_changed.emit("moon_unlocked", true)
			elif id == "unlock_interstellar":
				GameState.galaxy_unlocked = true
				GameState.unlock_changed.emit("galaxy_unlocked", true)
			elif id.begins_with("unlock_"):
				GameState.unlock_building(id.trim_prefix("unlock_"))
		else:
			skill_levels[id] = cur_lv + 1
			
		skill_unlocked.emit(id)
		GameState.save()
		return true
	return false

# Check if a node is visible (at least one parent is unlocked, or itself unlocked)
func is_visible(id: String) -> bool:
	if has_meta("debug_reveal_all") and get_meta("debug_reveal_all"):
		return true
	if id == "root" or id in unlocked_skills:
		return true
	var node: SkillNode = nodes.get(id, null)
	if node == null:
		return false
	for p in node.parents:
		if p in unlocked_skills:
			return true
	return false

# ── Dynamic Modifiers read by GameState/ProductionManager ─────────────────────

func get_solar_mult() -> float:
	var base := 1.0
	if "solar_efficiency" in unlocked_skills:
		base += 0.25
	if "dyson_swarm" in unlocked_skills:
		base += 1.00
	return base

func get_mine_speed_mult() -> float:
	var base := 1.0
	if "mine_speed" in unlocked_skills:
		var lv := get_skill_level("mine_speed")
		base += 0.05 * lv
	if "omega_core" in unlocked_skills:
		base += 0.20
	return base

func get_generator_output_mult() -> float:
	var base := 1.0
	if "generator_efficiency" in unlocked_skills:
		base += 0.05
	if "supercharged_generators" in unlocked_skills:
		var lv := get_skill_level("supercharged_generators")
		base += 0.02 * lv
	if "thermic_mastery" in unlocked_skills:
		base += 0.02 * get_skill_level("thermic_mastery")
	if "plasma_mastery" in unlocked_skills:
		base += 0.02 * get_skill_level("plasma_mastery")
	if "antimatter_mastery" in unlocked_skills:
		base += 0.02 * get_skill_level("antimatter_mastery")
	if "singularity_mastery" in unlocked_skills:
		base += 0.02 * get_skill_level("singularity_mastery")
	return base

func get_credits_mult() -> float:
	return 1.25 if "credit_boost" in unlocked_skills else 1.0

func get_mine_output_mult() -> float:
	var base := 1.0
	if "deep_mining" in unlocked_skills:
		base += 0.25
	if "deep_core_drilling" in unlocked_skills:
		var lv := get_skill_level("deep_core_drilling")
		base += 0.02 * lv
	return base

func get_energy_consume_mult() -> float:
	var mult := 1.0
	if "power_transmission" in unlocked_skills:
		mult -= 0.15
	if "energy_efficiency" in unlocked_skills:
		var lv := get_skill_level("energy_efficiency")
		mult -= 0.02 * lv
	return maxf(0.1, mult)

func get_global_speed_mult() -> float:
	var base := 1.0
	if "omega_core" in unlocked_skills:
		base += 0.20
	if "global_logistics" in unlocked_skills:
		var lv := get_skill_level("global_logistics")
		base += 0.05 * lv
	return base
	
func get_max_districts_add() -> int:
	if "planetary_architecture" in unlocked_skills:
		return get_skill_level("planetary_architecture")
	return 0
