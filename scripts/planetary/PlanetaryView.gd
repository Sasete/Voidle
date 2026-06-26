extends Control

@export var initial_planet: PlanetData
@export var random_on_start: bool = true
@export var debug_seed: int = 12345

@onready var planet_renderer: ColorRect = $PlanetContainer/PlanetRenderer
@onready var poi_layer: Node2D = $POILayer

var current_data:      PlanetData
var _local_system:     Array[PlanetData] = []   # planet + all its moons, flat
var _system_solar:     SolarData                # to restore when going back
var _companion_moons:  Array[ColorRect] = []
var _orbitron:         Font

func _make_system(root: PlanetData) -> Array[PlanetData]:
	var arr: Array[PlanetData] = [root]
	for m in root.moons:
		arr.append(m)
	return arr

func _apply_orbitron(lbl: Label, size: int) -> void:
	if _orbitron:
		lbl.add_theme_font_override("font", _orbitron)
	lbl.add_theme_font_size_override("font_size", size)

func _ready() -> void:
	_orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")
	planet_renderer.planet_clicked.connect(_on_planet_clicked)
	poi_layer.poi_clicked.connect(_on_poi_clicked)
	get_tree().root.size_changed.connect(_on_resize)
	($RightPanel/PanelContent/BackButton as Button).pressed.connect(_go_back)

	# load from transition if navigating from SolarView
	var planet_to_load: PlanetData = SceneTransition.pending_data as PlanetData
	if planet_to_load != null:
		SceneTransition.pending_data = null
		if planet_to_load.moons.is_empty():
			planet_to_load.generate_moons(planet_to_load.seed)
		_system_solar = planet_to_load.get_meta("__solar_data") as SolarData if planet_to_load.has_meta("__solar_data") else null
		_local_system = _make_system(planet_to_load)
	elif initial_planet != null:
		if initial_planet.moons.is_empty():
			initial_planet.generate_moons(initial_planet.seed)
		planet_to_load = initial_planet
		_local_system = _make_system(planet_to_load)
	elif random_on_start:
		planet_to_load = PlanetData.from_seed(randi() % 99999)
		planet_to_load.generate_moons(planet_to_load.seed)
		_local_system = _make_system(planet_to_load)
	else:
		planet_to_load = PlanetData.from_seed(debug_seed)
		planet_to_load.generate_moons(planet_to_load.seed)
		_local_system = _make_system(planet_to_load)
	load_planet(planet_to_load)

func _go_back() -> void:
	SceneTransition.go("res://scenes/solar/SolarView.tscn", _system_solar)

var _back_charge: int = 0

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_go_back()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_back_charge += 1
			if _back_charge >= 4:
				_back_charge = 0
				_go_back()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_back_charge = 0
	elif event is InputEventMagnifyGesture:
		if event.factor < 1.0:
			_back_charge += 1
			if _back_charge >= 4:
				_back_charge = 0
				_go_back()
		else:
			_back_charge = 0
	elif event is InputEventPanGesture:
		if event.delta.y > 0.5:   # scroll down = zoom out = go back
			_back_charge += 1
			if _back_charge >= 4:
				_back_charge = 0
				_go_back()
		elif event.delta.y < -0.5:
			_back_charge = 0

func load_planet(data: PlanetData) -> void:
	current_data = data
	_setup_material(data)
	_update_panel(data)
	_build_companion_moons(data)
	poi_layer.setup(planet_renderer)
	poi_layer.clear_pois()

	var pois: Array[Dictionary]
	if data.custom_pois.size() > 0:
		var lf := LocationFinder.new(data.seed, data.sea_level,
				data.terrain_roughness, data.continent_scale)
		for pd: POIData in data.custom_pois:
			var lon: float
			var lat: float
			if pd.manual_position:
				lon = deg_to_rad(pd.lon_deg)
				lat = deg_to_rad(pd.lat_deg)
			else:
				var pos: Vector2 = lf.find(pd.placement)
				lon = pos.x
				lat = pos.y
			pois.append({
				"lon_deg": rad_to_deg(lon), "lat_deg": rad_to_deg(lat),
				"label": pd.label,
				"data": {"type": pd.type_tag, "light_intensity": pd.light_intensity}
			})
	else:
		pois = PlanetData.generate_pois(data.planet_type, data.seed,
				data.sea_level, data.terrain_roughness, data.continent_scale)

	for poi in pois:
		poi_layer.add_poi(poi["lon_deg"], poi["lat_deg"], poi["label"], poi["data"])

	_upload_poi_lights(pois, data)

