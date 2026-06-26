extends Control

@export var galaxy_seed: int = 42

const ZOOM_MIN     := 0.25
const ZOOM_MAX     := 4.0
const TILT_MIN     := 0.20
const TILT_MAX     := 0.90
const ENTRY_CHARGE := 4   # scroll-in steps on a star to trigger entry

const STAR_R: Dictionary = {
	SolarData.StarType.WHITE_DWARF:     2.5,
	SolarData.StarType.RED_DWARF:       3.0,
	SolarData.StarType.YELLOW_DWARF:    3.5,
	SolarData.StarType.ORANGE_SUBGIANT: 4.0,
	SolarData.StarType.BLUE_GIANT:      5.5,
}
const STAR_COL: Dictionary = {
	SolarData.StarType.WHITE_DWARF:     Color(0.88, 0.92, 1.00),
	SolarData.StarType.RED_DWARF:       Color(1.00, 0.40, 0.28),
	SolarData.StarType.YELLOW_DWARF:    Color(1.00, 0.92, 0.55),
	SolarData.StarType.ORANGE_SUBGIANT: Color(1.00, 0.65, 0.30),
	SolarData.StarType.BLUE_GIANT:      Color(0.55, 0.75, 1.00),
}

var _galaxy:    GalaxyData
var _offset:    Vector2 = Vector2.ZERO
var _zoom:      float   = 1.0
var _tilt:      float   = 0.52

var _dragging:      bool    = false
var _drag_from:     Vector2 = Vector2.ZERO
var _tilt_dragging: bool    = false
var _rotation:      float   = 0.0   # horizontal galaxy rotation (radians)

var _entry_charge:  int  = 0
var _entry_target:  int  = -1
var _entering:      bool = false

var _hovered: int   = -1
var _pulse:   float = 0.0
var _orbitron: Font

func _ready() -> void:
	_orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")
	var gd: GalaxyData = SceneTransition.pending_data as GalaxyData
	if gd != null:
		SceneTransition.pending_data = null
		_galaxy = gd
	else:
		_galaxy = GalaxyData.from_seed(galaxy_seed)

	await get_tree().process_frame
	# restore saved camera or default to center
	if _galaxy.view_zoom > 0.0:
		_offset   = _galaxy.view_offset
		_zoom     = _galaxy.view_zoom
		_tilt     = _galaxy.view_tilt
		_rotation = _galaxy.view_rotation
	else:
		_offset = size * 0.5

func _process(delta: float) -> void:
	_pulse = fposmod(_pulse + delta * 1.8, TAU)
	var mouse   := get_viewport().get_mouse_position()
	var new_hov := -1
	for i in _galaxy.star_count():
		if not _galaxy.is_visible(i):
			continue
		if _star_screen_pos(i).distance_to(mouse) < _hit_radius(i):
			new_hov = i
			break
	if new_hov != _hovered:
		_hovered = new_hov
		if _entry_target != _hovered:
			_entry_charge = 0
			_entry_target = -1
		Input.set_default_cursor_shape(
			Input.CURSOR_POINTING_HAND if _hovered >= 0 else Input.CURSOR_ARROW)
	queue_redraw()

func _star_screen_pos(i: int) -> Vector2:
	var p  := _galaxy.positions[i]
	# rotate in world space (turntable around vertical axis)
	var rx := p.x * cos(_rotation) - p.y * sin(_rotation)
	var ry := p.x * sin(_rotation) + p.y * cos(_rotation)
	return Vector2(rx * _zoom, ry * _tilt * _zoom) + _offset

func _hit_radius(i: int) -> float:
	return float(STAR_R.get(_galaxy.types[i], 3.5)) * _zoom + 10.0

func _draw() -> void:
	if _galaxy == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.09, 1))
	_draw_lanes()
	_draw_stars()

func _draw_lanes() -> void:
	for link: Vector2i in _galaxy.links:
		if not (_galaxy.is_visible(link.x) and _galaxy.is_visible(link.y)):
			continue
		var a := _star_screen_pos(link.x)
		var b := _star_screen_pos(link.y)
		var bright := _galaxy.is_unlocked(link.x) and _galaxy.is_unlocked(link.y)
		draw_line(a, b, Color(0.35, 0.55, 0.90, 0.08 if not bright else 0.13), 3.5, true)
		draw_line(a, b, Color(0.45, 0.65, 1.00, 0.18 if not bright else 0.38), 1.2, true)

