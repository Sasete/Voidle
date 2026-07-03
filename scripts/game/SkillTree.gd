## SkillTree — Autoload singleton or script helper for management of incremental upgrades.
## Tracks unlocked skill IDs, levels, calculates modifiers, and defines node graph info.
extends Node

signal skill_unlocked(id: String)

# Global set of purchased/unlocked skill IDs
var unlocked_skills: Array[String] = ["root"]

# Dictionary for upgrade levels (for multi-level upgrades)
# format: { skill_id: current_level_int }
var skill_levels: Dictionary = {}

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

	func _init(p_id: String, p_name: String, p_desc: String, p_cost: float, p_pos: Vector2, p_parents: Array[String], p_tier: int, p_eff: String, p_max_lv: int = 1) -> void:
		id = p_id
		name = p_name
		description = p_desc
		cost = p_cost
		pos = p_pos
		parents = p_parents
		tier = p_tier
		effect_desc = p_eff
		max_level = p_max_lv

# The upgrade graph structure
var nodes: Dictionary = {}

func _init() -> void:
	# --- Core ---
	_add_node("root", "Central Core", "The heart of your colony. Grants basic Low-Density Housing, Solar Panels, and a University.", 0.0, Vector2(0, 0), [], 1, "Unlocks basic structures", 1)

	# --- STARBURST TIER 1 (6 directions from root) ---
	_add_node("unlock_advanced_lab", "Advanced Research", "Upgrades the basic University into a dedicated high-yield Research Lab.", 150.0, Vector2(0, -160), ["root"], 1, "Unlocks Advanced Lab", 1)
	_add_node("unlock_commercial", "Commercial Hubs", "Transitions from simple trade to high-density commercial centers.", 150.0, Vector2(0, 160), ["root"], 1, "Unlocks Commercial Center", 1)
	
	_add_node("unlock_thermal_plant", "Thermal Plant", "Unlocks the standard mineral-burning Thermal Generator.", 100.0, Vector2(160, -100), ["root"], 1, "Unlocks Thermal Generator", 1)
	_add_node("solar_efficiency", "Solar Arrays", "Improves basic solar cell design to absorb more stellar energy.", 50.0, Vector2(160, 100), ["root"], 1, "+25% Solar Array output", 5)
	
	_add_node("unlock_deep_drill", "Deep Drill", "Unlocks high-yield Deep Drills to penetrate bedrock.", 200.0, Vector2(-160, -100), ["root"], 1, "Unlocks Deep Drill", 1)
	_add_node("mine_speed", "Excavation Drills", "Equips mining facilities with high-torque diamond drills.", 50.0, Vector2(-160, 100), ["root"], 1, "+5% Mining production speed per level", 10)

	# --- ENERGY WING (Right) ---
	_add_node("generator_efficiency", "Heat Capture Loops", "Adds heat capture loops to standard Generators.", 250.0, Vector2(320, -100), ["unlock_thermal_plant"], 2, "+30% Generator Energy output", 5)
	_add_node("supercharged_generators", "Plasma Ignition", "Drastically increases output of all generators.", 800.0, Vector2(480, -160), ["generator_efficiency"], 3, "+10% Generator Energy output", 10)
	
	_add_node("power_transmission", "Superconducting Grid", "Reduces losses inside energy lines.", 400.0, Vector2(320, 100), ["solar_efficiency"], 2, "-15% Energy consumption on all buildings", 1)
	_add_node("energy_efficiency", "Zero-Point Regulators", "Reduces overall energy consumption via quantum stabilization.", 800.0, Vector2(480, 160), ["power_transmission"], 3, "-5% global energy consumption", 5)
	
	_add_node("unlock_fusion_reactor", "Fusion Reactor", "Unlocks massive industrial Fusion Reactors.", 1000.0, Vector2(480, 0), ["generator_efficiency", "power_transmission"], 3, "Unlocks Fusion Reactor", 1)
	_add_node("dyson_swarm", "Dyson Swarm Blueprint", "Begin constructing orbital solar collectors around the sun.", 5000.0, Vector2(640, 0), ["unlock_fusion_reactor"], 4, "Massive global energy boost", 1)

	# --- MASSIVE MINING WING (Left) ---
	_add_node("unlock_refinery", "Refinery", "Unlocks ore-to-mineral Refineries.", 400.0, Vector2(-320, -100), ["unlock_deep_drill"], 2, "Unlocks Refinery", 1)
	_add_node("deep_mining", "Seismic Sensors", "Deep scans tectonic plates to output higher yields.", 350.0, Vector2(-320, 100), ["mine_speed"], 2, "+25% Mine & Deep Drill output amount", 5)
	
	_add_node("core_extractor", "Core Extractor", "Extracts hyper-dense minerals directly from the planet's mantle.", 1200.0, Vector2(-480, -100), ["unlock_refinery"], 3, "Unlocks Core Extractor", 1)
	_add_node("deep_core_drilling", "Planetary Fracture", "Taps into the core to maximize global mineral yield.", 1500.0, Vector2(-640, -160), ["core_extractor"], 4, "+10% Mine output multiplier", 10)
	
	_add_node("mineral_compression", "Matter Compression", "Condenses raw minerals, vastly increasing storage efficiency.", 900.0, Vector2(-480, 100), ["deep_mining"], 3, "+100% Mineral Storage", 5)
	
	_add_node("omega_drill", "Omega Drill", "The ultimate planetary mining solution. Consumes huge energy.", 3000.0, Vector2(-640, 0), ["core_extractor", "mineral_compression"], 4, "Unlocks Omega Drill", 1)

	# --- SCIENCE & SPACE WING (Top) ---
	_add_node("unlock_space_station", "Orbital Facilities", "Launches basic structural components into Low Orbit.", 300.0, Vector2(0, -320), ["unlock_advanced_lab"], 2, "Unlocks Space Station District", 1)
	_add_node("unlock_orbital_shipyard", "Orbital Shipyard", "Constructs huge orbital vessels to boost local logistics.", 1000.0, Vector2(160, -320), ["unlock_space_station"], 3, "Unlocks Orbital Shipyard", 1)
	
	_add_node("unlock_moon", "Moon Outpost", "Provides orbital mechanics calculations required to establish lunar outposts.", 500.0, Vector2(0, -480), ["unlock_space_station"], 3, "Unlocks Moon Outpost", 1)
	_add_node("unlock_lunar_observatory", "Lunar Observatory", "Zero-atmosphere deep space observation for massive Science generation.", 1500.0, Vector2(-160, -480), ["unlock_moon"], 4, "Unlocks Lunar Observatory", 1)
	
	_add_node("unlock_asteroids", "Deep Space Tracking", "Allows tracking and mining of resource-rich Asteroids.", 1200.0, Vector2(0, -640), ["unlock_moon"], 4, "Unlocks Asteroid Mining", 1)
	_add_node("unlock_asteroid_harvester", "Asteroid Harvester", "Colossal mining rig tailored for zero-G asteroid cracking.", 3000.0, Vector2(160, -640), ["unlock_asteroids"], 5, "Unlocks Asteroid Harvester", 1)
	
	# Space Colonization Branches (Wider pattern from asteroids)
	_add_node("colonize_ice", "Cryo-Habitation", "Thermal insulation tech for Ice Worlds.", 2500.0, Vector2(-360, -800), ["unlock_asteroids"], 5, "Unlocks Ice Planet Colonization", 1)
	_add_node("unlock_cryo_vault", "Cryo-Vault Architecture", "Blueprints for massive underground cryo-vaults.", 4000.0, Vector2(-480, -960), ["colonize_ice"], 6, "Unlocks Cryo-Vault", 1)

	_add_node("colonize_desert", "Arid Habitation", "Water reclamation for Desert Worlds.", 2500.0, Vector2(-120, -800), ["unlock_asteroids"], 5, "Unlocks Desert Planet Colonization", 1)
	_add_node("unlock_solar_matrix", "Solar Matrix", "Blueprints for colossal solar arrays.", 4000.0, Vector2(-160, -960), ["colonize_desert"], 6, "Unlocks Solar Matrix", 1)

	_add_node("colonize_gas", "Atmospheric Harvesters", "Floating platforms for Gas Giants.", 2500.0, Vector2(120, -800), ["unlock_asteroids"], 5, "Unlocks Gas Planet Colonization", 1)
	_add_node("unlock_atmospheric_siphon", "Atmospheric Siphon", "Blueprints for massive gas siphons.", 4000.0, Vector2(160, -960), ["colonize_gas"], 6, "Unlocks Atmospheric Siphon", 1)

	_add_node("colonize_volcanic", "Thermal Shielding", "Extreme heat resistance for Volcanic Worlds.", 2500.0, Vector2(360, -800), ["unlock_asteroids"], 5, "Unlocks Volcanic Planet Colonization", 1)
	_add_node("unlock_geothermal_plant", "Geothermal Plant", "Blueprints for extreme geothermal energy extraction.", 4000.0, Vector2(480, -960), ["colonize_volcanic"], 6, "Unlocks Geothermal Plant", 1)
	
	# The Endless Interstellar Node (Ties the 4 colonies together)
	_add_node("unlock_interstellar", "Interstellar Travel", "Bend spacetime to discover entirely new Star Systems.", 10000.0, Vector2(0, -1120), ["colonize_ice", "colonize_desert", "colonize_gas", "colonize_volcanic"], 7, "Discovers 1 New Star System per level", 999)

	# --- CIVIC & ECONOMY WING (Bottom) ---
	_add_node("unlock_luxury_complex", "Luxury Complex", "Unlocks premium housing for elites.", 600.0, Vector2(0, 320), ["unlock_commercial"], 2, "Unlocks Luxury Complex", 1)
	_add_node("credit_boost", "Market Integration", "Integrates residential areas with local credit exchanges.", 400.0, Vector2(-160, 320), ["unlock_commercial"], 2, "+25% Residential credit payout", 5)
	_add_node("unlock_research_academy", "Research Academy", "Large-scale science academy to generate passive Science.", 800.0, Vector2(160, 320), ["unlock_commercial"], 2, "Unlocks Research Academy", 1)
	
	_add_node("unlock_trade_hub", "Interplanetary Trade Hub", "Massive logistics center that prints credits.", 1500.0, Vector2(0, 480), ["unlock_luxury_complex", "credit_boost"], 3, "Unlocks Trade Hub", 1)
	
	_add_node("unlock_commercial_hub", "Mega Commercial Hub", "Massive commercial hubs processing refined minerals.", 2000.0, Vector2(0, 640), ["unlock_trade_hub"], 4, "Unlocks Commercial Hub", 1)
	_add_node("unlock_logistics_center", "Planetary Logistics", "Blueprints for planet-wide logistics centers.", 5000.0, Vector2(-160, 640), ["unlock_trade_hub"], 4, "Unlocks Logistics Center", 1)
	_add_node("unlock_command_center", "Planetary Command", "Blueprints for planet-wide command centers.", 5000.0, Vector2(160, 640), ["unlock_trade_hub"], 4, "Unlocks Command Center", 1)
	
	_add_node("planetary_architecture", "Planetary Architecture", "Increases maximum districts available on all planets.", 2500.0, Vector2(160, 480), ["unlock_trade_hub"], 4, "+1 Max District", 3)
	_add_node("global_logistics", "Global Logistics", "Optimizes supply chains for all colonized worlds.", 2000.0, Vector2(-160, 480), ["unlock_trade_hub"], 4, "+5% global production speed", 10)

