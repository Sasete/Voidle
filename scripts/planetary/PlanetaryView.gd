extends Control

@export var initial_planet: PlanetData
@export var random_on_start: bool = true
@export var debug_seed: int = 12345

@onready var planet_renderer: ColorRect = $PlanetContainer/PlanetRenderer
@onready var poi_layer: Node2D = $POILayer

var current_data:      PlanetData
var _local_system:     Array[PlanetData] = []   # planet + all its moons, flat
var _system_solar:     SolarData                # to restore when going back
var _solar_btn:        Button = null            # shown when solar is unlocked
var _companion_moons:  Array[ColorRect] = []
var _system_dock:      Control = null
var _details_panel:    Control = null
var _details_open:     bool    = false
var _hovering_ui:      bool    = false
var _orbitron:         Font
var _ring_back:    Node2D = null
var _ring_front:   Node2D = null
var _ring_angle:   float  = 0.0
var _ring_particles: Array[Dictionary] = []
var _light_angle:  float  = 0.8
const LIGHT_SPEED: float = 0.04   # radians per second

func _make_system(root: PlanetData) -> Array[PlanetData]:
	var arr: Array[PlanetData] = [root]
	for m in root.moons:
		arr.append(m)
	return arr


func _ready() -> void:
	CursorManager.set_state(CursorManager.State.NORMAL)
	_orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")
	planet_renderer.planet_clicked.connect(_on_planet_clicked)
	poi_layer.poi_clicked.connect(_on_poi_clicked)
	get_tree().root.size_changed.connect(_on_resize)
	pass  # cursor handled per-element, not per-panel
	# back button removed — navigation handled via system dock / unlock flow
	GameState.unlock_changed.connect(_on_unlock_changed)
	GameState.planet_progress_changed.connect(func(_s: int) -> void:
		_build_system_panel()
		if current_data != null:
			_build_details_panel(current_data))
	_refresh_solar_btn()

	# load from transition if navigating from SolarView or first launch
	var planet_to_load: PlanetData = SceneTransition.pending_data as PlanetData
	if planet_to_load != null:
		SceneTransition.pending_data = null
		if planet_to_load.moons.is_empty():
			planet_to_load.generate_moons(planet_to_load.seed)
		_system_solar = planet_to_load.get_meta("__solar_data") as SolarData \
			if planet_to_load.has_meta("__solar_data") \
			else GameState.get_home_solar()
		_local_system = _make_system(planet_to_load)
	elif initial_planet != null:
		# inspector-assigned planet (editor testing)
		if initial_planet.moons.is_empty():
			initial_planet.generate_moons(initial_planet.seed)
		planet_to_load = initial_planet
		_local_system = _make_system(planet_to_load)
	else:
		# game start — always load home planet from GameState (Terran, persistent seed)
		planet_to_load = GameState.get_home_planet()
		_local_system  = _make_system(planet_to_load)
	# restore light angle, advancing it by however much real time passed while away
	var now := Time.get_unix_time_from_system() as int
	if GameState.light_last_unix > 0:
		var elapsed := float(now - GameState.light_last_unix)
		GameState.light_angle = fposmod(GameState.light_angle + elapsed * LIGHT_SPEED, TAU)
	_light_angle = GameState.light_angle
	GameState.light_last_unix = now

	load_planet(planet_to_load)

func _save_light_angle() -> void:
	GameState.light_angle     = _light_angle
	GameState.light_last_unix = Time.get_unix_time_from_system() as int

func _go_back() -> void:
	if not GameState.solar_unlocked:
		return
	_save_light_angle()
	var sd := _system_solar if _system_solar != null else GameState.get_home_solar()
	SceneTransition.go("res://scenes/solar/SolarView.tscn", sd)

func _on_unlock_changed(_key: String, _val: bool) -> void:
	_refresh_solar_btn()

func _refresh_solar_btn() -> void:
	pass   # navigation via right-click only