func redraw() -> void:
	var pd := PlanetData.from_seed(randi() % 99999)
	pd.generate_moons(pd.seed)
	_local_system = _make_system(pd)
	_system_solar  = null
	load_planet(pd)

func _setup_material(data: PlanetData) -> void:
	var shader := load(PlanetData.get_shader_path(data.planet_type)) as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader

	var sz: float = clamp(data.planet_size, 0.2, 2.0)
	var base_radius: float = clamp(0.42 * sz, 0.10, 0.48)
	# scale pixel_count only when planet is large (>1.2) to preserve pixel art feel
	var pcount: float = 140.0
	if sz > 1.2:
		pcount = round(clamp(140.0 * (sz / 1.2), 140.0, 280.0))
	mat.set_shader_parameter("rotation_offset",   0.0)
	mat.set_shader_parameter("planet_radius",     base_radius)
	mat.set_shader_parameter("pixel_count",       pcount)
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
			mat.set_shader_parameter("continent_scale",    data.continent_scale)
			mat.set_shader_parameter("specular_strength",  data.specular_strength)
			mat.set_shader_parameter("city_lights",        data.city_lights)
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

func _upload_poi_lights(pois: Array[Dictionary], data: PlanetData) -> void:
	var mat := planet_renderer.material as ShaderMaterial
	if mat == null:
		return
	var stype := PlanetData.get_shader_type(data.planet_type)
	if stype != PlanetData.ShaderType.ROCKY:
		return

	var count: int = mini(pois.size(), 5)
	mat.set_shader_parameter("poi_count", count)
	var names := ["poi_lights_0","poi_lights_1","poi_lights_2","poi_lights_3","poi_lights_4"]
	for i in range(5):
		if i < count:
			var lon: float = deg_to_rad(float(pois[i].get("lon_deg", 0.0)))
			var lat: float = deg_to_rad(float(pois[i].get("lat_deg", 0.0)))
			var intensity: float = float(pois[i].get("data", {}).get("light_intensity", 1.0))
			var nx: float = sin(lon) * cos(lat)
			var ny: float = -sin(lat)
			var nz: float = cos(lon) * cos(lat)
			mat.set_shader_parameter(names[i], Vector4(nx, ny, nz, intensity))
		else:
			mat.set_shader_parameter(names[i], Vector4(0,0,0,0))

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
	_build_system_panel()

