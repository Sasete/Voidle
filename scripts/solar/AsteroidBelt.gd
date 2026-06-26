class_name AsteroidBelt
extends Node2D

var Y_RATIO: float  = 0.38
const DUST_COUNT   := 45
const RING_R       := 13.0      # targeting circle radius
const PREVIEW_SIZE := 80
const BOX_PAD      := 6.0
const LINE_GAP     := 8.0       # gap between ring edge and line start

var orbit_radius_x: float = 200.0
var _view_angle:    float = 0.0
var _hovered_idx:   int   = -1
var _spin:          float = 0.0  # rotation of dashed ring (radians)
var _names:         Array[String] = []

# background dust
var _dust_angles:  Array[float] = []
var _dust_offsets: Array[float] = []
var _dust_sizes:   Array[float] = []

# interactable asteroid slots
var _ast_angles:  Array[float] = []
var _ast_offsets: Array[float] = []
var _previews:    Array[ColorRect] = []
var _bg_panels:   Array[ColorRect] = []
var _name_labels: Array[Label]    = []

var _orbitron: Font

func setup(rx: float, seed: int, count: int = 3) -> void:
	orbit_radius_x = rx
	z_as_relative  = false
	z_index        = 10
	_orbitron      = load("res://Fonts/Orbitron-VariableFont_wght.ttf")

	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0xA5BE

	for _i in DUST_COUNT:
		_dust_angles.append(rng.randf_range(0.0, TAU))
		_dust_offsets.append(rng.randf_range(-22.0, 22.0))
		_dust_sizes.append(rng.randf_range(0.7, 2.0))

	for _i in count:
		_ast_angles.append(rng.randf_range(0.0, TAU))
		_ast_offsets.append(rng.randf_range(-12.0, 12.0))
		var ast_seed: int = rng.randi() % 99999
		_names.append(_gen_name(rng))
		_bg_panels.append(_make_bg_panel())
		_previews.append(_make_preview(ast_seed))
		_name_labels.append(_make_name_label())

	queue_redraw()

func _gen_name(rng: RandomNumberGenerator) -> String:
	var pre := ["AST","RKX","VLD","KRN","ZXN","MNR","PLT","CRD"]
	var num := rng.randi_range(100, 9999)
	return pre[rng.randi() % pre.size()] + "-" + str(num)

func _make_bg_panel() -> ColorRect:
	var bg           := ColorRect.new()
	bg.size          = Vector2(PREVIEW_SIZE + BOX_PAD * 2.0, PREVIEW_SIZE + BOX_PAD * 2.0 + 22.0)
	bg.color         = Color(0.03, 0.05, 0.10, 0.96)
	bg.visible       = false
	bg.z_as_relative = false
	bg.z_index       = 199
	add_child(bg)
	return bg

func _make_preview(seed_val: int) -> ColorRect:
	var rect           := ColorRect.new()
	rect.size          = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
	rect.visible       = false
	rect.z_as_relative = false
	rect.z_index       = 200
	var mat    := ShaderMaterial.new()
	mat.shader  = load("res://shaders/planet_asteroid.gdshader")
	mat.set_shader_parameter("planet_radius",     0.40)
	mat.set_shader_parameter("pixel_count",       float(PREVIEW_SIZE))
	mat.set_shader_parameter("aspect_ratio",      1.0)
	mat.set_shader_parameter("seed",              seed_val)
	mat.set_shader_parameter("terrain_roughness", 1.4)
	mat.set_shader_parameter("rotation_offset",   0.0)
	mat.set_shader_parameter("irregularity",      0.55)
	mat.set_shader_parameter("elongation",        1.45)
	mat.set_shader_parameter("light_direction",   Vector3(0.6, -0.55, 0.65))
	rect.material = mat
	add_child(rect)
	return rect

func _make_name_label() -> Label:
	var lbl := Label.new()
	if _orbitron:
		lbl.add_theme_font_override("font", _orbitron)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color",         Color(0.90, 0.88, 0.55, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	lbl.add_theme_constant_override("outline_size",    3)
	lbl.visible       = false
	lbl.z_as_relative = false
	lbl.z_index       = 201
	add_child(lbl)
	return lbl

func set_view_angle(va: float) -> void:
	_view_angle = va
	_refresh_popup()
	queue_redraw()

func set_tilt(ratio: float) -> void:
	Y_RATIO = ratio
	queue_redraw()

func _ast_pos(i: int) -> Vector2:
	var a  := _ast_angles[i] + _view_angle
	var rx := orbit_radius_x + _ast_offsets[i]
	return Vector2(cos(a) * rx, sin(a) * rx * Y_RATIO)

func _process(delta: float) -> void:
	_spin = fposmod(_spin + delta * 1.4, TAU)

	var mouse_l := get_local_mouse_position()
	var new_hov := -1
	for i in _ast_angles.size():
		if _ast_pos(i).distance_to(mouse_l) < RING_R + 12.0:
			new_hov = i
			break
	if new_hov != _hovered_idx:
		_hovered_idx = new_hov
		_refresh_popup()
	queue_redraw()

var _zoom_charge: int = 0

func _navigate_to_asteroid(idx: int) -> void:
	var ast_seed: int = idx * 0x1337 ^ int(orbit_radius_x) ^ 0xBEEF
	var pd := PlanetData.from_seed(ast_seed % 99999)
	pd.planet_type  = PlanetData.Type.ASTEROID
	pd.planet_name  = _names[idx]
	pd.irregularity = 0.55
	var solar: SolarData = get_tree().root.get_meta("__active_solar") as SolarData if get_tree().root.has_meta("__active_solar") else null
	pd.set_meta("__solar_data", solar)
	SceneTransition.go("res://scenes/planetary/PlanetaryView.tscn", pd)

