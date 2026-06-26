extends Control

@export var galaxy_seed: int = 42

const TILT    := 0.52          # Y-axis compression for Stellaris-like overhead tilt
const ZOOM_MIN := 0.25
const ZOOM_MAX := 3.5

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
var _dragging:  bool    = false
var _drag_from: Vector2 = Vector2.ZERO
var _hovered:   int     = -1
var _pulse:     float   = 0.0
var _orbitron:  Font

func _ready() -> void:
	_orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")
	var gd: GalaxyData = SceneTransition.pending_data as GalaxyData
	if gd != null:
		SceneTransition.pending_data = null
		_galaxy = gd
	else:
		_galaxy = GalaxyData.from_seed(galaxy_seed)

	await get_tree().process_frame
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
		Input.set_default_cursor_shape(
			Input.CURSOR_POINTING_HAND if _hovered >= 0 else Input.CURSOR_ARROW)
	queue_redraw()

func _star_screen_pos(i: int) -> Vector2:
	var p := _galaxy.positions[i] * _zoom
	return Vector2(p.x, p.y * TILT) + _offset

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
		var a_vis := _galaxy.is_visible(link.x)
		var b_vis := _galaxy.is_visible(link.y)
		if not (a_vis and b_vis):
			continue
		var a := _star_screen_pos(link.x)
		var b := _star_screen_pos(link.y)
		var a_unl := _galaxy.is_unlocked(link.x)
		var b_unl := _galaxy.is_unlocked(link.y)
		var bright := a_unl and b_unl
		# glow
		draw_line(a, b, Color(0.35, 0.55, 0.90, 0.08 if not bright else 0.13), 3.5, true)
		# core
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

		var alpha := 1.0 if unlocked else 0.38

		# glow
		draw_circle(pos, r * (2.8 + 0.4 * sin(_pulse) if is_home else 2.2),
			Color(col.r, col.g, col.b, (0.14 if is_home else 0.07) * alpha))
		# shadow
		draw_circle(pos, (r * 1.4 if is_hov else r) + 1.2,
			Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, 0.5 * alpha))
		# body
		draw_circle(pos, r * 1.4 if is_hov else r, Color(col.r, col.g, col.b, alpha))

		# home pulse ring
		if is_home:
			draw_arc(pos, r * (3.4 + 0.5 * sin(_pulse)), 0.0, TAU, 48,
				Color(col.r, col.g, col.b, 0.30 + 0.15 * sin(_pulse)), 1.2)

		# label: always for home, only on hover for others
		if is_home or is_hov:
			_draw_label(pos, _galaxy.names[i], col, r, unlocked or is_home)

		# lock icon for visible-but-not-yet-unlocked
		if not unlocked:
			draw_arc(pos, r * 2.2, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.25), 1.0)

func _draw_label(pos: Vector2, label: String, col: Color, r: float, bright: bool) -> void:
	if _orbitron == null:
		return
	var sz := 10
	var ts  := _orbitron.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
	var lp  := pos + Vector2(r + 9.0, ts.y * 0.35)
	draw_string(_orbitron, lp + Vector2(1, 1), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.85))
	draw_string(_orbitron, lp, label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, sz,
		Color(col.r, col.g, col.b, 0.90 if bright else 0.50))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_dragging  = true
					_drag_from = mb.position
				elif mb.position.distance_to(_drag_from) < 5.0 and _hovered >= 0:
					_navigate_to(_hovered)
					_dragging = false
				else:
					_dragging = false
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(mb.position, 1.12)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(mb.position, 1.0 / 1.12)
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if mm.relative.length() > 0.5:
			_offset += mm.relative
			get_viewport().set_input_as_handled()

func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom: float = clamp(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	# zoom toward cursor: adjust offset so the point under cursor stays fixed
	_offset = screen_pos + (_offset - screen_pos) * (new_zoom / _zoom)
	_zoom   = new_zoom

func _navigate_to(star_idx: int) -> void:
	_galaxy.unlock(star_idx)
	var sd := SolarData.from_seed(_galaxy.seeds[star_idx])
	sd.system_name = _galaxy.names[star_idx]
	sd.star_type   = _galaxy.types[star_idx] as SolarData.StarType
	sd.set_meta("__galaxy_data", _galaxy)
	SceneTransition.go("res://scenes/solar/SolarView.tscn", sd)