func _build_system_panel() -> void:
	var panel_content := $RightPanel/PanelContent
	var old := panel_content.get_node_or_null("SystemSection")
	if old:
		old.free()
	if _local_system.size() <= 1:
		return

	var section := VBoxContainer.new()
	section.name = "SystemSection"
	section.add_child(HSeparator.new())

	var title := Label.new()
	title.text = "LOCAL SYSTEM"
	_apply_orbitron(title, 10)
	title.modulate = Color(0.65, 0.65, 0.65)
	section.add_child(title)

	const THUMB := 48
	for body in _local_system:
		var is_active := (body == current_data)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		if is_active:
			row.modulate = Color(1.5, 1.5, 1.0)   # yellow tint for active

		var rect := ColorRect.new()
		rect.custom_minimum_size     = Vector2(THUMB, THUMB)
		rect.size_flags_horizontal   = Control.SIZE_SHRINK_BEGIN
		rect.mouse_filter            = Control.MOUSE_FILTER_IGNORE
		var shader_path := PlanetData.get_shader_path(body.planet_type)
		var mat         := ShaderMaterial.new()
		mat.shader       = load(shader_path)
		mat.set_shader_parameter("planet_radius",     0.40)
		mat.set_shader_parameter("pixel_count",       float(THUMB))
		mat.set_shader_parameter("aspect_ratio",      1.0)
		mat.set_shader_parameter("seed",              body.seed)
		mat.set_shader_parameter("terrain_roughness", body.terrain_roughness)
		mat.set_shader_parameter("rotation_offset",   0.0)
		mat.set_shader_parameter("light_direction",   Vector3(0.6, -0.55, 0.65))
		var stype := PlanetData.get_shader_type(body.planet_type)
		match stype:
			PlanetData.ShaderType.ROCKY:
				mat.set_shader_parameter("sea_level",          body.sea_level)
				mat.set_shader_parameter("continent_scale",    body.continent_scale)
				mat.set_shader_parameter("has_clouds",         0.0)
				mat.set_shader_parameter("atmosphere_density", 0.0)
				mat.set_shader_parameter("specular_strength",  body.specular_strength)
				mat.set_shader_parameter("city_lights",        0.0)
				mat.set_shader_parameter("poi_count",          0)
				for key in PlanetData.get_colors(body.planet_type):
					mat.set_shader_parameter(key, PlanetData.get_colors(body.planet_type)[key])
			PlanetData.ShaderType.GAS:
				mat.set_shader_parameter("cloud_speed",        0.0)
				mat.set_shader_parameter("atmosphere_density", body.atmosphere_density)
				var c := PlanetData.get_colors(body.planet_type)
				mat.set_shader_parameter("color_band_a",    c.get("color_sand",       Vector3(0.72,0.55,0.35)))
				mat.set_shader_parameter("color_band_b",    c.get("color_forest",     Vector3(0.50,0.32,0.18)))
				mat.set_shader_parameter("color_storm",     c.get("color_snow",       Vector3(0.88,0.82,0.72)))
				mat.set_shader_parameter("color_atmosphere",c.get("color_atmosphere", Vector3(0.72,0.55,0.35)))
			PlanetData.ShaderType.MOON:
				var c := PlanetData.get_colors(body.planet_type)
				mat.set_shader_parameter("color_highland", c.get("color_mountain",   Vector3(0.62,0.60,0.56)))
				mat.set_shader_parameter("color_mare",     c.get("color_deep_ocean", Vector3(0.22,0.21,0.20)))
				mat.set_shader_parameter("color_rim",      c.get("color_snow",       Vector3(0.78,0.76,0.72)))
				mat.set_shader_parameter("color_floor",    c.get("color_ocean",      Vector3(0.16,0.15,0.14)))
			PlanetData.ShaderType.ASTEROID:
				mat.set_shader_parameter("irregularity", body.irregularity)
				mat.set_shader_parameter("elongation",   1.0 + body.irregularity * 0.8)
		rect.material = mat
		row.add_child(rect)

		var lbl := Label.new()
		lbl.text = body.planet_name
		_apply_orbitron(lbl, 10)
		lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.clip_contents         = true
		row.add_child(lbl)

		# make the whole row clickable
		var captured_body := body
		if not is_active:
			row.mouse_filter             = Control.MOUSE_FILTER_STOP
			row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			row.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					load_planet(captured_body)
			)
			row.mouse_entered.connect(func() -> void: row.modulate = Color(1.3, 1.3, 1.1))
			row.mouse_exited.connect(func()  -> void: row.modulate = Color.WHITE)

		section.add_child(row)

	var spacer_idx: int = panel_content.get_child_count() - 2
	panel_content.add_child(section)
	panel_content.move_child(section, max(spacer_idx, 0))

