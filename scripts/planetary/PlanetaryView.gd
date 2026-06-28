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
## Tracks which district POI is currently shown in the district panel.
## Used by _on_building_constructed to refresh panel without DOM traversal.
var _active_district_poi: POIData = null
var _overview_energy_val: Label = null   # kept for live energy updates
var _orbital_layer: OrbitalLayer = null

## Active rocket launch animation state. Empty when no launch in progress.
## Keys: rocket(Control), radius(float), angle_rel(float), alpha(float),
##       phase(int 0=rise/1=turn/2=fade), phase_t(float), on_complete(Callable),
##       planet_seed(int), orbit_inc(float), insert_angle_rel(float), planet_r(float)
var _rocket_anim: Dictionary = {}
## Toast log container — created lazily, anchored bottom-left.
var _toast_container: VBoxContainer = null
## Maps building pm_key -> bool indicating if its mineral switcher tray is expanded
var _open_mineral_switchers: Dictionary = {}

## Live district construction progress bars.
var _district_pbars: Dictionary = {}
func _make_system(root: PlanetData) -> Array[PlanetData]:
	var arr: Array[PlanetData] = [root]
	for m in root.moons:
		arr.append(m)
	return arr


func _ready() -> void:
	CursorManager.set_state(CursorManager.State.NORMAL)
	_orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")
	planet_renderer.planet_clicked.connect(_on_planet_clicked)
	poi_layer.poi_clicked.connect(_on_district_clicked)
	get_tree().root.size_changed.connect(_on_resize)
	pass  # cursor handled per-element, not per-panel
	# back button removed — navigation handled via system dock / unlock flow
	GameState.unlock_changed.connect(_on_unlock_changed)
	GameState.planet_progress_changed.connect(func(_s: int) -> void:
		_build_system_panel()
		if current_data != null:
			_build_details_panel(current_data)
			if _active_district_poi == null:
				_build_planet_overview(current_data)
			else:
				_build_district_panel(_active_district_poi, current_data))
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
		# Close slot dropdown on any click outside it
		if mb.pressed and _active_slot_dropdown != null \
				and is_instance_valid(_active_slot_dropdown):
			var dd_rect := _active_slot_dropdown.get_global_rect()
			if not dd_rect.has_point(get_viewport().get_mouse_position()):
				_active_slot_dropdown.queue_free()
				_active_slot_dropdown = null
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			if poi_layer._selected_index >= 0:
				poi_layer.deselect_all()
				_build_planet_overview(current_data)
				get_viewport().set_input_as_handled()
			else:
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
	_active_district_poi = null   # clear stale reference on planet switch
	_open_mineral_switchers.clear()
	GameState.active_planet_seed = data.seed
	GameState.cache_planet_data(data)
	_setup_material(data)
	# Sync light state to the renderer for this planet
	planet_renderer.local_time_offset = data.local_time_offset
	planet_renderer.light_angle       = _light_angle
	planet_renderer._update_light_direction()
	_update_panel(data)
	_build_companion_moons(data)
	_build_rings(data)
	_build_system_panel()
	_build_details_panel(data)
	poi_layer.setup(planet_renderer)
	poi_layer.clear_pois()
	_setup_orbital_layer(data.seed)

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
				# Store resolved position back so rotation and overview card can use it
				pd.lon_deg = rad_to_deg(lon)
				pd.lat_deg = rad_to_deg(lat)
				pd.manual_position = true
			pois.append({
				"lon_deg": rad_to_deg(lon), "lat_deg": rad_to_deg(lat),
				"label": pd.label,
				"data": {
					"type": pd.type_tag,
					"light_intensity": pd.light_intensity,
					"night_size": _district_night_size(data, pd.label),
				}
			})
	# no auto-generated POIs — only custom_pois are shown

	# rotate so the first (primary) POI faces the viewer at load
	if pois.size() > 0:
		planet_renderer.set_rotation_offset(deg_to_rad(pois[0]["lon_deg"]))

	for poi in pois:
		poi_layer.add_poi(poi["lon_deg"], poi["lat_deg"], poi["label"], poi["data"])

	_upload_poi_lights(pois, data)
	# After POIs are loaded, sync night sizes so shader glow starts correctly
	_update_poi_night_sizes(data)
	_refresh_poi_lights(data)
	_build_planet_overview(data)

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
			# Scale intensity by active building count: 0 bldgs = 0, 1 = tiny, max ~10 = ~0.35
			var ns: int     = int(pois[i].get("data", {}).get("night_size", 0))
			var intensity: float = clampf(float(ns) * 0.035, 0.0, 0.35)
			var nx: float = sin(lon) * cos(lat)
			var ny: float = -sin(lat)
			var nz: float = cos(lon) * cos(lat)
			mat.set_shader_parameter(names[i], Vector4(nx, ny, nz, intensity))
		else:
			mat.set_shader_parameter(names[i], Vector4(0,0,0,0))

func _refresh_poi_lights(data: PlanetData) -> void:
	if current_data == null or current_data.seed != data.seed:
		return
	var pp := GameState.get_planet(data.seed)
	var pois_fresh: Array[Dictionary] = []
	for pd: POIData in data.custom_pois:
		pois_fresh.append({
			"lon_deg": pd.lon_deg, "lat_deg": pd.lat_deg,
			"label":   pd.label,
			"data":    {
				"type": pd.type_tag,
				"light_intensity": pd.light_intensity,
				"night_size": _district_night_size(data, pd.label),
			}
		})
	_upload_poi_lights(pois_fresh, data)

func _update_panel(data: PlanetData) -> void:
	var name_label  := $RightPanel/PanelContent/PlanetName as Label
	var type_label  := $RightPanel/PanelContent/PlanetType as Label
	var type_names  := ["Terran", "Arid", "Ice", "Volcanic", "Barren", "Gas Giant", "Moon", "Asteroid"]
	if name_label: name_label.text = data.planet_name
	if type_label: type_label.text = type_names[data.planet_type]
	if type_label: type_label.visible = true
	_build_system_panel()

var _name_form_overlay: Control = null

func _show_district_name_form_modal(data: PlanetData, def: DistrictDef) -> void:
	if _name_form_overlay != null and is_instance_valid(_name_form_overlay):
		_name_form_overlay.queue_free()
		_name_form_overlay = null

	var panel_content := $RightPanel/PanelContent

	var overlay := PanelContainer.new()
	overlay.add_theme_stylebox_override("panel", _make_hud_style(Color(0.06, 0.08, 0.17, 0.98), 8))
	overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay.z_index = 20

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	overlay.add_child(vbox)

	# Header row: icon + type name + close
	var header := HBoxContainer.new()
	var type_lbl := Label.new()
	type_lbl.text = "%s  %s" % [def.icon, def.display_name]
	_apply_orbitron(type_lbl, 10)
	type_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	type_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(type_lbl)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	_apply_orbitron(close_btn, 9)
	close_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	close_btn.pressed.connect(func() -> void:
		overlay.queue_free()
		_name_form_overlay = null)
	header.add_child(close_btn)
	vbox.add_child(header)

	var desc_lbl := Label.new()
	desc_lbl.text = def.description
	_apply_orbitron(desc_lbl, 8)
	desc_lbl.add_theme_color_override("font_color", Color(0.50, 0.55, 0.72))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(desc_lbl)

	# Cost row
	var cost: float = DistrictDef.placement_cost(def, data)
	var cost_row := HBoxContainer.new()
	var cost_icon := Label.new()
	cost_icon.text = "◈"
	_apply_orbitron(cost_icon, 9)
	cost_icon.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	cost_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(cost_icon)
	var cost_lbl := Label.new()
	cost_lbl.text = HUDManager.fmt_credits(cost)
	_apply_orbitron(cost_lbl, 9)
	cost_lbl.add_theme_color_override("font_color",
		Color(0.55, 0.70, 0.40) if GameState.credits >= cost else Color(0.85, 0.32, 0.32))
	cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_row.add_child(cost_lbl)
	vbox.add_child(cost_row)

	var name_edit := LineEdit.new()
	name_edit.text             = def.suggest_name(data)
	name_edit.placeholder_text = "District name..."
	name_edit.custom_minimum_size = Vector2(0, 28)
	_apply_orbitron(name_edit, 10)
	vbox.add_child(name_edit)

	var confirm := Button.new()
	confirm.text = "▶  PLACE DISTRICT"
	_apply_orbitron(confirm, 9)
	confirm.add_theme_color_override("font_color",       Color(0.90, 0.82, 0.45))
	confirm.add_theme_color_override("font_hover_color", Color(1.00, 0.95, 0.60))
	confirm.disabled = GameState.credits < cost
	var cap_def  := def
	var cap_data := data
	var cap_cost := cost
	confirm.pressed.connect(func() -> void:
		if not GameState.spend_credits(cap_cost):
			return
		var lbl: String = name_edit.text.strip_edges()
		if lbl.is_empty(): lbl = cap_def.display_name
		if is_instance_valid(overlay):
			overlay.queue_free()
		_name_form_overlay = null
		_spawn_district(cap_data, lbl, cap_def))
	vbox.add_child(confirm)

	panel_content.add_child(overlay)
	_name_form_overlay = overlay
	name_edit.grab_focus()

func _spawn_district(data: PlanetData, lbl: String, def: DistrictDef) -> void:
	var poi          := POIData.new()
	poi.label        = lbl
	poi.poi_type     = def.to_poi_type()
	poi.type_tag     = DistrictDef.Type.keys()[def.id].to_lower()
	poi.placement    = def.placement
	poi.light_intensity = 0.0 if def.placement == LocationFinder.Placement.ANY else 1.0
	poi.constructing = true
	poi.construct_progress = 0.0
	poi.construct_duration = def.construction_duration

	# Pre-seed LocationFinder with existing district positions so new ones spread out.
	# Same-type districts use double the avoidance angle to push them further apart.
	var lf := LocationFinder.new(
		data.seed ^ (data.custom_pois.size() * 0xBEEF),
		data.sea_level, data.terrain_roughness, data.continent_scale)
	for existing: POIData in data.custom_pois:
		if existing.manual_position:
			var lon := deg_to_rad(existing.lon_deg)
			lf._used_lons.append(lon)
			# double-add same-type districts so avoidance loop hits twice → bigger gap
			if existing.poi_type == def.to_poi_type():
				lf._used_lons.append(fposmod(lon + deg_to_rad(5.0), TAU))

	var pos := lf.find(def.placement)
	poi.lon_deg = rad_to_deg(pos.x)
	poi.lat_deg = rad_to_deg(pos.y)
	poi.manual_position = true

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

	if not ProductionManager.building_progress_changed.is_connected(_on_production_update):
		ProductionManager.building_progress_changed.connect(_on_production_update)

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

	toggle_btn.mouse_entered.connect(func() -> void:
		if not _is_at_edge(): CursorManager.set_state(CursorManager.State.POINTER))
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
		val_color: Color = Color(0.85, 0.90, 1.0)) -> HBoxContainer:
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
	return hbox

## Vivid rarity-based border color (hue = rarity, always max sat/brightness).
func _rarity_border_color(rarity: int) -> Color:
	var r: float = clampf(float(rarity - 1) / 14.0, 0.0, 1.0)
	var hue: float
	if r < 0.33:
		hue = lerp(0.60, 0.35, r / 0.33)
	elif r < 0.66:
		hue = lerp(0.35, 0.78, (r - 0.33) / 0.33)
	else:
		hue = lerp(0.78, 0.12, (r - 0.66) / 0.34)
	return Color.from_hsv(hue, 0.88, 1.00)

## Format large numbers with K / M / B suffix.
func _fmt_amount(n: float) -> String:
	if n >= 1_000_000_000.0:
		return "%.1fB" % (n / 1_000_000_000.0)
	elif n >= 1_000_000.0:
		return "%.1fM" % (n / 1_000_000.0)
	elif n >= 1_000.0:
		return "%.1fK" % (n / 1_000.0)
	return "%.0f" % n

## Item-style resource card. Rarity = thick left border color. Tier = icon shape.
## show_count=false → compact square chip (discovery grid, no amount).
## show_count=true  → full-width card: icon left, formatted count right, no name label.
func _mineral_icon_cell(rd: ResourceData, show_count: bool, stored: float = 0.0) -> PanelContainer:
	var rarity_col := _rarity_border_color(rd.rarity)

	var cell := PanelContainer.new()
	var s    := StyleBoxFlat.new()
	s.bg_color            = Color(0.07, 0.08, 0.13, 0.92)
	s.border_color        = rarity_col
	s.border_width_left   = 3
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left     = 4; s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left  = 4; s.corner_radius_bottom_right = 4
	s.content_margin_left   = 5; s.content_margin_right  = 6
	s.content_margin_top    = 4; s.content_margin_bottom = 4
	cell.add_theme_stylebox_override("panel", s)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	if show_count:
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 5)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(inner)

	var tex       := MineralIcon.make(rd.tier, rd.display_color)
	var icon_rect := TextureRect.new()
	icon_rect.texture             = tex
	icon_rect.custom_minimum_size = Vector2(18, 18)
	icon_rect.stretch_mode        = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	inner.add_child(icon_rect)

	if show_count:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(spacer)

		var count_lbl := Label.new()
		count_lbl.text = _fmt_amount(stored)
		_apply_orbitron(count_lbl, 9)
		count_lbl.add_theme_color_override("font_color",
			Color(0.95, 0.97, 1.0) if stored > 0.0 else Color(0.42, 0.45, 0.55))
		count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(count_lbl)

	var tier_suffix := ResourceData.TIER_SUFFIXES[clampi(rd.tier - 1, 0, ResourceData.TIER_SUFFIXES.size() - 1)]
	var tip_body := "R%d  ·  T%d %s" % [rd.rarity, rd.tier, tier_suffix]
	cell.mouse_entered.connect(func() -> void:
		TooltipManager.show_tip(rd.unique_name, tip_body))
	cell.mouse_exited.connect(func() -> void:
		TooltipManager.hide_tip())

	return cell

