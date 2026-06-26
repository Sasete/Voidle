class_name MoonOrbitNode
extends Node2D

# Static moon — fixed position relative to its parent planet, no orbit animation.
const SIZE := 14

var _mini:         ColorRect
var _orbit_x:      float = 0.0
var _start_angle:  float = 0.0
var _y_ratio:      float = 0.38

func setup(data: PlanetData, orbit_x: float, start_angle: float) -> void:
	_orbit_x     = orbit_x
	_start_angle = start_angle
	_apply_position()
	_build(data)

func set_tilt(ratio: float) -> void:
	_y_ratio = ratio
	_apply_position()

func _apply_position() -> void:
	var z   := sin(_start_angle)
	position   = Vector2(cos(_start_angle) * _orbit_x, z * _orbit_x * _y_ratio)
	modulate.a = lerp(0.30, 0.90, (z + 1.0) * 0.5)
	z_index    = 1 if z >= 0.0 else -1

func _build(data: PlanetData) -> void:
	_mini              = ColorRect.new()
	_mini.size         = Vector2(SIZE, SIZE)
	_mini.position     = -Vector2(SIZE, SIZE) * 0.5
	_mini.pivot_offset = Vector2(SIZE, SIZE) * 0.5
	# Node2D scale pivot is at (0,0) which is already the moon center
	_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat    := ShaderMaterial.new()
	mat.shader  = load(PlanetData.get_shader_path(data.planet_type))
	mat.set_shader_parameter("planet_radius",     0.38)
	mat.set_shader_parameter("pixel_count",       float(SIZE))
	mat.set_shader_parameter("aspect_ratio",      1.0)
	mat.set_shader_parameter("seed",              data.seed)
	mat.set_shader_parameter("terrain_roughness", data.terrain_roughness)
	mat.set_shader_parameter("rotation_offset",   0.0)
	mat.set_shader_parameter("light_direction",   Vector3(0.6, -0.55, 0.65))
	var c := PlanetData.get_colors(data.planet_type)
	mat.set_shader_parameter("color_highland", c.get("color_mountain",   Vector3(0.62,0.60,0.56)))
	mat.set_shader_parameter("color_mare",     c.get("color_deep_ocean", Vector3(0.22,0.21,0.20)))
	mat.set_shader_parameter("color_rim",      c.get("color_snow",       Vector3(0.78,0.76,0.72)))
	mat.set_shader_parameter("color_floor",    c.get("color_ocean",      Vector3(0.16,0.15,0.14)))
	_mini.material = mat
	add_child(_mini)