func _build_companion_moons(data: PlanetData) -> void:
	for r in _companion_moons:
		r.queue_free()
	_companion_moons.clear()

	# show all other bodies in the local system as background companions
	var others: Array[PlanetData] = []
	for b in _local_system:
		if b != data:
			others.append(b)
	if others.is_empty():
		return

	const S := 90
	var offsets := [Vector2(-0.44, 0.12), Vector2(0.44, -0.18)]

	for i in mini(others.size(), offsets.size()):
		var moon := others[i]
		var rect := ColorRect.new()
		rect.custom_minimum_size = Vector2(S, S)
		rect.size                = Vector2(S, S)
		rect.z_index             = -1    # behind main planet renderer
		rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE  # pass clicks to planet renderer

		var mat         := ShaderMaterial.new()
		mat.shader       = load(PlanetData.get_shader_path(moon.planet_type))
		mat.set_shader_parameter("planet_radius",     0.38)
		mat.set_shader_parameter("pixel_count",       float(S))
		mat.set_shader_parameter("aspect_ratio",      1.0)
		mat.set_shader_parameter("seed",              moon.seed)
		mat.set_shader_parameter("terrain_roughness", moon.terrain_roughness)
		mat.set_shader_parameter("rotation_offset",   0.0)
		mat.set_shader_parameter("light_direction",   Vector3(0.6, -0.55, 0.65))
		var stype := PlanetData.get_shader_type(moon.planet_type)
		match stype:
			PlanetData.ShaderType.ROCKY:
				mat.set_shader_parameter("sea_level",          moon.sea_level)
				mat.set_shader_parameter("continent_scale",    moon.continent_scale)
				mat.set_shader_parameter("has_clouds",         0.0)
				mat.set_shader_parameter("atmosphere_density", 0.0)
				mat.set_shader_parameter("specular_strength",  moon.specular_strength)
				mat.set_shader_parameter("city_lights",        0.0)
				mat.set_shader_parameter("poi_count",          0)
				for key in PlanetData.get_colors(moon.planet_type):
					mat.set_shader_parameter(key, PlanetData.get_colors(moon.planet_type)[key])
			PlanetData.ShaderType.GAS:
				mat.set_shader_parameter("cloud_speed",        0.0)
				mat.set_shader_parameter("atmosphere_density", moon.atmosphere_density)
				var gc := PlanetData.get_colors(moon.planet_type)
				mat.set_shader_parameter("color_band_a",    gc.get("color_sand",       Vector3(0.72,0.55,0.35)))
				mat.set_shader_parameter("color_band_b",    gc.get("color_forest",     Vector3(0.50,0.32,0.18)))
				mat.set_shader_parameter("color_storm",     gc.get("color_snow",       Vector3(0.88,0.82,0.72)))
				mat.set_shader_parameter("color_atmosphere",gc.get("color_atmosphere", Vector3(0.72,0.55,0.35)))
			PlanetData.ShaderType.MOON:
				var mc := PlanetData.get_colors(moon.planet_type)
				mat.set_shader_parameter("color_highland", mc.get("color_mountain",   Vector3(0.62,0.60,0.56)))
				mat.set_shader_parameter("color_mare",     mc.get("color_deep_ocean", Vector3(0.22,0.21,0.20)))
				mat.set_shader_parameter("color_rim",      mc.get("color_snow",       Vector3(0.78,0.76,0.72)))
				mat.set_shader_parameter("color_floor",    mc.get("color_ocean",      Vector3(0.16,0.15,0.14)))
			PlanetData.ShaderType.ASTEROID:
				mat.set_shader_parameter("irregularity", moon.irregularity)
				mat.set_shader_parameter("elongation",   1.0 + moon.irregularity * 0.8)
		rect.material     = mat
		rect.pivot_offset = Vector2(S, S) * 0.5

		$PlanetContainer.add_child(rect)
		_companion_moons.append(rect)

	_position_companions()

func _on_planet_hover_on() -> void:
	for r in _companion_moons:
		var tw := r.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(r, "modulate",   Color(1.5, 1.5, 1.5), 0.15)
		tw.tween_property(r, "scale",      Vector2(1.25, 1.25),  0.15)

func _on_planet_hover_off() -> void:
	for r in _companion_moons:
		var tw := r.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(r, "modulate",   Color(1.0, 1.0, 1.0), 0.12)
		tw.tween_property(r, "scale",      Vector2(1.0, 1.0),    0.12)

func _position_companions() -> void:
	if _companion_moons.is_empty():
		return
	const S := 90
	var offsets := [Vector2(-0.44, 0.12), Vector2(0.44, -0.18)]
	var sz := ($PlanetContainer as Control).size
	for i in _companion_moons.size():
		var off: Vector2 = offsets[i]
		_companion_moons[i].scale    = Vector2.ONE
		_companion_moons[i].position = Vector2(
			sz.x * 0.5 + off.x * sz.x * 0.5 - S * 0.5,
			sz.y * 0.5 + off.y * sz.y * 0.5 - S * 0.5
		)

func _update_aspect() -> void:
	if planet_renderer.material == null:
		return
	var s := planet_renderer.size
	if s.y > 0.0:
		planet_renderer.material.set_shader_parameter("aspect_ratio", s.x / s.y)

func _on_resize() -> void:
	await get_tree().process_frame
	_update_aspect()
	_position_companions()

var _companions_highlighted: bool = false

func _process(_delta: float) -> void:
	_update_aspect()
	_update_companion_hover()

func _update_companion_hover() -> void:
	if _companion_moons.is_empty():
		return
	var mouse_g := get_viewport().get_mouse_position()
	var pr_rect  := planet_renderer.get_global_rect()
	var hov      := pr_rect.has_point(mouse_g)
	if not hov:
		for r: ColorRect in _companion_moons:
			if r.get_global_rect().has_point(mouse_g):
				hov = true
				break
	if hov != _companions_highlighted:
		_companions_highlighted = hov
		if hov:
			_on_planet_hover_on()
		else:
			_on_planet_hover_off()

func _on_planet_clicked(_screen_pos: Vector2) -> void:
	pass

func _on_poi_clicked(index: int, _data: Dictionary) -> void:
	if index < poi_layer._pois.size():
		print("POI clicked: ", poi_layer._pois[index]["label"])

func _on_seed_clicked(event: InputEvent, s: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		DisplayServer.clipboard_set(str(s))
