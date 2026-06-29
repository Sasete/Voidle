@tool
extends ColorRect

signal planet_clicked(screen_pos: Vector2)

@export var momentum_decay: float = 0.88

## Editor preview controls — no effect at runtime.
@export_group("Editor Preview")
@export var preview_planet_type: PlanetData.Type = PlanetData.Type.TERRAN:
	set(v):
		preview_planet_type = v
		if Engine.is_editor_hint():
			if is_inside_tree(): _apply_preview()
			else: call_deferred("_apply_preview")
@export var preview_seed: int = 42:
	set(v):
		preview_seed = v
		if Engine.is_editor_hint():
			if is_inside_tree(): _apply_preview()
			else: call_deferred("_apply_preview")
@export_range(0.1, 2.0, 0.05) var preview_planet_size: float = 1.0:
	set(v):
		preview_planet_size = v
		if Engine.is_editor_hint():
			if is_inside_tree(): _apply_preview()
			else: call_deferred("_apply_preview")
@export_group("")

var _dragging := false
var _drag_velocity := 0.0
var _drag_total_px := 0.0
var _rotation_offset := 0.0
var _last_mouse_x := 0.0
var _planet_radius_px := 0.0
## Global light angle (shared time-of-day clock, advances in PlanetaryView._process)
var light_angle: float = 0.0
## Per-planet offset so each world has its own "local noon" position
var local_time_offset: float = 0.0

func _ready() -> void:
	if Engine.is_editor_hint():
		call_deferred("_apply_preview")
	# At runtime, material is assigned externally by PlanetaryView._setup_material()

func _apply_preview() -> void:
	if not Engine.is_editor_hint():
		return
	var data := PlanetData.new()
	data.planet_type = preview_planet_type
	data.seed        = preview_seed
	data.planet_size = preview_planet_size
	# Fill in defaults that from_seed() would normally set
	data.has_atmosphere    = true
	data.atmosphere_density = 1.0
	data.has_clouds        = true
	data.cloud_speed       = 0.04
	data.cloud_coverage    = 0.55
	data.sea_level         = 0.0
	data.continent_scale   = 1.0
	data.terrain_roughness = 1.0
	data.specular_strength = 0.4
	data.city_lights       = 0.0
	data.irregularity      = 0.4

	var shader := load(PlanetData.get_shader_path(data.planet_type)) as Shader
	var mat    := ShaderMaterial.new()
	mat.shader  = shader

	var sz: float          = clamp(data.planet_size, 0.2, 2.0)
	var base_radius: float = clamp(0.42 * sz, 0.10, 0.48)
	var pcount: float      = 140.0
	if sz > 1.2:
		pcount = round(clamp(140.0 * (sz / 1.2), 140.0, 280.0))

	mat.set_shader_parameter("rotation_offset",   0.0)
	mat.set_shader_parameter("planet_radius",     base_radius)
	mat.set_shader_parameter("pixel_count",       pcount)
	mat.set_shader_parameter("seed",              data.seed)
	mat.set_shader_parameter("terrain_roughness", data.terrain_roughness)

	var stype := PlanetData.get_shader_type(data.planet_type)
	var colors := PlanetData.get_colors(data.planet_type)
	match stype:
		PlanetData.ShaderType.ROCKY:
			mat.set_shader_parameter("cloud_speed",        data.cloud_speed)
			mat.set_shader_parameter("cloud_coverage",     data.cloud_coverage)
			mat.set_shader_parameter("has_clouds",         1.0 if data.has_clouds else 0.0)
			mat.set_shader_parameter("atmosphere_density", data.atmosphere_density)
			mat.set_shader_parameter("sea_level",          data.sea_level)
			mat.set_shader_parameter("continent_scale",    data.continent_scale)
			mat.set_shader_parameter("specular_strength",  data.specular_strength)
			mat.set_shader_parameter("city_lights",        data.city_lights)
			for key in colors:
				mat.set_shader_parameter(key, colors[key])
		PlanetData.ShaderType.GAS:
			mat.set_shader_parameter("cloud_speed",        data.cloud_speed)
			mat.set_shader_parameter("atmosphere_density", data.atmosphere_density)
			mat.set_shader_parameter("color_band_a",     colors.get("color_sand",        Vector3(0.72, 0.55, 0.35)))
			mat.set_shader_parameter("color_band_b",     colors.get("color_forest",      Vector3(0.50, 0.32, 0.18)))
			mat.set_shader_parameter("color_storm",      colors.get("color_snow",        Vector3(0.88, 0.82, 0.72)))
			mat.set_shader_parameter("color_atmosphere", colors.get("color_atmosphere",  Vector3(0.72, 0.55, 0.35)))
		PlanetData.ShaderType.MOON:
			mat.set_shader_parameter("color_highland", colors.get("color_mountain",   Vector3(0.62, 0.60, 0.56)))
			mat.set_shader_parameter("color_mare",     colors.get("color_deep_ocean", Vector3(0.22, 0.21, 0.20)))
			mat.set_shader_parameter("color_rim",      colors.get("color_snow",       Vector3(0.78, 0.76, 0.72)))
			mat.set_shader_parameter("color_floor",    colors.get("color_ocean",      Vector3(0.16, 0.15, 0.14)))
		PlanetData.ShaderType.ASTEROID:
			mat.set_shader_parameter("irregularity", data.irregularity)
			mat.set_shader_parameter("elongation",   1.0 + data.irregularity * 0.8)

	material = mat
	# Fake a midday light direction so the planet is visible
	var ld := Vector3(0.6, -0.4, 0.7).normalized()
	mat.set_shader_parameter("light_direction", ld)