var _back_charge: int = 0

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			CursorManager.set_state(CursorManager.State.EXIT)
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
	_build_rings(data)
	_build_system_panel()
	_build_details_panel(data)
	poi_layer.setup(planet_renderer)
	poi_layer.clear_pois()

	var pois: Array[Dictionary] = []
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
	# no auto-generated POIs — only custom_pois are shown

	# rotate so the first (primary) POI faces the viewer at load
	if pois.size() > 0:
		planet_renderer.set_rotation_offset(deg_to_rad(pois[0]["lon_deg"]))

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
	var type_names  := ["Terran", "Arid", "Ice", "Volcanic", "Barren", "Gas Giant", "Moon", "Asteroid"]
	if name_label: name_label.text = data.planet_name
	if type_label: type_label.text = type_names[data.planet_type]
	if type_label: type_label.visible = true
	_build_system_panel()

func _build_poi_form(data: PlanetData) -> void:
	var panel_content := $RightPanel/PanelContent
	var old := panel_content.get_node_or_null("POIForm")
	if old: old.free()

	var form := VBoxContainer.new()
	form.name = "POIForm"
	form.add_theme_constant_override("separation", 6)
	form.add_child(HSeparator.new())

	var title := Label.new()
	title.text = "ADD POI"
	_apply_orbitron(title, 10)
	title.modulate = Color(0.65, 0.65, 0.65)
	form.add_child(title)

	# label input
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "POI name..."
	name_edit.custom_minimum_size = Vector2(0, 28)
	_apply_orbitron(name_edit, 10)
	form.add_child(name_edit)

	# placement buttons
	var is_gas   := data.planet_type == PlanetData.Type.GAS_GIANT
	var has_ring := is_gas and data.has_rings
	var placements: Array[String] = []
	if is_gas:
		placements = ["Any"]
		if has_ring: placements.append("Ring")
	else:
		placements = ["Land", "Sea", "Coast", "Any"]

	var place_box := HBoxContainer.new()
	place_box.add_theme_constant_override("separation", 4)
	var selected_placement: Array[String] = [placements[0]]   # mutable reference
	var place_btns: Array[Button] = []
	for p in placements:
		var pb := Button.new()
		pb.text    = p
		pb.flat    = false
		pb.toggle_mode = true
		pb.button_pressed = (p == placements[0])
		_apply_orbitron(pb, 9)
		pb.custom_minimum_size = Vector2(0, 22)
		pb.pressed.connect(func() -> void:
			selected_placement[0] = p
			for other in place_btns:
				other.button_pressed = (other.text == p))
		place_btns.append(pb)
		place_box.add_child(pb)
	form.add_child(place_box)

	# confirm button
	var confirm := Button.new()
	confirm.text = "▶  PLACE POI"
	confirm.flat = false
	_apply_orbitron(confirm, 10)
	confirm.add_theme_color_override("font_color",        Color(0.90, 0.82, 0.45))
	confirm.add_theme_color_override("font_hover_color",  Color(1.00, 0.95, 0.60))
	confirm.pressed.connect(func() -> void:
		var lbl: String = name_edit.text.strip_edges()
		if lbl.is_empty(): lbl = "Site"
		_spawn_poi(data, lbl, selected_placement[0]))
	form.add_child(confirm)

	# insert before BackButton (last child)
	panel_content.add_child(form)
	panel_content.move_child(form, panel_content.get_child_count() - 2)

func _spawn_poi(data: PlanetData, lbl: String, placement: String) -> void:
	var poi       := POIData.new()
	poi.label     = lbl
	poi.type_tag  = placement.to_lower()

	if placement == "Ring":
		# place on ring at a random angle
		var rng := RandomNumberGenerator.new()
		rng.seed = data.seed ^ (data.custom_pois.size() * 0x1234)
		poi.type_tag       = "ring"
		poi.manual_position = true
		poi.lon_deg        = rng.randf_range(0.0, 360.0)   # ring angle degrees
		poi.lat_deg        = rng.randf_range(0.2, 0.8)     # dist_t within ring
		poi.light_intensity = 0.0
	else:
		match placement:
			"Land":  poi.placement = LocationFinder.Placement.LAND
			"Sea":   poi.placement = LocationFinder.Placement.SEA
			"Coast": poi.placement = LocationFinder.Placement.COAST
			_:       poi.placement = LocationFinder.Placement.ANY
		poi.light_intensity = 1.0

	data.custom_pois.append(poi)
	load_planet(data)   # refresh

func _apply_orbitron(node: CanvasItem, size: int) -> void:
	if _orbitron == null:
		return
	node.add_theme_font_override("font", _orbitron)
	node.add_theme_font_size_override("font_size", size)

