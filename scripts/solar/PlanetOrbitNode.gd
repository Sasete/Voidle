class_name PlanetOrbitNode
extends Node2D

signal clicked(planet_data: PlanetData)

const SIZE := 40

var planet_data:    PlanetData
var orbit_radius_x: float
var orbit_radius_y: float
var angle:          float

var _view_angle:      float = 0.0
var _side:            float = 1.0
var _rotation_offset: float = 0.0
var _spin_speed:      float = 0.0   # rad/s, set in setup
var _mini:        ColorRect
var _hover_label: Label
var _hover:       bool = false

func setup(data: PlanetData, radius_x: float, start_angle: float) -> void:
	planet_data    = data
	orbit_radius_x = radius_x
	orbit_radius_y = radius_x * 0.38
	angle          = start_angle
	# each planet spins at a slightly different speed (seed-based)
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed ^ 0xF00D
	_spin_speed      = rng.randf_range(0.06, 0.18)
	_rotation_offset = rng.randf_range(0.0, TAU)
	_build()
	_update_position()

func _process(delta: float) -> void:
	_rotation_offset = fposmod(_rotation_offset + _spin_speed * delta, TAU)
	if _mini and _mini.material:
		(_mini.material as ShaderMaterial).set_shader_parameter("rotation_offset", _rotation_offset)

func set_view_angle(va: float) -> void:
	_view_angle = va
	_update_position()

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

	_mini.mouse_entered.connect(_on_hover_start)
	_mini.mouse_exited.connect(_on_hover_end)
	_mini.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(planet_data)
	)

	_hover_label = Label.new()
	_hover_label.text    = planet_data.planet_name
	_hover_label.add_theme_font_size_override("font_size", 14)
	_hover_label.add_theme_color_override("font_color",              Color(1.0, 1.0, 1.0, 1.0))
	_hover_label.add_theme_color_override("font_outline_color",      Color(0.0, 0.0, 0.0, 1.0))
	_hover_label.add_theme_constant_override("outline_size",         4)
	_hover_label.add_theme_color_override("font_shadow_color",       Color(0.0, 0.0, 0.0, 0.8))
	_hover_label.add_theme_constant_override("shadow_offset_x",      2)
	_hover_label.add_theme_constant_override("shadow_offset_y",      2)
	_hover_label.visible = false
	add_child(_hover_label)

func _on_hover_start() -> void:
	_hover = true
	_hover_label.visible = true
	# let label compute its size before positioning
	await get_tree().process_frame
	_update_label_position()
	queue_redraw()
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_mini, "scale", Vector2(1.9, 1.9), 0.14)

func _on_hover_end() -> void:
	_hover = false
	queue_redraw()
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_mini, "scale", Vector2(1.0, 1.0), 0.12)
	_hover_label.visible = false

func _draw() -> void:
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
	position   = Vector2(cx * orbit_radius_x, z * orbit_radius_y)
	modulate.a = lerp(0.35, 1.0, (z + 1.0) * 0.5)

	z_as_relative = false
	z_index = 20 if z < 0.0 else 80

	# side determines label/line direction: positive x = right, negative = left
	_side = sign(cx) if abs(cx) > 0.05 else 1.0
	_update_label_position()

	var ld := Vector3(-cx, -z * 0.6, 0.5).normalized()
	if _mini and _mini.material:
		(_mini.material as ShaderMaterial).set_shader_parameter("light_direction", ld)

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
