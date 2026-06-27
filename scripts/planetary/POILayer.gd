extends Node2D

signal poi_clicked(index: int, data: Dictionary)

const DOT_RADIUS       := 5.0
const DOT_HOVER_RADIUS := 8.0
const LINE_DIAG_LEN    := 28.0
const LINE_HORIZ_LEN   := 52.0
const FONT_SIZE        := 15

var _planet: ColorRect
var _pois: Array[Dictionary] = []
var _hovered_index: int = -1

func setup(renderer: ColorRect) -> void:
	_planet = renderer
	set_process_input(true)

func clear_pois() -> void:
	_pois.clear()
	_hovered_index = -1

func add_poi(lon_deg: float, lat_deg: float, label: String, data: Dictionary = {}) -> void:
	_pois.append({
		"lon":    deg_to_rad(lon_deg),
		"lat":    deg_to_rad(lat_deg),
		"label":  label,
		"data":   data,
		"screen": Vector2.ZERO,
		"visible": false,
		"alpha":  0.0,
	})

func _get_planet_params() -> Dictionary:
	if not _planet or not _planet.material:
		return {}
	var center := _planet.global_position + _planet.size * 0.5
	var radius_frac: float = _planet.material.get_shader_parameter("planet_radius")
	var aspect: float      = _planet.material.get_shader_parameter("aspect_ratio")
	var r_px := _planet.size.y * radius_frac  # radius in screen pixels (based on height)
	return {"center": center, "r_px": r_px, "aspect": aspect}

func _get_rotation() -> float:
	if _planet and _planet.has_method("get_rotation_offset"):
		return _planet.get_rotation_offset()
	return 0.0

func _process(_delta: float) -> void:
	if not _planet:
		return
	var p := _get_planet_params()
	if p.is_empty():
		return
	var center: Vector2 = p["center"]
	var r_px: float     = p["r_px"]
	var rot: float      = _get_rotation()

	for poi in _pois:
		var lon: float = poi["lon"] - rot
		var lat: float = poi["lat"]
		var sx  := sin(lon) * cos(lat)
		var sy  := -sin(lat)
		var sz  := cos(lon) * cos(lat)

		poi["screen"]  = center + Vector2(sx * r_px, sy * r_px)
		poi["alpha"]   = clamp(sz * 4.0, 0.0, 1.0)
		poi["visible"] = sz > -0.05
		poi["lat_f"]   = lat   # store for direction

	queue_redraw()

var _orbitron: Font

func _ready() -> void:
	_orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")

func _draw() -> void:
	if _pois.is_empty():
		return
	var font: Font = _orbitron if _orbitron else ThemeDB.fallback_font

	for i in _pois.size():
		var poi: Dictionary = _pois[i]
		if not poi["visible"]:
			continue

		var alpha: float  = poi["alpha"]
		var sp: Vector2   = poi["screen"] - global_position
		var lat: float    = poi["lat_f"]
		var hovered: bool = (i == _hovered_index)

		# direction: away from equator (north→up, south→down)
		var vert_dir: float = -sign(lat) if abs(lat) > 0.05 else -1.0
		# horizontal: use sine of effective longitude — positive lon half → right
		# This avoids screen-space center flip when POI crosses center
		var eff_lon: float = poi["lon"] - _get_rotation()
		var horiz_dir: float = sign(sin(eff_lon))
		if horiz_dir == 0.0:
			horiz_dir = 1.0

		var diag_end := sp + Vector2(horiz_dir * LINE_DIAG_LEN * 0.7, vert_dir * LINE_DIAG_LEN)
		var horiz_end := diag_end + Vector2(horiz_dir * LINE_HORIZ_LEN, 0.0)

		var col := Color(0.85, 0.85, 0.85, alpha * 0.9)
		var dot_col := Color(1.0, 0.82, 0.25, alpha) if not hovered else Color(1.0, 0.95, 0.5, alpha)
		var dot_r   := DOT_HOVER_RADIUS if hovered else DOT_RADIUS

		# dot
		draw_circle(sp, dot_r + 1.5, Color(0, 0, 0, alpha * 0.5))
		draw_circle(sp, dot_r, dot_col)

		# leader lines
		draw_line(sp, diag_end, col, 1.0, true)
		draw_line(diag_end, horiz_end, col, 1.0, true)

		# label
		var label: String = poi["label"]
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		var label_pos := horiz_end + Vector2(horiz_dir * 3.0, text_size.y * 0.35)
		if horiz_dir < 0.0:
			label_pos.x -= text_size.x

		# thick outline
		var oc := Color(0.0, 0.0, 0.0, alpha * 0.90)
		for ox: int in [-1, 0, 1]:
			for oy: int in [-1, 0, 1]:
				if ox == 0 and oy == 0:
					continue
				draw_string(font, label_pos + Vector2(ox * 1.5, oy * 1.5), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, oc)
		# foreground
		var fc := Color(1.0, 0.95, 0.5, alpha) if hovered else Color(1.0, 1.0, 1.0, alpha)
		draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, fc)

		# hover ring
		if hovered:
			draw_arc(sp, dot_r + 3.0, 0, TAU, 20, Color(1, 0.95, 0.5, alpha * 0.6), 1.0)

func _input(event: InputEvent) -> void:
	if not _planet:
		return

	if event is InputEventMouseMotion:
		var prev := _hovered_index
		_hovered_index = _get_poi_at(event.global_position)
		if _hovered_index != prev:
			queue_redraw()
			if _hovered_index >= 0:
				CursorManager.set_state(CursorManager.State.POINTER)
			else:
				CursorManager.set_state(CursorManager.State.NORMAL)

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx := _get_poi_at(event.global_position)
		if idx >= 0:
			poi_clicked.emit(idx, _pois[idx]["data"])
			get_viewport().set_input_as_handled()

func _get_poi_at(global_pos: Vector2) -> int:
	for i in _pois.size():
		var poi: Dictionary = _pois[i]
		if not poi["visible"] or poi["alpha"] < 0.3:
			continue
		var sp: Vector2 = poi["screen"]
		if global_pos.distance_to(sp) <= DOT_HOVER_RADIUS + 4.0:
			return i
	return -1