# ── Details Panel ─────────────────────────────────────────────────────────────

func _build_details_panel(data: PlanetData) -> void:
	if _details_panel and is_instance_valid(_details_panel):
		_details_panel.queue_free()
		_details_panel = null

	var container: Control = planet_renderer.get_parent()
	var pp := GameState.get_planet(data.seed)

	# Root wrapper — freed as one unit via _details_panel
	var root := Control.new()
	root.mouse_filter    = Control.MOUSE_FILTER_IGNORE
	root.z_as_relative   = false
	root.z_index         = 120
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.add_child(root)
	_details_panel = root

	# ── Toggle button ─────────────────────────────────────────────────────────
	var toggle_btn := Button.new()
	toggle_btn.text   = "i"
	toggle_btn.flat   = false
	_apply_orbitron(toggle_btn, 11)
	toggle_btn.add_theme_color_override("font_color",        Color(0.75, 0.80, 1.0, 0.9))
	toggle_btn.add_theme_color_override("font_hover_color",  Color(1.0, 1.0, 1.0))
	toggle_btn.add_theme_stylebox_override("normal",  _make_hud_style(Color(0.07, 0.08, 0.14, 0.85), 6))
	toggle_btn.add_theme_stylebox_override("hover",   _make_hud_style(Color(0.12, 0.14, 0.22, 0.95), 6))
	toggle_btn.add_theme_stylebox_override("pressed", _make_hud_style(Color(0.05, 0.06, 0.12, 0.95), 6))
	toggle_btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())
	toggle_btn.custom_minimum_size = Vector2(28, 28)
	toggle_btn.anchor_left   = 0.0
	toggle_btn.anchor_top    = 0.0
	toggle_btn.offset_left   = 12.0
	toggle_btn.offset_top    = 12.0
	toggle_btn.mouse_filter  = Control.MOUSE_FILTER_STOP
	root.add_child(toggle_btn)

	# ── Info panel ────────────────────────────────────────────────────────────
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_hud_style(Color(0.06, 0.07, 0.13, 0.94), 10))
	panel.anchor_left   = 0.0
	panel.anchor_top    = 0.0
	panel.offset_left   = 12.0
	panel.offset_top    = 48.0
	panel.custom_minimum_size = Vector2(200, 0)
	panel.mouse_filter  = Control.MOUSE_FILTER_STOP
	panel.visible       = _details_open
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	if pp.is_colonized:
		_fill_colonized_details(vbox, data, pp)
	else:
		_fill_uncolonized_details(vbox, data)

	toggle_btn.pressed.connect(func() -> void:
		_details_open = not _details_open
		panel.visible = _details_open)

	toggle_btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	toggle_btn.mouse_exited.connect(func()  -> void: CursorManager.set_state(CursorManager.State.NORMAL))

func _make_hud_style(col: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.border_width_left   = 1
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.25, 0.30, 0.50, 0.35)
	s.corner_radius_top_left     = radius
	s.corner_radius_top_right    = radius
	s.corner_radius_bottom_left  = radius
	s.corner_radius_bottom_right = radius
	s.content_margin_left   = 10.0
	s.content_margin_right  = 10.0
	s.content_margin_top    = 8.0
	s.content_margin_bottom = 8.0
	return s

func _details_row(parent: VBoxContainer, label: String, value: String,
		val_color: Color = Color(0.85, 0.90, 1.0)) -> void:
	var hbox := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_orbitron(lbl, 9)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.7))
	var val := Label.new()
	val.text = value
	_apply_orbitron(val, 9)
	val.add_theme_color_override("font_color", val_color)
	hbox.add_child(lbl)
	hbox.add_child(val)
	parent.add_child(hbox)

func _details_section(parent: VBoxContainer, title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	_apply_orbitron(lbl, 8)
	lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.65))
	parent.add_child(lbl)
	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.2, 0.25, 0.4, 0.4)
	sep_style.content_margin_top    = 0
	sep_style.content_margin_bottom = 0
	sep.add_theme_stylebox_override("separator", sep_style)
	parent.add_child(sep)