## Square grid card: icon top, count bottom, fixed width. Used in resource grid.
func _mineral_grid_card(rd: ResourceData, stored: float, show_count: bool, sub_label: String = "", pp: PlanetProgress = null) -> PanelContainer:
	var rarity_col := _rarity_border_color(rd.rarity)

	var card := PanelContainer.new()
	var s    := StyleBoxFlat.new()
	s.bg_color            = Color(0.07, 0.08, 0.13, 0.92)
	s.border_color        = rarity_col
	s.border_width_left   = 2
	s.border_width_right  = 2
	s.border_width_top    = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left     = 5; s.corner_radius_top_right    = 5
	s.corner_radius_bottom_left  = 5; s.corner_radius_bottom_right = 5
	s.content_margin_left   = 6; s.content_margin_right  = 6
	s.content_margin_top    = 6; s.content_margin_bottom = 5
	card.add_theme_stylebox_override("panel", s)
	card.custom_minimum_size = Vector2(44, 44) if not show_count else Vector2(52, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var tex       := MineralIcon.make(rd.tier, rd.display_color)
	var icon_rect := TextureRect.new()
	icon_rect.texture   = tex
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if show_count:
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 3)
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(vbox)

		icon_rect.custom_minimum_size   = Vector2(22, 22)
		icon_rect.stretch_mode          = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon_rect)

		var count_lbl := Label.new()
		count_lbl.text = _fmt_amount(stored)
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_apply_orbitron(count_lbl, 8)
		count_lbl.add_theme_color_override("font_color",
			Color(0.95, 0.97, 1.0) if stored > 0.0 else Color(0.42, 0.45, 0.55))
		count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(count_lbl)
	else:
		var vbox2 := VBoxContainer.new()
		vbox2.add_theme_constant_override("separation", 2)
		vbox2.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(vbox2)

		icon_rect.custom_minimum_size   = Vector2(24, 24)
		icon_rect.stretch_mode          = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox2.add_child(icon_rect)

		if sub_label != "":
			var sl := Label.new()
			sl.text = sub_label
			sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_apply_orbitron(sl, 7)
			sl.add_theme_color_override("font_color", Color(0.70, 0.75, 0.90))
			sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox2.add_child(sl)

	var tier_suffix := ResourceData.TIER_SUFFIXES[clampi(rd.tier - 1, 0, ResourceData.TIER_SUFFIXES.size() - 1)]
	var cap_rd := rd
	var cap_pp := pp
	card.mouse_entered.connect(func() -> void:
		var header := "R%d  ·  T%d %s" % [cap_rd.rarity, cap_rd.tier, tier_suffix]
		var rid    := cap_rd.resource_id()
		if cap_pp == null:
			TooltipManager.show_tip(cap_rd.unique_name, header)
			return
		# Compute per-building income / expense for this resource
		var income_lines: Array[String] = []
		var expense_lines: Array[String] = []
		var net: float = 0.0
		for entry: Dictionary in cap_pp.buildings:
			if entry.get("constructing", false): continue
			var def := BuildingDef.find(entry.get("building_id", ""))
			if def == null: continue
			var amt: int     = entry.get("amount", 1)
			var cycle: float = def.tick_duration if def.tick_duration > 0.0 else 1.0
			# Producer: mine / refinery outputting this specific resource
			if (def.output_type == BuildingDef.OutputType.RAW_MINERAL or
					def.output_type == BuildingDef.OutputType.REFINED_MINERAL):
				var tgt: String = entry.get("target_mineral", "")
				if tgt == rid:
					var rate: float = def.output_amount * float(amt) * get_node("/root/SkillTree").get_mine_output_mult() / cycle
					income_lines.append("+%.2f/s  %s" % [rate, def.display_name])
					net += rate
			# Consumer: building that uses this resource as input
			if def.input_type != BuildingDef.OutputType.NONE:
				var input_rid: String = entry.get("input_mineral", "")
				if input_rid == rid:
					var rate: float = def.input_amount * float(amt) / cycle
					expense_lines.append("−%.2f/s  %s" % [rate, def.display_name])
					net -= rate
		var body_lines: Array[String] = [header]
		if not income_lines.is_empty() or not expense_lines.is_empty():
			body_lines.append("")
			body_lines.append_array(income_lines)
			body_lines.append_array(expense_lines)
		var net_cost: String = ""
		if not income_lines.is_empty() or not expense_lines.is_empty():
			var net_sign := "+" if net >= 0.0 else ""
			net_cost = "%s%.2f / s" % [net_sign, net]
		TooltipManager.show_tip(cap_rd.unique_name, "\n".join(body_lines), net_cost)
		# Tint Net label red when negative
		if net_cost != "":
			TooltipManager.set_cost_color(Color(0.35, 0.85, 0.45) if net >= 0.0 else Color(0.90, 0.38, 0.28)))
	card.mouse_exited.connect(func() -> void:
		TooltipManager.hide_tip())

	return card

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
	_fill_modifiers_section(vbox, data)
	_details_section(vbox, "PLANET INFO")
	_details_row(vbox, "Type", PlanetData.Type.keys()[data.planet_type].capitalize())
	var size_str := "Small" if data.planet_size < 0.8 else ("Large" if data.planet_size > 1.3 else "Medium")
	_details_row(vbox, "Size", size_str)
	if data.has_atmosphere:
		var atm := "Thin" if data.atmosphere_density < 0.4 else ("Dense" if data.atmosphere_density > 0.7 else "Standard")
		_details_row(vbox, "Atm.", atm)
	else:
		_details_row(vbox, "Atm.", "None", Color(0.6, 0.4, 0.4))
	_details_section(vbox, "STATUS")
	_details_row(vbox, "Colony", "Not established", Color(0.65, 0.45, 0.35))
	_fill_deposits_section(vbox, data)

func _fill_colonized_details(vbox: VBoxContainer, data: PlanetData, _pp: PlanetProgress) -> void:
	_fill_modifiers_section(vbox, data)
	_details_section(vbox, "PLANET INFO")
	_details_row(vbox, "Type", PlanetData.Type.keys()[data.planet_type].capitalize())
	var size_str := "Small" if data.planet_size < 0.8 else ("Large" if data.planet_size > 1.3 else "Medium")
	_details_row(vbox, "Size", size_str)
	if data.has_atmosphere:
		var atm := "Thin" if data.atmosphere_density < 0.4 else ("Dense" if data.atmosphere_density > 0.7 else "Standard")
		_details_row(vbox, "Atm.", atm)
	else:
		_details_row(vbox, "Atm.", "None", Color(0.6, 0.4, 0.4))
	_fill_deposits_section(vbox, data)

## Left panel "DEPOSITS" — shows which T1 raw minerals can be mined here. No amounts.
func _fill_deposits_section(vbox: VBoxContainer, data: PlanetData) -> void:
	var br := GameState.get_body_resources_for(data)
	if br.as_array().is_empty():
		return

	_details_section(vbox, "DEPOSITS")

	var rng := RandomNumberGenerator.new()
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	for rd: ResourceData in br.as_array():
		var rid := rd.resource_id()
		var mineral_density: float
		if data.mineral_densities.has(rid):
			mineral_density = float(data.mineral_densities[rid])
		else:
			rng.seed = data.seed ^ (rd.rarity * 0x4E3D)
			mineral_density = data.deposit_density * rng.randf_range(0.75, 1.25)
		var pct_text := "%d%%" % int(round(mineral_density * 100.0))
		grid.add_child(_mineral_grid_card(rd, 0.0, false, pct_text))
	vbox.add_child(grid)

## Active building count for a district (for night-light glow size).
## Excludes constructing and user-paused buildings.
func _district_night_size(data: PlanetData, district_label: String) -> int:
	var pp := GameState.get_planet(data.seed)
	var total: int = 0
	var entries := pp.buildings_in_district(district_label)
	for i in entries.size():
		var b: Dictionary = entries[i]
		if b.get("constructing", false):
			continue
		var global_idx: int = pp.building_real_index(b)
		var pm_key: String  = "%d:%s:%d" % [data.seed, district_label, global_idx]
		if ProductionManager.is_user_paused(pm_key):
			continue
		total += b.get("amount", 1)
	return total

func _update_poi_night_sizes(data: PlanetData) -> void:
	for i in poi_layer._pois.size():
		var label: String = poi_layer._pois[i]["label"]
		poi_layer._pois[i]["data"]["night_size"] = _district_night_size(data, label)

## Returns total energy balance (positive = surplus) and per-district breakdown dict.
func _planet_energy_breakdown(pp: PlanetProgress, data: PlanetData) -> Dictionary:
	var total: float = 0.0
	var by_district: Dictionary = {}  # label -> float
	for i in pp.buildings.size():
		var b: Dictionary = pp.buildings[i]
		if b.get("constructing", false) or ProductionManager.is_user_paused(
				"%d:%s:%d" % [pp.planet_seed, b.get("district_id",""), i]):
			continue
		var def := BuildingDef.find(b.get("building_id", ""))
		if def == null:
			continue
		var amt: int  = b.get("amount", 1)
		var label: String = b.get("district_id", "")
		
		# Read modified energy flow
		var etick := def.energy_per_tick
		if etick > 0.0:
			if def.building_id == "solar_panel":
				etick *= get_node("/root/SkillTree").get_solar_mult()
		elif etick < 0.0:
			etick *= get_node("/root/SkillTree").get_energy_consume_mult()
			
		var contrib: float = etick * amt
		if def.output_type == BuildingDef.OutputType.ENERGY:
			var mult := 1.0
			if def.building_id == "solar_panel":
				mult = get_node("/root/SkillTree").get_solar_mult()
			elif def.building_id == "generator":
				mult = get_node("/root/SkillTree").get_generator_output_mult()
				var in_min: String = b.get("burning_mineral", "")
				if in_min != "":
					var rd: ResourceData = GameState.known_resources.get(in_min)
					if rd: mult *= float(rd.rarity)
				else:
					mult = 0.0 # No fuel, no energy!
			contrib += def.output_amount * amt * mult
			
		total += contrib
		by_district[label] = by_district.get(label, 0.0) + contrib
	var result: Dictionary = { "total": total }
	for poi: POIData in data.custom_pois:
		if by_district.has(poi.label):
			result[poi.label] = by_district[poi.label]
	return result

func _planet_energy_balance(pp: PlanetProgress) -> float:
	var bal: float = 0.0
	for b: Dictionary in pp.buildings:
		if b.get("constructing", false):
			continue
		var def := BuildingDef.find(b.get("building_id", ""))
		if def == null:
			continue
		var amt: int = b.get("amount", 1)
		
		# Read modified energy flow
		var etick := def.energy_per_tick
		if etick > 0.0:
			if def.building_id == "solar_panel":
				etick *= get_node("/root/SkillTree").get_solar_mult()
		elif etick < 0.0:
			etick *= get_node("/root/SkillTree").get_energy_consume_mult()
			
		bal += etick * amt
		if def.output_type == BuildingDef.OutputType.ENERGY:
			var mult := 1.0
			if def.building_id == "solar_panel":
				mult = get_node("/root/SkillTree").get_solar_mult()
			elif def.building_id == "generator":
				mult = get_node("/root/SkillTree").get_generator_output_mult()
				var in_min: String = b.get("burning_mineral", "")
				if in_min != "":
					var rd: ResourceData = GameState.known_resources.get(in_min)
					if rd: mult *= float(rd.rarity)
				else:
					mult = 0.0 # No fuel, no energy!
			bal += def.output_amount * amt * mult
	return bal

func _fill_modifiers_section(vbox: VBoxContainer, data: PlanetData) -> void:
	var mods := PlanetModifier.for_planet(data.planet_type)
	if mods.is_empty():
		return
	var tag_row := HFlowContainer.new()
	tag_row.add_theme_constant_override("h_separation", 4)
	tag_row.add_theme_constant_override("v_separation", 5)
	tag_row.size_flags_horizontal = Control.SIZE_FILL
	for m: PlanetModifier in mods:
		var positive := m.is_positive()
		var tag := Button.new()
		tag.text = "%s %s" % [m.display_name, m.value_label()]
		tag.flat = true
		_apply_orbitron(tag, 8)
		# Outer glow/outline wrapper — dark stroke around the pill
		var outer := PanelContainer.new()
		var os := StyleBoxFlat.new()
		os.bg_color    = Color(0.0, 0.0, 0.0, 0.55)
		os.border_color = Color(0.0, 0.0, 0.0, 0.45)
		os.border_width_left = 1; os.border_width_right  = 1
		os.border_width_top  = 1; os.border_width_bottom = 1
		os.corner_radius_top_left     = 5; os.corner_radius_top_right    = 5
		os.corner_radius_bottom_left  = 5; os.corner_radius_bottom_right = 5
		os.content_margin_left   = 1; os.content_margin_right  = 1
		os.content_margin_top    = 1; os.content_margin_bottom = 1
		outer.add_theme_stylebox_override("panel", os)
		outer.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var border_col := Color(0.35, 0.85, 0.48, 0.90) if positive else Color(0.88, 0.32, 0.32, 0.90)
		var bg_col     := Color(0.07, 0.18, 0.10, 0.88) if positive else Color(0.18, 0.06, 0.06, 0.88)
		var s := StyleBoxFlat.new()
		s.bg_color = bg_col
		s.border_color = border_col
		s.border_width_left = 1; s.border_width_right  = 1
		s.border_width_top  = 1; s.border_width_bottom = 1
		s.corner_radius_top_left     = 4; s.corner_radius_top_right    = 4
		s.corner_radius_bottom_left  = 4; s.corner_radius_bottom_right = 4
		s.content_margin_left = 6; s.content_margin_right  = 6
		s.content_margin_top  = 2; s.content_margin_bottom = 2
		tag.add_theme_stylebox_override("normal",  s)
		tag.add_theme_stylebox_override("hover",   s)
		tag.add_theme_stylebox_override("pressed", s)
		tag.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())
		tag.add_theme_color_override("font_color",
			Color(0.55, 0.96, 0.62) if positive else Color(1.0, 0.58, 0.58))
		outer.add_child(tag)
		var cap_m := m
		tag.mouse_entered.connect(func() -> void:
			TooltipManager.show_tip(cap_m.display_name, cap_m.description))
		tag.mouse_exited.connect(func() -> void:
			TooltipManager.hide_tip())
		tag_row.add_child(outer)
	vbox.add_child(tag_row)

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
			if not _is_at_edge(): CursorManager.set_state(CursorManager.State.POINTER)
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

func _setup_orbital_layer(planet_seed: int) -> void:
	# Remove old layer if switching planets
	if _orbital_layer != null and is_instance_valid(_orbital_layer):
		_orbital_layer.queue_free()
	var layer := OrbitalLayer.new()
	layer.z_index = 5   # above planet, below HUD rings
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	planet_renderer.get_parent().add_child(layer)
	layer.setup(planet_seed)
	layer.ship_hovered.connect(func(ship: ShipData, _pos: Vector2) -> void:
		# Title includes status inline: "Pioneer I  · in orbit"
		var title: String
		if ship.is_travelling():
			var dest_pd := GameState.get_planet_data(ship.dest_seed)
			var dest_name: String = dest_pd.planet_name if dest_pd != null else "Unknown"
			title = ship.ship_name + "  · → " + dest_name + "  eta %.0fs" % ship.eta_seconds()
		else:
			title = ship.ship_name + "  · in orbit"
		# Body: icon + ×amount only (like inventory card, no repeated name)
		var body: Array = []
		if not ship.cargo.is_empty():
			var first := true
			for rid: String in ship.cargo:
				var rd: ResourceData = GameState.known_resources.get(rid, null)
				if rd == null:
					continue
				if not first:
					body.append("\n")
				first = false
				body.append(MineralIcon.make(rd.tier, rd.display_color))
				body.append("  ×%.0f" % ship.cargo[rid])
		TooltipManager.show_tip(title, body))
	layer.ship_unhovered.connect(func() -> void:
		TooltipManager.hide_tip())
	_orbital_layer = layer

func _process(delta: float) -> void:
	_update_aspect()
	if _ring_back != null or _ring_front != null:
		_ring_angle = planet_renderer.get_rotation_offset()
		if _ring_back  and is_instance_valid(_ring_back):  _ring_back.queue_redraw()
		if _ring_front and is_instance_valid(_ring_front): _ring_front.queue_redraw()

	_light_angle = fposmod(_light_angle + delta * LIGHT_SPEED, TAU)
	_apply_light_angle()
	_update_cursor()
	if _orbital_layer != null and is_instance_valid(_orbital_layer):
		_orbital_layer._planet_radius   = planet_renderer._planet_radius_px
		_orbital_layer._planet_rotation = planet_renderer.get_rotation_offset()
		# Keep orbital center in sync with actual planet renderer center
		var _oc: Control = planet_renderer.get_parent()
		_orbital_layer._planet_center   = planet_renderer.global_position + planet_renderer.size * 0.5 - _oc.get_global_rect().position
		_orbital_layer.queue_redraw()
		
	if current_data != null:
		var any_finished = false
		for poi_label in _district_pbars:
			var pbar: ProgressBar = _district_pbars[poi_label]
			if is_instance_valid(pbar):
				for poi: POIData in current_data.custom_pois:
					if poi.label == poi_label:
						if poi.constructing:
							# Smooth UI update
							poi.construct_progress += delta / max(0.1, poi.construct_duration)
							if poi.construct_progress >= 1.0:
								poi.construct_progress = 1.0
								poi.constructing = false
								any_finished = true
						pbar.value = poi.construct_progress * 100.0
						break
		if any_finished:
			GameState.planet_progress_changed.emit(current_data.seed)

	if not _rocket_anim.is_empty():
		_tick_rocket_anim(delta)

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
	CursorManager.set_state(CursorManager.State.NORMAL)

