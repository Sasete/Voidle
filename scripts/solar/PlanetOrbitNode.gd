class_name PlanetOrbitNode
extends Node2D

signal clicked(planet_data: PlanetData)
signal hover_start(planet_data: PlanetData)
signal hover_end

const SIZE := 40

var planet_data:    PlanetData
var orbit_radius_x: float
var orbit_radius_y: float
var angle:          float

var _view_angle:      float = 0.0
var _side:            float = 1.0
var _rotation_offset: float = 0.0
var _spin_speed:      float = 0.0
var _moon_nodes:      Array[MoonOrbitNode] = []
var _moon_base_pos:   Array[Vector2]       = []
var _mini:        ColorRect
var _hover_label: Label
var _ring_front:  Node2D   # child drawn on top of planet for ring front half
var _hover:       bool   = false
var _height:      float  = 0.0
var _hover_tween: Tween  = null
var _is_home:     bool   = false

func setup(data: PlanetData, radius_x: float, start_angle: float) -> void:
	planet_data    = data
	orbit_radius_x = radius_x
	orbit_radius_y = radius_x * 0.38
	angle          = start_angle
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed ^ 0xF00D
	_spin_speed      = rng.randf_range(0.06, 0.18)
	_rotation_offset = rng.randf_range(0.0, TAU)
	_height          = rng.randf_range(-28.0, 28.0)
	_build()
	_build_moons(data)
	_update_position()

func _process(delta: float) -> void:
	_rotation_offset = fposmod(_rotation_offset + _spin_speed * delta, TAU)
	if _mini and _mini.material:
		(_mini.material as ShaderMaterial).set_shader_parameter("rotation_offset", _rotation_offset)
	# keep rings in sync with _mini scale during hover tween; pulse home marker
	if _is_home or _hover or (_mini and _mini.scale.x > 1.01):
		queue_redraw()
		if _ring_front:
			_ring_front.queue_redraw()

func set_view_angle(va: float) -> void:
	_view_angle = va
	_update_position()

func set_tilt(ratio: float) -> void:
	orbit_radius_y = orbit_radius_x * ratio
	for moon in _moon_nodes:
		moon.set_tilt(ratio)
	_update_position()
	for i in _moon_nodes.size():
		_moon_base_pos[i] = _moon_nodes[i].position
	if _ring_front:
		_ring_front.queue_redraw()