func _fill_uncolonized_details(vbox: VBoxContainer, data: PlanetData) -> void:
	_details_section(vbox, "PLANET INFO")
	_details_row(vbox, "Type",  PlanetData.Type.keys()[data.planet_type].capitalize())
	var size_str := "Small" if data.planet_size < 0.8 else ("Large" if data.planet_size > 1.3 else "Medium")
	_details_row(vbox, "Size",  size_str)
	if data.has_atmosphere:
		var atm := "Thin" if data.atmosphere_density < 0.4 else ("Dense" if data.atmosphere_density > 0.7 else "Standard")
		_details_row(vbox, "Atm.", atm)
	else:
		_details_row(vbox, "Atm.",  "None", Color(0.6, 0.4, 0.4))
	_details_row(vbox, "Sea",  "%.0f%%" % (data.sea_level * 100.0) if data.has_atmosphere else "—")

	_details_section(vbox, "RESOURCES")
	var br := GameState.get_body_resources(data.seed, 1, 3)
	for rd: ResourceData in br.as_array():
		_details_row(vbox, "T%d" % rd.tier, rd.unique_name, Color(rd.display_color.r, rd.display_color.g, rd.display_color.b))

	_details_section(vbox, "STATUS")
	_details_row(vbox, "Colony", "Not established", Color(0.65, 0.45, 0.35))

func _fill_colonized_details(vbox: VBoxContainer, data: PlanetData, pp: PlanetProgress) -> void:
	# Header: name + level
	var name_lbl := Label.new()
	name_lbl.text = data.planet_name
	_apply_orbitron(name_lbl, 13)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	vbox.add_child(name_lbl)

	_details_section(vbox, "COLONY")
	_details_row(vbox, "Level",     "Lv %d" % pp.level, Color(1.0, 0.88, 0.4))
	_details_row(vbox, "Districts", "%d / %d" % [pp.districts_used, pp.max_districts])

	_details_section(vbox, "RESOURCES")
	var br := GameState.get_body_resources(data.seed, 1, 3)
	for rd: ResourceData in br.as_array():
		_details_row(vbox, "T%d  %s" % [rd.tier, rd.unique_name], "Available", Color(rd.display_color.r, rd.display_color.g, rd.display_color.b))

	_details_section(vbox, "PLANET INFO")
	_details_row(vbox, "Type", PlanetData.Type.keys()[data.planet_type].capitalize())
	var size_str := "Small" if data.planet_size < 0.8 else ("Large" if data.planet_size > 1.3 else "Medium")
	_details_row(vbox, "Size", size_str)