func _apply_light_angle() -> void:
	if planet_renderer == null:
		return
	# Just update the value — PlanetRenderer._process calls _update_light_direction()
	# at the END of every frame (after both parent and child _process have run),
	# so light_direction is always computed with fresh rotation_offset + light_angle.
	planet_renderer.light_angle = _light_angle


func _rotate_to_lon(lon_deg: float, duration: float = 0.45) -> void:
	var target  := fposmod(deg_to_rad(lon_deg), TAU)
	var current := fposmod(planet_renderer.get_rotation_offset(), TAU)
	var diff    := fposmod(target - current + PI, TAU) - PI
	var tween   := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(
		func(v: float) -> void: planet_renderer.set_rotation_offset(v),
		current, current + diff, duration)

func _on_planet_clicked(_screen_pos: Vector2) -> void:
	poi_layer.deselect_all()
	_build_planet_overview(current_data)

func _build_planet_overview(data: PlanetData) -> void:
	if data == null:
		return
	var panel_content := $RightPanel/PanelContent
	var old := panel_content.get_node_or_null("DistrictBuildPanel")
	if old:
		old.name = "__freeing_district__"   # free name slot before queue_free
		old.queue_free()
		_bar_meta.clear()
		_active_slot_dropdown = null
	poi_layer.deselect_all()
	_active_district_poi = null   # overview shown — don’t auto-reopen on construction

	var pp := GameState.get_planet(data.seed)

	var root := VBoxContainer.new()
	root.name = "DistrictBuildPanel"
	root.add_theme_constant_override("separation", 8)
	root.add_child(HSeparator.new())

	if not pp.is_colonized:
		_build_resources_section(root, data, pp)
		panel_content.add_child(root)
		return

	# Planet name + level
	var name_lbl := Label.new()
	name_lbl.text = data.planet_name
	_apply_orbitron(name_lbl, 13)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	root.add_child(name_lbl)

	var level_row := HBoxContainer.new()
	var lv_lbl := Label.new()
	lv_lbl.text = "Level"
	lv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_orbitron(lv_lbl, 9)
	lv_lbl.add_theme_color_override("font_color", Color(0.50, 0.55, 0.70))
	var lv_val := Label.new()
	lv_val.text = "Lv %d" % pp.level
	_apply_orbitron(lv_val, 9)
	lv_val.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4))
	level_row.add_child(lv_lbl); level_row.add_child(lv_val)
	root.add_child(level_row)

	var dist_row := HBoxContainer.new()
	var dr_lbl := Label.new()
	dr_lbl.text = "Districts"
	dr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_orbitron(dr_lbl, 9)
	dr_lbl.add_theme_color_override("font_color", Color(0.50, 0.55, 0.70))
	var dr_val := Label.new()
	dr_val.text = "%d / %d" % [data.custom_pois.size(), pp.max_districts]
	_apply_orbitron(dr_val, 9)
	dr_val.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
	dist_row.add_child(dr_lbl); dist_row.add_child(dr_val)
	root.add_child(dist_row)

	# Energy balance row with per-district tooltip
	var e_breakdown := _planet_energy_breakdown(pp, data)
	var energy_bal: float = e_breakdown.get("total", 0.0)
	var e_sign := "+" if energy_bal >= 0.0 else ""
	var e_row := HBoxContainer.new()
	var e_lbl := Label.new()
	e_lbl.text = "Energy"
	e_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_orbitron(e_lbl, 9)
	e_lbl.add_theme_color_override("font_color", Color(0.50, 0.55, 0.70))
	var e_val := Label.new()
	e_val.text = e_sign + "%.0f ⚡" % energy_bal
	_apply_orbitron(e_val, 9)
	e_val.add_theme_color_override("font_color",
		Color(0.9, 0.82, 0.25) if energy_bal >= 0.0 else Color(0.9, 0.40, 0.28))
	e_row.add_child(e_lbl); e_row.add_child(e_val)
	_overview_energy_val = e_val
	root.add_child(e_row)
	# Tooltip with per-district breakdown — show all districts (producers + consumers)
	var tip_producers: Array[String] = []
	var tip_consumers: Array[String] = []
	for poi_t: POIData in data.custom_pois:
		var d_val: float = e_breakdown.get(poi_t.label, 0.0) as float
		if d_val == 0.0:
			continue
		var d_sign := "+" if d_val >= 0.0 else ""
		var line := "%s  %s%.0f ⚡" % [poi_t.label, d_sign, d_val]
		if d_val >= 0.0:
			tip_producers.append(line)
		else:
			tip_consumers.append(line)
	var cap_data_ref := data
	e_row.mouse_entered.connect(func() -> void:
		if cap_data_ref == null: return
		var cur_pp := GameState.get_planet(cap_data_ref.seed)
		if cur_pp == null: return
		var bd := _planet_energy_breakdown(cur_pp, cap_data_ref)
		var prod: Array[String] = []
		var cons: Array[String] = []
		for poi_t: POIData in cap_data_ref.custom_pois:
			var d_val: float = bd.get(poi_t.label, 0.0) as float
			if d_val == 0.0: continue
			var line := "%s  %s%.0f ⚡" % [poi_t.label, "+" if d_val >= 0.0 else "", d_val]
			if d_val >= 0.0: prod.append(line)
			else:            cons.append(line)
		var lines: Array[String] = prod + cons
		if not lines.is_empty():
			TooltipManager.show_tip("Energy by District", "\n".join(lines)))
	e_row.mouse_exited.connect(func() -> void:
		TooltipManager.hide_tip())

	_build_resources_section(root, data, pp)

	# POI list
	if not data.custom_pois.is_empty():
		var sep := HSeparator.new()
		var sep_s := StyleBoxFlat.new()
		sep_s.bg_color = Color(0.2, 0.25, 0.4, 0.35)
		sep.add_theme_stylebox_override("separator", sep_s)
		root.add_child(sep)
		var poi_title := Label.new()
		poi_title.text = "DISTRICTS"
		_apply_orbitron(poi_title, 8)
		poi_title.add_theme_color_override("font_color", Color(0.40, 0.45, 0.65))
		root.add_child(poi_title)

		for poi: POIData in data.custom_pois:
			var poi_card := _build_district_overview_card(poi, data, pp, panel_content, root)
			root.add_child(poi_card)

	# ADD DISTRICT card (always shown when slots remain)
	var can_add_district := data.custom_pois.size() < pp.max_districts
	var add_dist_card := _build_add_district_card(data, can_add_district)
	root.add_child(add_dist_card)

	panel_content.add_child(root)

func _build_resources_section(parent: VBoxContainer, data: PlanetData, pp: PlanetProgress) -> void:
	var sep := HSeparator.new()
	var sep_s := StyleBoxFlat.new()
	sep_s.bg_color = Color(0.2, 0.25, 0.4, 0.35)
	sep.add_theme_stylebox_override("separator", sep_s)
	parent.add_child(sep)

	var title := Label.new()
	title.text = "RESOURCES"
	_apply_orbitron(title, 8)
	title.add_theme_color_override("font_color", Color(0.40, 0.45, 0.65))
	parent.add_child(title)

	# Collect stored resources with amount > 0, resolved from known_resources
	var stored_entries: Array[ResourceData] = []
	for rid: String in pp.stored_resources:
		var amt: float = pp.stored_resources[rid]
		if amt <= 0.0:
			continue
		var rd: ResourceData = GameState.known_resources.get(rid, null)
		if rd == null:
			continue
		stored_entries.append(rd)
	stored_entries.sort_custom(func(a: ResourceData, b: ResourceData) -> bool:
		return a.rarity < b.rarity if a.rarity != b.rarity else a.tier < b.tier)

	if stored_entries.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "No resources stored"
		_apply_orbitron(none_lbl, 8)
		none_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.55))
		parent.add_child(none_lbl)
		return

	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for rd: ResourceData in stored_entries:
		var stored: float = pp.stored_resources.get(rd.resource_id(), 0.0)
		grid.add_child(_mineral_grid_card(rd, stored, true, "", pp))
	parent.add_child(grid)

func _build_district_overview_card(poi: POIData, planet: PlanetData, pp: PlanetProgress,
		_panel_content: VBoxContainer, _root: VBoxContainer) -> PanelContainer:
	var card := PanelContainer.new()
	var s := _card_panel_style()
	s.bg_color = Color(0.07, 0.09, 0.17, 0.80)
	card.add_theme_stylebox_override("panel", s)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size   = Vector2(0, 40)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   10)
	margin.add_theme_constant_override("margin_right",   8)
	margin.add_theme_constant_override("margin_top",     6)
	margin.add_theme_constant_override("margin_bottom",  6)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(hbox)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override("separation", 1)

	var n_lbl := Label.new()
	n_lbl.text = poi.label
	n_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_orbitron(n_lbl, 10)
	n_lbl.add_theme_color_override("font_color", Color(0.82, 0.88, 1.0))

	var t_lbl := Label.new()
	var district_buildings := pp.buildings_in_district(poi.label)
	var total_size: int = 0
	for eb: Dictionary in district_buildings:
		total_size += eb.get("amount", 1)
	t_lbl.text = poi.type_label() + "  ·  Size %d" % total_size
	t_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_orbitron(t_lbl, 8)
	t_lbl.add_theme_color_override("font_color", Color(0.42, 0.48, 0.68))

	info.add_child(n_lbl); info.add_child(t_lbl)

	if poi.constructing:
		var pbar := ProgressBar.new()
		pbar.value = poi.construct_progress * 100.0
		pbar.custom_minimum_size = Vector2(0, 4)
		pbar.show_percentage = false
		var bg_s := StyleBoxFlat.new()
		bg_s.bg_color = Color(0.1, 0.1, 0.15)
		var fg_s := StyleBoxFlat.new()
		fg_s.bg_color = Color(0.3, 0.7, 0.4)
		pbar.add_theme_stylebox_override("background", bg_s)
		pbar.add_theme_stylebox_override("fill", fg_s)
		info.add_child(pbar)
		t_lbl.text = "Constructing..."
		
		# Register for live updates
		_district_pbars[poi.label] = pbar
		pbar.tree_exited.connect(func():
			if _district_pbars.get(poi.label) == pbar:
				_district_pbars.erase(poi.label)
		)

	hbox.add_child(info)

	# Whole card clickable — no separate arrow button
	var cap_poi    := poi
	var cap_planet := planet
	var cap_card   := card
	var norm_s2 := card.get_theme_stylebox("panel") as StyleBoxFlat
	var hov_s2  := norm_s2.duplicate() as StyleBoxFlat
	hov_s2.bg_color = Color(0.10, 0.14, 0.28, 0.92)
	card.mouse_entered.connect(func() -> void:
		cap_card.add_theme_stylebox_override("panel", hov_s2)
		if cap_poi.constructing:
			TooltipManager.show_tip("Constructing", "This District is not fully operational yet.")
		if not _is_at_edge(): CursorManager.set_state(CursorManager.State.POINTER))
	card.mouse_exited.connect(func() -> void:
		cap_card.add_theme_stylebox_override("panel", norm_s2)
		TooltipManager.hide_tip()
		CursorManager.set_state(CursorManager.State.NORMAL))
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_select_district_on_planet(cap_poi.label)
			_rotate_to_lon(cap_poi.lon_deg)
			if cap_poi.constructing:
				TooltipManager.show_tip("Constructing", "This District is not fully operational yet.")
				return
			_build_district_panel(cap_poi, cap_planet))
	return card

func _select_district_on_planet(label: String) -> void:
	for i in poi_layer._pois.size():
		if poi_layer._pois[i].get("label", "") == label:
			poi_layer.select_poi(i)
			return

func _build_add_district_card(data: PlanetData, enabled: bool) -> VBoxContainer:
	var wrapper := VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 0)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var card := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.12, 0.22, 0.55) if enabled else Color(0.05, 0.06, 0.10, 0.35)
	s.border_color = Color(0.28, 0.40, 0.75, 0.45) if enabled else Color(0.18, 0.22, 0.35, 0.30)
	s.border_width_left = 1; s.border_width_right  = 1
	s.border_width_top  = 1; s.border_width_bottom = 1
	s.corner_radius_top_left     = 5; s.corner_radius_top_right    = 5
	s.corner_radius_bottom_left  = 5; s.corner_radius_bottom_right = 5
	s.content_margin_left   = 10; s.content_margin_right  = 10
	s.content_margin_top    = 8;  s.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", s)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(card)

	var hbox := HBoxContainer.new()
	card.add_child(hbox)

	var plus_lbl := Label.new()
	plus_lbl.text = "+"
	_apply_orbitron(plus_lbl, 14)
	plus_lbl.add_theme_color_override("font_color",
		Color(0.45, 0.60, 1.0, 0.9) if enabled else Color(0.30, 0.35, 0.50, 0.5))
	plus_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(plus_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	var txt := Label.new()
	txt.text = "ADD DISTRICT" if enabled else "SLOTS FULL"
	_apply_orbitron(txt, 8)
	txt.add_theme_color_override("font_color",
		Color(0.55, 0.70, 1.0, 0.75) if enabled else Color(0.35, 0.38, 0.52, 0.6))
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(txt)

	if enabled:
		card.mouse_entered.connect(func() -> void:
			if not _is_at_edge(): CursorManager.set_state(CursorManager.State.POINTER))
		card.mouse_exited.connect(func() -> void:
			CursorManager.set_state(CursorManager.State.NORMAL))
		# Dropdown panel — appended to wrapper, appears below card
		var dropdown_ref: Array[Control] = [null]
		var cap_data  := data
		var cap_wrap  := wrapper
		card.gui_input.connect(func(e: InputEvent) -> void:
			if not (e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
					and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
				return
			# Toggle
			if dropdown_ref[0] != null and is_instance_valid(dropdown_ref[0]):
				dropdown_ref[0].queue_free()
				dropdown_ref[0] = null
				return
			var dd := _build_district_type_dropdown(cap_data, cap_wrap, dropdown_ref)
			cap_wrap.add_child(dd)
			dropdown_ref[0] = dd)

	return wrapper

func _build_district_type_dropdown(data: PlanetData, _anchor: VBoxContainer,
		dropdown_ref: Array[Control]) -> PanelContainer:
	var dd := PanelContainer.new()
	dd.add_theme_stylebox_override("panel", _make_hud_style(Color(0.06, 0.08, 0.16, 0.97), 6))
	dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	dd.add_child(vbox)

	var available := DistrictDef.for_planet(data.planet_type)
	for def: DistrictDef in available:
		var row := _build_district_type_row(data, def, dropdown_ref)
		vbox.add_child(row)

	return dd

func _build_district_type_row(data: PlanetData, def: DistrictDef,
		dropdown_ref: Array[Control]) -> Control:
	var btn := Button.new()
	btn.flat = true
	btn.text = "%s  %s" % [def.icon, def.display_name]
	_apply_orbitron(btn, 9)
	var cost: float = DistrictDef.placement_cost(def, data)
	var can_afford: bool = GameState.credits >= cost

	btn.disabled = not can_afford
	if not can_afford:
		btn.add_theme_color_override("font_disabled_color", Color(0.9, 0.3, 0.3))
	else:
		btn.add_theme_color_override("font_color",       Color(0.75, 0.82, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0,  0.95, 0.55))

	var norm := StyleBoxFlat.new()
	norm.bg_color = Color(0, 0, 0, 0)
	norm.content_margin_left = 10; norm.content_margin_right  = 10
	norm.content_margin_top  = 6;  norm.content_margin_bottom = 6
	var hov := norm.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.12, 0.18, 0.35, 0.60)
	btn.add_theme_stylebox_override("normal",  norm)
	btn.add_theme_stylebox_override("hover",   hov)
	btn.add_theme_stylebox_override("pressed", hov)
	btn.add_theme_stylebox_override("disabled", norm)
	btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())

	var cost_str := HUDManager.fmt_credits(cost)
	btn.mouse_entered.connect(func() -> void:
		if not _is_at_edge(): CursorManager.set_state(CursorManager.State.POINTER)
		var t_title = def.display_name
		var t_desc = def.description
		if not can_afford:
			t_desc += "\n\n[color=red]Insufficient Credits[/color]"
		TooltipManager.show_tip(t_title, t_desc, cost_str))
	btn.mouse_exited.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.NORMAL)
		TooltipManager.hide_tip())

	var cap_def  := def
	var cap_data := data
	btn.pressed.connect(func() -> void:
		if dropdown_ref[0] != null and is_instance_valid(dropdown_ref[0]):
			dropdown_ref[0].queue_free()
			dropdown_ref[0] = null
		if not GameState.spend_credits(DistrictDef.placement_cost(cap_def, cap_data)):
			return
		_spawn_district(cap_data, cap_def.suggest_name(cap_data), cap_def))

	return btn