func _build() -> void:
	_mini              = ColorRect.new()
	_mini.size         = Vector2(SIZE, SIZE)
	_mini.position     = -Vector2(SIZE, SIZE) * 0.5
	_mini.pivot_offset = Vector2(SIZE, SIZE) * 0.5   # scale from center
	_mini.mouse_filter = Control.MOUSE_FILTER_STOP

	var shader_path := PlanetData.get_shader_path(planet_data.planet_type)
	var mat         := ShaderMaterial.new()
	mat.shader       = load(shader_path)

	mat.set_shader_parameter("planet_radius",     0.40)
	mat.set_shader_parameter("pixel_count",       float(SIZE))
	mat.set_shader_parameter("aspect_ratio",      1.0)
	mat.set_shader_parameter("seed",              planet_data.seed)
	mat.set_shader_parameter("terrain_roughness", planet_data.terrain_roughness)
	mat.set_shader_parameter("rotation_offset",   0.0)

	var stype := PlanetData.get_shader_type(planet_data.planet_type)
	match stype:
		PlanetData.ShaderType.ROCKY:
			mat.set_shader_parameter("sea_level",          planet_data.sea_level)
			mat.set_shader_parameter("continent_scale",    planet_data.continent_scale)
			mat.set_shader_parameter("has_clouds",         0.0)
			mat.set_shader_parameter("atmosphere_density",
				planet_data.atmosphere_density if planet_data.has_atmosphere else 0.0)
			mat.set_shader_parameter("specular_strength",  planet_data.specular_strength)
			mat.set_shader_parameter("city_lights",        0.0)
			mat.set_shader_parameter("poi_count",          0)
			for key in PlanetData.get_colors(planet_data.planet_type):
				mat.set_shader_parameter(key, PlanetData.get_colors(planet_data.planet_type)[key])
		PlanetData.ShaderType.GAS:
			mat.set_shader_parameter("cloud_speed",        0.0)
			mat.set_shader_parameter("atmosphere_density", planet_data.atmosphere_density)
			var c := PlanetData.get_colors(planet_data.planet_type)
			mat.set_shader_parameter("color_band_a",    c.get("color_sand",       Vector3(0.72,0.55,0.35)))
			mat.set_shader_parameter("color_band_b",    c.get("color_forest",     Vector3(0.50,0.32,0.18)))
			mat.set_shader_parameter("color_storm",     c.get("color_snow",       Vector3(0.88,0.82,0.72)))
			mat.set_shader_parameter("color_atmosphere",c.get("color_atmosphere", Vector3(0.72,0.55,0.35)))
		PlanetData.ShaderType.MOON:
			var c := PlanetData.get_colors(planet_data.planet_type)
			mat.set_shader_parameter("color_highland", c.get("color_mountain",   Vector3(0.62,0.60,0.56)))
			mat.set_shader_parameter("color_mare",     c.get("color_deep_ocean", Vector3(0.22,0.21,0.20)))
			mat.set_shader_parameter("color_rim",      c.get("color_snow",       Vector3(0.78,0.76,0.72)))
			mat.set_shader_parameter("color_floor",    c.get("color_ocean",      Vector3(0.16,0.15,0.14)))
		PlanetData.ShaderType.ASTEROID:
			mat.set_shader_parameter("irregularity", planet_data.irregularity)
			mat.set_shader_parameter("elongation",   1.0 + planet_data.irregularity * 0.8)

	_mini.material = mat
	add_child(_mini)

	# ring front layer (drawn on top of planet sprite)
	if planet_data.has_rings:
		_ring_front = Node2D.new()
		add_child(_ring_front)
		_ring_front.draw.connect(_on_ring_front_draw)

	_mini.mouse_entered.connect(_on_hover_start)
	_mini.mouse_exited.connect(_on_hover_end)
	_mini.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(planet_data)
	)

	_hover_label = Label.new()
	_hover_label.text    = planet_data.planet_name
	var _orbitron := load("res://Fonts/Orbitron-VariableFont_wght.ttf") as Font
	if _orbitron:
		_hover_label.add_theme_font_override("font", _orbitron)
	_hover_label.add_theme_font_size_override("font_size", 13)
	_hover_label.add_theme_color_override("font_color",         Color(1.0, 1.0, 1.0, 1.0))
	_hover_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_hover_label.add_theme_constant_override("outline_size",    4)
	_hover_label.add_theme_color_override("font_shadow_color",  Color(0.0, 0.0, 0.0, 0.8))
	_hover_label.add_theme_constant_override("shadow_offset_x", 2)
	_hover_label.add_theme_constant_override("shadow_offset_y", 2)
	_hover_label.z_as_relative = false
	_hover_label.z_index       = 200    # always on top of everything
	_hover_label.visible       = false
	add_child(_hover_label)

func _build_moons(data: PlanetData) -> void:
	if data.moons.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed ^ 0x1234
	for i in data.moons.size():
		var moon_rx:  float = 22.0 + i * 12.0
		var start:    float = rng.randf_range(0.0, TAU)
		var node := MoonOrbitNode.new()
		add_child(node)
		node.setup(data.moons[i], moon_rx, start)
		_moon_nodes.append(node)
		_moon_base_pos.append(node.position)

func _on_hover_start() -> void:
	_hover = true
	_hover_label.visible = true
	hover_start.emit(planet_data)
	await get_tree().process_frame
	_update_label_position()
	queue_redraw()
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(_mini, "scale", Vector2(1.9, 1.9), 0.14)
	const S := 1.9
	for i in _moon_nodes.size():
		var moon := _moon_nodes[i]
		var mt := moon.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		mt.tween_property(moon, "scale",    Vector2(S, S),         0.14)
		mt.tween_property(moon, "position", _moon_base_pos[i] * S, 0.14)