func _build_system_panel() -> void:
	if _system_dock and is_instance_valid(_system_dock):
		_system_dock.queue_free()
		_system_dock = null

	# Moons unlock check — use the root planet's progress (not the moon's)
	var root_planet := _local_system[0]
	var pp := GameState.get_planet(root_planet.seed) if root_planet != null else null
	var moons_unlocked := pp != null and pp.moons_unlocked

	# Build visible list: planet always; moons only when unlocked
	# No locked placeholders — if locked, dock just shows the planet alone
	var visible_system: Array[PlanetData] = []
	for body in _local_system:
		if body == root_planet or moons_unlocked:
			visible_system.append(body)

	# No dock needed if only one body is visible
	if visible_system.size() <= 1:
		return

	const THUMB  := 52
	const PAD_H  := 16
	const PAD_V  := 10
	const GAP    := 14

	# HUD background panel — anchored to planet container bottom-center
	var planet_container: Control = planet_renderer.get_parent()

	var bg := PanelContainer.new()
	bg.name = "SystemDock"
	# style: dark semi-transparent rounded pill
	var style := StyleBoxFlat.new()
	style.bg_color          = Color(0.06, 0.07, 0.12, 0.82)
	style.corner_radius_top_left     = 12
	style.corner_radius_top_right    = 12
	style.corner_radius_bottom_left  = 0
	style.corner_radius_bottom_right = 0
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 0
	style.border_color        = Color(0.35, 0.45, 0.70, 0.25)
	style.content_margin_left   = PAD_H
	style.content_margin_right  = PAD_H
	style.content_margin_top    = PAD_V
	style.content_margin_bottom = PAD_V
	bg.add_theme_stylebox_override("panel", style)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var dock := HBoxContainer.new()
	dock.add_theme_constant_override("separation", GAP)
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(dock)

	for body_idx in visible_system.size():
		var body      = visible_system[body_idx]
		var is_active: bool = (body == current_data)

		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 5)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var rect := ColorRect.new()
		rect.custom_minimum_size = Vector2(THUMB, THUMB)
		rect.pivot_offset        = Vector2(THUMB, THUMB) * 0.5
		rect.mouse_filter        = Control.MOUSE_FILTER_STOP

		rect.mouse_default_cursor_shape = Control.CURSOR_ARROW if is_active else Control.CURSOR_POINTING_HAND
		var pd := body as PlanetData
		_fill_planet_shader(rect, pd, THUMB)
		if is_active:
			rect.modulate = Color(1.35, 1.28, 0.85)

		var lbl := Label.new()
		lbl.text = pd.planet_name
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_apply_orbitron(lbl, 8)
		lbl.modulate = Color(1.0, 0.92, 0.55) if is_active else Color(0.75, 0.78, 0.85, 0.7)

		slot.add_child(rect)
		slot.add_child(lbl)
		dock.add_child(slot)

		# callout label drawn above the slot via a Node2D overlay
		var callout := Node2D.new()
		callout.visible = is_active
		callout.z_index = 20
		slot.add_child(callout)
		var body_name: String = pd.planet_name
		var is_active_ref := is_active
		var slot_idx      := body_idx
		var slot_count    := visible_system.size()
		callout.draw.connect(func() -> void:
			if _orbitron == null: return
			var go_right: bool = (slot_idx * 2 >= slot_count - 1)
			var dir: float = 1.0 if go_right else -1.0
			var anchor := Vector2(THUMB * 0.5, 0)
			var diag  := Vector2(10.0 * dir, -28.0 if is_active_ref else -18.0)
			var horiz := Vector2(28.0 * dir,   0.0)
			var col   := Color(1.0, 0.92, 0.55) if is_active_ref else Color(0.85, 0.88, 1.0)
			callout.draw_line(anchor, anchor + diag, Color(col, 0.7), 1.0, true)
			callout.draw_line(anchor + diag, anchor + diag + horiz, Color(col, 0.7), 1.0, true)
			callout.draw_circle(anchor, 2.2, Color(col, 0.9))
			var text_offset := Vector2(3.0 * dir, 4.0) if go_right else Vector2(-3.0, 4.0)
			var align := HORIZONTAL_ALIGNMENT_LEFT if go_right else HORIZONTAL_ALIGNMENT_RIGHT
			var text_pos := anchor + diag + horiz + text_offset
			if not go_right:
				var tw := _orbitron.get_string_size(body_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
				text_pos.x -= tw
			callout.draw_string(_orbitron, text_pos, body_name, align, -1, 9, col))

		var cap_lbl     := lbl
		var cap_callout := callout
		var cap_active  := is_active
		rect.mouse_entered.connect(func() -> void:
			CursorManager.set_state(CursorManager.State.POINTER)
			var tw := rect.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(rect, "scale", Vector2(1.22, 1.22), 0.12)
			cap_lbl.modulate = Color(1.0, 1.0, 1.0)
			cap_callout.visible = true
			cap_callout.queue_redraw())
		rect.mouse_exited.connect(func() -> void:
			CursorManager.set_state(CursorManager.State.NORMAL)
			var tw := rect.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(rect, "scale", Vector2(1.0, 1.0), 0.10)
			cap_lbl.modulate = Color(1.0, 0.92, 0.55) if cap_active else Color(0.75, 0.78, 0.85, 0.7)
			cap_callout.visible = cap_active)

		if not is_active:
			var captured_body: PlanetData = pd
			rect.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					load_planet(captured_body))

	# center horizontally, auto-height growing upward from 52px above bottom
	# stick to bottom of planet container, centered horizontally within it
	bg.anchor_left   = 0.5
	bg.anchor_right  = 0.5
	bg.anchor_top    = 1.0
	bg.anchor_bottom = 1.0
	bg.z_as_relative = false
	bg.z_index       = 100   # always on top of rings and planet
	bg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bg.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	bg.offset_left   = 0.0
	bg.offset_right  = 0.0
	bg.offset_bottom = 20.0   # bleed below screen edge so bottom border/corners are hidden
	bg.offset_top    = 0.0

	planet_container.add_child(bg)
	_system_dock = bg

