## Draws orbital ships with proper Y-axis (longitude) rotation.
## Ships on the far side of the planet are hidden behind it.
class_name OrbitalLayer
extends Control

var _planet_seed:     int     = -1
var _planet_radius:   float   = 0.0
var _planet_rotation: float   = 0.0   # Y-axis rotation (longitude) from planet drag
var _planet_center:   Vector2 = Vector2.ZERO   # actual planet center in local coords
var _hovered_ship:    ShipData = null

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
	for ship: ShipData in ShipManager.ships_for(_planet_seed):
		ship.orbit_angle += ship.orbit_speed * delta
	queue_redraw()

func _on_ship_changed(ship: ShipData) -> void:
	if ship.orbit_seed == _planet_seed:
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

## Pixel-art cross: 2×2 blocks — large enough to read, sprite-feel.
func _draw_pixel_ship(pos: Vector2, col: Color) -> void:
	var p   := (pos - Vector2.ONE).floor()   # snap to even grid
	var sz  := Vector2(2, 2)
	draw_rect(Rect2(p,                          sz), col)   # center
	draw_rect(Rect2(p + Vector2(-2,  0),        sz), col)   # left
	draw_rect(Rect2(p + Vector2( 2,  0),        sz), col)   # right
	draw_rect(Rect2(p + Vector2( 0, -2),        sz), col)   # up
	draw_rect(Rect2(p + Vector2( 0,  2),        sz), col)   # down

func _draw() -> void:
	if _planet_seed < 0 or _planet_radius <= 0.0:
		return
	var center := _planet_center if _planet_center != Vector2.ZERO else size * 0.5

	for ship: ShipData in ShipManager.ships_for(_planet_seed):
		# ── Orbit path — dash-dash: 3 segments on, 3 off ────────────────────────
		var steps := 90   # divisible by 6 for clean dash repeat
		var alpha: float = 0.30 if not ship.is_travelling() else 0.45
		var prev_v   := _project(ship, 0.0)
		var prev_pos := center + Vector2(prev_v.x, prev_v.y)
		for s in range(1, steps + 1):
			var a: float = (float(s) / float(steps)) * TAU
			var v        := _project(ship, a)
			var cur_pos  := center + Vector2(v.x, v.y)
			# dash pattern: draw 3, skip 3
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