func _add_node(id: String, name: String, desc: String, cost: float, pos: Vector2, parents: Array[String], tier: int, eff: String, max_lv: int = 1) -> void:
	nodes[id] = SkillNode.new(id, name, desc, cost, pos, parents, tier, eff, max_lv)

# Get current level of a node (returns 0 if locked/not started)
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
			
			if id == "unlock_moon":
				GameState.moon_unlocked = true
			elif id == "unlock_solar":
				GameState.solar_unlocked = true
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
	return 1.25 if "solar_efficiency" in unlocked_skills else 1.0

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
		base += 0.30
	if "supercharged_generators" in unlocked_skills:
		var lv := get_skill_level("supercharged_generators")
		base += 0.10 * lv
	return base

func get_credits_mult() -> float:
	return 1.25 if "credit_boost" in unlocked_skills else 1.0

func get_mine_output_mult() -> float:
	var base := 1.0
	if "deep_mining" in unlocked_skills:
		base += 0.25
	if "deep_core_drilling" in unlocked_skills:
		var lv := get_skill_level("deep_core_drilling")
		base += 0.10 * lv
	return base

func get_energy_consume_mult() -> float:
	var mult := 1.0
	if "power_transmission" in unlocked_skills:
		mult -= 0.15
	if "energy_efficiency" in unlocked_skills:
		var lv := get_skill_level("energy_efficiency")
		mult -= 0.05 * lv
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
