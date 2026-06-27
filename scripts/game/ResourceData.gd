class_name ResourceData
extends Resource

## Tags — define where this resource sits in the production chain.
enum Tag {
	RAW_MINERAL,      # comes from Mining Facility
	REFINED_MINERAL,  # comes from Refinery
	ENERGY,           # comes from Generator
	CREDITS,          # comes from City (virtual — tracked separately in GameState)
	GAS,              # harvested from gas giants
	FOOD,             # grown on terran/ice planets
	EXOTIC,           # rare drops, anomalies
}

static var TAG_NAMES: Array[String] = [
	"Raw Mineral", "Refined Mineral", "Energy", "Credits", "Gas", "Food", "Exotic"
]

## Fixed suffixes per processing tier.
const TIER_SUFFIXES: Array[String] = ["Ore", "Ingot", "Alloy", "Component", "Core"]

# ── Identity ──────────────────────────────────────────────────────────────────
## The mineral's base name — derived from rarity, consistent across all bodies.
## e.g. "Veltrium"
@export var mineral_name: String = ""

## Full display name including tier suffix. e.g. "Veltrium Ore", "Veltrium Ingot"
@export var unique_name:  String = ""

@export var tag:    Tag = Tag.RAW_MINERAL

## Rarity: how rare/deep this mineral is. Higher = found only in asteroid belts,
## far systems, etc. Consistent universe-wide (R1 is always the same mineral).
@export var rarity: int = 1

## Tier: processing level. T1 = raw ore, T2 = ingot, T3 = alloy, etc.
## Increases when the mineral is processed in a Refinery district.
@export var tier:   int = 1

# ── Economy ───────────────────────────────────────────────────────────────────
## Effective power of this resource: sqrt(rarity) + sqrt(tier).
## Used for building inputs, value calculations, and district unlocks.
@export var power: float = 2.0

## Credit value per unit — derived from power × tag multiplier.
@export var base_value: float = 1.0

## How much fits in one cargo slot.
@export var stack_size: float = 100.0

# ── Visuals ───────────────────────────────────────────────────────────────────
## Tint used in UI icons — hue from rarity, brightness from tier.
@export var display_color: Color = Color.WHITE

# ── Source ───────────────────────────────────────────────────────────────────
## Seed of the body where this deposit was first found (used for generation only).
@export var origin_seed: int = 0

# ── Unique identifier ─────────────────────────────────────────────────────────
## Stable key for stored_resources dict: tag + rarity + tier.
## Origin-independent — same R/T mineral is the same resource regardless of body.
func resource_id() -> String:
	return "R%d_T%d_%s" % [rarity, tier, Tag.keys()[tag]]

# ═══════════════════════════════════════════════════════════════════════════════
#  Procedural generation
# ═══════════════════════════════════════════════════════════════════════════════

## Syllable pools for mineral name generation
const _PREFIXES: Array[String] = [
	"Vel", "Ash", "Crys", "Thal", "Myr", "Keth", "Sol",
	"Vex", "Zyn", "Aur", "Phos", "Neb", "Cal", "Drav", "Stel",
	"Hyx", "Torn", "Umr", "Bril", "Fen", "Gal", "Ith", "Jor", "Ryn",
]
const _MIDDLES: Array[String] = [
	"it", "el", "ar", "on", "um", "ix", "al", "en",
	"or", "ur", "an", "ys", "eth", "ium", "ath",
	"os", "ri", "lo", "na", "er", "is", "ul", "yn",
]

## Generate a ResourceData for a given rarity and tier.
## Mineral name is seeded by rarity only — consistent across all bodies.
static func generate(body_seed: int, res_tag: Tag, res_rarity: int, res_tier: int = 1) -> ResourceData:
	# Name seed: rarity + tag only, so R1 RAW_MINERAL is always the same name everywhere
	var name_rng := RandomNumberGenerator.new()
	name_rng.seed = res_rarity * 0x7919 + res_tag * 0x1F3A

	var rd            := ResourceData.new()
	rd.tag            = res_tag
	rd.rarity         = res_rarity
	rd.tier           = res_tier
	rd.origin_seed    = body_seed
	rd.mineral_name   = _gen_mineral_name(name_rng, res_rarity)
	rd.unique_name    = rd.mineral_name + " " + _tier_suffix(res_tier)
	rd.power          = _calc_power(res_rarity, res_tier)
	rd.base_value     = _calc_base_value(res_tag, res_rarity, res_tier)
	rd.stack_size     = _calc_stack_size(res_rarity, res_tier)
	rd.display_color  = _resource_color(res_tag, res_rarity, res_tier)
	return rd

