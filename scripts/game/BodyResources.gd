class_name BodyResources
extends RefCounted

## Holds all ResourceData instances available on a single body (planet/moon/asteroid).
## Generated once per body seed and cached in GameState.

var body_seed: int = 0
var tier_min:  int = 1
var tier_max:  int = 1

## { resource_id -> ResourceData }
var resources: Dictionary = {}

# ── Generation ────────────────────────────────────────────────────────────────

## Create the resource pool for a body.
## tier_min/max define the tier band available here.
## Raw minerals are always generated; refined come from processing (not stored here).
static func generate(b_seed: int, t_min: int, t_max: int) -> BodyResources:
	var br       := BodyResources.new()
	br.body_seed  = b_seed
	br.tier_min   = t_min
	br.tier_max   = t_max

	var rng := RandomNumberGenerator.new()
	rng.seed = b_seed ^ 0xC0FFEE

	# Number of distinct raw mineral types on this body (1 for T1 home, more for richer bodies)
	var variety: int = rng.randi_range(1, mini(3, t_max - t_min + 2))

	for _i in variety:
		var tier: int = rng.randi_range(t_min, t_max)
		var rd := ResourceData.generate(b_seed ^ (_i * 0x7919), ResourceData.Tag.RAW_MINERAL, tier)
		br.resources[rd.resource_id()] = rd

	# Gas giants also produce Gas resources
	# (caller can pass a flag — for now detected via tier band conventionally)
	return br

## Convenience: returns all resources as an array, sorted by tier.
func as_array() -> Array[ResourceData]:
	var arr: Array[ResourceData] = []
	for rd in resources.values():
		arr.append(rd as ResourceData)
	arr.sort_custom(func(a: ResourceData, b: ResourceData) -> bool: return a.tier < b.tier)
	return arr

func get_by_tag(tag: ResourceData.Tag) -> Array[ResourceData]:
	var arr: Array[ResourceData] = []
	for rd in resources.values():
		if (rd as ResourceData).tag == tag:
			arr.append(rd as ResourceData)
	return arr