func _on_district_clicked(index: int, _data: Dictionary) -> void:
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
	_build_district_panel(poi, current_data)

## pm_key -> { "fill": Control, "prog": Array[float] }
var _bar_meta: Dictionary = {}
var _active_slot_dropdown: Control = null
var _dd_layer: CanvasLayer = null  # CanvasLayer overlay for slot dropdown (always on top)

func _is_at_edge() -> bool:
	var mouse := get_viewport().get_mouse_position()
	var vp    := get_viewport().get_visible_rect().size
	const EDGE := 40.0
	return mouse.x < EDGE or mouse.y < EDGE or mouse.x > vp.x - EDGE or mouse.y > vp.y - EDGE

func _on_production_update(_planet_seed: int, key: String, progress: float) -> void:
	if _district_pbars.has(key):
		var pbar: ProgressBar = _district_pbars[key]
		if is_instance_valid(pbar):
			print("[UI Debug] Updating pbar for ", key, " to ", progress * 100.0)
			pbar.value = progress * 100.0
		else:
			print("[UI Debug] pbar is invalid for ", key)
	else:
		if " " in key: # naive check for district names to see if we missed it
			print("[UI Debug] Key not in _district_pbars: ", key)

	if not _bar_meta.has(key):
		return
	var m: Dictionary = _bar_meta[key]
	(m["prog"] as Array)[0] = progress
	var fc: Control = m["fill"]
	if is_instance_valid(fc):
		fc.queue_redraw()
	# Update percent label on construction bars only — status label updates via building_ticked
	if m.get("construction", false) and m.has("pct"):
		var pct: Label = m["pct"]
		if is_instance_valid(pct):
			pct.text = "%d%%" % int(progress * 100)

func _on_building_ticked_night(planet_seed: int, key: String) -> void:
	if current_data != null and current_data.seed == planet_seed:
		_update_poi_night_sizes(current_data)
		_refresh_poi_lights(current_data)
	if _bar_meta.has(key):
		var fc: Control = _bar_meta[key]["fill"]
		if is_instance_valid(fc):
			fc.queue_redraw()
		_refresh_bar_label_status(key)
		
	# Energy ratio can change when any building starts/stops.
	# Refresh all slowed_lbl visibilities for the whole planet to ensure UI consistency.
	var er := ProductionManager.get_energy_ratio(planet_seed)
	for k: String in _bar_meta:
		var m: Dictionary = _bar_meta[k]
		if m.get("planet_seed", -1) == planet_seed:
			var sl: Label = m.get("slowed_lbl", null)
			if is_instance_valid(sl):
				var paused := ProductionManager.is_paused(k)
				sl.text    = "⚡ Slowed %d%% — Energy Crisis" % [int((1.0 - er) * 100)]
				sl.visible = not paused and er < 0.999

	_refresh_district_energy_lbl()

var _active_district_energy_lbl: Label = null

func _refresh_district_energy_lbl() -> void:
	if not is_instance_valid(_active_district_energy_lbl):
		return
	if current_data == null or _active_district_poi == null:
		return
	var pp := GameState.get_planet(current_data.seed)
	var breakdown := _planet_energy_breakdown(pp, current_data)
	var d_energy: float = breakdown.get(_active_district_poi.label, 0.0)
	var de_sign := "+" if d_energy >= 0.0 else ""
	_active_district_energy_lbl.text = de_sign + "%.0f ⚡" % d_energy
	_active_district_energy_lbl.add_theme_color_override("font_color",
		Color(0.85, 0.78, 0.22) if d_energy >= 0.0 else Color(0.85, 0.38, 0.25))

func _on_building_toggled(key: String, _paused: bool) -> void:
	if not _bar_meta.has(key):
		return
	var fc: Control = _bar_meta[key]["fill"]
	if is_instance_valid(fc):
		fc.queue_redraw()
	_refresh_bar_label_status(key)

func _refresh_bar_label_status(key: String) -> void:
	if not _bar_meta.has(key):
		return
	var m: Dictionary = _bar_meta[key]
	if m.get("construction", false):
		return
	# Spaceport: update prog_ref + reset launch button when re-paused
	if m.has("launch_btn"):
		(m["prog"] as Array)[0] = ProductionManager.get_progress(key)
		var btn: Button = m["launch_btn"]
		if is_instance_valid(btn) and ProductionManager.is_user_paused(key):
			btn.text     = "🚀 Launch"
			btn.disabled = false
		return
	var out_lbl: Label = m.get("out_lbl", null)
	var def: BuildingDef = m.get("def", null)
	var fc: Color = m.get("fc", Color.WHITE)
	if is_instance_valid(out_lbl) and def != null:
		var paused := ProductionManager.is_paused(key)
		var out_text := "⏸ waiting"
		if not paused:
			var out_val := def.output_amount
			if def.output_type == BuildingDef.OutputType.CREDITS:
				out_val *= get_node("/root/SkillTree").get_credits_mult()
			elif def.output_type == BuildingDef.OutputType.ENERGY:
				if def.building_id == "solar_panel":
					out_val *= get_node("/root/SkillTree").get_solar_mult()
				elif def.building_id == "generator":
					out_val *= get_node("/root/SkillTree").get_generator_output_mult()
					var in_min: String = m.get("entry", {}).get("burning_mineral", "")
					if in_min != "":
						var rd: ResourceData = GameState.known_resources.get(in_min)
						if rd: out_val *= float(rd.rarity)
					else:
						out_val = 0.0 # No fuel
			elif def.output_type == BuildingDef.OutputType.RAW_MINERAL or def.output_type == BuildingDef.OutputType.REFINED_MINERAL:
				out_val *= get_node("/root/SkillTree").get_mine_output_mult()
				
			match def.output_type:
				BuildingDef.OutputType.ENERGY:          out_text = "+%.0f ⚡" % out_val
				BuildingDef.OutputType.CREDITS:         out_text = "+%.0f cr" % out_val
				BuildingDef.OutputType.RAW_MINERAL:     out_text = "+%.0f ore" % out_val
				BuildingDef.OutputType.REFINED_MINERAL: out_text = "+%.0f ref" % out_val
				
		out_lbl.text = out_text
		out_lbl.add_theme_color_override("font_color",
			Color(0.45, 0.48, 0.60) if paused else fc)

		var slowed_lbl: Label = m.get("slowed_lbl", null)
		if is_instance_valid(slowed_lbl):
			var er := ProductionManager.get_energy_ratio(m.get("planet_seed", -1))
			slowed_lbl.text    = "⚡ Slowed %d%% — Energy Crisis" % [int((1.0 - er) * 100)]
			slowed_lbl.visible = not paused and er < 0.999

func _on_building_constructed(planet_seed: int, key: String) -> void:
	if current_data == null or current_data.seed != planet_seed:
		return

	# Parse key format: "{seed}:{poi_label}:{idx}"
	var last_col  := key.rfind(":")
	var first_col := key.find(":")
	var building_name := ""
	var poi_label     := ""
	if last_col > first_col and first_col >= 0:
		var idx       := key.substr(last_col + 1).to_int()
		poi_label      = key.substr(first_col + 1, last_col - first_col - 1)
		var pp := GameState.get_planet(planet_seed)
		if pp != null and idx >= 0 and idx < pp.buildings.size():
			var entry := pp.buildings[idx]
			var def   := BuildingDef.find(entry.get("building_id", ""))
			if def != null:
				building_name = def.display_name

	# Always show a toast — never auto-select / reopen the district.
	_show_construction_toast(
		building_name if building_name != "" else "Building",
		poi_label)

	# If a spaceport just finished construction, mark planet and refresh ships
	var pp_check := GameState.get_planet(planet_seed)
	if pp_check != null and not pp_check.has_spaceport:
		var pp_buildings: Array = pp_check.buildings
		for eb: Dictionary in pp_buildings:
			if eb.get("building_id", "") == "spaceport" and not eb.get("constructing", false):
				pp_check.has_spaceport = true
				break

	_refresh_overview_energy()

	# Refresh panel only if the player is actively viewing that specific district.
	if _active_district_poi == null:
		return
	if poi_label != "" and _active_district_poi.label != poi_label:
		return   # completed in a different district — don’t switch view
	_build_district_panel(_active_district_poi, current_data)

func _refresh_overview_energy() -> void:
	if not is_instance_valid(_overview_energy_val) or current_data == null:
		return
	var pp := GameState.get_planet(current_data.seed)
	if pp == null:
		return
	var e_breakdown := _planet_energy_breakdown(pp, current_data)
	var bal: float   = e_breakdown.get("total", 0.0)
	var sign := "+" if bal >= 0.0 else ""
	_overview_energy_val.text = sign + "%.0f ⚡" % bal
	_overview_energy_val.add_theme_color_override("font_color",
		Color(0.9, 0.82, 0.25) if bal >= 0.0 else Color(0.9, 0.40, 0.28))

## Starts a rocket launch animation. State is ticked in _process each frame.
func _play_rocket_animation(planet_seed: int, poi: POIData, on_complete: Callable) -> void:
	# Kill any existing animation
	if not _rocket_anim.is_empty():
		var old: Control = _rocket_anim.get("rocket")
		if old != null and is_instance_valid(old):
			old.queue_free()
		_rocket_anim.clear()

	var container: Control = planet_renderer.get_parent()
	var planet_r:  float   = planet_renderer._planet_radius_px
	const ORBIT_FRAC: float = 1.06

	# Planet center — same reference as POILayer (_planet.global_position + size*0.5)
	var planet_center_global: Vector2 = planet_renderer.global_position + planet_renderer.size * 0.5
	var center_local:         Vector2 = planet_center_global - container.get_global_rect().position

	# POI lon/lat for positioning (POILayer formula: x=sin(lon-rot)*cos(lat), y=-sin(lat))
	var poi_lon:   float = 0.0
	var poi_lat:   float = 0.0
	var start_r:   float = planet_r
	if poi != null and poi_layer != null and is_instance_valid(poi_layer):
		var ll: Vector2 = poi_layer.get_poi_lon_lat(poi.label)
		poi_lon = ll.x
		poi_lat = ll.y
		var p: Dictionary = poi_layer._get_planet_params()
		if not p.is_empty():
			start_r = p.get("r_px", planet_r)

	# Random orbit insertion point: random longitude sweep + random target latitude
	var sweep_target: float = randf_range(PI * 0.15, PI * 0.75) * (1.0 if randf() > 0.5 else -1.0)
	var sweep_sign:   float = sign(sweep_target)
	var lat_target:   float = randf_range(-PI * 0.35, PI * 0.35)

	# ── Rocket node ──────────────────────────────────────────────────────────────
	var rocket := Control.new()
	rocket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rocket.z_index      = 12
	container.add_child(rocket)

	# Set initial position directly from POI screen pos — no formula conversion needed
	if poi != null and poi_layer != null and is_instance_valid(poi_layer):
		var poi_global: Vector2 = poi_layer.get_poi_screen_pos(poi.label)
		if poi_global != Vector2.ZERO:
			rocket.position = poi_global - container.get_global_rect().position

	rocket.draw.connect(func() -> void:
		if _rocket_anim.is_empty():
			return
		var flame_a:    float   = _rocket_anim.get("flame_alpha", 1.0)
		var cl:         Vector2 = _rocket_anim.get("center_local", Vector2.ZERO)
		var rocket_off: Vector2 = rocket.position - cl
		var exhaust_dir: Vector2 = -rocket_off.normalized() if rocket_off.length() > 1.0 else Vector2.DOWN
		if flame_a > 0.01:
			var back: Vector2 = exhaust_dir * 4.0
			for fi: int in 5:
				var fa: float = flame_a * (0.35 + randf() * 0.65)
				var fc: Color
				if fi < 2:   fc = Color(1.0, 0.35 + randf() * 0.5, 0.05, fa)
				elif fi < 4: fc = Color(1.0, 0.80, 0.20, fa * 0.6)
				else:        fc = Color(0.9, 0.4, 0.1, fa * 0.35)
				rocket.draw_rect(Rect2((back + Vector2(randf_range(-2,2), randf_range(-2,2))).floor(), Vector2.ONE), fc)
		var col := Color(1, 1, 1, 0.95)
		var p   := Vector2.ZERO
		rocket.draw_rect(Rect2(p,                   Vector2(2, 2)), col)
		rocket.draw_rect(Rect2(p + Vector2(-2,  0), Vector2(2, 2)), col)
		rocket.draw_rect(Rect2(p + Vector2( 2,  0), Vector2(2, 2)), col)
		rocket.draw_rect(Rect2(p + Vector2( 0, -2), Vector2(2, 2)), col)
		rocket.draw_rect(Rect2(p + Vector2( 0,  2), Vector2(2, 2)), col))

	var lbl := Label.new()
	lbl.text = "· launching to orbit"
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_orbitron(lbl, 7)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.88, 1.0, 0.80))
	lbl.position = Vector2(6, -5)
	rocket.add_child(lbl)

	_rocket_anim = {
		"rocket":          rocket,
		"container":       container,
		"center_local":    center_local,
		"planet_r_frac":   start_r / maxf(planet_r, 1.0),   # start radius as fraction
		"anim_r":          start_r,
		"poi_lon":      poi_lon,
		"poi_lat":      poi_lat,
		"lon_sweep":    0.0,
		"lat_sweep":    0.0,
		"sweep_target": sweep_target,
		"lat_target":   lat_target,
		"sweep_sign":   sweep_sign,
		"flame_alpha":     1.0,
		"phase":           0,
		"phase_t":         0.0,
		"planet_seed":     planet_seed,
		"hover_active":    false,
		"on_complete":     on_complete,
	}

