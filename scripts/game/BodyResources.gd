class_name BodyResources
extends RefCounted

## Holds all ResourceData instances available on a single body (planet/moon/asteroid).
## Generated once per body seed and cached in GameState.

var body_seed:   int = 0
var rarity_min:  int = 1
var rarity_max:  int = 1

## { resource_id -> ResourceData }
var resources: Dictionary = {}

# ── Generation ────────────────────────────────────────────────────────────────

## Rarity ranges by body type — controls what minerals can be found where.
static func rarity_range_for(planet_type: PlanetData.Type) -> Vector2i:
	match planet_type:
		PlanetData.Type.MOON:      return Vector2i(1, 2)
		PlanetData.Type.ASTEROID:  return Vector2i(2, 3)
		# Standard planets always start at R1; richer varieties can appear at higher R
		PlanetData.Type.BARREN,\
		PlanetData.Type.VOLCANIC:  return Vector2i(1, 2)
		PlanetData.Type.TERRAN,\
		PlanetData.Type.ARID,\
		PlanetData.Type.ICE:       return Vector2i(1, 2)
		_:                         return Vector2i(1, 1)

## Generate the resource pool for a body.
## Each distinct rarity in [rarity_min, rarity_max] produces exactly one mineral —
## consistent universe-wide (R1 is always the same mineral regardless of body).
static func generate(b_seed: int, r_min: int, r_max: int) -> BodyResources:
	var br        := BodyResources.new()
	br.body_seed   = b_seed
	br.rarity_min  = r_min
	br.rarity_max  = r_max

	var rng := RandomNumberGenerator.new()
	rng.seed = b_seed ^ 0xC0FFEE

	# Bodies don't always expose every rarity in their range — add some variety
	for r in range(r_min, r_max + 1):
		# Higher rarities have a chance of not appearing (rarer = harder to find)
		var chance: float = 1.0 if r == r_min else 0.65
		if rng.randf() > chance:
			continue
		var rd := ResourceData.generate(b_seed, ResourceData.Tag.RAW_MINERAL, r, 1)
		br.resources[rd.resource_id()] = rd

	# Guarantee at least one resource
	if br.resources.is_empty():
		var rd := ResourceData.generate(b_seed, ResourceData.Tag.RAW_MINERAL, r_min, 1)
		br.resources[rd.resource_id()] = rd

	return br

## Convenience: returns all resources as an array, sorted by rarity then tier.
func as_array() -> Array[ResourceData]:
	var arr: Array[ResourceData] = []
	for rd in resources.values():
		arr.append(rd as ResourceData)
	arr.sort_custom(func(a: ResourceData, b: ResourceData) -> bool:
		return a.rarity < b.rarity if a.rarity != b.rarity else a.tier < b.tier)
	return arr

func get_by_tag(tag: ResourceData.Tag) -> Array[ResourceData]:
	var arr: Array[ResourceData] = []
	for rd in resources.values():
		if (rd as ResourceData).tag == tag:
			arr.append(rd as ResourceData)
	return arr

## Average power across all resources on this body.
func avg_power() -> float:
	var arr := as_array()
	if arr.is_empty():
		return 1.0
	var sum: float = 0.0
	for rd: ResourceData in arr:
		sum += rd.power
	return sum / float(arr.size())