func _draw_stars() -> void:
	for i in _galaxy.star_count():
		if not _galaxy.is_visible(i):
			continue
		var pos:     Vector2 = _star_screen_pos(i)
		var stype:   int     = _galaxy.types[i]
		var col:     Color   = STAR_COL.get(stype, Color.WHITE)
		var r:       float   = float(STAR_R.get(stype, 3.5)) * _zoom
		var unlocked := _galaxy.is_unlocked(i)
		var is_home  := (i == _galaxy.home_idx)
		var is_hov   := (i == _hovered)
		var alpha    := 1.0 if unlocked else 0.38

		# entry-charge progress arc
		if is_hov and _entry_charge > 0 and _entry_target == i:
			var frac: float = float(_entry_charge) / float(ENTRY_CHARGE)
			draw_arc(pos, r * (3.2 + frac * 1.8), 0.0, TAU * frac, 64,
				Color(col.r, col.g, col.b, 0.60 * frac), 2.0)

		draw_circle(pos, r * (2.8 + 0.4 * sin(_pulse) if is_home else 2.2),
			Color(col.r, col.g, col.b, (0.14 if is_home else 0.07) * alpha))
		draw_circle(pos, (r * 1.4 if is_hov else r) + 1.2,
			Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, 0.5 * alpha))
		draw_circle(pos, r * 1.4 if is_hov else r, Color(col.r, col.g, col.b, alpha))

		if is_home:
			draw_arc(pos, r * (3.4 + 0.5 * sin(_pulse)), 0.0, TAU, 48,
				Color(col.r, col.g, col.b, 0.30 + 0.15 * sin(_pulse)), 1.2)

		if not unlocked:
			draw_arc(pos, r * 2.2, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.25), 1.0)

		if is_home or is_hov:
			_draw_callout(pos, _galaxy.names[i], col, r, unlocked or is_home)

func _draw_callout(pos: Vector2, label: String, col: Color, r: float, bright: bool) -> void:
	if _orbitron == null:
		return
	# direction: away from galaxy center (screen center = _offset)
	var raw: Vector2 = pos - _offset
	var dir: Vector2
	if raw.length() > 8.0:
		dir = raw.normalized()
		# un-apply tilt so the direction is in world-space
		dir = Vector2(dir.x, dir.y / max(_tilt, 0.05)).normalized()
	else:
		dir = Vector2(1.0, -0.5).normalized()

	var line_start := pos + dir * (r + 4.0)
	var line_end   := pos + dir * (r + 22.0)
	var a := 0.50 if bright else 0.28
	draw_line(line_start, line_end, Color(col.r, col.g, col.b, a), 1.0, true)
	draw_circle(line_end, 2.0, Color(col.r, col.g, col.b, a * 1.3))

	var sz := 9
	var ts  := _orbitron.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
	var lp  := line_end + (Vector2(5.0, ts.y * 0.35) if dir.x >= 0.0 else Vector2(-ts.x - 5.0, ts.y * 0.35))
	draw_string(_orbitron, lp + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.85))
	draw_string(_orbitron, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, sz,
		Color(col.r, col.g, col.b, 0.90 if bright else 0.50))

func _input(event: InputEvent) -> void:
	if _entering:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					if mb.double_click and _hovered >= 0:
						_entering = true
						_navigate_to(_hovered)
						return
					_dragging  = true
					_drag_from = mb.position
				else:
					# single click with minimal drag = enter star
					if _hovered >= 0 and mb.position.distance_to(_drag_from) < 6.0:
						_entering = true
						_navigate_to(_hovered)
					_dragging = false
			MOUSE_BUTTON_RIGHT:
				_tilt_dragging = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if _hovered >= 0:
					# hovering a star: never zoom map, only charge entry
					_charge_entry(1)
				else:
					_zoom_at(mb.position, 1.12)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(mb.position, 1.0 / 1.12)
				_reset_charge()

	elif event is InputEventMagnifyGesture:
		if event.factor > 1.0:
			if _hovered >= 0:
				_charge_entry(1)
			else:
				_zoom_at(event.position, event.factor)
		else:
			_zoom_at(event.position, event.factor)
			_reset_charge()

	elif event is InputEventPanGesture:
		var dy: float = event.delta.y
		if abs(dy) > 0.1:
			var factor := 1.0 - dy * 0.04
			if factor > 1.0:
				if _hovered >= 0:
					_charge_entry(1)
				else:
					_zoom_at(event.position, factor)
			else:
				_zoom_at(event.position, factor)
				_reset_charge()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _tilt_dragging:
			# right-drag X = horizontal rotation, Y = tilt
			_rotation = fposmod(_rotation - mm.relative.x * 0.005, TAU)
			_tilt      = clamp(_tilt + mm.relative.y * 0.004, TILT_MIN, TILT_MAX)
			get_viewport().set_input_as_handled()
		elif _dragging and mm.relative.length() > 0.5:
			_offset += mm.relative
			get_viewport().set_input_as_handled()

func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom: float = clamp(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_offset = screen_pos + (_offset - screen_pos) * (new_zoom / _zoom)
	_zoom   = new_zoom

func _charge_entry(amount: int) -> void:
	if _hovered < 0:
		_reset_charge()
		return
	if _entry_target != _hovered:
		_entry_charge = 0
		_entry_target = _hovered
	_entry_charge += amount
	if _entry_charge >= ENTRY_CHARGE:
		_entering = true
		_navigate_to(_hovered)

func _reset_charge() -> void:
	_entry_charge = 0
	_entry_target = -1

func _navigate_to(star_idx: int) -> void:
	_galaxy.unlock(star_idx)
	# save camera so we restore it on return
	_galaxy.view_offset   = _offset
	_galaxy.view_zoom     = _zoom
	_galaxy.view_tilt     = _tilt
	_galaxy.view_rotation = _rotation
	var sd := SolarData.from_seed(_galaxy.seeds[star_idx])
	sd.system_name = _galaxy.names[star_idx]
	sd.star_type   = _galaxy.types[star_idx] as SolarData.StarType
	sd.set_meta("__galaxy_data", _galaxy)
	SceneTransition.go("res://scenes/solar/SolarView.tscn", sd)