## Called every _process frame while _rocket_anim is active.
func _tick_rocket_anim(delta: float) -> void:
	var d: Dictionary = _rocket_anim
	var rocket: Control = d["rocket"]
	if not is_instance_valid(rocket):
		_rocket_anim.clear()
		return

	var phase: int   = d["phase"]
	var t:     float = d["phase_t"]

	# Planet radius fresh each tick (handles window resize)
	var planet_r: float = planet_renderer._planet_radius_px
	var orbit_r:  float = planet_r * 1.06
	var start_r:  float = d["planet_r_frac"] * planet_r

	# Two sub-phases within phase 0, each 0→1:
	# Sub-phase A (t < 0.5): radial rise using POILayer formula (starts at exact district pos)
	# Sub-phase B (t ≥ 0.5): circularise — lerp from rise-end to orbital insert point
	# Both endpoints re-computed each tick so planet drag rotates everything correctly.

	const LAUNCH_DUR: float = 18.0

	# Speed profile: sin curve — accelerates to peak at t=0.5, then decelerates to 0.
	# lon_sweep uses integral of sin: 0.5*(1-cos(t*PI)) → smooth S from 0 to sweep_target.
	# radius uses same curve (ease in+out together).
	var finished := false
	match phase:
		0:
			t += delta / LAUNCH_DUR
			if t >= 1.0:
				t = 1.0
				finished = true
			d["phase_t"] = t

			# Speed profile: ease-in [0→0.5], then linear decel to CRUISE_FRAC of peak [0.5→1].
			# Normalized so curve reaches exactly 1.0 at t=1 (no stopping short).
			# CRUISE_FRAC = velocity at orbit entry as fraction of peak.
			const CRUISE_FRAC: float = 0.10
			const D: float = (1.0 + CRUISE_FRAC) * 0.5
			var curve: float
			if t <= 0.5:
				curve = 0.5 * (1.0 - cos(t * PI))
			else:
				var u: float    = (t - 0.5) / 0.5
				var integ: float = u - u * u * (1.0 - CRUISE_FRAC) * 0.5
				curve = 0.5 + (integ / D) * 0.5
			d["anim_r"]      = lerpf(start_r, orbit_r, curve)
			d["lon_sweep"]   = d["sweep_target"] * curve
			d["lat_sweep"]   = (d["lat_target"] - d["poi_lat"]) * curve
			d["flame_alpha"] = clampf(1.0 - t / 0.5, 0.0, 1.0) if t < 0.5 else 0.0

			# Booster separation particles at peak speed (t crosses 0.5)
			if not d.get("boosters_spawned", false) and t >= 0.5:
				d["boosters_spawned"] = true
				d["booster_particles"] = []
				var rot_bp:  float   = planet_renderer.get_rotation_offset()
				var lon_bp:  float   = d["poi_lon"] + d["lon_sweep"] - rot_bp
				var lat_bp:  float   = d["poi_lat"] + d["lat_sweep"]
				var ctr_bp:  Vector2 = planet_renderer.global_position + planet_renderer.size * 0.5 \
					- d["container"].get_global_rect().position
				var pos_bp:  Vector2 = ctr_bp + Vector2(sin(lon_bp)*cos(lat_bp), -sin(lat_bp)) * d["anim_r"]
				var vel_dir: Vector2 = Vector2(
					cos(lon_bp)*cos(lat_bp)*d["sweep_target"],
					-cos(lat_bp)*(d["lat_target"]-d["poi_lat"])
				).normalized()
				var perp: Vector2 = Vector2(-vel_dir.y, vel_dir.x)
				for sp: float in [1.0, -1.0]:
					var bp_data: Dictionary = {"pos": pos_bp, "vel": perp * sp * 8.0, "alpha": 1.0}
					var bp_node := Control.new()
					bp_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
					bp_node.z_index = 11
					bp_node.size    = Vector2(4, 4)
					bp_node.position = pos_bp
					d["container"].add_child(bp_node)
					bp_data["node"] = bp_node
					var bp_ref: Dictionary = bp_data   # capture
					bp_node.draw.connect(func() -> void:
						if bp_ref["alpha"] > 0.0:
							bp_node.draw_rect(Rect2(Vector2.ZERO, Vector2(2, 2)),
								Color(1.0, 0.8, 0.3, bp_ref["alpha"])))
					d["booster_particles"].append(bp_data)

	# ── Tick booster particles ────────────────────────────────────────────────────
	if d.get("booster_particles") != null:
		var alive: Array = []
		for bp: Dictionary in d["booster_particles"]:
			bp["pos"]   += bp["vel"] * delta
			bp["vel"]   *= pow(0.85, delta * 60.0)
			bp["alpha"] -= delta * 0.55
			if bp["alpha"] > 0.0:
				alive.append(bp)
			else:
				if bp.get("node") != null and is_instance_valid(bp["node"]):
					bp["node"].queue_free()
		d["booster_particles"] = alive

	# POILayer formula — same as POILayer._process, tracks planet rotation exactly
	var rot:     float   = planet_renderer.get_rotation_offset()
	var lon_eff: float   = d["poi_lon"] + d["lon_sweep"] - rot
	var lat:     float   = d["poi_lat"] + d["lat_sweep"]
	var r:       float   = d["anim_r"]
	# Re-derive center each frame so it stays in sync with OrbitalLayer._planet_center.
	var center:  Vector2 = planet_renderer.global_position + planet_renderer.size * 0.5 \
		- d["container"].get_global_rect().position
	d["center_local"] = center
	var offset:  Vector2 = Vector2(sin(lon_eff) * cos(lat), -sin(lat)) * r
	rocket.position = center + offset

	# ── Occlusion: hide when behind planet ────────────────────────────────────────
	var depth: float = cos(lon_eff) * cos(lat)
	rocket.visible = not (depth < -0.05 and offset.length() < planet_r * 0.99)

	rocket.queue_redraw()

	# ── Booster particles: update positions and trigger redraws ──────────────────
	if d.get("booster_particles") != null:
		for bp: Dictionary in d["booster_particles"]:
			if bp.get("node") != null and is_instance_valid(bp["node"]):
				bp["node"].position = bp["pos"]
				bp["node"].queue_redraw()

	# ── Hover tooltip ────────────────────────────────────────────────────────────
	var ctr2: Control = d["container"]
	var mp:   Vector2 = get_viewport().get_mouse_position()
	var rp:   Vector2 = ctr2.get_global_rect().position + rocket.position
	var near: bool    = mp.distance_to(rp) < 12.0
	if near and not d["hover_active"]:
		d["hover_active"] = true
		TooltipManager.show_tip("Shuttle", "· launching to orbit")
	elif not near and d["hover_active"]:
		d["hover_active"] = false
		TooltipManager.hide_tip()

	if finished:
		_finish_rocket_anim()
		return

## Same projection formula as OrbitalLayer._project, returns 2D screen offset from center.
func _orbital_project_2d(angle: float, inc: float, r: float, rot: float) -> Vector2:
	var px: float = r * cos(angle)
	var py: float = r * sin(angle) * sin(inc)
	var pz: float = r * sin(angle) * cos(inc)
	var rx: float = px * cos(rot) + pz * sin(rot)
	return Vector2(rx, py)

## Finds the orbit_angle whose screen projection is closest to the given offset.
## Numerical search: 720 coarse samples + 100 fine refinement steps.
func _find_orbit_angle_for_pos(target: Vector2, inc: float, r: float, rot: float) -> float:
	const COARSE: int = 720
	var best_a: float = 0.0
	var best_d: float = INF
	for i in COARSE:
		var a: float   = i * TAU / COARSE
		var d: float   = (_orbital_project_2d(a, inc, r, rot) - target).length_squared()
		if d < best_d:
			best_d = d
			best_a = a
	# Refine around best_a
	var step: float = TAU / COARSE
	for i in 100:
		var a: float = best_a + (i - 50) * step * 0.02
		var d: float = (_orbital_project_2d(a, inc, r, rot) - target).length_squared()
		if d < best_d:
			best_d = d
			best_a = a
	return best_a

## Called when fade phase ends — spawns ship and clears animation state.
func _finish_rocket_anim() -> void:
	var d: Dictionary = _rocket_anim
	var rocket: Control = d.get("rocket")
	var container: Control = d["container"]

	if rocket != null and is_instance_valid(rocket):
		rocket.queue_free()
	TooltipManager.hide_tip()

	var rot_now: float = planet_renderer.get_rotation_offset()
	var orbit_r: float = planet_renderer._planet_radius_px * 1.06

	# Compute insertion point analytically at t=1 — avoids reading rocket.position
	# from the previous frame (t<1) which caused a visible teleport on spawn.
	var lon_final: float = d["poi_lon"] + d["sweep_target"] - rot_now
	var lat_final: float = d["lat_target"]
	var tx: float = sin(lon_final) * cos(lat_final)   # normalised
	var ty: float = -sin(lat_final)

	# Analytical 3-DOF solution: orbit_angle + orbit_inc + orbit_node
	# gives EXACT position AND correct tangent direction simultaneously.
	#
	# Fix a = ±π/2 (tangent is purely horizontal at these points):
	#   a = -π/2 → tangent = (+cos(R), 0), matches sweep going right
	#   a = +π/2 → tangent = (-cos(R), 0), matches sweep going left
	# where R = rot_now + node.
	#
	# Then solve inc and node from position equations at the chosen a.
	var sweep_s: float = d["sweep_sign"]

	# a = ±π/2 → tangent is purely horizontal, matches rocket's sweep direction.
	# a = -π/2: tangent = (+cos(R), 0) → sweep right
	# a = +π/2: tangent = (-cos(R), 0) → sweep left
	var orbit_angle: float
	var orbit_inc:   float
	var orbit_node:  float

	# Full analytical 3-DOF solve: orbit_angle, orbit_inc, orbit_node
	# such that position = (tx,ty) AND tangent direction = (rdx,rdy) simultaneously.
	#
	# Direction: vector from launch position to insertion point — simple and intuitive.
	var start_x: float  = sin(d["poi_lon"] - rot_now) * cos(d["poi_lat"])
	var start_y: float  = -sin(d["poi_lat"])
	var rdx_raw: float  = tx - start_x
	var rdy_raw: float  = ty - start_y
	var rlen:      float = maxf(sqrt(rdx_raw * rdx_raw + rdy_raw * rdy_raw), 0.001)
	var rdx:       float = rdx_raw / rlen
	var rdy:       float = rdy_raw / rlen

	# Solution (derived from P⊥V on circular orbit):
	#   sin_inc = sqrt(ty²+rdy²)  [always positive — sign comes from a and node]
	#   a = atan2(ty, rdy)
	#   cos(R)         = (tx·rdy - rdx·ty) / sin_inc
	#   cos_inc·sin(R) = (tx·ty  + rdx·rdy) / sin_inc
	var sin_inc_sq: float = clampf(ty * ty + rdy * rdy, 0.0, 1.0)
	var sin_inc:    float = sqrt(sin_inc_sq)   # always positive
	var cos_inc:    float = sqrt(maxf(0.0, 1.0 - sin_inc_sq))

	orbit_angle = atan2(ty, rdy)
	orbit_inc   = asin(clampf(sin_inc, 0.0, 1.0))

	# Solve for orbit_node (R) from the position equation only:
	#   cos(a)*cos(R) + sin(a)*cos_inc*sin(R) = tx
	#   amplitude = sqrt(cos²a + sin²a*cos²_inc) = sqrt(1 - ty²) = cos(lat_final)
	# Two valid solutions — pick the one whose orbit tangent sign matches rdx_raw.
	var sa: float = sin(orbit_angle)   # = ty / sin_inc
	var ca: float = cos(orbit_angle)   # = rdy / sin_inc
	var amp: float = sqrt(maxf(0.0, 1.0 - ty * ty))   # = cos(lat_final)
	var phase: float = atan2(sa * cos_inc, ca)
	var R: float
	if amp > 0.001:
		var delta: float = acos(clampf(tx / amp, -1.0, 1.0))
		var R1: float = phase + delta
		var R2: float = phase - delta
		# Tangent x at each candidate: -sa*cos(R) + ca*cos_inc*sin(R)
		var t1: float = -sa * cos(R1) + ca * cos_inc * sin(R1)
		var t2: float = -sa * cos(R2) + ca * cos_inc * sin(R2)
		# Pick whichever matches the rdx_raw direction
		R = R1 if (t1 * rdx_raw >= 0.0) else R2
	else:
		# High-latitude insertion: use sweep direction to pick node
		R = (PI * 0.5 if rdx_raw >= 0.0 else -PI * 0.5) + atan2(ty * cos_inc, 0.001)
	orbit_node = R - rot_now

	# Tangent at orbit_angle is (rdx, rdy) for speed_sign=+1 by construction.
	# Verify sign against sweep direction to handle any degenerate edge case.
	var eff_rot2: float   = rot_now + orbit_node
	var p1:       Vector2 = _orbital_project_2d(orbit_angle,       orbit_inc, orbit_r, eff_rot2)
	var p2:       Vector2 = _orbital_project_2d(orbit_angle + 0.002, orbit_inc, orbit_r, eff_rot2)
	var speed_sign: float = 1.0 if (p2 - p1).dot(Vector2(rdx_raw, rdy_raw)) >= 0.0 else -1.0

	var ship := ShipManager.launch(d["planet_seed"], "Shuttle")
	ship.orbit_angle       = orbit_angle
	ship.orbit_inclination = orbit_inc
	ship.orbit_node        = orbit_node
	# CRUISE_FRAC=0.10, D=0.55, LAUNCH_DUR=18 → exit_rate ≈ 0.020 → orbit_speed ≈ 0.01 for rlen≈0.5
	const _CF: float = 0.10
	const _D:  float = (1.0 + _CF) * 0.5
	const _LD: float = 18.0
	var exit_rate: float = (_CF / _D) * (2.0 / _LD)
	ship.orbit_speed = speed_sign * rlen * exit_rate
	if _orbital_layer != null and is_instance_valid(_orbital_layer):
		_orbital_layer.queue_redraw()

	var cb: Callable = d["on_complete"]
	_rocket_anim.clear()
	cb.call()

# ── Toast / build-log notification ───────────────────────────────────────────

func _get_toast_container() -> VBoxContainer:
	if _toast_container != null and is_instance_valid(_toast_container):
		return _toast_container
	var tc := VBoxContainer.new()
	tc.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	tc.grow_vertical   = Control.GROW_DIRECTION_BEGIN   # stack upward
	tc.grow_horizontal = Control.GROW_DIRECTION_END
	tc.custom_minimum_size = Vector2(260, 0)
	tc.offset_left = 14.0
	tc.add_theme_constant_override("separation", 5)
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tc)
	_toast_container = tc
	return tc

## Measures the credits panel height and updates the toast container offset so
## toasts always stack just above the credits bar. Safe to call every time.
func _reanchor_toast_above_credits() -> void:
	var tc := _get_toast_container()
	# HUDManager lives on a CanvasLayer sibling — find it in the scene tree
	var hud: Node = get_tree().root.find_child("HUDManager", true, false)
	var credits_h: float = 38.0   # fallback
	if hud != null:
		var cp = hud.get("credits_panel")
		if cp != null and is_instance_valid(cp as Node):
			var real_h: float = (cp as Control).size.y
			if real_h > 4.0:
				credits_h = real_h
	# credits panel: offset_bottom = -12, height = credits_h
	# gap between credits top and toast bottom = 8px
	tc.offset_bottom = -(12.0 + credits_h + 8.0)