func _update_radius() -> void:
	if material == null:
		return
	var r: float = material.get_shader_parameter("planet_radius")
	# radius in screen pixels = height * planet_radius (aspect-corrected circle)
	_planet_radius_px = size.y * r

func get_rotation_offset() -> float:
	return _rotation_offset

func set_rotation_offset(val: float) -> void:
	_rotation_offset = fposmod(val, TAU)
	if material:
		(material as ShaderMaterial).set_shader_parameter("rotation_offset", _rotation_offset)
		# Note: light_direction is recomputed every frame in _process;
		# calling _update_light_direction here too ensures tweens stay in sync.
		_update_light_direction()

func _update_light_direction() -> void:
	if material == null:
		return
	# eff = global_time + planet_local_offset + surface_rotation
	# Adding rotation_offset means the light rotates WITH the terrain:
	# a landmass that's in night stays in night as you spin the planet,
	# giving the feel of a camera orbiting a stationary world.
	var eff: float = light_angle + local_time_offset + _rotation_offset
	var lx := cos(eff) * 0.85
	var lz := sin(eff) * 0.55
	var ld := Vector3(lx, -0.45, lz).normalized()
	(material as ShaderMaterial).set_shader_parameter("light_direction", ld)

func _unhandled_input(event: InputEvent) -> void:
	# Absolutely block and ignore any click, drag, or hover events if SkillTreeView is active
	var root := get_tree().root
	var is_tree_open := false
	for child in root.get_children():
		var script = child.get_script()
		if script != null and script.resource_path.ends_with("SkillTreeView.gd"):
			is_tree_open = true
			break
			
	if is_tree_open:
		_dragging = false
		_drag_velocity = 0.0
		return
			
	_update_radius()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var local := get_local_mouse_position()
		var center := size * 0.5
		# account for aspect ratio when hit-testing the circle
		var ar: float = size.x / size.y if size.y > 0 else 1.0
		var corrected := Vector2((local.x - center.x) * ar, local.y - center.y)
		var dist := corrected.length()
		if event.pressed and dist < _planet_radius_px:
			_dragging = true
			_drag_velocity = 0.0
			_drag_total_px = 0.0
			_last_mouse_x = float(event.position.x)
		elif not event.pressed:
			# Only treat as a tap if total drag distance was small
			if _dragging and _drag_total_px < 8.0:
				planet_clicked.emit(event.position)
			_dragging = false
			_drag_total_px = 0.0

	if event is InputEventMouseMotion and _dragging:
		root = get_tree().root
		is_tree_open = false
		for child in root.get_children():
			var script = child.get_script()
			if script != null and script.resource_path.ends_with("SkillTreeView.gd"):
				is_tree_open = true
				break
				
		if is_tree_open:
			_dragging = false
			_drag_velocity = 0.0
			return
				
		var delta_x: float = float(event.position.x) - _last_mouse_x
		_drag_total_px += abs(delta_x)
		_last_mouse_x = float(event.position.x)
		# 1:1 surface mapping: dragging by r_px = π radians rotation
		var delta_rot: float = delta_x / _planet_radius_px
		_rotation_offset = fposmod(_rotation_offset - delta_rot, TAU)
		_drag_velocity = -delta_rot
		if material:
			material.set_shader_parameter("rotation_offset", _rotation_offset)
			# light_direction synced at end of _process every frame

func _process(_delta: float) -> void:
	if not _dragging and abs(_drag_velocity) > 0.0001:
		_drag_velocity *= momentum_decay
		_rotation_offset = fposmod(_rotation_offset + _drag_velocity, TAU)
		if material:
			material.set_shader_parameter("rotation_offset", _rotation_offset)
	# Always sync light direction at the END of every frame so both
	# rotation_offset (updated above or in _input) and light_angle
	# (updated by PlanetaryView._process which runs before us as the parent)
	# are fully up-to-date before the GPU renders.
	_update_light_direction()