func _fill_planet_shader(rect: ColorRect, body: PlanetData, thumb: int) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(PlanetData.get_shader_path(body.planet_type))
	mat.set_shader_parameter("planet_radius",     0.40)
	mat.set_shader_parameter("pixel_count",       float(thumb))
	mat.set_shader_parameter("aspect_ratio",      1.0)
	mat.set_shader_parameter("seed",              body.seed)
	mat.set_shader_parameter("terrain_roughness", body.terrain_roughness)
	mat.set_shader_parameter("rotation_offset",   0.0)
	mat.set_shader_parameter("light_direction",   Vector3(cos(_light_angle) * 0.85, -0.45, sin(_light_angle) * 0.55).normalized())
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

func _build_companion_moons(_data: PlanetData) -> void:
	pass   # replaced by bottom dock in _build_system_panel

func _on_planet_hover_on() -> void:
	pass

func _on_planet_hover_off() -> void:
	pass

func _position_companions() -> void:
	pass

func _update_aspect() -> void:
	if planet_renderer.material == null:
		return
	var s := planet_renderer.size
	if s.y > 0.0:
		planet_renderer.material.set_shader_parameter("aspect_ratio", s.x / s.y)

func _on_resize() -> void:
	await get_tree().process_frame
	_update_aspect()

func _process(delta: float) -> void:
	_update_aspect()
	if _ring_back != null or _ring_front != null:
		_ring_angle = planet_renderer.get_rotation_offset()
		if _ring_back  and is_instance_valid(_ring_back):  _ring_back.queue_redraw()
		if _ring_front and is_instance_valid(_ring_front): _ring_front.queue_redraw()

	_light_angle = fposmod(_light_angle + delta * LIGHT_SPEED, TAU)
	_apply_light_angle()
	_update_cursor()

func _update_cursor() -> void:
	if planet_renderer == null or planet_renderer._planet_radius_px <= 0:
		return
	var mouse := get_viewport().get_mouse_position()
	var vp    := get_viewport().get_visible_rect().size

	# Drag takes highest priority
	if planet_renderer._dragging:
		_hovering_ui = false
		CursorManager.set_state(CursorManager.State.GRAB)
		return
	# POI hover
	if poi_layer._hovered_index >= 0:
		CursorManager.set_state(CursorManager.State.POINTER)
		return
	# Screen edge → EXIT
	const EDGE := 40.0
	if mouse.x < EDGE or mouse.y < EDGE or mouse.x > vp.x - EDGE or mouse.y > vp.y - EDGE:
		CursorManager.set_state(CursorManager.State.EXIT)
		return
	# Everything else → NORMAL (panel bg, planet surface, empty space)
	CursorManager.set_state(CursorManager.State.NORMAL)

func _apply_light_angle() -> void:
	if planet_renderer == null or planet_renderer.material == null:
		return
	var lx := cos(_light_angle) * 0.85
	var lz := sin(_light_angle) * 0.55
	var ld := Vector3(lx, -0.45, lz).normalized()
	(planet_renderer.material as ShaderMaterial).set_shader_parameter("light_direction", ld)

func _on_planet_clicked(_screen_pos: Vector2) -> void:
	pass

func _on_poi_clicked(index: int, _data: Dictionary) -> void:
	if index >= poi_layer._pois.size():
		return
	var poi_dict: Dictionary = poi_layer._pois[index]
	var poi_label: String    = poi_dict.get("label", "")
	if current_data == null:
		return
	# Find matching POIData
	var poi: POIData = null
	for pd: POIData in current_data.custom_pois:
		if pd.label == poi_label:
			poi = pd
			break
	if poi == null:
		return
	_build_poi_panel(poi, current_data)