## Shows a brief construction-complete notification at the bottom-left,
## then fades it out after a few seconds.
func _show_construction_toast(building_name: String, district_label: String) -> void:
	# Re-measure credits panel height each time in case it changed after layout
	_reanchor_toast_above_credits()
	var tc := _get_toast_container()

	# ── Outer panel ─────────────────────────────────────────────────────────
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color     = Color(0.07, 0.10, 0.15, 0.90)
	ps.border_color = Color(0.28, 0.78, 0.48, 0.55)
	ps.set_border_width_all(1)
	ps.corner_radius_top_left     = 6
	ps.corner_radius_top_right    = 6
	ps.corner_radius_bottom_left  = 6
	ps.corner_radius_bottom_right = 6
	ps.content_margin_left   = 10.0
	ps.content_margin_right  = 12.0
	ps.content_margin_top    = 7.0
	ps.content_margin_bottom = 7.0
	panel.add_theme_stylebox_override("panel", ps)

	# ── Content row ─────────────────────────────────────────────────────────
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	# Checkmark icon
	var icon := Label.new()
	icon.text = "✓"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_theme_font_size_override("font_size", 13)
	icon.add_theme_color_override("font_color", Color(0.28, 0.90, 0.52))
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(icon)

	# Text column
	var tvbox := VBoxContainer.new()
	tvbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tvbox.add_theme_constant_override("separation", 1)
	hbox.add_child(tvbox)

	var name_lbl := Label.new()
	name_lbl.text = building_name
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_orbitron(name_lbl, 9)
	name_lbl.add_theme_color_override("font_color", Color(0.88, 0.95, 1.0))
	tvbox.add_child(name_lbl)

	if district_label != "":
		var sub := Label.new()
		sub.text = "Built in " + district_label
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_orbitron(sub, 7)
		sub.add_theme_color_override("font_color", Color(0.45, 0.58, 0.72))
		tvbox.add_child(sub)

	tc.add_child(panel)

	# ── Tween: fade-in → hold → fade-out → free ─────────────────────────────
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.25)
	tw.tween_interval(3.0)
	tw.tween_property(panel, "modulate:a", 0.0, 0.75)
	tw.tween_callback(panel.queue_free)

func _card_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color           = Color(0.07, 0.09, 0.16, 0.92)
	s.border_width_left  = 1; s.border_width_right  = 1
	s.border_width_top   = 1; s.border_width_bottom = 1
	s.border_color       = Color(0.22, 0.28, 0.50, 0.45)
	s.corner_radius_top_left     = 5
	s.corner_radius_top_right    = 5
	s.corner_radius_bottom_left  = 5
	s.corner_radius_bottom_right = 5
	return s

## Orb-of-Creation style: card whose background fills left→right as production ticks.
## count = number of this building type in this POI (for ×N badge)
## poi/planet/pp needed for "+" stacking button
func _build_construction_bar(def: BuildingDef, pm_key: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_panel_style())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true

	var body := MarginContainer.new()
	body.custom_minimum_size   = Vector2(0, 50)
	card.add_child(body)

	var fill_ctrl := Control.new()
	fill_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var prog_ref: Array = [ProductionManager.get_construct_progress(pm_key)]
	fill_ctrl.draw.connect(func() -> void:
		var p: float = (prog_ref as Array)[0]
		var w: float = fill_ctrl.size.x * p
		if w > 0.5:
			fill_ctrl.draw_rect(Rect2(0, 0, w, fill_ctrl.size.y), Color(0.72, 0.52, 0.12, 0.22))
			fill_ctrl.draw_rect(Rect2(w - 2.0, 0, 2.0, fill_ctrl.size.y), Color(0.95, 0.75, 0.25, 0.65)))
	body.add_child(fill_ctrl)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",  10)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    7)
	margin.add_theme_constant_override("margin_bottom", 7)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(hbox)

	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_lbl := Label.new()
	name_lbl.text = def.display_name
	_apply_orbitron(name_lbl, 10)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var status_lbl := Label.new()
	status_lbl.text = "CONSTRUCTING..."
	_apply_orbitron(status_lbl, 8)
	status_lbl.add_theme_color_override("font_color", Color(0.65, 0.50, 0.20))
	status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	name_col.add_child(name_lbl)
	name_col.add_child(status_lbl)
	hbox.add_child(name_col)

	# Percent label on right
	var pct_lbl := Label.new()
	pct_lbl.text = "0%"
	_apply_orbitron(pct_lbl, 9)
	pct_lbl.add_theme_color_override("font_color", Color(0.70, 0.58, 0.25))
	pct_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(pct_lbl)

	# Wire live updates via _bar_meta
	_bar_meta[pm_key] = {"fill": fill_ctrl, "prog": prog_ref, "pct": pct_lbl, "construction": true}

	return card

func _build_production_bar(def: BuildingDef, pm_key: String, _planet_seed: int,
		count: int, poi: POIData, planet: PlanetData, pp: PlanetProgress,
		entry: Dictionary = {}) -> PanelContainer:
	var paused := ProductionManager.is_paused(pm_key)
	var prog   := ProductionManager.get_progress(pm_key)
	var fc     := def.output_color()

	# ── Spaceport: custom launch card ────────────────────────────────────────────
	if def.building_id == "spaceport":
		return _build_spaceport_card(def, pm_key, pp, poi)

	# Outer card
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_panel_style())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true

	# Inner layer control — fill draws here, content sits on top
	var body := MarginContainer.new()
	body.custom_minimum_size   = Vector2(0, 54)
	card.add_child(body)

	# Fill control — redraws each production tick
	var fill_ctrl := Control.new()
	fill_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var prog_ref: Array = [prog]
	var cap_fill_key := pm_key
	fill_ctrl.draw.connect(func() -> void:
		var p: float = (prog_ref as Array)[0]
		var user_off: bool  = ProductionManager.is_user_paused(cap_fill_key)
		var auto_off: bool  = ProductionManager.is_paused(cap_fill_key)
		var w: float = fill_ctrl.size.x * p
		if user_off:
			fill_ctrl.draw_rect(Rect2(0, 0, fill_ctrl.size.x, fill_ctrl.size.y),
				Color(0.08, 0.08, 0.14, 0.72))
			# Diagonal hatch
			for xi: int in range(0, int(fill_ctrl.size.x) + int(fill_ctrl.size.y), 14):
				var x0: float = float(xi)
				fill_ctrl.draw_line(Vector2(x0, 0),
					Vector2(x0 - fill_ctrl.size.y, fill_ctrl.size.y),
					Color(0.25, 0.28, 0.42, 0.30), 1.0)
		elif auto_off:
			fill_ctrl.draw_rect(Rect2(0, 0, w, fill_ctrl.size.y),
				Color(0.35, 0.38, 0.55, 0.22))
		elif w > 0.5:
			fill_ctrl.draw_rect(Rect2(0, 0, w, fill_ctrl.size.y),
				Color(fc.r, fc.g, fc.b, 0.20))
			fill_ctrl.draw_rect(Rect2(w - 2.0, 0, 2.0, fill_ctrl.size.y),
				Color(fc.r, fc.g, fc.b, 0.55)))
	body.add_child(fill_ctrl)

	# Content layout on top of fill
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   10)
	margin.add_theme_constant_override("margin_right",   8)
	margin.add_theme_constant_override("margin_top",     7)
	margin.add_theme_constant_override("margin_bottom",  7)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 6)
	margin.add_child(hbox)

	# Left: name column
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	# Name row: "Hab Block" + "×2" count badge
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_theme_constant_override("separation", 5)
	var name_lbl := Label.new()
	name_lbl.text = def.display_name
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_orbitron(name_lbl, 10)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	name_row.add_child(name_lbl)
	if count > 1:
		var cnt_lbl := Label.new()
		cnt_lbl.text = "×%d" % count
		cnt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_orbitron(cnt_lbl, 8)
		cnt_lbl.add_theme_color_override("font_color", Color(0.55, 0.65, 1.0, 0.8))
		name_row.add_child(cnt_lbl)
	vbox.add_child(name_row)

	# Energy + output info row
	var info_row := HBoxContainer.new()
	info_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_row.add_theme_constant_override("separation", 8)
	
	# Determine modified output label text
	var out_val := def.output_amount
	if def.output_type == BuildingDef.OutputType.CREDITS:
		out_val *= get_node("/root/SkillTree").get_credits_mult()
	elif def.output_type == BuildingDef.OutputType.ENERGY:
		if def.building_id == "solar_panel":
			out_val *= get_node("/root/SkillTree").get_solar_mult()
		elif def.building_id == "generator":
			out_val *= get_node("/root/SkillTree").get_generator_output_mult()
			var in_min: String = entry.get("burning_mineral", "")
			if in_min != "":
				var rd: ResourceData = GameState.known_resources.get(in_min)
				if rd: out_val *= float(rd.rarity)
			else:
				out_val = 0.0 # No fuel
	elif def.output_type == BuildingDef.OutputType.RAW_MINERAL or def.output_type == BuildingDef.OutputType.REFINED_MINERAL:
		out_val *= get_node("/root/SkillTree").get_mine_output_mult()
		
	var out_text := "⏸ waiting" if paused else ""
	if not paused:
		match def.output_type:
			BuildingDef.OutputType.ENERGY:          out_text = "+%.0f ⚡" % out_val
			BuildingDef.OutputType.CREDITS:         out_text = "+%.0f cr" % out_val
			BuildingDef.OutputType.RAW_MINERAL:     out_text = "+%.0f ore" % out_val
			BuildingDef.OutputType.REFINED_MINERAL: out_text = "+%.0f ref" % out_val

	var out_lbl := Label.new()
	out_lbl.text = out_text
	out_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out_lbl.custom_minimum_size = Vector2(60, 0)
	_apply_orbitron(out_lbl, 8)
	out_lbl.add_theme_color_override("font_color",
		Color(0.45, 0.48, 0.60) if paused else fc)
	info_row.add_child(out_lbl)
	
	if def.energy_per_tick != 0.0:
		var etick := def.energy_per_tick
		if etick > 0.0:
			if def.building_id == "solar_panel":
				etick *= get_node("/root/SkillTree").get_solar_mult()
		else:
			etick *= get_node("/root/SkillTree").get_energy_consume_mult()
			
		var e_lbl := Label.new()
		var sign := "+" if etick > 0.0 else ""
		e_lbl.text = sign + "%.0f ⚡" % etick
		e_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_orbitron(e_lbl, 8)
		e_lbl.add_theme_color_override("font_color",
			Color(0.9, 0.82, 0.25, 0.55) if etick > 0 else Color(0.75, 0.48, 0.28, 0.55))
		info_row.add_child(e_lbl)

	var is_mine := def.output_type == BuildingDef.OutputType.RAW_MINERAL and def.input_type == BuildingDef.OutputType.NONE
	var is_generator := def.input_type == BuildingDef.OutputType.RAW_MINERAL and def.output_type == BuildingDef.OutputType.ENERGY

	# ── Dynamic Mineral Selection Tray ───────────────────────────────────────────
	# Handled via Dependency Injection (BuildingLogic)
	var is_consumer := def.logic != null and def.logic.requires_mineral_selector()

	if is_consumer:
		var br := GameState.get_body_resources_for(planet)
		var raw_list := br.get_by_tag(ResourceData.Tag.RAW_MINERAL)
		if not raw_list.is_empty():
			var target_key := "input_mineral"
			var tgt: String = entry.get(target_key, "")
			if tgt == "":
				tgt = (raw_list[0] as ResourceData).resource_id()
				entry[target_key] = tgt

			var current_rd: ResourceData = null
			for rd: ResourceData in raw_list:
				if rd.resource_id() == tgt:
					current_rd = rd
					break
			if current_rd == null:
				current_rd = raw_list[0]
				tgt = current_rd.resource_id()
				entry[target_key] = tgt

			var sep_lbl := Label.new()
			sep_lbl.text = "·"
			sep_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_apply_orbitron(sep_lbl, 8)
			sep_lbl.add_theme_color_override("font_color", Color(0.35, 0.38, 0.50))
			info_row.add_child(sep_lbl)

			if is_generator and def.input_amount > 0.0:
				var cost_lbl := Label.new()
				cost_lbl.text = " −%.0f " % (def.input_amount * count)
				cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_apply_orbitron(cost_lbl, 9)
				cost_lbl.add_theme_color_override("font_color", Color(0.85, 0.45, 0.45))
				info_row.add_child(cost_lbl)

			var chip_btn := Button.new()
			chip_btn.flat = false
			chip_btn.focus_mode = Control.FOCUS_NONE
			chip_btn.custom_minimum_size = Vector2(26, 26)
			
			var chip_style := StyleBoxFlat.new()
			chip_style.bg_color = current_rd.display_color.darkened(0.55)
			chip_style.border_color = current_rd.display_color
			chip_style.set_border_width_all(1)
			chip_style.corner_radius_top_left = 3
			chip_style.corner_radius_top_right = 3
			chip_style.corner_radius_bottom_left = 3
			chip_style.corner_radius_bottom_right = 3
			chip_btn.add_theme_stylebox_override("normal", chip_style)

			var chip_hover := chip_style.duplicate() as StyleBoxFlat
			chip_hover.bg_color = current_rd.display_color.darkened(0.4)
			chip_btn.add_theme_stylebox_override("hover", chip_hover)

			var icon_tex := MineralIcon.make(current_rd.tier, current_rd.display_color)
			var icon_rect := TextureRect.new()
			icon_rect.texture = icon_tex
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip_btn.add_child(icon_rect)
			icon_rect.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

			var action_desc := "Refining" if def.output_type == BuildingDef.OutputType.REFINED_MINERAL else "Burning"
			var tip_str := "%s: %s" % [action_desc, current_rd.unique_name]
			if def.input_amount > 0.0:
				tip_str += "\nConsumes: %.0f per cycle" % (def.input_amount * count)
			if raw_list.size() > 1:
				tip_str += "\n(Click to switch alternative mineral)"

			chip_btn.mouse_entered.connect(func() -> void:
				if not _is_at_edge(): CursorManager.set_state(CursorManager.State.POINTER)
				TooltipManager.show_tip(current_rd.unique_name, tip_str))
			chip_btn.mouse_exited.connect(func() -> void:
				CursorManager.set_state(CursorManager.State.NORMAL)
				TooltipManager.hide_tip())

			if raw_list.size() > 1:
				var cap_chip_btn := chip_btn
				var cap_raw_list := raw_list
				var cap_target_key := target_key
				var cap_tgt := tgt
				var cap_poi := poi
				var cap_planet := planet
				var cap_entry := entry
				chip_btn.pressed.connect(func() -> void:
					_toggle_mineral_dropdown(cap_chip_btn, cap_raw_list, cap_target_key, cap_tgt, cap_poi, cap_planet, cap_entry))
			else:
				chip_btn.disabled = true
				chip_btn.focus_mode = Control.FOCUS_NONE

			info_row.add_child(chip_btn)
			vbox.add_child(info_row)
		else:
			vbox.add_child(info_row)
	else:
		vbox.add_child(info_row)

	# Energy-crisis "Slowed" label — shown below info row for energy consumers
	var slowed_lbl: Label = null
	if def.energy_per_tick < 0.0:
		slowed_lbl = Label.new()
		slowed_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_orbitron(slowed_lbl, 7)
		slowed_lbl.add_theme_color_override("font_color", Color(0.90, 0.55, 0.20))
		var er := ProductionManager.get_energy_ratio(pp.planet_seed)
		slowed_lbl.text    = "⚡ Slowed %d%% — Energy Crisis" % [int((1.0 - er) * 100)]
		slowed_lbl.visible = er < 0.999
		vbox.add_child(slowed_lbl)

	# Right: "+" stacking and "−" demolish buttons
	var slots_free: int  = pp.district_slots(poi) - pp.slots_used_in_district(poi.label)
	var can_add: bool    = slots_free >= def.slot_cost and GameState.credits >= def.base_cost
	var cap_poi    := poi
	var cap_def    := def
	var cap_planet := planet
	var cap_entry  := entry  # dict reference for demolish

	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 2)
	btn_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var add_btn := Button.new()
	add_btn.text     = "＋"
	add_btn.flat     = false
	add_btn.disabled = not can_add
	_apply_orbitron(add_btn, 10)
	add_btn.custom_minimum_size = Vector2(30, 22)
	var add_s := StyleBoxFlat.new()
	add_s.bg_color    = Color(0.12, 0.30, 0.15, 1.0) if can_add else Color(0.10, 0.10, 0.16, 1.0)
	add_s.border_color = Color(0.35, 0.75, 0.40, 1.0) if can_add else Color(0.22, 0.25, 0.38, 1.0)
	add_s.border_width_left = 1; add_s.border_width_right  = 1
	add_s.border_width_top  = 1; add_s.border_width_bottom = 1
	add_s.corner_radius_top_left     = 3; add_s.corner_radius_top_right    = 3
	add_s.corner_radius_bottom_left  = 3; add_s.corner_radius_bottom_right = 3
	add_s.content_margin_left = 3; add_s.content_margin_right = 3
	add_btn.add_theme_stylebox_override("normal",   add_s)
	add_btn.add_theme_stylebox_override("disabled", add_s)
	add_btn.add_theme_stylebox_override("focus",    StyleBoxEmpty.new())
	add_btn.add_theme_color_override("font_color",
		Color(0.60, 0.95, 0.65) if can_add else Color(0.30, 0.33, 0.45))
	var tip_add: String
	if not can_add and slots_free < def.slot_cost:
		tip_add = "No slots · Upgrade district"
	elif not can_add:
		tip_add = "Need %.0f cr" % def.base_cost
	else:
		tip_add = "Stack one more %s\n%.0f cr · %d slot" % [def.display_name, def.base_cost, def.slot_cost]
	add_btn.mouse_entered.connect(func() -> void:
		if not _is_at_edge(): CursorManager.set_state(CursorManager.State.POINTER)
		TooltipManager.show_tip("＋ " + def.display_name, tip_add))
	add_btn.mouse_exited.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.NORMAL)
		TooltipManager.hide_tip())
	add_btn.pressed.connect(func() -> void:
		if GameState.spend_credits(cap_def.base_cost):
			pp.stack_building_unchecked(cap_poi.label, cap_def.building_id)
			GameState.planet_progress_changed.emit(cap_planet.seed)
			_refresh_overview_energy()
			_build_district_panel(cap_poi, cap_planet))

	var rem_btn := Button.new()
	rem_btn.text = "−"
	rem_btn.flat = false
	_apply_orbitron(rem_btn, 10)
	rem_btn.custom_minimum_size = Vector2(30, 22)
	var rem_s := StyleBoxFlat.new()
	rem_s.bg_color     = Color(0.28, 0.10, 0.10, 1.0)
	rem_s.border_color  = Color(0.65, 0.28, 0.28, 1.0)
	rem_s.border_width_left = 1; rem_s.border_width_right  = 1
	rem_s.border_width_top  = 1; rem_s.border_width_bottom = 1
	rem_s.corner_radius_top_left     = 3; rem_s.corner_radius_top_right    = 3
	rem_s.corner_radius_bottom_left  = 3; rem_s.corner_radius_bottom_right = 3
	rem_s.content_margin_left = 3; rem_s.content_margin_right = 3
	rem_btn.add_theme_stylebox_override("normal", rem_s)
	rem_btn.add_theme_stylebox_override("focus",  StyleBoxEmpty.new())
	rem_btn.add_theme_color_override("font_color", Color(0.90, 0.45, 0.45))
	var tip_rem := "Remove one %s" % def.display_name if count > 1 else "Demolish %s" % def.display_name
	rem_btn.mouse_entered.connect(func() -> void:
		if not _is_at_edge(): CursorManager.set_state(CursorManager.State.POINTER)
		TooltipManager.show_tip("−", tip_rem))
	rem_btn.mouse_exited.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.NORMAL)
		TooltipManager.hide_tip())
	rem_btn.pressed.connect(func() -> void:
		var amt: int = cap_entry.get("amount", 1)
		if amt <= 1:
			pp.buildings.erase(cap_entry)
		else:
			cap_entry["amount"] = amt - 1
		GameState.planet_progress_changed.emit(cap_planet.seed)
		_build_district_panel(cap_poi, cap_planet))

	btn_vbox.add_child(add_btn)
	btn_vbox.add_child(rem_btn)
	hbox.add_child(btn_vbox)

	# Click card body (not the "+" button) to toggle building on/off
	var cap_toggle_key := pm_key
	body.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				ProductionManager.toggle_user_pause(cap_toggle_key))

	_bar_meta[pm_key] = {
		"fill":        fill_ctrl,
		"prog":        prog_ref,
		"out_lbl":     out_lbl,
		"slowed_lbl":  slowed_lbl,
		"planet_seed": pp.planet_seed,
		"def":         def,
		"fc":          fc,
		"entry":       entry
	}
	return card

