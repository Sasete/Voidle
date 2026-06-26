class_name POIData
extends Resource

@export var label: String = "Site"
@export var type_tag: String = ""
@export var light_intensity: float = 1.0

## Where on the planet this POI should appear.
@export var placement: LocationFinder.Placement = LocationFinder.Placement.LAND

## If true, use lon_deg / lat_deg as-is instead of auto-placing.
@export var manual_position: bool = false
@export var lon_deg: float = 0.0
@export var lat_deg: float = 0.0
