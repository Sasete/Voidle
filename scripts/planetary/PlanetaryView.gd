extends Control

@export var initial_planet: PlanetData
@export var random_on_start: bool = true
@export var debug_seed: int = 12345

@onready var planet_renderer: ColorRect = $PlanetContainer/PlanetRenderer
@onready var poi_layer: Node2D = $POILayer

var current_data: PlanetData

func _ready() -> void:
	planet_renderer.planet_clicked.connect(_on_planet_clicked)
	poi_layer.poi_clicked.connect(_on_poi_clicked)
	get_tree().root.size_changed.connect(_on_resize)
	($RightPanel/PanelContent/RedrawButton as Button).pressed.connect(redraw)

	if initial_planet != null:
		load_planet(initial_planet)
	elif random_on_start:
		load_planet(PlanetData.from_seed(randi() % 99999))
	else:
		load_planet(PlanetData.from_seed(debug_seed))

func load_planet(data: PlanetData) -> void:
	current_data = data
	_setup_material(data)
	_update_panel(data)
	poi_layer.setup(planet_renderer)
	poi_layer.clear_pois()

	var pois: Array[Dictionary]
	if data.custom_pois.size() > 0:
		for pd: POIData in data.custom_pois:
			pois.append({"lon_deg": pd.lon_deg, "lat_deg": pd.lat_deg,
				"label": pd.label, "data": {"type": pd.type_tag}})
	else:
		pois = PlanetData.generate_pois(data.planet_type, data.seed, data.sea_level, data.terrain_roughness)

	for poi in pois:
		poi_layer.add_poi(poi["lon_deg"], poi["lat_deg"], poi["label"], poi["data"])

func redraw() -> void:
	load_planet(PlanetData.from_seed(randi() % 99999))

func _setup_material(data: PlanetData) -> void:
	var shader := load(PlanetData.get_shader_path(data.planet_type)) as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader

	var base_radius: float = 0.42 * clamp(data.planet_size, 0.2, 2.0)
	mat.set_shader_parameter("rotation_offset",   0.0)
	mat.set_shader_parameter("planet_radius",     clamp(base_radius, 0.10, 0.48))
	mat.set_shader_parameter("pixel_count",       140.0)
	mat.set_shader_parameter("seed",              data.seed)
	mat.set_shader_parameter("terrain_roughness", data.terrain_roughness)

	var stype := PlanetData.get_shader_type(data.planet_type)
	match stype:
		PlanetData.ShaderType.ROCKY:
			mat.set_shader_parameter("cloud_speed",        data.cloud_speed)
			mat.set_shader_parameter("cloud_coverage",     data.cloud_coverage)
			mat.set_shader_parameter("has_clouds",         1.0 if data.has_clouds else 0.0)
			mat.set_shader_parameter("atmosphere_density", data.atmosphere_density if data.has_atmosphere else 0.0)
			mat.set_shader_parameter("sea_level",          data.sea_level)
			var colors := PlanetData.get_colors(data.planet_type)
			for key in colors:
				mat.set_shader_parameter(key, colors[key])
		PlanetData.ShaderType.GAS:
			mat.set_shader_parameter("cloud_speed",        data.cloud_speed)
			mat.set_shader_parameter("atmosphere_density", data.atmosphere_density)
			var colors := PlanetData.get_colors(data.planet_type)
			mat.set_shader_parameter("color_band_a",     colors.get("color_sand",        Vector3(0.72, 0.55, 0.35)))
			mat.set_shader_parameter("color_band_b",     colors.get("color_forest",      Vector3(0.50, 0.32, 0.18)))
			mat.set_shader_parameter("color_storm",      colors.get("color_snow",        Vector3(0.88, 0.82, 0.72)))
			mat.set_shader_parameter("color_atmosphere", colors.get("color_atmosphere",  Vector3(0.72, 0.55, 0.35)))
		PlanetData.ShaderType.MOON:
			var colors := PlanetData.get_colors(data.planet_type)
			mat.set_shader_parameter("color_highland", colors.get("color_mountain",  Vector3(0.62, 0.60, 0.56)))
			mat.set_shader_parameter("color_mare",     colors.get("color_deep_ocean",Vector3(0.22, 0.21, 0.20)))
			mat.set_shader_parameter("color_rim",      colors.get("color_snow",      Vector3(0.78, 0.76, 0.72)))
			mat.set_shader_parameter("color_floor",    colors.get("color_ocean",     Vector3(0.16, 0.15, 0.14)))
		PlanetData.ShaderType.ASTEROID:
			mat.set_shader_parameter("irregularity", data.irregularity)
			mat.set_shader_parameter("elongation",   1.0 + data.irregularity * 0.8)

	planet_renderer.material = mat
	_update_aspect()

func _update_panel(data: PlanetData) -> void:
	var name_label  := $RightPanel/PanelContent/PlanetName as Label
	var type_label  := $RightPanel/PanelContent/PlanetType as Label
	var seed_value  := $RightPanel/PanelContent/SeedRow/SeedValue as Label
	var type_names  := ["Terran", "Arid", "Ice", "Volcanic", "Barren", "Gas Giant", "Moon", "Asteroid"]
	if name_label: name_label.text = data.planet_name
	if type_label: type_label.text = type_names[data.planet_type]
	if seed_value:
		seed_value.text = str(data.seed)
		if not seed_value.gui_input.is_connected(_on_seed_clicked):
			seed_value.gui_input.connect(_on_seed_clicked.bind(data.seed))

func _update_aspect() -> void:
	if planet_renderer.material == null:
		return
	var s := planet_renderer.size
	if s.y > 0.0:
		planet_renderer.material.set_shader_parameter("aspect_ratio", s.x / s.y)

func _on_resize() -> void:
	await get_tree().process_frame
	_update_aspect()

func _process(_delta: float) -> void:
	_update_aspect()

func _on_planet_clicked(_screen_pos: Vector2) -> void:
	pass

func _on_poi_clicked(index: int, _data: Dictionary) -> void:
	if index < poi_layer._pois.size():
		print("POI clicked: ", poi_layer._pois[index]["label"])

func _on_seed_clicked(event: InputEvent, s: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		DisplayServer.clipboard_set(str(s))