func _build_poi_panel(poi: POIData, planet: PlanetData) -> void:
	var panel_content := $RightPanel/PanelContent
	var old := panel_content.get_node_or_null("POIBuildPanel")
	if old:
		old.free()

	var pp   := GameState.get_planet(planet.seed)
	var root := VBoxContainer.new()
	root.name = "POIBuildPanel"
	root.add_theme_constant_override("separation", 8)
	root.add_child(HSeparator.new())

	var header := HBoxContainer.new()
	var poi_title := Label.new()
	poi_title.text = poi.label + "  ·  " + poi.type_label()
	_apply_orbitron(poi_title, 11)
	poi_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	poi_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(poi_title)

	var slots_lbl := Label.new()
	var slots_used := pp.slots_used_in_poi(poi.label)
	slots_lbl.text = "%d/%d slots" % [slots_used, poi.max_building_slots()]
	_apply_orbitron(slots_lbl, 9)
	slots_lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.8))
	header.add_child(slots_lbl)
	root.add_child(header)

	# ── Installed buildings ───────────────────────────────────────────────────
	var installed := pp.buildings_in_poi(poi.label)
	if installed.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No buildings yet."
		_apply_orbitron(empty_lbl, 9)
		empty_lbl.add_theme_color_override("font_color", Color(0.45, 0.5, 0.65))
		root.add_child(empty_lbl)
	else:
		for entry: Dictionary in installed:
			var def := BuildingDef.find(entry.get("building_id", ""))
			if def == null:
				continue
			var row := HBoxContainer.new()
			var name_lbl := Label.new()
			name_lbl.text = def.display_name
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_apply_orbitron(name_lbl, 10)
			name_lbl.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0))
			var energy_lbl := Label.new()
			var sign := "+" if def.energy_delta > 0 else ""
			energy_lbl.text = sign + "%.0f⚡" % def.energy_delta
			_apply_orbitron(energy_lbl, 9)
			energy_lbl.add_theme_color_override("font_color",
				Color(0.4, 1.0, 0.6) if def.energy_delta > 0 else Color(0.9, 0.6, 0.3))
			row.add_child(name_lbl)
			row.add_child(energy_lbl)
			root.add_child(row)

	# ── Buildable list ────────────────────────────────────────────────────────
	var buildable := BuildingDef.for_poi_type(poi.poi_type)
	if not buildable.is_empty():
		var build_title := Label.new()
		build_title.text = "BUILD"
		_apply_orbitron(build_title, 8)
		build_title.add_theme_color_override("font_color", Color(0.4, 0.45, 0.65))
		root.add_child(build_title)

	for def: BuildingDef in buildable:
		if def.min_planet_lv > pp.level:
			continue
		var slots_free := poi.max_building_slots() - pp.slots_used_in_poi(poi.label)
		var can_afford := GameState.credits >= def.base_cost
		var has_slots  := slots_free >= def.slot_cost

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var def_name := Label.new()
		def_name.text = def.display_name
		_apply_orbitron(def_name, 10)
		def_name.add_theme_color_override("font_color",
			Color(0.75, 0.82, 1.0) if (can_afford and has_slots) else Color(0.4, 0.43, 0.55))
		var def_cost := Label.new()
		def_cost.text = "%.0f cr  ·  %d slot" % [def.base_cost, def.slot_cost]
		_apply_orbitron(def_cost, 8)
		def_cost.add_theme_color_override("font_color",
			Color(0.5, 0.75, 0.45) if can_afford else Color(0.7, 0.35, 0.3))
		info.add_child(def_name)
		info.add_child(def_cost)

		var btn := Button.new()
		btn.text     = "▶"
		btn.flat     = false
		btn.disabled = not (can_afford and has_slots)
		_apply_orbitron(btn, 10)
		btn.custom_minimum_size = Vector2(28, 28)
		btn.add_theme_color_override("font_color", Color(0.9, 0.82, 0.45))
		btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
		btn.mouse_exited.connect(func()  -> void: CursorManager.set_state(CursorManager.State.NORMAL))
		var cap_poi := poi
		var cap_def := def
		var cap_planet := planet
		btn.pressed.connect(func() -> void:
			if GameState.spend_credits(cap_def.base_cost):
				pp.build_in_poi(cap_poi, cap_def.building_id)
				GameState.planet_progress_changed.emit(cap_planet.seed)
				_build_poi_panel(cap_poi, cap_planet))

		row.add_child(info)
		row.add_child(btn)
		root.add_child(row)

	panel_content.add_child(root)

