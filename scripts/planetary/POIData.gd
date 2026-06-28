class_name POIData
extends Resource

enum POIType {
	CITY,       # general buildings, city districts
	MINING,     # extraction, raw minerals
	ENERGY,     # generators, power distribution
	OUTPOST,    # military, defense
	SCIENCE,    # research, anomaly study
	SPACEPORT,  # launch pads, orbital logistics — one per planet
}

static var TYPE_LABELS: Array[String] = ["City", "Mining", "Energy", "Outpost", "Science", "Spaceport"]
static var TYPE_ICONS:  Array[String] = ["⬡", "⛏", "⚡", "⬡", "⬡", "🚀"]

@export var label:         String  = "Site"
@export var poi_type:      POIType = POIType.CITY
@export var light_intensity: float = 1.0
@export var level:         int     = 1    # 1–5; grows as buildings are added

@export var constructing:       bool  = false
@export var construct_progress: float = 0.0
@export var construct_duration: float = 15.0

## Where on the planet this POI should appear.
@export var placement: LocationFinder.Placement = LocationFinder.Placement.LAND

## If true, use lon_deg / lat_deg as-is instead of auto-placing.
@export var manual_position: bool  = false
@export var lon_deg:         float = 0.0
@export var lat_deg:         float = 0.0

## Legacy string tag kept for shader/ring logic only — do not use for type checks.
@export var type_tag: String = ""

func max_building_slots() -> int:
	return level * 2   # Lv1=2, Lv2=4, Lv3=6, Lv4=8, Lv5=10

func type_label() -> String:
	return TYPE_LABELS[poi_type]
