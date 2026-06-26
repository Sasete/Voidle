class_name SolarData
extends Resource

enum StarType { YELLOW_DWARF, RED_DWARF, BLUE_GIANT, ORANGE_SUBGIANT, WHITE_DWARF }

@export var system_name:  String = "Unknown System"
@export var star_type:    StarType = StarType.YELLOW_DWARF
@export var seed:         int = 0
@export var is_home:      bool = false   # true for the starting system
@export var planets:          Array[PlanetData] = []
@export var asteroid_belt_slots: Array[int] = []

# Binary companion
@export var is_binary:      bool     = false
@export var secondary_type: StarType = StarType.RED_DWARF
@export var binary_dist:    float    = 0.0   # px distance from primary (set in from_seed)  # indices: belt sits after planets[i]

static func from_seed(s: int) -> SolarData:
	var data := SolarData.new()
	data.seed = s
	var rng := RandomNumberGenerator.new()
	rng.seed = s

	var roll := rng.randi() % 10
	if   roll < 4: data.star_type = StarType.YELLOW_DWARF
	elif roll < 7: data.star_type = StarType.RED_DWARF
	elif roll < 9: data.star_type = StarType.ORANGE_SUBGIANT
	else:          data.star_type = StarType.BLUE_GIANT

	data.system_name = _gen_name(rng)

	var count := rng.randi_range(3, 6)
	for i in count:
		var pseed: int = (s * 31 + i * 1337 + 7) % 99999
		var pd    := PlanetData.from_seed_no_minor(pseed)
		# bias inner planets rocky, outer planets gas
		var orbit_ratio: float = float(i) / float(count - 1) if count > 1 else 0.5
		if orbit_ratio < 0.35 and pd.planet_type == PlanetData.Type.GAS_GIANT:
			pd = PlanetData.from_seed_no_minor(pseed + 3)
		pd.generate_moons(pseed)
		data.planets.append(pd)

	# ~25% chance of binary companion (smaller type than primary)
	if rng.randf() < 0.25:
		data.is_binary = true
		var secondary_roll := rng.randi() % 3
		if   secondary_roll == 0: data.secondary_type = StarType.RED_DWARF
		elif secondary_roll == 1: data.secondary_type = StarType.WHITE_DWARF
		else:                     data.secondary_type = StarType.ORANGE_SUBGIANT
		data.binary_dist = rng.randf_range(80.0, 140.0)

	# 1-2 asteroid belts placed at random gaps between planets
	var belt_count: int = rng.randi_range(1, 2)
	var used: Array[int] = []
	for _b in belt_count:
		var slot: int = rng.randi_range(0, count - 2)
		if slot not in used:
			used.append(slot)
			data.asteroid_belt_slots.append(slot)

	return data

static func _gen_name(rng: RandomNumberGenerator) -> String:
	var pre := ["Alpha","Beta","Gamma","Delta","Epsilon","Zeta","Eta","Theta","Iota","Kappa"]
	var suf := ["Prime","Nova","Minor","Major","Centauri","Eridani","Cygni","Lyrae","Aquilae","Draconis"]
	return pre[rng.randi() % pre.size()] + " " + suf[rng.randi() % suf.size()]

static func get_star_colors(type: StarType) -> Dictionary:
	match type:
		StarType.RED_DWARF:
			return {"core": Vector3(1.0,0.55,0.20), "surface": Vector3(0.90,0.30,0.08), "corona": Vector3(0.75,0.18,0.04)}
		StarType.BLUE_GIANT:
			return {"core": Vector3(0.88,0.94,1.0),  "surface": Vector3(0.55,0.72,1.0),  "corona": Vector3(0.35,0.55,1.0)}
		StarType.ORANGE_SUBGIANT:
			return {"core": Vector3(1.0,0.90,0.65),  "surface": Vector3(1.0,0.62,0.22),  "corona": Vector3(0.90,0.38,0.05)}
		StarType.WHITE_DWARF:
			return {"core": Vector3(0.95,0.97,1.0),  "surface": Vector3(0.82,0.90,1.0),  "corona": Vector3(0.65,0.75,1.0)}
		_: # YELLOW_DWARF
			return {"core": Vector3(1.0,0.98,0.88),  "surface": Vector3(1.0,0.78,0.30),  "corona": Vector3(1.0,0.45,0.08)}

static func get_star_radius(type: StarType) -> float:
	match type:
		StarType.RED_DWARF:      return 0.10
		StarType.BLUE_GIANT:     return 0.22
		StarType.ORANGE_SUBGIANT:return 0.16
		StarType.WHITE_DWARF:    return 0.06
		_:                       return 0.13

static func get_star_type_name(type: StarType) -> String:
	match type:
		StarType.RED_DWARF:       return "Red Dwarf"
		StarType.BLUE_GIANT:      return "Blue Giant"
		StarType.ORANGE_SUBGIANT: return "Orange Subgiant"
		StarType.WHITE_DWARF:     return "White Dwarf"
		_:                        return "Yellow Dwarf"
