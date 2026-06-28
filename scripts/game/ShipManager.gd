## ShipManager — autoload singleton.
## Tracks all ships across all planets, ticks orbital motion and travel.
extends Node

signal ship_changed(ship: ShipData)   # orbit angle updated or state changed
signal ship_arrived(ship: ShipData)   # reached destination

## { planet_seed -> Array[ShipData] }
var _ships: Dictionary = {}

const ORBIT_SPEED: float = 0.12   # radians per second

func _process(delta: float) -> void:
	for seed_val: int in _ships:
		for ship: ShipData in _ships[seed_val]:
			if ship.is_travelling():
				ship.travel_progress += delta / ship.travel_duration
				if ship.travel_progress >= 1.0:
					ship.travel_progress = 1.0
					_on_arrived(ship)
			else:
				ship.orbit_angle = fmod(ship.orbit_angle + ship.orbit_speed * delta, TAU)
			ship_changed.emit(ship)

func _on_arrived(ship: ShipData) -> void:
	var old_seed := ship.orbit_seed
	ship.orbit_seed      = ship.dest_seed
	ship.dest_seed       = -1
	ship.travel_progress = 0.0
	ship.travel_duration = 0.0
	# Move ship to new planet's list
	remove_ship(old_seed, ship.ship_id)
	add_ship(ship)
	ship_arrived.emit(ship)

# ── Public API ────────────────────────────────────────────────────────────────

func ships_for(planet_seed: int) -> Array[ShipData]:
	return _ships.get(planet_seed, []) as Array[ShipData]

func add_ship(ship: ShipData) -> void:
	if not _ships.has(ship.orbit_seed):
		_ships[ship.orbit_seed] = []
	(_ships[ship.orbit_seed] as Array).append(ship)
	ship_changed.emit(ship)

func remove_ship(planet_seed: int, ship_id: String) -> void:
	if not _ships.has(planet_seed):
		return
	var arr: Array = _ships[planet_seed]
	for i in arr.size():
		if (arr[i] as ShipData).ship_id == ship_id:
			arr.remove_at(i)
			return

## Launch a new ship from a spaceport planet. Returns the new ShipData.
func launch(planet_seed: int, name: String, cargo: Dictionary = {}) -> ShipData:
	var angle := randf() * TAU
	var ship   := ShipData.make(name, planet_seed, angle)
	ship.cargo  = cargo
	add_ship(ship)
	return ship

## Send an orbiting ship to a destination planet.
func dispatch(ship: ShipData, dest_seed: int, duration_sec: float) -> void:
	ship.dest_seed       = dest_seed
	ship.travel_duration = duration_sec
	ship.travel_progress = 0.0
	ship_changed.emit(ship)

## Save / load
func serialize() -> Array:
	var out: Array = []
	for seed_val: int in _ships:
		for ship: ShipData in _ships[seed_val]:
			out.append({
				"ship_id":           ship.ship_id,
				"ship_name":         ship.ship_name,
				"orbit_seed":        ship.orbit_seed,
				"orbit_angle":       ship.orbit_angle,
				"orbit_radius":      ship.orbit_radius,
				"orbit_speed":       ship.orbit_speed,
				"orbit_inclination": ship.orbit_inclination,
				"orbit_node":        ship.orbit_node,
				"cargo":             ship.cargo,
				"dest_seed":         ship.dest_seed,
				"travel_progress":   ship.travel_progress,
				"travel_duration":   ship.travel_duration,
			})
	return out

func deserialize(arr: Array) -> void:
	_ships.clear()
	for d: Dictionary in arr:
		var s               := ShipData.new()
		s.ship_id           = d.get("ship_id",        "")
		s.ship_name         = d.get("ship_name",      "Shuttle")
		s.orbit_seed        = d.get("orbit_seed",     -1)
		s.orbit_angle       = d.get("orbit_angle",       0.0)
		s.orbit_radius      = d.get("orbit_radius",      1.06)
		s.orbit_speed       = d.get("orbit_speed",       1.0)
		s.orbit_inclination = d.get("orbit_inclination", 0.0)
		s.orbit_node        = d.get("orbit_node",        0.0)
		s.cargo             = d.get("cargo",             {})
		s.dest_seed         = d.get("dest_seed",      -1)
		s.travel_progress   = d.get("travel_progress",0.0)
		s.travel_duration   = d.get("travel_duration",0.0)
		if s.orbit_seed >= 0:
			add_ship(s)
