## A single ship in orbit around a planet.
class_name ShipData
extends Resource

## Unique id — generated at launch.
@export var ship_id:      String = ""
@export var ship_name:    String = "Shuttle"

## Which planet this ship currently orbits (seed).
@export var orbit_seed:   int    = -1

## Orbital angle in radians (advances each tick).
@export var orbit_angle:  float  = 0.0

## Orbital radius as fraction of planet radius (1.0 = surface, ~1.02 = just above).
@export var orbit_radius: float  = 1.06

## Inclination of orbital plane in radians (random per ship — gives varied tilt angles).
@export var orbit_inclination: float = 0.0

## Orbital angular speed in rad/s. Positive = one direction, negative = opposite.
@export var orbit_speed: float = 0.15

## Cargo: resource_id -> amount
@export var cargo:        Dictionary = {}

## Destination planet seed (-1 = parked in orbit).
@export var dest_seed:    int    = -1

## Travel progress 0.0–1.0 (0 = just launched, 1 = arrived).
@export var travel_progress: float = 0.0

## Travel duration in seconds.
@export var travel_duration: float = 0.0

func is_travelling() -> bool:
	return dest_seed >= 0 and travel_progress < 1.0

func eta_seconds() -> float:
	if not is_travelling():
		return 0.0
	return travel_duration * (1.0 - travel_progress)

func cargo_total() -> float:
	var t: float = 0.0
	for v in cargo.values():
		t += float(v)
	return t

static func make(name: String, planet_seed: int, angle: float = 0.0) -> ShipData:
	var s               := ShipData.new()
	s.ship_id            = "%d_%d" % [planet_seed, Time.get_ticks_msec()]
	s.ship_name          = name
	s.orbit_seed         = planet_seed
	s.orbit_angle        = angle
	s.orbit_inclination  = randf() * TAU   # random orbital plane tilt
	return s