func _on_hover_end() -> void:
	_hover = false
	hover_end.emit()
	queue_redraw()
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_hover_tween.tween_property(_mini, "scale", Vector2(1.0, 1.0), 0.12)
	for i in _moon_nodes.size():
		var moon := _moon_nodes[i]
		var mt := moon.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		mt.tween_property(moon, "scale",    Vector2(1.0, 1.0), 0.12)
		mt.tween_property(moon, "position", _moon_base_pos[i], 0.12)
	_hover_label.visible = false

func _ring_arc(target: CanvasItem, from_a: float, to_a: float,
		rx: float, yr: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	var steps := 36
	for s in steps + 1:
		var t := from_a + (to_a - from_a) * float(s) / float(steps)
		pts.append(Vector2(cos(t) * rx, sin(t) * rx * yr))
	target.draw_polyline(pts, col, w, true)

func _draw_rings(target: CanvasItem, from_a: float, to_a: float) -> void:
	if not planet_data or not planet_data.has_rings:
		return
	var scale_x: float = _mini.scale.x if _mini else 1.0
	var half: float    = float(SIZE) * 0.5 * scale_x
	var yr:   float    = orbit_radius_y / maxf(orbit_radius_x, 1.0)
	var ir:   float = half * planet_data.ring_inner
	var or_:  float = half * planet_data.ring_outer
	var col:  Color = planet_data.ring_color
	var bands: int  = 7
	for k in bands:
		var t:   float = float(k) / float(bands - 1)
		var rx:  float = lerp(ir, or_, t)
		var alp: float = col.a * lerp(0.55, 0.85, 1.0 - abs(t - 0.5) * 2.0)
		_ring_arc(target, from_a, to_a, rx, yr,
			Color(col.r, col.g, col.b, alp), 1.8)

func mark_as_home() -> void:
	_is_home = true
	queue_redraw()

func _on_ring_front_draw() -> void:
	_draw_rings(_ring_front, 0.0, PI)   # front half (closer to camera)

func _draw() -> void:
	# ring back half — drawn before planet child renders
	_draw_rings(self, PI, TAU)

	# home planet marker: pulsing golden arc
	if _is_home:
		var r: float  = float(SIZE) * 0.5 * (_mini.scale.x if _mini else 1.0) + 5.0
		var pulse_val := fposmod(Time.get_ticks_msec() * 0.002, TAU)
		var a: float  = 0.55 + 0.25 * sin(pulse_val)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(1.0, 0.88, 0.35, a), 1.5)

	if not _hover:
		return
	var half:  float = SIZE * 0.5
	var x0: float    = half * _side + 1.0 * _side
	var x1: float    = half * _side + 14.0 * _side
	draw_line(Vector2(x0, 0.0), Vector2(x1, 0.0), Color(1.0, 1.0, 1.0, 0.55), 1.0)

func _update_position() -> void:
	var eff:  float = angle + _view_angle
	var cx:   float = cos(eff)
	var z:    float = sin(eff)
	var y_ratio: float = orbit_radius_y / maxf(orbit_radius_x, 1.0)
	# height contributes to screen Y proportional to current tilt
	position   = Vector2(cx * orbit_radius_x, z * orbit_radius_y + _height * y_ratio)
	modulate.a = lerp(0.35, 1.0, (z + 1.0) * 0.5)

	z_as_relative = false
	z_index = 20 if z < 0.0 else 80

	# side determines label/line direction: positive x = right, negative = left
	_side = sign(cx) if abs(cx) > 0.05 else 1.0
	_update_label_position()

	var ld := Vector3(-cx, -z * 0.6, 0.5).normalized()
	if _mini and _mini.material:
		(_mini.material as ShaderMaterial).set_shader_parameter("light_direction", ld)
	queue_redraw()
	if _ring_front:
		_ring_front.queue_redraw()

func _update_label_position() -> void:
	if _hover_label == null:
		return
	var half:  float = SIZE * 0.5
	var gap:   float = 16.0
	if _side >= 0.0:
		# right side: label starts after the line
		_hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_hover_label.position = Vector2(half + gap, -8.0)
	else:
		# left side: label ends before the line, right-aligned relative to planet edge
		_hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var label_w: float = _hover_label.size.x if _hover_label.size.x > 0 else 80.0
		_hover_label.position = Vector2(-half - gap - label_w, -8.0)
	queue_redraw()