func _input(event: InputEvent) -> void:
	if _hovered_idx < 0:
		_zoom_charge = 0
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_navigate_to_asteroid(_hovered_idx)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_charge += 1
			if _zoom_charge >= 3:
				_zoom_charge = 0
				_navigate_to_asteroid(_hovered_idx)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_charge = 0
	elif event is InputEventMagnifyGesture:
		if event.factor > 1.0:
			_zoom_charge += 1
			if _zoom_charge >= 3:
				_zoom_charge = 0
				_navigate_to_asteroid(_hovered_idx)
		else:
			_zoom_charge = 0
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		if event.delta.y < -0.5:
			_zoom_charge += 1
			if _zoom_charge >= 3:
				_zoom_charge = 0
				_navigate_to_asteroid(_hovered_idx)
		elif event.delta.y > 0.5:
			_zoom_charge = 0
		get_viewport().set_input_as_handled()

static func _popup_box_origin(ast_pos: Vector2) -> Vector2:
	var side := 1.0 if ast_pos.x >= 0.0 else -1.0
	var bx   := ast_pos.x + side * (RING_R + LINE_GAP)
	if side < 0.0:
		bx -= PREVIEW_SIZE + BOX_PAD * 2.0
	var by := ast_pos.y - PREVIEW_SIZE * 0.5 - BOX_PAD
	return Vector2(bx, by)

func _refresh_popup() -> void:
	for i in _previews.size():
		var hov := (i == _hovered_idx)
		_previews[i].visible    = hov
		_bg_panels[i].visible   = hov
		_name_labels[i].visible = hov
		if hov:
			var pos    := _ast_pos(i)
			var origin := _popup_box_origin(pos)   # top-left of border box (local Node2D space)
			_previews[i].position  = origin + Vector2(BOX_PAD, BOX_PAD)
			_bg_panels[i].position = origin
			var lbl := _name_labels[i]
			lbl.text     = _names[i]
			lbl.position = origin + Vector2(BOX_PAD, float(PREVIEW_SIZE) + BOX_PAD * 2.0 + 4.0)

func _draw() -> void:
	# background dust
	for i in _dust_angles.size():
		var a:   float = _dust_angles[i] + _view_angle
		var rx:  float = orbit_radius_x + _dust_offsets[i]
		var z:   float = sin(a)
		var pos: Vector2 = Vector2(cos(a) * rx, z * rx * Y_RATIO)
		var dust_a: float = lerp(0.45, 0.90, (z + 1.0) * 0.5)
		draw_circle(pos, _dust_sizes[i], Color(0.82, 0.78, 0.72, dust_a))

	# targeting cursors
	for i in _ast_angles.size():
		var a:   float   = _ast_angles[i] + _view_angle
		var z:   float   = sin(a)
		var pos: Vector2 = _ast_pos(i)
		var alp: float   = lerp(0.40, 1.0, (z + 1.0) * 0.5)
		var hov: bool    = (i == _hovered_idx)

		if hov:
			_draw_spinning_ring(pos, RING_R, alp)
			_draw_popup_line_and_box(pos, alp, i)
		else:
			_draw_idle_ring(pos, RING_R * 0.75, alp)

func _draw_idle_ring(center: Vector2, r: float, alp: float) -> void:
	# small static dashed circle — 4 arc segments
	var col := Color(0.68, 0.64, 0.50, alp)
	var segs := 4
	for s in segs:
		var a0: float = (float(s) / float(segs)) * TAU
		var a1: float = a0 + TAU / float(segs) * 0.55
		draw_arc(center, r, a0, a1, 12, col, 1.2)

func _draw_spinning_ring(center: Vector2, r: float, alp: float) -> void:
	var col  := Color(1.0, 0.92, 0.40, alp)
	var segs := 6
	for s in segs:
		var a0: float = (float(s) / float(segs)) * TAU + _spin
		var a1: float = a0 + TAU / float(segs) * 0.55
		draw_arc(center, r, a0, a1, 16, col, 1.8)
	# center dot
	draw_circle(center, 2.0, Color(1.0, 0.92, 0.40, alp * 0.8))

func _draw_popup_line_and_box(center: Vector2, alp: float, idx: int) -> void:
	var side   := 1.0 if center.x >= 0.0 else -1.0
	var origin := _popup_box_origin(center)   # top-left of border box
	var bw     := float(PREVIEW_SIZE + int(BOX_PAD) * 2)
	var bh     := float(PREVIEW_SIZE + int(BOX_PAD) * 2)

	# short horizontal line from ring edge to box border
	var line_start := center + Vector2(side * RING_R, 0.0)
	var line_end   := Vector2(origin.x + (bw if side < 0.0 else 0.0), center.y)
	draw_line(line_start, line_end, Color(1.0, 0.92, 0.40, alp * 0.85), 1.2, true)

	# border box
	draw_rect(Rect2(origin, Vector2(bw, bh)),
		Color(1.0, 0.92, 0.40, alp * 0.75), false, 1.5)
	# inner fill
	draw_rect(Rect2(origin + Vector2(1, 1), Vector2(bw - 2.0, bh - 2.0)),
		Color(0.05, 0.08, 0.14, alp * 0.65), true)