## Spaceport card: idle "READY" state with Launch button, or filling progress bar.
func _build_spaceport_card(def: BuildingDef, pm_key: String,
		pp: PlanetProgress, poi: POIData) -> PanelContainer:
	var is_ready := ProductionManager.is_user_paused(pm_key)
	var prog     := ProductionManager.get_progress(pm_key)

	var card := PanelContainer.new()
	var s := _card_panel_style()
	card.add_theme_stylebox_override("panel", s)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.clip_contents = true

	var body := MarginContainer.new()
	body.custom_minimum_size = Vector2(0, 54)
	card.add_child(body)

	# Fill bar (only visible when launching)
	var prog_ref: Array = [prog]
	var fill_ctrl := Control.new()
	fill_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cap_key := pm_key
	fill_ctrl.draw.connect(func() -> void:
		var p: float = (prog_ref as Array)[0]
		if ProductionManager.is_user_paused(cap_key):
			return
		var w: float = fill_ctrl.size.x * p
		if w > 0.5:
			fill_ctrl.draw_rect(Rect2(0, 0, w, fill_ctrl.size.y), Color(0.35, 0.75, 1.0, 0.18))
			fill_ctrl.draw_rect(Rect2(w - 2.0, 0, 2.0, fill_ctrl.size.y), Color(0.5, 0.9, 1.0, 0.55)))
	body.add_child(fill_ctrl)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   10)
	margin.add_theme_constant_override("margin_right",   8)
	margin.add_theme_constant_override("margin_top",     7)
	margin.add_theme_constant_override("margin_bottom",  7)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	margin.add_child(hbox)

	# Left: name + status
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = def.display_name
	_apply_orbitron(name_lbl, 10)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var status_lbl := Label.new()
	status_lbl.text = "–8 ⚡   Ready to launch"
	_apply_orbitron(status_lbl, 8)
	status_lbl.add_theme_color_override("font_color", Color(0.45, 0.65, 0.95, 0.70))
	status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(status_lbl)

	# Right: Launch button
	var cap_poi      := poi
	var cap_pp       := pp
	var launch_btn   := Button.new()
	launch_btn.text  = "🚀 Launch"
	_apply_orbitron(launch_btn, 9)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color     = Color(0.12, 0.28, 0.55, 0.90)
	btn_style.border_color = Color(0.35, 0.65, 1.0, 0.80)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(4)
	btn_style.content_margin_left  = 10
	btn_style.content_margin_right = 10
	btn_style.content_margin_top   = 4
	btn_style.content_margin_bottom = 4
	launch_btn.add_theme_stylebox_override("normal",  btn_style)
	launch_btn.add_theme_stylebox_override("hover",   btn_style)
	launch_btn.add_theme_stylebox_override("pressed", btn_style)
	launch_btn.add_theme_color_override("font_color", Color(0.65, 0.88, 1.0))
	launch_btn.custom_minimum_size = Vector2(90, 0)

	launch_btn.pressed.connect(func() -> void:
		if not launch_btn.disabled:
			launch_btn.text     = "Launching…"
			launch_btn.disabled = true
			pp.has_spaceport    = true
			_play_rocket_animation(pp.planet_seed, poi, func() -> void:
				if is_instance_valid(launch_btn):
					launch_btn.text    = "🚀 Launch"
					launch_btn.disabled = false))

	hbox.add_child(launch_btn)

	# Register in _bar_meta so _on_building_ticked_night drives queue_redraw automatically
	_bar_meta[pm_key] = {
		"fill":        fill_ctrl,
		"prog":        prog_ref,
		"planet_seed": pp.planet_seed,
		"launch_btn":  launch_btn,
	}

	return card

## Empty slot card — shows "+" and opens a build dropdown on click.
func _build_slot_card(poi: POIData, planet: PlanetData, pp: PlanetProgress,
		root: VBoxContainer, slot_idx: int) -> PanelContainer:
	var card := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color      = Color(0.06, 0.08, 0.14, 0.70)
	s.border_width_left  = 1; s.border_width_right  = 1
	s.border_width_top   = 1; s.border_width_bottom = 1
	s.border_color  = Color(0.28, 0.35, 0.60, 0.35)
	s.corner_radius_top_left     = 5
	s.corner_radius_top_right    = 5
	s.corner_radius_bottom_left  = 5
	s.corner_radius_bottom_right = 5
	card.add_theme_stylebox_override("panel", s)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size   = Vector2(0, 38)

	var plus := Label.new()
	plus.text = "＋  Empty Slot"
	plus.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	plus.offset_left = 10
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_orbitron(plus, 10)
	plus.add_theme_color_override("font_color", Color(0.30, 0.38, 0.65, 0.70))
	card.add_child(plus)

	card.mouse_entered.connect(func() -> void:
		if not _is_at_edge(): CursorManager.set_state(CursorManager.State.POINTER)
		plus.add_theme_color_override("font_color", Color(0.55, 0.65, 1.0, 0.9)))
	card.mouse_exited.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.NORMAL)
		plus.add_theme_color_override("font_color", Color(0.30, 0.38, 0.65, 0.70)))
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_toggle_slot_dropdown(card, poi, planet, pp, root, slot_idx))
	return card