## Create a processed (higher-tier) version of this resource.
func processed() -> ResourceData:
	return ResourceData.generate(origin_seed, tag, rarity, tier + 1)

static func _tier_suffix(t: int) -> String:
	const SUFFIXES: Array[String] = ["Ore", "Ingot", "Alloy", "Component", "Core"]
	return SUFFIXES[clampi(t - 1, 0, SUFFIXES.size() - 1)]

static func _gen_mineral_name(rng: RandomNumberGenerator, res_rarity: int) -> String:
	var prefix: String = _PREFIXES[rng.randi() % _PREFIXES.size()]
	var middle: String = _MIDDLES[rng.randi() % _MIDDLES.size()]
	# High rarity minerals get an extra qualifier prefix
	var qualifier := ""
	if res_rarity >= 12:
		qualifier = ["Void", "Abyss", "Null", "Prime"][rng.randi() % 4] + " "
	elif res_rarity >= 7:
		qualifier = ["Deep", "Dark", "High", "Core"][rng.randi() % 4] + " "
	return qualifier + prefix + middle

static func _calc_power(res_rarity: int, res_tier: int) -> float:
	return sqrt(float(res_rarity)) + sqrt(float(res_tier))

static func _calc_base_value(res_tag: Tag, res_rarity: int, res_tier: int) -> float:
	var p := _calc_power(res_rarity, res_tier)
	match res_tag:
		Tag.RAW_MINERAL:     return 1.0  * p
		Tag.REFINED_MINERAL: return 3.5  * p
		Tag.ENERGY:          return 8.0  * p
		Tag.GAS:             return 2.0  * p
		Tag.FOOD:            return 1.5  * p
		Tag.EXOTIC:          return 25.0 * p
		_:                   return 1.0  * p

static func _calc_stack_size(_res_rarity: int, res_tier: int) -> float:
	return maxf(20.0, 100.0 - (res_tier - 1) * 15.0)

## Color: hue from rarity (gray-blue → green → purple → gold),
##        brightness from tier (dark raw → vivid processed).
static func _resource_color(res_tag: Tag, res_rarity: int, res_tier: int) -> Color:
	match res_tag:
		Tag.ENERGY: return Color(1.0, 0.85, 0.2)
		Tag.GAS:    return Color(0.4, 0.8, 1.0)
		Tag.FOOD:   return Color(0.4, 0.9, 0.3)
		Tag.EXOTIC: return Color(0.9, 0.4, 1.0)

	var r: float = clamp(float(res_rarity - 1) / 14.0, 0.0, 1.0)

	# Hue arc: R1=blue-gray(0.60) → R5=teal(0.48) → R8=green(0.35)
	#          → R11=purple(0.78) → R15=gold(0.12)
	var hue: float
	if r < 0.33:
		hue = lerp(0.60, 0.35, r / 0.33)
	elif r < 0.66:
		hue = lerp(0.35, 0.78, (r - 0.33) / 0.33)
	else:
		hue = lerp(0.78, 0.12, (r - 0.66) / 0.34)

	# Saturation: always visible — even R1 has strong color
	var sat: float = lerp(0.60, 0.92, r)

	# Brightness: tier 1 = darker raw ore, tier 5 = bright processed material
	var t: float   = clamp(float(res_tier - 1) / 4.0, 0.0, 1.0)
	var val: float = lerp(0.55, 1.00, t)

	# REFINED_MINERAL gets a slight hue shift to distinguish from raw
	if res_tag == Tag.REFINED_MINERAL:
		hue = fmod(hue + 0.08, 1.0)

	return Color.from_hsv(hue, sat, val)