func _on_seed_clicked(event: InputEvent, s: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		DisplayServer.clipboard_set(str(s))

func _build_rings(data: PlanetData) -> void:
	if _ring_back  and is_instance_valid(_ring_back):  _ring_back.queue_free()
	if _ring_front and is_instance_valid(_ring_front): _ring_front.queue_free()
	_ring_back  = null
	_ring_front = null
	_ring_particles.clear()
	_ring_angle = 0.0
	if not data.has_rings:
		return

	# generate a few particles with seed-based positions
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed ^ 0x52494E47
	var ptc_count: int = rng.randi_range(2, 4)
	for _p in ptc_count:
		_ring_particles.append({
			"angle":  rng.randf_range(0.0, TAU),
			"dist_t": rng.randf_range(0.15, 0.85),   # lerp between inner/outer
			"size":   rng.randf_range(3.0, 6.0),
			"speed":  rng.randf_range(0.04, 0.10),
		})

	# both ring nodes live inside PlanetContainer so z_index is comparable to planet_renderer
	var container: Control = planet_renderer.get_parent()
	planet_renderer.z_index = 5   # explicit so ring nodes can go above/below

	_ring_back = Node2D.new()
	_ring_back.z_as_relative = false
	_ring_back.z_index = 4
	container.add_child(_ring_back)
	_ring_back.draw.connect(func() -> void: _draw_planet_rings(_ring_back, PI, TAU, true))

	_ring_front = Node2D.new()
	_ring_front.z_as_relative = false
	_ring_front.z_index = 6
	container.add_child(_ring_front)
	_ring_front.draw.connect(func() -> void: _draw_planet_rings(_ring_front, 0.0, PI, false))

	# POILayer must stay above ring_front so labels are never covered
	poi_layer.z_as_relative = false
	poi_layer.z_index = 10

func _draw_planet_rings(target: Node2D, from_a: float, to_a: float, is_back: bool) -> void:
	if current_data == null or not current_data.has_rings:
		return
	var r:    Rect2 = planet_renderer.get_rect()
	var cx:   float = r.position.x + r.size.x * 0.5
	var cy:   float = r.position.y + r.size.y * 0.5
	var half: float = r.size.x * 0.5
	var yr:   float = 0.26
	var ir:   float = half * current_data.ring_inner
	var or_:  float = half * current_data.ring_outer
	var col:  Color = current_data.ring_color
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
		for s in steps + 1:
			var a := from_a + (to_a - from_a) * float(s) / float(steps)
			pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * rx * yr))
		target.draw_polyline(pts, Color(col.r, col.g, col.b, alp), 2.0, true)

	# ring POIs — same depth-faking trick as particles, only in front node
	if not is_back and current_data != null:
		for pd: POIData in current_data.custom_pois:
			if pd.type_tag != "ring":
				continue
			var pa: float  = fposmod(deg_to_rad(pd.lon_deg) + _ring_angle, TAU)
			var dt: float  = pd.lat_deg   # dist_t stored in lat_deg
			var rx: float  = lerp(ir, or_, dt)
			var px: float  = cx + cos(pa) * rx
			var py: float  = cy + sin(pa) * rx * yr
			var depth: float = (sin(pa) + 1.0) * 0.5
			var a: float   = lerp(0.20, 1.0, depth)
			var fc: Color  = Color(1.0, 0.92, 0.55, a)
			target.draw_circle(Vector2(px, py), 5.0, Color(0.0, 0.0, 0.0, a * 0.6))
			target.draw_circle(Vector2(px, py), 3.5, fc)
			if depth > 0.35:   # only show label when near front
				if _orbitron:
					target.draw_string(_orbitron, Vector2(px + 7, py + 4),
						pd.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
						Color(1.0, 0.92, 0.55, a * 0.9))

	# particles: only draw in _ring_front (is_back=false) to avoid node-switch jump.
	if is_back:
		return
	for ptc: Dictionary in _ring_particles:
		var pa:    float = fposmod(ptc["angle"] + _ring_angle, TAU)
		var rx:    float = lerp(ir, or_, float(ptc["dist_t"]))
		var px:    float = cx + cos(pa) * rx
		var py:    float = cy + sin(pa) * rx * yr
		var ps:    float = float(ptc["size"])
		# depth: sin(pa) ranges -1 (top/back) to +1 (bottom/front)
		var depth: float = (sin(pa) + 1.0) * 0.5
		var palp:  float = col.a * lerp(0.22, 0.95, depth)   # dim when behind
		var psize: float = ps * lerp(0.5, 1.0, depth)         # smaller when behind
		target.draw_circle(Vector2(px, py), psize,
			Color(col.r * 1.1, col.g * 1.05, col.b, palp))
		target.draw_circle(Vector2(px, py), psize * 0.45,
			Color(1.0, 0.96, 0.88, palp * 0.9))
