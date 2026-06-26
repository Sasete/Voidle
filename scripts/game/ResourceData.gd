class_name ResourceData
extends Resource

## Tags — define where this resource sits in the production chain.
enum Tag {
	RAW_MINERAL,      # comes from Mining Facility
	REFINED_MINERAL,  # comes from Refinery
	ENERGY,           # comes from Generator
	CREDITS,          # comes from City (virtual — tracked separately in GameState)
	GAS,              # future: harvested from gas giants
	FOOD,             # future: grown on terran/ice planets
	EXOTIC,           # future: rare drops, anomalies
}

static var TAG_NAMES: Array[String] = [
	"Raw Mineral", "Refined Mineral", "Energy", "Credits", "Gas", "Food", "Exotic"
]

# ── Identity ─────────────────────────────────────────────────────────────────
@export var unique_name: String = ""   # e.g. "Veltrium Ore", "Ash Crystite"
@export var tag:         Tag    = Tag.RAW_MINERAL
@export var tier:        int    = 1    # 1 = basic, 15+ = endgame

# ── Economy ───────────────────────────────────────────────────────────────────
## Credit value per unit — scales exponentially with tier.
@export var base_value: float = 1.0

## How much of this resource fits in one ship cargo slot.
@export var stack_size: float = 100.0

# ── Visuals ───────────────────────────────────────────────────────────────────
## Tint used in UI icons — derived from tier + tag on generation.
@export var display_color: Color = Color.WHITE

# ── Source ───────────────────────────────────────────────────────────────────
## Seed of the body where this resource was first found.
@export var origin_seed: int = 0

# ── Unique identifier (tag + tier + origin) ──────────────────────────────────
func resource_id() -> String:
	return "%s_%d_%d" % [Tag.keys()[tag], tier, origin_seed]

# ════════════════════════════════════════════════════════════════════════════
#  Procedural generation
# ════════════════════════════════════════════════════════════════════════════

## Syllable pools for name generation — split by "feel"
const _PREFIXES: Array[String] = [
	"Vel", "Ash", "Crys", "Thal", "Myr", "Ore", "Keth", "Sol",
	"Vex", "Zyn", "Aur", "Phos", "Neb", "Cal", "Drav", "Stel",
	"Hyx", "Torn", "Umr", "Bril", "Fen", "Gal", "Ith", "Jor",
]
const _MIDDLES: Array[String] = [
	"it", "el", "ar", "on", "um", "ix", "al", "en",
	"or", "ur", "an", "ys", "eth", "ite", "ium", "ath",
	"os", "ae", "ri", "lo", "na", "er", "is", "ul",
]
const _SUFFIXES_RAW: Array[String] = [
	"Ore", "Stone", "Dust", "Shard", "Vein", "Rock", "Cluster", "Deposit",
]
const _SUFFIXES_REFINED: Array[String] = [
	"Crystal", "Ingot", "Compound", "Alloy", "Extract", "Plate", "Bar", "Pellet",
]

## Generate a ResourceData for a given body seed, tag, and tier.
static func generate(body_seed: int, res_tag: Tag, res_tier: int) -> ResourceData:
	var rng := RandomNumberGenerator.new()
	rng.seed = body_seed ^ (res_tag * 0x1F3A + res_tier * 0x4B71)

	var rd           := ResourceData.new()
	rd.tag           = res_tag
	rd.tier          = res_tier
	rd.origin_seed   = body_seed
	rd.base_value    = _calc_base_value(res_tag, res_tier)
	rd.stack_size    = _calc_stack_size(res_tag, res_tier)
	rd.display_color = _tier_color(res_tag, res_tier)
	rd.unique_name   = _gen_name(rng, res_tag, res_tier)
	return rd

static func _gen_name(rng: RandomNumberGenerator, res_tag: Tag, res_tier: int) -> String:
	var prefix: String = _PREFIXES[rng.randi() % _PREFIXES.size()]
	var middle: String = _MIDDLES[rng.randi()  % _MIDDLES.size()]
	var base: String   = prefix + middle

	# tier suffix: higher tiers get "Prime", "Void", "Core" etc.
	var tier_qualifier: String = ""
	if res_tier >= 10:
		tier_qualifier = ["Void ", "Abyss ", "Core ", "Null "][rng.randi() % 4]
	elif res_tier >= 5:
		tier_qualifier = ["Prime ", "Deep ", "Dark ", "High "][rng.randi() % 4]

	match res_tag:
		Tag.RAW_MINERAL:
			var suf := _SUFFIXES_RAW[rng.randi() % _SUFFIXES_RAW.size()]
			return tier_qualifier + base + " " + suf
		Tag.REFINED_MINERAL:
			var suf := _SUFFIXES_REFINED[rng.randi() % _SUFFIXES_REFINED.size()]
			return tier_qualifier + base + " " + suf
		Tag.ENERGY:
			return "Energy"
		Tag.GAS:
			return base + " Gas"
		Tag.FOOD:
			return base + " Yield"
		Tag.EXOTIC:
			return tier_qualifier + base + " Fragment"
		_:
			return base

static func _calc_base_value(res_tag: Tag, res_tier: int) -> float:
	var tier_mult: float = pow(1.6, res_tier - 1)   # exponential: T1=1, T5≈6.6, T10≈68, T15≈700
	match res_tag:
		Tag.RAW_MINERAL:     return 1.0  * tier_mult
		Tag.REFINED_MINERAL: return 3.5  * tier_mult
		Tag.ENERGY:          return 8.0  * tier_mult
		Tag.GAS:             return 2.0  * tier_mult
		Tag.FOOD:            return 1.5  * tier_mult
		Tag.EXOTIC:          return 25.0 * tier_mult
		_:                   return 1.0  * tier_mult

static func _calc_stack_size(_res_tag: Tag, res_tier: int) -> float:
	# Higher tier = denser/rarer, smaller stack
	return maxf(20.0, 100.0 - (res_tier - 1) * 6.0)

## HSV colour ramp: T1=grey-blue → T5=green → T10=purple → T15=gold
static func _tier_color(res_tag: Tag, res_tier: int) -> Color:
	var t: float = clamp(float(res_tier - 1) / 14.0, 0.0, 1.0)
	var hue: float
	match res_tag:
		Tag.ENERGY:          return Color(1.0, 0.85, 0.2)
		Tag.GAS:             return Color(0.4, 0.8, 1.0)
		Tag.FOOD:            return Color(0.4, 0.9, 0.3)
		Tag.EXOTIC:          return Color(0.9, 0.4, 1.0)
		Tag.REFINED_MINERAL: hue = lerp(0.55, 0.78, t)   # cyan → violet
		_:                   hue = lerp(0.58, 0.12, t)   # blue-grey → gold
	var sat: float = lerp(0.25, 0.85, t)
	var val: float = lerp(0.70, 1.00, t)
	return Color.from_hsv(hue, sat, val)