func _toggle_slot_dropdown(card: PanelContainer, poi: POIData, planet: PlanetData,
		pp: PlanetProgress, root: VBoxContainer, _slot_idx: int) -> void:
	# Toggle off if already open for this slot
	if _active_slot_dropdown != null and is_instance_valid(_active_slot_dropdown):
		var prev_card = _active_slot_dropdown.get_meta("slot_card", null)
		_active_slot_dropdown.queue_free()
		_active_slot_dropdown = null
		if prev_card == card:
			return

	var buildable := BuildingDef.for_poi_type(poi.poi_type)
	if buildable.is_empty():
		return

	var slots_free: int = pp.district_slots(poi) - pp.slots_used_in_district(poi.label)

	# ── CanvasLayer overlay — always renders above game UI ───────────
	if _dd_layer == null or not is_instance_valid(_dd_layer):
		_dd_layer = CanvasLayer.new()
		_dd_layer.layer = 120   # above HUD (100) but below tooltip (150)
		add_child(_dd_layer)

	var outer := PanelContainer.new()
	outer.set_meta("slot_card", card)
	outer.add_theme_stylebox_override("panel",
		_make_hud_style(Color(0.05, 0.07, 0.14, 0.97), 6))

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	outer.add_child(list)

	for def: BuildingDef in buildable:
		if def.min_planet_lv > pp.level:
			continue
		var can_afford: bool = GameState.credits >= def.base_cost
		var has_slots:  bool = slots_free >= def.slot_cost
		var enabled: bool    = can_afford and has_slots

		var row_panel := PanelContainer.new()
		var norm_s := StyleBoxFlat.new()
		norm_s.bg_color = Color(0, 0, 0, 0)
		norm_s.content_margin_left = 10; norm_s.content_margin_right  = 10
		norm_s.content_margin_top  = 7;  norm_s.content_margin_bottom = 7
		var hov_s := norm_s.duplicate() as StyleBoxFlat
		hov_s.bg_color = Color(0.12, 0.18, 0.35, 0.60)
		row_panel.add_theme_stylebox_override("panel", norm_s)
		row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 2)
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var n_lbl := Label.new()
		n_lbl.text = def.display_name
		n_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_orbitron(n_lbl, 10)
		n_lbl.add_theme_color_override("font_color",
			Color(0.80, 0.88, 1.0) if enabled else Color(0.38, 0.40, 0.55))

		var reason := ""
		if not has_slots: reason = "No free slots"
		elif not can_afford: reason = "Need %.0f cr" % def.base_cost

		# Compact sub-line: RichTextLabel so we can embed inline mineral icon
		var row_color := Color(0.45, 0.72, 0.40) if (can_afford and has_slots) \
			else Color(0.60, 0.30, 0.28)
		var ore_sub_icon := MineralIcon.make(1, Color(0.55, 0.60, 0.70))

		var c_lbl := RichTextLabel.new()
		c_lbl.bbcode_enabled  = true
		c_lbl.fit_content     = true
		c_lbl.scroll_active   = false
		c_lbl.mouse_filter    = Control.MOUSE_FILTER_IGNORE
		c_lbl.add_theme_font_size_override("normal_font_size", 8)
		c_lbl.add_theme_color_override("default_color", row_color)
		if _orbitron: c_lbl.add_theme_font_override("normal_font", _orbitron)
		c_lbl.custom_minimum_size = Vector2(0, 14)

		c_lbl.append_text("%.0f cr" % def.base_cost)
		if def.output_type == BuildingDef.OutputType.ENERGY:
			var net := def.energy_per_tick + def.output_amount
			c_lbl.append_text(" · %s%.0f ⚡" % ["+" if net >= 0.0 else "", net])
		elif def.energy_per_tick != 0.0:
			c_lbl.append_text(" · %.0f ⚡" % def.energy_per_tick)
		if def.input_amount > 0.0 and def.input_type == BuildingDef.OutputType.RAW_MINERAL:
			c_lbl.append_text(" · −%.0f " % def.input_amount)
			c_lbl.add_image(ore_sub_icon, 11, 11)
		if def.output_label() != "" and def.output_type != BuildingDef.OutputType.ENERGY:
			if def.output_type == BuildingDef.OutputType.RAW_MINERAL:
				c_lbl.append_text(" · %s " % def.output_label().replace(" ore", ""))
				c_lbl.add_image(ore_sub_icon, 11, 11)
			else:
				c_lbl.append_text(" · %s" % def.output_label())

		vbox.add_child(n_lbl); vbox.add_child(c_lbl)
		row_panel.add_child(vbox)
		list.add_child(row_panel)

		var cap_poi    := poi
		var cap_def    := def
		var cap_planet := planet
		var cap_row    := row_panel
		var cap_norm   := norm_s
		var cap_hov    := hov_s
		var tip_title := def.display_name

		# ── Dynamic stat calculation ────────────────────────────────
		var sk         := get_node("/root/SkillTree")
		var mods       := PlanetModifier.for_planet(planet.planet_type)
		var spd_mult: float = sk.get_global_speed_mult()
		var out_mult   := 1.0
		var cycle_s    := def.tick_duration

		match def.output_type:
			BuildingDef.OutputType.RAW_MINERAL:
				out_mult = PlanetModifier.combined(mods, PlanetModifier.Effect.MINE_OUTPUT_MULT) \
					* sk.get_mine_output_mult()
				spd_mult *= sk.get_mine_speed_mult()
			BuildingDef.OutputType.CREDITS:
				out_mult = sk.get_credits_mult()
			BuildingDef.OutputType.ENERGY:
				if def.building_id == "solar_panel":  out_mult = sk.get_solar_mult()
				elif def.building_id == "generator":  out_mult = sk.get_generator_output_mult()

		if cycle_s > 0.0 and spd_mult > 0.0:
			cycle_s = cycle_s / spd_mult

		var dyn_output := def.output_amount * out_mult
		var dyn_energy := def.energy_per_tick  # upkeep doesn't scale with output_mult

		# ── Ore icon (colorless gray T1 shape used inline) ─────────
		var ore_icon := MineralIcon.make(1, Color(0.55, 0.58, 0.70))

		# ── Find which ore this building will consume/produce ────
		var pd_for_tip := planet
		var br_for_tip := GameState.get_body_resources_for(pd_for_tip)
		var raw_arr    := br_for_tip.get_by_tag(ResourceData.Tag.RAW_MINERAL)
		# Use the first/lowest-rarity ore on this planet as the example
		var example_rd: ResourceData = raw_arr[0] if not raw_arr.is_empty() else null
		var example_ore_power: float = example_rd.power if example_rd != null else 1.0

		# ── Body: description + stat rows as mixed Array ─────────
		# Order: Cycle, then production (+), then upkeep (−).
		var tip_body_parts: Array = [def.description, "\n\n"]
		if def.slot_cost > 1:
			tip_body_parts.append("Slots    %d\n" % def.slot_cost)
		tip_body_parts.append("Cycle    %.0fs" % cycle_s)

		# Active energy output on the same line as Cycle
		if def.output_type == BuildingDef.OutputType.ENERGY:
			tip_body_parts.append("    +%.0f ⚡" % dyn_output)

		# Production rows (after cycle)
		if def.output_type == BuildingDef.OutputType.RAW_MINERAL:
			tip_body_parts.append("\n+%.1f " % dyn_output)
			tip_body_parts.append(ore_icon)
		elif def.output_type == BuildingDef.OutputType.CREDITS:
			tip_body_parts.append("\n+%.0f cr" % dyn_output)
		elif def.output_type == BuildingDef.OutputType.REFINED_MINERAL:
			tip_body_parts.append("\n+%.1f refined" % dyn_output)

		# Upkeep / consumption (below production)
		if dyn_energy < 0.0:
			tip_body_parts.append("\nUpkeep   %.0f ⚡" % dyn_energy)  # negative value includes sign
		if def.input_type == BuildingDef.OutputType.RAW_MINERAL and def.input_amount > 0.0:
			tip_body_parts.append("\nUses     −%.0f " % def.input_amount)
			tip_body_parts.append(ore_icon)

		if reason != "":
			tip_body_parts.append("\n\n➡ " + reason)
		var tip_cost := "%.0f cr" % def.base_cost

		row_panel.mouse_entered.connect(func() -> void:
			cap_row.add_theme_stylebox_override("panel", cap_hov)
			if enabled and not _is_at_edge():
				CursorManager.set_state(CursorManager.State.POINTER)
			TooltipManager.show_tip(tip_title, tip_body_parts, tip_cost))
		row_panel.mouse_exited.connect(func() -> void:
			cap_row.add_theme_stylebox_override("panel", cap_norm)
			CursorManager.set_state(CursorManager.State.NORMAL)
			TooltipManager.hide_tip())

		var cap_overlay := outer
		if enabled:
			row_panel.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
						and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
					if GameState.spend_credits(cap_def.base_cost):
						pp.build_in_district(cap_poi, cap_def.building_id)
						if is_instance_valid(cap_overlay):
							cap_overlay.queue_free()
						_active_slot_dropdown = null
						GameState.planet_progress_changed.emit(cap_planet.seed)
						_refresh_overview_energy()
						_build_district_panel(cap_poi, cap_planet))

	_dd_layer.add_child(outer)
	# CanvasLayer children use screen-space coordinates directly
	await get_tree().process_frame
	if not is_instance_valid(outer):
		return
	var card_rect := card.get_global_rect()
	outer.position            = Vector2(card_rect.position.x, card_rect.end.y)
	outer.custom_minimum_size = Vector2(card_rect.size.x, 0)
	_active_slot_dropdown = outer

func _toggle_mineral_dropdown(btn: Control, raw_list: Array, target_key: String, current_tgt: String, poi: POIData, planet: PlanetData, entry: Dictionary) -> void:
	if _active_slot_dropdown != null and is_instance_valid(_active_slot_dropdown):
		var prev_btn = _active_slot_dropdown.get_meta("trigger_btn", null)
		_active_slot_dropdown.queue_free()
		_active_slot_dropdown = null
		if prev_btn == btn:
			return

	if _dd_layer == null or not is_instance_valid(_dd_layer):
		_dd_layer = CanvasLayer.new()
		_dd_layer.layer = 120
		add_child(_dd_layer)

	var outer := PanelContainer.new()
	outer.set_meta("trigger_btn", btn)
	var tray_style := StyleBoxFlat.new()
	tray_style.bg_color = Color(0.05, 0.07, 0.12, 0.95)
	tray_style.border_color = Color(0.2, 0.25, 0.4, 0.7)
	tray_style.set_border_width_all(1)
	tray_style.corner_radius_top_left = 4
	tray_style.corner_radius_top_right = 4
	tray_style.corner_radius_bottom_left = 4
	tray_style.corner_radius_bottom_right = 4
	tray_style.content_margin_left = 6
	tray_style.content_margin_right = 6
	tray_style.content_margin_top = 4
	tray_style.content_margin_bottom = 4
	outer.add_theme_stylebox_override("panel", tray_style)

	var tray_h := HBoxContainer.new()
	tray_h.add_theme_constant_override("separation", 6)
	outer.add_child(tray_h)

	for alternative: ResourceData in raw_list:
		var is_current := alternative.resource_id() == current_tgt
		var alt_btn := Button.new()
		alt_btn.flat = true
		alt_btn.focus_mode = Control.FOCUS_NONE
		alt_btn.custom_minimum_size = Vector2(28, 28)
		
		var alt_icon := TextureRect.new()
		alt_icon.texture = MineralIcon.make(alternative.tier, alternative.display_color)
		alt_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		alt_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		alt_btn.add_child(alt_icon)
		alt_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

		var alt_style := StyleBoxFlat.new()
		alt_style.bg_color = Color(0.1, 0.12, 0.2, 0.8)
		alt_style.border_color = alternative.display_color.darkened(0.3)
		if is_current:
			alt_style.bg_color = Color(0.15, 0.25, 0.15, 0.9)
			alt_style.border_color = Color(0.4, 0.8, 0.4, 0.8)
		alt_style.set_border_width_all(1)
		alt_style.corner_radius_top_left = 3
		alt_style.corner_radius_top_right = 3
		alt_style.corner_radius_bottom_left = 3
		alt_style.corner_radius_bottom_right = 3
		alt_btn.add_theme_stylebox_override("normal", alt_style)

		var alt_hover := alt_style.duplicate() as StyleBoxFlat
		alt_hover.bg_color = Color(0.15, 0.18, 0.3, 0.95)
		alt_hover.border_color = alternative.display_color
		alt_btn.add_theme_stylebox_override("hover", alt_hover)
		
		if is_current:
			alt_btn.disabled = true
			alt_btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
		else:
			alt_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

		var cap_target_key := target_key
		var cap_alternative := alternative
		var cap_poi := poi
		var cap_planet := planet
		var cap_entry := entry
		var cap_outer := outer
		alt_btn.pressed.connect(func() -> void:
			cap_entry[cap_target_key] = cap_alternative.resource_id()
			if is_instance_valid(cap_outer):
				cap_outer.queue_free()
			_active_slot_dropdown = null
			_build_district_panel(cap_poi, cap_planet))
		
		alt_btn.mouse_entered.connect(func() -> void:
			if not _is_at_edge(): CursorManager.set_state(CursorManager.State.POINTER)
			TooltipManager.show_tip("Switch to:", cap_alternative.unique_name))
		alt_btn.mouse_exited.connect(func() -> void:
			CursorManager.set_state(CursorManager.State.NORMAL)
			TooltipManager.hide_tip())

		tray_h.add_child(alt_btn)

	_dd_layer.add_child(outer)
	await get_tree().process_frame
	if not is_instance_valid(outer):
		return
	var btn_rect := btn.get_global_rect()
	outer.position = Vector2(btn_rect.position.x, btn_rect.end.y)
	_active_slot_dropdown = outer

func _build_district_panel(poi: POIData, planet: PlanetData) -> void:
	_active_district_poi = poi   # remember for _on_building_constructed
	var panel_content := $RightPanel/PanelContent
	var old := panel_content.get_node_or_null("DistrictBuildPanel")
	if old:
		old.name = "__freeing_district__"   # free name slot before queue_free
		old.queue_free()
		_bar_meta.clear()
		if _active_slot_dropdown != null and is_instance_valid(_active_slot_dropdown):
			_active_slot_dropdown.queue_free()
		_active_slot_dropdown = null

	var pp   := GameState.get_planet(planet.seed)
	var root := VBoxContainer.new()
	root.name = "DistrictBuildPanel"
	root.add_theme_constant_override("separation", 8)
	root.add_child(HSeparator.new())

	var header := HBoxContainer.new()

	# Inline rename: click label → LineEdit appears
	var title_stack := Control.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.custom_minimum_size    = Vector2(0, 22)
	header.add_child(title_stack)

	var poi_title := Label.new()
	poi_title.text = poi.label + "  ·  " + poi.type_label()
	_apply_orbitron(poi_title, 11)
	poi_title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	poi_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	poi_title.mouse_filter = Control.MOUSE_FILTER_STOP
	title_stack.add_child(poi_title)

	var cap_poi_rename  := poi
	var cap_planet_ren  := planet
	var cap_pp_rename   := pp
	poi_title.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton): return
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			poi_title.visible = false
			var edit := LineEdit.new()
			edit.text = cap_poi_rename.label
			_apply_orbitron(edit, 10)
			edit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			title_stack.add_child(edit)
			edit.grab_focus()
			edit.select_all()
			var _commit := func(new_name: String) -> void:
				var trimmed := new_name.strip_edges()
				if trimmed.is_empty(): trimmed = cap_poi_rename.label
				# Update POI label and re-key all building entries
				var old_label := cap_poi_rename.label
				cap_poi_rename.label = trimmed
				for b: Dictionary in cap_pp_rename.buildings:
					if b.get("district_id") == old_label:
						b["district_id"] = trimmed
				edit.queue_free()
				poi_title.text = trimmed + "  ·  " + cap_poi_rename.type_label()
				poi_title.visible = true
				GameState.planet_progress_changed.emit(cap_planet_ren.seed)
			edit.text_submitted.connect(_commit)
			edit.focus_exited.connect(func() -> void: _commit.call(edit.text)))

	var slots_used  := pp.slots_used_in_district(poi.label)
	var slots_total := pp.district_slots(poi)
	var dist_lv: int = pp.district_levels.get(poi.label, 1)
	var slots_lbl := Label.new()
	slots_lbl.text = "%d/%d  Lv%d" % [slots_used, slots_total, dist_lv]
	_apply_orbitron(slots_lbl, 9)
	slots_lbl.add_theme_color_override("font_color",
		Color(0.85, 0.55, 0.35) if slots_used >= slots_total else Color(0.5, 0.6, 0.8))
	header.add_child(slots_lbl)

	# District upgrade button
	var upg_cost := 500 * dist_lv
	var upg_btn  := Button.new()
	upg_btn.text    = "⬆"
	upg_btn.flat    = true
	upg_btn.disabled = GameState.credits < upg_cost
	_apply_orbitron(upg_btn, 10)
	upg_btn.custom_minimum_size = Vector2(22, 22)
	upg_btn.add_theme_color_override("font_color",
		Color(0.9, 0.82, 0.45) if GameState.credits >= upg_cost else Color(0.35, 0.38, 0.50))
	upg_btn.mouse_entered.connect(func() -> void:
		if not _is_at_edge(): CursorManager.set_state(CursorManager.State.POINTER)
		TooltipManager.show_tip("Upgrade District",
			"Increases slot capacity by 2.", "%d cr" % upg_cost))
	upg_btn.mouse_exited.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.NORMAL)
		TooltipManager.hide_tip())
	var cap_poi_upg    := poi
	var cap_planet_upg := planet
	upg_btn.pressed.connect(func() -> void:
		if GameState.spend_credits(upg_cost):
			pp.upgrade_district(cap_poi_upg.label)
			GameState.planet_progress_changed.emit(cap_planet_upg.seed)
			_build_district_panel(cap_poi_upg, cap_planet_upg))
	header.add_child(upg_btn)
	root.add_child(header)

	# District energy balance row
	var de_row := HBoxContainer.new()
	var de_lbl := Label.new()
	de_lbl.text = "District Energy"
	de_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_orbitron(de_lbl, 8)
	de_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.65))
	var de_val := Label.new()
	_active_district_energy_lbl = de_val
	_refresh_district_energy_lbl()
	_apply_orbitron(de_val, 8)
	de_row.add_child(de_lbl); de_row.add_child(de_val)
	root.add_child(de_row)

	# Connect production updates to refresh bar fills live
	if not ProductionManager.building_progress_changed.is_connected(_on_production_update):
		ProductionManager.building_progress_changed.connect(_on_production_update)
	if not ProductionManager.building_constructed.is_connected(_on_building_constructed):
		ProductionManager.building_constructed.connect(_on_building_constructed)
	if not ProductionManager.building_toggled.is_connected(_on_building_toggled):
		ProductionManager.building_toggled.connect(_on_building_toggled)
	if not ProductionManager.building_ticked.is_connected(_on_building_ticked_night):
		ProductionManager.building_ticked.connect(_on_building_ticked_night)

	# ── Installed buildings as full-bleed production cards ────────────────────
	# One card per building entry; amount field drives ×N display and output scaling
	var installed := pp.buildings_in_district(poi.label)
	for entry: Dictionary in installed:
		var bid: String = entry.get("building_id", "")
		var def := BuildingDef.find(bid)
		if def == null:
			continue
		var idx: int       = pp.building_real_index(entry)
		var pm_key: String = "%d:%s:%d" % [planet.seed, poi.label, idx]
		var amount: int    = entry.get("amount", 1)
		if entry.get("constructing", false):
			root.add_child(_build_construction_bar(def, pm_key))
		else:
			root.add_child(_build_production_bar(def, pm_key, planet.seed, amount, poi, planet, pp, entry))

	# ── Empty slot "+" cards ──────────────────────────────────────────────────
	var total_slots := pp.district_slots(poi)
	var used_slots  := pp.slots_used_in_district(poi.label)
	for si in (total_slots - used_slots):
		root.add_child(_build_slot_card(poi, planet, pp, root, si))

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
