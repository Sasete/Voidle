## Draws orbital ships with proper Y-axis (longitude) rotation.
## Ships on the far side of the planet are hidden behind it.
class_name OrbitalLayer
extends Control

var _planet_seed:     int     = -1
var _planet_radius:   float   = 0.0
var _planet_rotation: float   = 0.0   # Y-axis rotation (longitude) from planet drag
var _planet_center:   Vector2 = Vector2.ZERO   # actual planet center in local coords
var _hovered_ship:    ShipData = null

## Per-ship orbit-reveal: ship_id -> {progress: float, spawn_angle: float}
var _reveal: Dictionary = {}

signal ship_hovered(ship: ShipData, screen_pos: Vector2)
signal ship_unhovered()

func setup(planet_seed: int) -> void:
	_planet_seed = planet_seed
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ShipManager.ship_changed.connect(_on_ship_changed)

func _process(delta: float) -> void:
	if _planet_seed < 0:
		return
	var needs_redraw := false
	for ship_id: String in _reveal:
		var rv: Dictionary = _reveal[ship_id]
		if rv["progress"] < 1.0:
			rv["progress"] = minf(rv["progress"] + delta * 1.8, 1.0)
			needs_redraw = true
	if needs_redraw:
		queue_redraw()
	else:
		queue_redraw()

func _on_ship_changed(ship: ShipData) -> void:
	if ship.orbit_seed == _planet_seed:
		if not _reveal.has(ship.ship_id):
			_reveal[ship.ship_id] = {"progress": 0.0, "spawn_angle": ship.orbit_angle}
		queue_redraw()

## Projects a ship's 3D orbital position to screen (x,y) and returns depth z.
## z > 0 = behind planet, z < 0 = in front.
func _project(ship: ShipData, angle: float) -> Vector3:
	var r: float   = _planet_radius * ship.orbit_radius
	var inc: float = ship.orbit_inclination
	var px: float  = r * cos(angle)
	var py: float  = r * sin(angle) * sin(inc)
	var pz: float  = r * sin(angle) * cos(inc)
	var rot: float = _planet_rotation + ship.orbit_node   # node rotates orbital plane around Y
	var rx: float  =  px * cos(rot) + pz * sin(rot)
	var rz: float  = -px * sin(rot) + pz * cos(rot)
	return Vector3(rx, py, rz)

func _is_occluded(proj: Vector3) -> bool:
	# Use full radius (not 0.96) so ships disappear right at the planet edge
	return proj.z > 0.0 and Vector2(proj.x, proj.y).length() < _planet_radius

## Pixel-art cross: shuttle shape.
func _draw_pixel_ship(pos: Vector2, col: Color) -> void:
	var p  := (pos - Vector2.ONE).floor()
	var sz := Vector2(2, 2)
	draw_rect(Rect2(p,                   sz), col)
	draw_rect(Rect2(p + Vector2(-2,  0), sz), col)
	draw_rect(Rect2(p + Vector2( 2,  0), sz), col)
	draw_rect(Rect2(p + Vector2( 0, -2), sz), col)
	draw_rect(Rect2(p + Vector2( 0,  2), sz), col)

## Pixel-art ISS: horizontal truss + solar panels + center node.
func _draw_pixel_station(pos: Vector2, col: Color) -> void:
	var p  := (pos - Vector2.ONE).floor()
	var sz := Vector2(2, 2)
	# Main truss (horizontal bar, 5 blocks)
	for ox: int in [-4, -2, 0, 2, 4]:
		draw_rect(Rect2(p + Vector2(ox, 0), sz), col)
	# Center vertical node
	draw_rect(Rect2(p + Vector2(0, -2), sz), col)
	draw_rect(Rect2(p + Vector2(0,  2), sz), col)
	# Left solar panels (top + bottom)
	draw_rect(Rect2(p + Vector2(-6, -2), sz), col)
	draw_rect(Rect2(p + Vector2(-6,  2), sz), col)
	# Right solar panels (top + bottom)
	draw_rect(Rect2(p + Vector2( 6, -2), sz), col)
	draw_rect(Rect2(p + Vector2( 6,  2), sz), col)

func _draw() -> void:
	if _planet_seed < 0 or _planet_radius <= 0.0:
		return
	var center := _planet_center if _planet_center != Vector2.ZERO else size * 0.5

	for ship: ShipData in ShipManager.ships_for(_planet_seed):
		# ── Orbit path — reveal animates in the direction of travel ─────────────
		var steps := 90   # divisible by 6 for clean dash repeat
		var alpha: float = 0.30 if not ship.is_travelling() else 0.45
		var rv: Dictionary = _reveal.get(ship.ship_id, {})
		var arc_frac:    float = rv.get("progress",    1.0)
		var spawn_angle: float = rv.get("spawn_angle", 0.0)
		var dir: float = sign(ship.orbit_speed) if ship.orbit_speed != 0.0 else 1.0
		var arc_total: float   = arc_frac * TAU
		var prev_v   := _project(ship, spawn_angle)
		var prev_pos := center + Vector2(prev_v.x, prev_v.y)
		for s in range(1, steps + 1):
			var frac: float = float(s) / float(steps)
			if frac * TAU > arc_total:
				break
			var a: float = spawn_angle + dir * frac * TAU
			var v        := _project(ship, a)
			var cur_pos  := center + Vector2(v.x, v.y)
			var in_dash: bool = (s % 6) < 3
			if in_dash and not _is_occluded(prev_v) and not _is_occluded(v):
				draw_line(prev_pos, cur_pos, Color(1, 1, 1, alpha), 1.5, true)
			prev_v   = v
			prev_pos = cur_pos

		# ── Ship (pixel cross) ────────────────────────────────────────────────────
		var sv := _project(ship, ship.orbit_angle)
		if _is_occluded(sv):
			continue
		var spos := center + Vector2(sv.x, sv.y)
		var col  := Color(1.0, 0.92, 0.40) if ship == _hovered_ship else Color(1, 1, 1, 0.92)
		if ship.ship_type == "station":
			_draw_pixel_station(spos, col)
		else:
			_draw_pixel_ship(spos, col)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var prev := _hovered_ship
		_hovered_ship = _ship_at(event.global_position)
		if _hovered_ship != prev:
			queue_redraw()
			if _hovered_ship != null:
				ship_hovered.emit(_hovered_ship, event.global_position)
			else:
				ship_unhovered.emit()

func _ship_at(global_pos: Vector2) -> ShipData:
	if _planet_seed < 0 or _planet_radius <= 0.0:
		return null
	var center := get_global_rect().position + (_planet_center if _planet_center != Vector2.ZERO else size * 0.5)
	for ship: ShipData in ShipManager.ships_for(_planet_seed):
		var sv := _project(ship, ship.orbit_angle)
		if _is_occluded(sv):
			continue
		var spos := center + Vector2(sv.x, sv.y)
		if global_pos.distance_to(spos) <= 8.0:
			return ship
	return null
