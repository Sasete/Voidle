extends Node

@export var export_path: String = "res://icon_export.png"
@export var resolution: Vector2i = Vector2i(512, 512)
@export var planet_type: PlanetData.Type = PlanetData.Type.TERRAN
@export var seed_value: int = 42
@export var light_angle: float = 0.5 # radians (0 = midday, PI/2 = dawn/dusk)
@export var rotation_offset: float = 0.0
@export var planet_size: float = 1.0

@export_group("Orbital Ring")
@export var has_rings: bool = false
@export var ring_color: Color = Color(0.85, 0.78, 0.55, 0.65)

@export_group("Planet Details")
@export var planet_pixelation: float = 256.0
@export var city_lights: float = 1.5

var _viewport: SubViewport
var _planet: ColorRect
var _frames_waited := 0

func _ready() -> void:
	# 1. Create a transparent viewport
	_viewport = SubViewport.new()
	_viewport.size = resolution
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	if has_rings:
		var back_ring = Control.new()
		back_ring.position = Vector2.ZERO
		back_ring.draw.connect(_draw_planet_rings.bind(back_ring, PI, TAU, true))
		_viewport.add_child(back_ring)

	# 2. Setup the planet renderer
	var pr_script = preload("res://scripts/planetary/PlanetRenderer.gd")
	_planet = pr_script.new()
	_planet.custom_minimum_size = Vector2(resolution)
	_planet.size = Vector2(resolution)
	
	
	# Create data and apply defaults
	var data := PlanetData.new()
	data.planet_type = planet_type
	data.seed = seed_value
	data.planet_size = planet_size
	data.has_atmosphere = true
	data.atmosphere_density = 1.0
	data.has_clouds = true
	data.cloud_speed = 0.04
	data.cloud_coverage = 0.55
	data.sea_level = 0.0
	data.continent_scale = 1.0
	data.terrain_roughness = 1.0
	data.specular_strength = 0.4
	data.city_lights = city_lights
	data.irregularity = 0.4
	data.has_rings = has_rings
	data.ring_color = ring_color
	data.ring_inner = 1.25
	data.ring_outer = 1.95

	var shader := load(PlanetData.get_shader_path(data.planet_type)) as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader

	var sz: float = clamp(data.planet_size, 0.2, 2.0)
	var base_radius: float = clamp(0.42 * sz, 0.10, 0.48)
	var pcount: float = planet_pixelation

	mat.set_shader_parameter("rotation_offset", 0.0)
	mat.set_shader_parameter("planet_radius", base_radius)
	mat.set_shader_parameter("pixel_count", pcount)
	mat.set_shader_parameter("seed", data.seed)
	mat.set_shader_parameter("terrain_roughness", data.terrain_roughness)
	
	# Signal to the shader that this is the IconExporter (Ecumenopolis Mode & higher bloom)
	mat.set_shader_parameter("poi_count", -1)

	var stype := PlanetData.get_shader_type(data.planet_type)
	var colors := PlanetData.get_colors(data.planet_type)
	match stype:
		PlanetData.ShaderType.ROCKY:
			mat.set_shader_parameter("cloud_speed", data.cloud_speed)
			mat.set_shader_parameter("cloud_coverage", data.cloud_coverage)
			mat.set_shader_parameter("has_clouds", 1.0 if data.has_clouds else 0.0)
			mat.set_shader_parameter("atmosphere_density", data.atmosphere_density)
			mat.set_shader_parameter("sea_level", data.sea_level)
			mat.set_shader_parameter("continent_scale", data.continent_scale)
			mat.set_shader_parameter("specular_strength", data.specular_strength)
			mat.set_shader_parameter("city_lights", data.city_lights)
			for key in colors:
				mat.set_shader_parameter(key, colors[key])
		PlanetData.ShaderType.GAS:
			mat.set_shader_parameter("cloud_speed", data.cloud_speed)
			mat.set_shader_parameter("atmosphere_density", data.atmosphere_density)
			mat.set_shader_parameter("color_band_a", colors.get("color_sand", Vector3(0.72, 0.55, 0.35)))
			mat.set_shader_parameter("color_band_b", colors.get("color_forest", Vector3(0.50, 0.32, 0.18)))
			mat.set_shader_parameter("color_storm", colors.get("color_snow", Vector3(0.88, 0.82, 0.72)))
			mat.set_shader_parameter("color_atmosphere", colors.get("color_atmosphere", Vector3(0.72, 0.55, 0.35)))
		PlanetData.ShaderType.MOON:
			mat.set_shader_parameter("color_highland", colors.get("color_mountain", Vector3(0.62, 0.60, 0.56)))
			mat.set_shader_parameter("color_mare", colors.get("color_deep_ocean", Vector3(0.22, 0.21, 0.20)))
			mat.set_shader_parameter("color_rim", colors.get("color_snow", Vector3(0.78, 0.76, 0.72)))
			mat.set_shader_parameter("color_floor", colors.get("color_ocean", Vector3(0.16, 0.15, 0.14)))
		PlanetData.ShaderType.ASTEROID:
			mat.set_shader_parameter("irregularity", data.irregularity)
			mat.set_shader_parameter("elongation", 1.0 + data.irregularity * 0.8)

	_planet.material = mat
	
	_planet.light_angle = light_angle
	_planet.local_time_offset = 0.0
	_planet.set_rotation_offset(rotation_offset)
	_planet._update_light_direction()
	
	_viewport.add_child(_planet)

	if has_rings:
		var front_ring = Control.new()
		front_ring.position = Vector2.ZERO
		front_ring.draw.connect(_draw_planet_rings.bind(front_ring, 0.0, PI, false))
		_viewport.add_child(front_ring)

func _draw_planet_rings(target: Control, from_a: float, to_a: float, is_back: bool) -> void:
	if not has_rings:
		return
	# In IconExporter, the planet is drawn exactly at the center of the viewport with size = resolution
	var cx:   float = resolution.x * 0.5
	var cy:   float = resolution.y * 0.5
	var half: float = resolution.x * 0.5
	var yr:   float = 0.26
	var ir:   float = half * 1.25
	var or_:  float = half * 1.95
	var col:  Color = ring_color
	var bands: int  = 11
	for k in bands:
		var t:   float = float(k) / float(bands - 1)
		# Cassini-like gap near the middle
		var gap_alpha: float = 1.0 - smoothstep(0.0, 1.0, 1.0 - abs(t - 0.52) * 6.0)
		var rx:  float = lerp(ir, or_, t)
		var base_alp: float = 0.72 if is_back else 0.85
		var alp: float = col.a * lerp(base_alp * 0.55, base_alp, 1.0 - abs(t - 0.5) * 2.0) * gap_alpha
		var pts := PackedVector2Array()
		var steps := 80
		
		# Start and end angles
		var start = from_a
		var end = to_a
		
		for i in (steps + 1):
			var a = start + (end - start) * (float(i) / float(steps))
			var px = cx + cos(a) * rx
			var py = cy + sin(a) * rx * yr
			pts.append(Vector2(px, py))
			
		target.draw_polyline(pts, Color(col.r, col.g, col.b, alp), 2.0, true)

func _process(_delta: float) -> void:
	# Wait a few frames for the shader to compile and render
	_frames_waited += 1
	if _frames_waited >= 3:
		_save_image()
		set_process(false)

func _save_image() -> void:
	var img := _viewport.get_texture().get_image()
	var err := img.save_png(export_path)
	if err == OK:
		print("SUCCESS: Planet icon exported to ", export_path)
	else:
		print("ERROR: Failed to save icon. Error code: ", err)
	get_tree().quit()
