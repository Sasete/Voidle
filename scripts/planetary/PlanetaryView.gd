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
var _top_tab_active: String = "DETAILS"    # "DETAILS" or "INVENTORY"
var _inner_tab_active: String = "SURFACE"  # "SURFACE" or "ORBITAL"
var _overview_energy_val: Label = null   # kept for live energy updates
var _orbital_layer: OrbitalLayer = null
var _mission_builder_overlay: Control = null  # non-null while Mission Builder is open

## Active rocket launch animation state. Empty when no launch in progress.
## Keys: rocket(Control), radius(float), angle_rel(float), alpha(float),
##       phase(int 0=rise/1=turn/2=fade), phase_t(float), on_complete(Callable),
##       planet_seed(int), orbit_inc(float), insert_angle_rel(float), planet_r(float)
var _rocket_anims: Array[Dictionary] = []
## Station deploy particle anims: {ship, ctrl, t, duration}
var _deploy_anims: Array[Dictionary] = []
## Toast log container — created lazily, anchored bottom-left.
var _toast_container: VBoxContainer = null
var _ship_panel: PanelContainer = null
var _radial_menu: Control = null
## Maps building pm_key -> bool indicating if its mineral switcher tray is expanded
var _open_mineral_switchers: Dictionary = {}

## Live district construction progress bars.
var _district_pbars: Dictionary = {}
var _planet_upgrade_pbar: ProgressBar = null
var _inventory_tab_btn: Button = null

# ── Tutorial highlight state ──────────────────────────────────────────────────
var _tut_highlight:      String  = ""     # current highlight target id
var _tut_highlight_node: Control = null   # specific UI node being pulsed
var _tut_node_tween:     Tween   = null
var _tut_panel_node:     Control = null   # right-panel card secondary pulse
var _tut_panel_tween:    Tween   = null
var _poi_overview_cards: Dictionary = {}  # poi.label -> PanelContainer card

func _make_system(root: PlanetData) -> Array[PlanetData]:
	var arr: Array[PlanetData] = [root]
	for m in root.moons:
		arr.append(m)
	return arr


func _ready() -> void:
	CursorManager.set_state(CursorManager.State.NORMAL)
	mouse_filter = Control.MOUSE_FILTER_PASS
	if has_node("Background"):
		get_node("Background").mouse_filter = Control.MOUSE_FILTER_IGNORE
	if planet_renderer:
		planet_renderer.mouse_filter = Control.MOUSE_FILTER_PASS
		if planet_renderer.get_parent() is Control:
			(planet_renderer.get_parent() as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	_orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")
	planet_renderer.planet_clicked.connect(_on_planet_clicked)
	poi_layer.poi_clicked.connect(_on_district_clicked)
	get_tree().root.size_changed.connect(_on_resize)
	# back button removed — navigation handled via system dock / unlock flow
	GameState.unlock_changed.connect(_on_unlock_changed)
	GameState.planet_progress_changed.connect(func(seed_val: int) -> void:
		_build_system_panel()
		if current_data != null and seed_val == current_data.seed:
			_update_panel(current_data)
			_refresh_pois(current_data)
			_build_details_panel(current_data)
			if _active_district_poi == null:
				_build_planet_overview(current_data)
			else:
				_build_district_panel(_active_district_poi, current_data))
	_refresh_solar_btn()
	_register_mission_tasks()
	TutorialManager.highlight_changed.connect(_on_tutorial_highlight)
	TutorialManager.highlight_cleared.connect(_on_tutorial_highlight_clear)

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

# ── Tutorial highlight helpers ───────────────────────────────────────────────

func _on_tutorial_highlight(target_id: String) -> void:
	_tut_highlight = target_id
	if target_id == "construction_wait":
		if is_instance_valid(_tut_highlight_node):
			_tut_highlight_node.modulate = Color.WHITE
		if _tut_node_tween != null and _tut_node_tween.is_valid():
			_tut_node_tween.kill()
		_tut_highlight_node = null
		_stop_tut_panel_pulse()
		TutorialManager.set_highlight_pos(Vector2(-999.0, -999.0))

func _on_tutorial_highlight_clear() -> void:
	_tut_highlight = ""
	if is_instance_valid(_tut_highlight_node):
		_tut_highlight_node.modulate = Color.WHITE
	if _tut_node_tween != null and _tut_node_tween.is_valid():
		_tut_node_tween.kill()
	_tut_highlight_node = null
	_stop_tut_panel_pulse()
	TutorialManager.set_allowed_rects([])
	TutorialManager.set_highlight_pos(Vector2(-999.0, -999.0))

func _start_tut_node_pulse(node: Control) -> void:
	if _tut_node_tween != null and _tut_node_tween.is_valid():
		_tut_node_tween.kill()
	if is_instance_valid(_tut_highlight_node) and _tut_highlight_node != node:
		_tut_highlight_node.modulate = Color.WHITE
	if not is_instance_valid(node):
		return
	node.modulate = Color.WHITE
	_tut_node_tween = create_tween().set_loops()
	_tut_node_tween.tween_property(node, "modulate", Color(2.2, 2.0, 1.6, 1.0), 0.50)
	_tut_node_tween.tween_property(node, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.50)

func _start_tut_panel_pulse(node: Control) -> void:
	_stop_tut_panel_pulse()
	if not is_instance_valid(node):
		return
	_tut_panel_node = node
	node.modulate = Color.WHITE
	_tut_panel_tween = create_tween().set_loops()
	_tut_panel_tween.tween_property(node, "modulate", Color(2.2, 2.0, 1.6, 1.0), 0.50)
	_tut_panel_tween.tween_property(node, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.50)

func _stop_tut_panel_pulse() -> void:
	if _tut_panel_tween != null and _tut_panel_tween.is_valid():
		_tut_panel_tween.kill()
	if is_instance_valid(_tut_panel_node):
		_tut_panel_node.modulate = Color.WHITE
	_tut_panel_node = null
	_tut_panel_tween = null

func _notify_tutorial_district_opened(poi: POIData, root: VBoxContainer) -> void:
	if TutorialManager._waiting_for_bid != "":
		return
	var target_bid := TutorialManager.get_action_building_target()
	if target_bid == "":
		return
	var buildable := BuildingDef.for_poi_type(poi.poi_type)
	var can_here := false
	for def in buildable:
		if def.building_id == target_bid:
			can_here = true
			break
	if not can_here:
		return
	for child in root.get_children():
		if child is PanelContainer and child.has_meta("is_slot_card"):
			_tut_highlight_node = child as Control
			_start_tut_node_pulse(_tut_highlight_node)
			return

func _notify_tutorial_district_type_dropdown(dd: PanelContainer) -> void:
	if TutorialManager._waiting_for_bid != "":
		return
	if TutorialManager.get_action_step_type() != "district":
		return
	var target_id: int = TutorialManager.get_action_district_target()
	if target_id < 0:
		return
	var vbox := dd.get_child(0) as VBoxContainer
	if vbox == null:
		return
	for child in vbox.get_children():
		if child is Button and child.has_meta("district_def_id"):
			if int(child.get_meta("district_def_id")) == target_id:
				_tut_highlight_node = child as Control
				_start_tut_node_pulse(_tut_highlight_node)
				return

func _update_tutorial_highlight() -> void:
	if not TutorialManager._action_block_on:
		return
	var allowed: Array[Rect2] = []
	var vp := get_viewport().get_visible_rect()
	var planet_area := Rect2(0.0, 0.0, vp.size.x * 0.57, vp.size.y)
	# Construction wait
	if TutorialManager._waiting_for_bid != "":
		TutorialManager.set_highlight_pos(Vector2(-999.0, -999.0))
		_stop_tut_panel_pulse()
		for card_v in _poi_overview_cards.values():
			if card_v != null and is_instance_valid(card_v):
				allowed.append((card_v as Control).get_global_rect())
		allowed.append(planet_area)
		TutorialManager.set_allowed_rects(allowed)
		return
	if _tut_highlight == "":
		return
	# Specific dropdown row
	if is_instance_valid(_tut_highlight_node) and (
			_tut_highlight_node.has_meta("building_id") or
			_tut_highlight_node.has_meta("district_def_id")):
		TutorialManager.set_highlight_pos(Vector2(-999.0, -999.0))
		allowed.append(_tut_highlight_node.get_global_rect())
		TutorialManager.set_allowed_rects(allowed)
		return
	# Slot card / ADD DISTRICT button
	if is_instance_valid(_tut_highlight_node):
		TutorialManager.set_highlight_pos(Vector2(-999.0, -999.0))
		var parent := _tut_highlight_node.get_parent()
		if parent != null:
			for sib in parent.get_children():
				if sib is Control and sib.has_meta("is_slot_card"):
					allowed.append((sib as Control).get_global_rect())
		if allowed.is_empty():
			allowed.append(_tut_highlight_node.get_global_rect())
		allowed.append(planet_area)
		TutorialManager.set_allowed_rects(allowed)
		return
	# POI ring modes
	var ring_pos := Vector2(-999.0, -999.0)
	var panel_lbl := ""
	match _tut_highlight:
		"capital":
			for poi in poi_layer._pois:
				var lbl: String = poi.get("label", "") if poi is Dictionary else poi.label
				if lbl == "Capital":
					ring_pos = poi_layer.get_poi_screen_pos(lbl)
					break
			panel_lbl = "Capital"
			if ring_pos.x > -900.0:
				allowed.append(Rect2(ring_pos - Vector2(90, 90), Vector2(180, 180)))
			var cap_card_v = _poi_overview_cards.get("Capital", null)
			if cap_card_v != null and is_instance_valid(cap_card_v):
				allowed.append((cap_card_v as Control).get_global_rect())
		"generator_district":
			if _active_district_poi != null:
				if planet_renderer != null:
					ring_pos = planet_renderer.global_position + Vector2(
						planet_renderer.size.x * 0.25, planet_renderer.size.y * 0.65)
				allowed.append(planet_area)
			else:
				for poi in poi_layer._pois:
					var lbl: String = poi.get("label", "") if poi is Dictionary else poi.label
					var orb: bool = poi.get("is_orbital", false) if poi is Dictionary else poi.is_orbital()
					if not orb and lbl != "Capital" and lbl != "":
						ring_pos = poi_layer.get_poi_screen_pos(lbl)
						var cv = _poi_overview_cards.get(lbl, null)
						if cv != null and is_instance_valid(cv):
							allowed.append((cv as Control).get_global_rect())
						break
				if ring_pos.x > -900.0:
					allowed.append(Rect2(ring_pos - Vector2(90, 90), Vector2(180, 180)))
		"add_district":
			if planet_renderer != null:
				ring_pos = planet_renderer.global_position + planet_renderer.size * 0.5
			if is_instance_valid(_tut_highlight_node):
				allowed.append(_tut_highlight_node.get_global_rect())
			elif ring_pos.x > -900.0:
				allowed.append(Rect2(ring_pos - Vector2(90, 90), Vector2(180, 180)))
		"construction_wait":
			TutorialManager.set_highlight_pos(Vector2(-999.0, -999.0))
			if _active_district_poi != null:
				var cv = _poi_overview_cards.get(_active_district_poi.label, null)
				if cv != null and is_instance_valid(cv):
					allowed.append((cv as Control).get_global_rect())
			allowed.append(planet_area)
			TutorialManager.set_allowed_rects(allowed)
			return
	# Always allow planet drag and all district overview cards
	allowed.append(planet_area)
	for card_v in _poi_overview_cards.values():
		if card_v != null and is_instance_valid(card_v):
			allowed.append((card_v as Control).get_global_rect())
	TutorialManager.set_highlight_pos(ring_pos)
	TutorialManager.set_allowed_rects(allowed)
	# Panel card pulse
	var want_card_v = _poi_overview_cards.get(panel_lbl, null)
	var want_card: Control = (want_card_v as Control) if (want_card_v != null and is_instance_valid(want_card_v)) else null
	if want_card != _tut_panel_node:
		if want_card == null:
			_stop_tut_panel_pulse()
		else:
			_start_tut_panel_pulse(want_card)

# ─────────────────────────────────────────────────────────────────────────────

func _go_back() -> void:
	if not GameState.solar_unlocked and not GameState.moon_unlocked:
		return
	AudioManager.set_construction_active(false)
	_save_light_angle()
	var sd := _system_solar if _system_solar != null else GameState.get_home_solar()
	
	var parent_planet: PlanetData = null
	if current_data != null:
		if current_data.planet_type == PlanetData.Type.MOON:
			for p in sd.planets:
				if p.moons.has(current_data):
					parent_planet = p
					break
		else:
			parent_planet = current_data
			
	if parent_planet != null:
		parent_planet.set_meta("__solar_data", sd)
		SceneTransition.go("res://scenes/solar/SolarView.tscn", parent_planet)
	else:
		SceneTransition.go("res://scenes/solar/SolarView.tscn", sd)

func _on_unlock_changed(_key: String, _val: bool) -> void:
	_refresh_solar_btn()

func _refresh_solar_btn() -> void:
	pass   # navigation via right-click only

var _back_charge: int = 0

func _input(event: InputEvent) -> void:
	if SkillTreeView.is_open:
		return
	# ESC closes radial menu if open
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_ESCAPE and _radial_menu != null:
			_close_radial_menu()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Tutorial deselect: during generator-district step with panel open,
		# left-click on planet area closes it so ADD DISTRICT becomes visible.
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT \
				and _tut_highlight == "generator_district" and _active_district_poi != null:
			var click := mb.position
			var vp_w: float = get_viewport().get_visible_rect().size.x
			if click.x < vp_w * 0.57:
				_active_district_poi = null
				_tut_highlight_node = null
				_build_planet_overview(current_data)
				get_viewport().set_input_as_handled()
				return
		# Close slot dropdown on any click outside it
		if mb.pressed and _active_slot_dropdown != null \
				and is_instance_valid(_active_slot_dropdown):
			var dd_rect := _active_slot_dropdown.get_global_rect()
			if not dd_rect.has_point(get_viewport().get_mouse_position()):
				_active_slot_dropdown.queue_free()
				_active_slot_dropdown = null
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			# Check if right-clicking on a ship → ship radial menu
			if _orbital_layer != null and is_instance_valid(_orbital_layer):
				var ship_hit := _orbital_layer._ship_at(mb.global_position)
				if ship_hit != null:
					if _orbital_layer._selected_ship != ship_hit:
						_orbital_layer.select_ship(ship_hit)
					_show_radial_menu(ship_hit, mb.global_position, _orbital_layer)
					get_viewport().set_input_as_handled()
					return
			# Right-click on planet → planet command menu (or go back)
			if poi_layer._selected_index >= 0:
				poi_layer.deselect_all()
				_build_planet_overview(current_data)
				get_viewport().set_input_as_handled()
			else:
				if _orbital_layer != null and _orbital_layer._selected_ship != null:
					_show_planet_radial_menu(mb.global_position)
				else:
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
		# 2-finger horizontal swipe → rotate planet
		if abs(event.delta.x) > abs(event.delta.y) * 0.5:
			var r_px: float = planet_renderer.size.x * 0.5
			if r_px > 0.0:
				var delta_rot: float = event.delta.x / r_px
				planet_renderer.set_rotation_offset(planet_renderer.get_rotation_offset() + delta_rot)
			get_viewport().set_input_as_handled()

func load_planet(data: PlanetData) -> void:
	if current_data == null or current_data.seed != data.seed:
		_top_tab_active   = "DETAILS"
		_inner_tab_active = "SURFACE"
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
	poi_layer.setup(planet_renderer)
	poi_layer.clear_pois()
	_setup_orbital_layer(data.seed)
	_build_details_panel(data)

	_refresh_pois(data)
	# rotate so the first (primary) POI faces the viewer at load (if any)
	if poi_layer._pois.size() > 0:
		planet_renderer.set_rotation_offset(poi_layer._pois[0]["lon"])
	_build_planet_overview(data)

func _clean_custom_pois(data: PlanetData) -> void:
	if data == null or data.custom_pois.is_empty():
		return
	var cleaned: Array[POIData] = []
	for item in data.custom_pois:
		if typeof(item) == TYPE_DICTIONARY:
			var untyped = [item][0]
			var pd := POIData.new()
			pd.lon_deg = float(untyped.get("lon_deg", 0.0))
			pd.lat_deg = float(untyped.get("lat_deg", 0.0))
			pd.label = str(untyped.get("label", ""))
			pd.manual_position = true
			if untyped.has("data") and typeof(untyped["data"]) == TYPE_DICTIONARY:
				var pdata: Dictionary = untyped["data"]
				pd.type_tag = str(pdata.get("type", ""))
				pd.light_intensity = float(pdata.get("light_intensity", 1.0))
				if pd.type_tag == "station":
					pd.poi_type = POIData.POIType.STATION
			cleaned.append(pd)
		elif item is POIData:
			cleaned.append(item as POIData)
	data.custom_pois = cleaned

func _refresh_pois(data: PlanetData) -> void:
	_clean_custom_pois(data)
	poi_layer.clear_pois()
	var pois: Array[Dictionary] = []
	if data.custom_pois.size() > 0:
		var lf := LocationFinder.new(data.seed, data.sea_level,
				data.terrain_roughness, data.continent_scale)
		for pd: POIData in data.custom_pois:
			if pd.is_orbital():
				continue  # orbital districts drawn by OrbitalLayer, not POILayer
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
	if type_label:
		var pp := GameState.get_planet(data.seed)
		var lv_str := "  ·  Lv %d" % pp.level if pp.is_colonized else ""
		type_label.text = type_names[data.planet_type] + lv_str
		type_label.visible = true
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
	poi.constructing = true
	poi.construct_progress = 0.0
	poi.construct_duration = def.construction_duration

	if def.is_orbital:
		var rng := RandomNumberGenerator.new()
		rng.seed = data.seed ^ 0xC4F3A1
		poi.orbit_angle       = rng.randf_range(0.0, TAU)
		poi.orbit_speed       = 0.01
		poi.orbit_inclination = rng.randf_range(0.35, 1.1)
		poi.orbit_node        = rng.randf_range(0.0, TAU)
		poi.orbit_radius      = 1.06
		poi.light_intensity   = 0.0
		poi.manual_position   = true
		# Pick a surface district as the launch pad (prefer Capital, else first surface POI)
		var surface_pois_launch: Array[POIData] = []
		for p: POIData in data.custom_pois:
			if not p.is_orbital() and not p.constructing:
				surface_pois_launch.append(p)
		var launch_poi: POIData = null
		for p: POIData in surface_pois_launch:
			if p.label.to_lower().contains("capital"):
				launch_poi = p; break
		if launch_poi == null and not surface_pois_launch.is_empty():
			launch_poi = surface_pois_launch[0]
		# Rotate planet to face the launch pad, then start rocket
		if launch_poi != null:
			_rotate_to_lon(launch_poi.lon_deg, 0.5)
		AudioManager.play("construct")
		AchievementManager.notify_trigger(AchievementDef.Trigger.FIRST_DISTRICT)
		AchievementManager.notify_trigger(AchievementDef.Trigger.FIRST_ORBITAL)
		# Add immediately so panel shows "Constructing"; OrbitalLayer skips constructing=true pois
		data.custom_pois.append(poi)
		_play_rocket_animation(data.seed, launch_poi, func() -> void:
			poi.constructing = false
			GameState.planet_progress_changed.emit(data.seed),
			"", "Pioneer", "station", {}, "", "", "", 0, false, [], poi)
		load_planet(data)
	else:
		poi.light_intensity = 1.0
		# Pre-seed LocationFinder with existing district positions so new ones spread out.
		var lf := LocationFinder.new(
			data.seed ^ (data.custom_pois.size() * 0xBEEF),
			data.sea_level, data.terrain_roughness, data.continent_scale)
		for existing: POIData in data.custom_pois:
			if existing.manual_position:
				var lon := deg_to_rad(existing.lon_deg)
				lf._used_lons.append(lon)
				if existing.poi_type == def.to_poi_type():
					lf._used_lons.append(fposmod(lon + deg_to_rad(5.0), TAU))
		var pos := lf.find(def.placement)
		poi.lon_deg = rad_to_deg(pos.x)
		poi.lat_deg = rad_to_deg(pos.y)
		poi.manual_position = true
		AudioManager.play("construct")
		AchievementManager.notify_trigger(AchievementDef.Trigger.FIRST_DISTRICT)
		data.custom_pois.append(poi)
		GameState.district_placed.emit(data.seed, def.id)
		load_planet(data)

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
	root.z_index         = 200
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.add_child(root)
	_details_panel = root

	if not ProductionManager.building_progress_changed.is_connected(_on_production_update):
		ProductionManager.building_progress_changed.connect(_on_production_update)
	if not ProductionManager.resource_produced.is_connected(_on_resource_produced):
		ProductionManager.resource_produced.connect(_on_resource_produced)


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
	icon_rect.texture_filter      = CanvasItem.TEXTURE_FILTER_NEAREST
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
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	if show_count:
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 3)
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(vbox)

		icon_rect.custom_minimum_size   = Vector2(28, 28)
		icon_rect.stretch_mode          = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon_rect)

		var count_lbl := Label.new()
		count_lbl.text = _fmt_amount(stored)
		count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_apply_orbitron(count_lbl, 10)
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

		icon_rect.custom_minimum_size   = Vector2(32, 32)
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

	# Hover juice: scale up + yellow border highlight, z_index brings to front
	card.mouse_entered.connect(func() -> void:
		AudioManager.play("poi_hover")
		card.z_index = 10
		card.pivot_offset = card.size * 0.5
		var tw := card.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "scale", Vector2(1.10, 1.10), 0.12)
		s.border_color = Color(1.0, 0.90, 0.25))
	card.mouse_exited.connect(func() -> void:
		card.z_index = 0
		card.pivot_offset = card.size * 0.5
		var tw := card.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "scale", Vector2(1.0, 1.0), 0.10)
		s.border_color = rarity_col)

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

func _planet_energy_balance(_pp: PlanetProgress) -> float:
	return ProductionManager.get_global_energy()

func _planet_energy_balance_UNUSED(pp: PlanetProgress) -> float:
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
		
	# The bottom dock showing the local system moons has been removed
	# since players can now view and click moons in the Local System mode.

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
	# Disconnect any previous ShipManager bindings to avoid accumulation
	if ShipManager.ship_added.is_connected(_on_ship_roster_changed):
		ShipManager.ship_added.disconnect(_on_ship_roster_changed)
	if ShipManager.ship_arrived.is_connected(_on_ship_roster_changed):
		ShipManager.ship_arrived.disconnect(_on_ship_roster_changed)
	# Remove old layer if switching planets
	if _orbital_layer != null and is_instance_valid(_orbital_layer):
		_orbital_layer.queue_free()
	var layer := OrbitalLayer.new()
	layer.z_index = 5   # above planet, below HUD rings
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	planet_renderer.get_parent().add_child(layer)
	layer.setup(planet_seed)
	layer.ship_hovered.connect(func(_ship: ShipData, _pos: Vector2) -> void:
		pass)   # Name drawn directly on OrbitalLayer canvas (like districts)
	layer.ship_unhovered.connect(func() -> void:
		pass)
	layer.ship_clicked.connect(func(ship: ShipData) -> void:
		TooltipManager.hide_tip()
		layer.suppress_label = true
		_show_ship_panel(ship, layer))
	layer.ship_deselected.connect(func() -> void:
		layer.suppress_label = false
		_close_ship_panel()
		_close_radial_menu())
	layer.ship_right_clicked.connect(func(ship: ShipData, gpos: Vector2) -> void:
		_show_radial_menu(ship, gpos, layer))
	layer.ship_landed.connect(func(landed_ship: ShipData) -> void:
		# Return cargo to planet storage on landing
		var dest_pp := GameState.get_planet(landed_ship.orbit_seed)
		if dest_pp != null and not landed_ship.cargo.is_empty():
			for res_id: String in landed_ship.cargo:
				GameState.add_resource(res_id, float(landed_ship.cargo[res_id]))
			GameState.planet_progress_changed.emit(landed_ship.orbit_seed)
		if current_data != null: _build_planet_overview(current_data))
	ShipManager.ship_arrived.connect(_on_ship_roster_changed)
	ShipManager.ship_added.connect(_on_ship_roster_changed)
	layer.station_poi_clicked.connect(func(poi_label: String) -> void:
		if current_data == null: return
		for poi: POIData in current_data.custom_pois:
			if poi.label == poi_label and poi.is_orbital():
				_active_district_poi = poi
				layer.set_selected_station(poi_label)
				poi_layer.deselect_all()
				_build_district_panel(poi, current_data)
				return)
	_orbital_layer = layer
	_add_orbit_toggle(planet_renderer.get_parent(), layer)
	_register_ship_commands(layer)

func _on_ship_roster_changed(ship: ShipData) -> void:
	if current_data != null and ship.orbit_seed == current_data.seed:
		_build_planet_overview(current_data)

func _register_ship_commands(layer: OrbitalLayer) -> void:
	ShipCommandRegistry.register_callable("deselect",
		func(ship: ShipData, _l: OrbitalLayer) -> void: layer.deselect())
	ShipCommandRegistry.register_callable("land",
		func(ship: ShipData, _l: OrbitalLayer) -> void:
			_close_ship_panel()
			layer.start_landing(ship))
	ShipCommandRegistry.register_callable("solar_view",
		func() -> void:
			CursorManager.set_state(CursorManager.State.EXIT)
			_go_back())
	ShipCommandRegistry.register_callable("rendezvous",
		func(ship: ShipData, _l: OrbitalLayer) -> void:
			_show_rendezvous_picker(ship, layer))
	if layer.rendezvous_reached.get_connections().is_empty():
		layer.rendezvous_reached.connect(func(ship: ShipData, target: ShipData) -> void:
			# rendezvous reached
			# Floating text at meeting point
			var sv := layer._project(ship, ship.orbit_angle)
			var r: float = layer._planet_radius * ship.orbit_radius
			var nx: float = sv.x / r; var ny: float = sv.y / r
			var lat_r: float = -asin(clampf(ny, -1.0, 1.0))
			var lon_r: float = asin(clampf(nx / maxf(cos(lat_r), 0.01), -1.0, 1.0))
			poi_layer.spawn_floating_text(
				rad_to_deg(lon_r + layer._planet_rotation), rad_to_deg(lat_r),
				"Rendezvous", Color(0.30, 0.92, 1.0, 1.0), 12)
			# Execute rendezvous_tasks from the current move_station entry
			var lon_deg2: float = rad_to_deg(lon_r + layer._planet_rotation)
			var lat_deg2: float = rad_to_deg(lat_r) + 2.0
			var ms_task: Dictionary = ship.mission_tasks[ship.mission_task_index]
			ship.mission_task_index += 1  # past move_station
			for t: Dictionary in ms_task.get("rendezvous_tasks", []):
				var ttype: String = t.get("type", "")
				if ttype == "deliver":
					for res_id: String in ship.cargo:
						target.cargo[res_id] = target.cargo.get(res_id, 0) + ship.cargo[res_id]
					ship.cargo.clear()
					poi_layer.spawn_floating_text(lon_deg2, lat_deg2, "Delivered!", Color(0.35, 1.0, 0.50, 1.0), 11)
				elif ttype == "pickup":
					var res_id: String = t.get("transfer_resource", "")
					var want: int      = t.get("transfer_amount", 0)
					var avail: int     = int(target.cargo.get(res_id, 0))
					var take: int      = mini(want, avail)
					if take > 0:
						target.cargo[res_id] = avail - take
						ship.cargo[res_id]   = ship.cargo.get(res_id, 0) + take
					poi_layer.spawn_floating_text(lon_deg2, lat_deg2, "Loaded x%d!" % take, Color(0.35, 1.0, 0.50, 1.0), 11)
			# Normalize orbit_node for clean landing trajectory
			if ship.orbit_node != 0.0:
				var anchor: Vector2 = layer._project_2d(ship, ship.orbit_angle)
				ship.orbit_node = 0.0
				var a: float = ship.orbit_angle
				for _i: int in 16:
					var p0: Vector2 = layer._project_2d(ship, a)
					var p1: Vector2 = layer._project_2d(ship, a + 0.005)
					var tangent: Vector2 = (p1 - p0) / 0.005
					var err: Vector2 = p0 - anchor
					if tangent.length_squared() < 0.0001:
						break
					a -= err.dot(tangent) / tangent.length_squared()
				ship.orbit_angle = a
			_advance_mission(ship))

## Ship info panel — appears at bottom-left of planet view when a ship is selected.
func _show_ship_panel(ship: ShipData, layer: OrbitalLayer) -> void:
	_close_ship_panel()
	# Station ships also open the district panel immediately
	if ship.ship_type == "station" and current_data != null:
		_open_station_district(ship, planet_renderer.get_parent())
	var planet_cont: Control = planet_renderer.get_parent()

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color     = Color(0.06, 0.08, 0.14, 0.92)
	ps.border_color = Color(1.0, 0.92, 0.30, 0.70)
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(5)
	ps.content_margin_left = 14; ps.content_margin_right  = 14
	ps.content_margin_top  = 10; ps.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", ps)
	panel.z_index = 10
	panel.custom_minimum_size = Vector2(180, 0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Name + status on the same row (name left, status right)
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(title_row)

	var name_lbl := Label.new()
	name_lbl.text = ship.ship_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_orbitron(name_lbl, 11)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.30))
	title_row.add_child(name_lbl)

	var status_lbl := Label.new()
	status_lbl.text = "In orbit" if not ship.is_travelling() else "En route…"
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_apply_orbitron(status_lbl, 9)
	status_lbl.add_theme_color_override("font_color", Color(0.6, 0.75, 0.95, 0.80))
	title_row.add_child(status_lbl)

	# Cargo — inventory card style matching PlanetOverview
	if not ship.cargo.is_empty():
		var sep := HSeparator.new()
		sep.add_theme_color_override("color", Color(1, 1, 1, 0.12))
		vbox.add_child(sep)
		var cargo_grid := GridContainer.new()
		cargo_grid.columns = 4
		cargo_grid.add_theme_constant_override("h_separation", 4)
		cargo_grid.add_theme_constant_override("v_separation", 4)
		vbox.add_child(cargo_grid)
		for rid: String in ship.cargo:
			var rd: ResourceData = GameState.known_resources.get(rid, null)
			if rd == null:
				continue
			cargo_grid.add_child(_mineral_grid_card(rd, ship.cargo[rid], true))

	# ── Capacity row ─────────────────────────────────────────────────────────
	var cap_sep := HSeparator.new()
	cap_sep.add_theme_color_override("color", Color(1, 1, 1, 0.10))
	vbox.add_child(cap_sep)

	var cap_row := HBoxContainer.new()
	cap_row.add_theme_constant_override("separation", 6)
	vbox.add_child(cap_row)

	var cargo_hint := Label.new()
	cargo_hint.text = "right-click for actions"
	cargo_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_orbitron(cargo_hint, 7)
	cargo_hint.add_theme_color_override("font_color", Color(0.4, 0.5, 0.7, 0.5))
	cargo_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap_row.add_child(cargo_hint)

	# Cargo weight used / capacity — bottom right
	var ship_cap: int = 60 if ship.ship_type == "station" else 20
	var ship_used: int = 0
	for rid: String in ship.cargo:
		var rd2: ResourceData = GameState.known_resources.get(rid, null)
		if rd2 != null:
			ship_used += (rd2.rarity + rd2.tier - 1) * int(ship.cargo[rid])
	var cap_lbl3 := Label.new()
	cap_lbl3.text = "%d / %d" % [ship_used, ship_cap]
	_apply_orbitron(cap_lbl3, 7)
	cap_lbl3.add_theme_color_override("font_color",
		Color(0.42, 0.88, 0.58) if ship_used <= ship_cap else Color(0.95, 0.38, 0.28))
	cap_lbl3.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cap_lbl3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap_row.add_child(cap_lbl3)

	panel.anchor_left = 0; panel.anchor_top = 0
	panel.anchor_right = 0; panel.anchor_bottom = 0
	planet_cont.add_child(panel)
	_ship_panel = panel

func _close_ship_panel() -> void:
	if _ship_panel != null and is_instance_valid(_ship_panel):
		_ship_panel.queue_free()
	_ship_panel = null

## Info panel for a ship that is currently launching (not yet in orbit).
func _show_launch_info_panel(anim_d: Dictionary, container: Control) -> void:
	_close_ship_panel()

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color     = Color(0.06, 0.08, 0.14, 0.92)
	ps.border_color = Color(1.0, 0.92, 0.30, 0.70)
	ps.set_border_width_all(1); ps.set_corner_radius_all(5)
	ps.content_margin_left = 14; ps.content_margin_right  = 14
	ps.content_margin_top  = 10; ps.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", ps)
	panel.z_index = 10
	panel.custom_minimum_size = Vector2(180, 0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Title row
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(title_row)

	var name_lbl := Label.new()
	name_lbl.text = anim_d.get("ship_name", "Ship")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_orbitron(name_lbl, 11)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.30))
	title_row.add_child(name_lbl)

	var type_lbl := Label.new()
	type_lbl.text = anim_d.get("ship_type", "shuttle").capitalize()
	_apply_orbitron(type_lbl, 9)
	type_lbl.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0, 0.75))
	title_row.add_child(type_lbl)

	var status_lbl := Label.new()
	status_lbl.text = "launching to orbit"
	_apply_orbitron(status_lbl, 8)
	status_lbl.add_theme_color_override("font_color", Color(0.45, 0.90, 0.65, 0.80))
	vbox.add_child(status_lbl)

	# Cargo
	var cargo: Dictionary = anim_d.get("ship_cargo", {})
	if not cargo.is_empty():
		var sep := HSeparator.new()
		sep.add_theme_color_override("color", Color(1, 1, 1, 0.12))
		vbox.add_child(sep)
		var cargo_grid := GridContainer.new()
		cargo_grid.columns = 4
		cargo_grid.add_theme_constant_override("h_separation", 4)
		cargo_grid.add_theme_constant_override("v_separation", 4)
		vbox.add_child(cargo_grid)
		for rid: String in cargo:
			var rd: ResourceData = GameState.known_resources.get(rid, null)
			if rd != null:
				cargo_grid.add_child(_mineral_grid_card(rd, float(cargo[rid]), true))

	container.add_child(panel)
	_ship_panel = panel
	# Store rocket ref so _process can follow it each frame
	var rocket: Control = anim_d.get("rocket", null)
	panel.set_meta("launch_rocket", rocket if rocket != null else Control.new())
	if rocket != null and is_instance_valid(rocket):
		panel.position = rocket.position + Vector2(16, -40)

func _close_radial_menu() -> void:
	if _radial_menu != null and is_instance_valid(_radial_menu):
		_radial_menu.queue_free()
	_radial_menu = null
	CursorManager.set_state(CursorManager.State.NORMAL)

func _show_planet_radial_menu(global_pos: Vector2) -> void:
	var defs := ShipCommandRegistry.get_planet_commands()
	var actions: Array[Dictionary] = []
	for def: ShipCommandDef in defs:
		if not ShipCommandRegistry.has_callable(def.command_id):
			continue
		var cb: Callable = ShipCommandRegistry.get_callable(def.command_id)
		actions.append({
			"icon":   def.icon,
			"label":  def.label,
			"color":  def.color,
			"action": func() -> void: cb.call(),
		})
	if actions.is_empty():
		_go_back()
		return
	_show_radial_menu_at(actions, global_pos)

func _show_radial_menu(ship: ShipData, global_pos: Vector2, layer: OrbitalLayer) -> void:
	var defs := ShipCommandRegistry.get_ship_commands(ship.ship_type)
	var actions: Array[Dictionary] = []
	for def: ShipCommandDef in defs:
		if not ShipCommandRegistry.has_callable(def.command_id):
			continue
		var cb: Callable = ShipCommandRegistry.get_callable(def.command_id)
		actions.append({
			"icon":   def.icon,
			"label":  def.label,
			"color":  def.color,
			"action": func() -> void: cb.call(ship, layer),
		})
	if actions.is_empty():
		return
	_show_radial_menu_at(actions, global_pos, ship)

func _show_radial_menu_at(actions: Array[Dictionary], global_pos: Vector2,
		follow_ship: ShipData = null) -> void:
	_close_radial_menu()
	var container: Control = planet_renderer.get_parent()
	var local_pos: Vector2 = global_pos - container.get_global_rect().position

	const RADIUS:   float = 52.0
	const BTN_R:    float = 16.0
	const FADE_DUR: float = 0.12

	var menu := Control.new()
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	menu.z_index = 20
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.add_child(menu)
	_radial_menu = menu

	# Full-screen backdrop: click outside closes menu
	var backdrop := Control.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_close_radial_menu())
	menu.add_child(backdrop)

	# ESC is handled in _input when _radial_menu != null

	# Pivot: all radial elements live here; repositioned each frame when following a ship
	var pivot := Control.new()
	pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot.z_index = 1
	pivot.position = local_pos
	menu.add_child(pivot)
	if follow_ship != null:
		menu.set_meta("follow_ship", follow_ship)
		menu.set_meta("pivot_node",  pivot)

	# Connector lines — drawn in pivot-local space (origin = ship center)
	var lines_ctrl := Control.new()
	lines_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line_fade: Array[float] = [0.0]
	var line_endpoints: Array[Vector2] = []
	lines_ctrl.draw.connect(func() -> void:
		for ep: Vector2 in line_endpoints:
			lines_ctrl.draw_line(Vector2.ZERO, ep,
				Color(0.5, 0.6, 0.9, 0.25 * line_fade[0]), 1.0, true))
	pivot.add_child(lines_ctrl)

	var n: int = actions.size()
	for i in n:
		var angle: float = -PI * 0.5 + (float(i) / maxf(float(n), 1.0)) * TAU if n > 1 else -PI * 0.5
		var btn_center: Vector2 = Vector2(cos(angle), sin(angle)) * RADIUS
		line_endpoints.append(btn_center)

		var btn_ctrl := Control.new()
		btn_ctrl.position = btn_center - Vector2(BTN_R, BTN_R)
		btn_ctrl.custom_minimum_size = Vector2(BTN_R * 2.0, BTN_R * 2.0)
		btn_ctrl.size                = Vector2(BTN_R * 2.0, BTN_R * 2.0)
		btn_ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
		btn_ctrl.z_index = 2

		var ac: Dictionary        = actions[i]
		var btn_color: Color      = ac["color"]
		var btn_hovered: Array[bool]  = [false]
		var fade_ref: Array[float]    = [0.0]

		btn_ctrl.draw.connect(func() -> void:
			var f: float = fade_ref[0]
			var h: bool  = btn_hovered[0]
			btn_ctrl.draw_circle(Vector2(BTN_R, BTN_R), BTN_R,
				Color(0.06, 0.08, 0.18, 0.93 * f))
			if h:
				btn_ctrl.draw_circle(Vector2(BTN_R, BTN_R), BTN_R,
					Color(btn_color, 0.18 * f))
			var pts := PackedVector2Array()
			for k in 24:
				var a: float = float(k) / 24.0 * TAU
				pts.append(Vector2(BTN_R + cos(a) * (BTN_R - 1.0),
								   BTN_R + sin(a) * (BTN_R - 1.0)))
			pts.append(pts[0])
			btn_ctrl.draw_polyline(pts, Color(btn_color, (0.75 if h else 0.40) * f), 1.5, true)
			var font: Font = ThemeDB.fallback_font
			var txt: String = ac["icon"]
			var tsz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			var tp := Vector2(BTN_R - tsz.x * 0.5, BTN_R + tsz.y * 0.38)
			btn_ctrl.draw_string(font, tp + Vector2(0, 1), txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0, 0, 0, 0.55 * f))
			btn_ctrl.draw_string(font, tp, txt,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(btn_color, f)))

		var lbl := Label.new()
		lbl.text = ac["label"]
		_apply_orbitron(lbl, 7)
		lbl.add_theme_color_override("font_color", Color(btn_color, 0.70))
		var font_tmp: Font = ThemeDB.fallback_font
		var lsz := font_tmp.get_string_size(ac["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 7)
		lbl.position = Vector2(BTN_R - lsz.x * 0.5, BTN_R * 2.0 + 3.0)
		btn_ctrl.add_child(lbl)

		btn_ctrl.mouse_entered.connect(func() -> void:
			btn_hovered[0] = true
			btn_ctrl.queue_redraw()
			CursorManager.set_state(CursorManager.State.POINTER))
		btn_ctrl.mouse_exited.connect(func() -> void:
			btn_hovered[0] = false
			btn_ctrl.queue_redraw()
			CursorManager.set_state(CursorManager.State.NORMAL))
		btn_ctrl.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton:
				var mb2 := ev as InputEventMouseButton
				if mb2.button_index == MOUSE_BUTTON_LEFT and mb2.pressed:
					_close_radial_menu()
					(ac["action"] as Callable).call())

		pivot.add_child(btn_ctrl)

		var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(v: float) -> void:
			fade_ref[0] = v
			line_fade[0] = v
			btn_ctrl.queue_redraw()
			lines_ctrl.queue_redraw(), 0.0, 1.0, FADE_DUR)

## Orbit visibility toggle — bottom-right corner of planet view.
func _add_orbit_toggle(planet_cont: Control, layer: OrbitalLayer) -> void:
	for ch: Node in planet_cont.get_children():
		if ch.get_meta("orbit_toggle", false):
			ch.queue_free()

	const SIZE := 36.0
	var btn := Control.new()
	btn.set_meta("orbit_toggle", true)
	btn.custom_minimum_size = Vector2(SIZE, SIZE)
	btn.z_index = 12
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.tooltip_text = "Toggle orbits"

	var visible_ref: Array = [true]   # [0] = orbits visible
	btn.draw.connect(func() -> void:
		var is_vis: bool = visible_ref[0]
		var bg    := Color(0.06, 0.08, 0.14, 0.82)
		var border := Color(0.35, 0.55, 0.90, 0.55 if is_vis else 0.30)
		var icon_c := Color(0.55, 0.78, 1.0, 1.0 if is_vis else 0.35)
		var c      := Vector2(SIZE * 0.5, SIZE * 0.5)
		# Background rounded rect
		btn.draw_rect(Rect2(1, 1, SIZE - 2, SIZE - 2), bg)
		btn.draw_rect(Rect2(1, 1, SIZE - 2, SIZE - 2), border, false, 1.5)
		# Orbit ellipse: wide ellipse around center
		var pts: PackedVector2Array = []
		for i in 32:
			var a: float = (float(i) / 32.0) * TAU
			pts.append(c + Vector2(cos(a) * 12.0, sin(a) * 5.0))
		btn.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(icon_c, 0.70), 1.2, true)
		# Small satellite: cross at orbit's right side
		var sp := c + Vector2(12.0, 0.0)
		btn.draw_rect(Rect2(sp + Vector2(-1, -1), Vector2(2, 2)), icon_c)
		btn.draw_rect(Rect2(sp + Vector2(-3, 0),  Vector2(2, 1)), icon_c)
		btn.draw_rect(Rect2(sp + Vector2( 2, 0),  Vector2(2, 1)), icon_c)
		# Eye shape in center
		if is_vis:
			btn.draw_arc(c, 5.0, -PI * 0.55, PI * 0.55, 12, icon_c, 1.2, true)
			btn.draw_arc(c, 5.0,  PI * 0.45, PI * 1.55, 12, icon_c, 1.2, true)
			btn.draw_circle(c, 2.0, icon_c)
		else:
			# Crossed-out eye
			btn.draw_line(c + Vector2(-5, -5), c + Vector2(5, 5), icon_c, 1.5, true))

	btn.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				layer.visible = not layer.visible
				visible_ref[0] = layer.visible
				btn.queue_redraw())

	btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	btn.mouse_exited.connect(func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))

	planet_cont.add_child(btn)
	btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.offset_bottom = -12
	btn.offset_right  = -12
	btn.offset_top    = btn.offset_bottom - SIZE
	btn.offset_left   = btn.offset_right  - SIZE

func _process(delta: float) -> void:
	_update_tutorial_highlight()
	_update_aspect()

	# Construction loop audio — active whenever any POI is constructing
	if current_data != null:
		var any_constructing := false
		for p: POIData in current_data.custom_pois:
			if p.constructing:
				any_constructing = true
				break
		AudioManager.set_construction_active(any_constructing)

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
		var _oc: Control = planet_renderer.get_parent()
		_orbital_layer._planet_center   = planet_renderer.global_position + planet_renderer.size * 0.5 - _oc.get_global_rect().position
		# Advance space station orbit angles
		if current_data != null:
			for poi: POIData in current_data.custom_pois:
				if poi.is_orbital():
					poi.orbit_angle = fposmod(poi.orbit_angle + poi.orbit_speed * delta, TAU)
		_orbital_layer.queue_redraw()
		# Keep ship panel glued to selected ship, on opposite side from nameplate leader
		if _ship_panel != null and is_instance_valid(_ship_panel):
			# Launch panel: follow rocket position
			if _ship_panel.has_meta("launch_rocket"):
				var lrocket: Control = _ship_panel.get_meta("launch_rocket")
				if is_instance_valid(lrocket):
					_ship_panel.position = lrocket.position + Vector2(16, -_ship_panel.size.y * 0.5)
				else:
					_close_ship_panel()  # rocket finished, close panel
			else:
				var sel: ShipData = _orbital_layer._selected_ship
				if sel != null:
					var sv := _orbital_layer._project(sel, sel.orbit_angle)
					var spos := _orbital_layer._planet_center + Vector2(sv.x, sv.y)
					var panel_size := _ship_panel.size
					var cont_size  := _oc.size
					var center_x := cont_size.x * 0.5
					var label_goes_right: bool = spos.x >= center_x
					var px: float
					if label_goes_right:
						px = spos.x - panel_size.x - 16.0
					else:
						px = spos.x + 16.0
					px = clampf(px, 8.0, cont_size.x - panel_size.x - 8.0)
					var py: float = spos.y - panel_size.y * 0.5
					py = clampf(py, 8.0, cont_size.y - panel_size.y - 8.0)
					_ship_panel.position = Vector2(px, py)

		# Follow ship with radial menu pivot
		if _radial_menu != null and is_instance_valid(_radial_menu) \
				and _radial_menu.has_meta("follow_ship"):
			var fship: ShipData = _radial_menu.get_meta("follow_ship")
			var piv: Control    = _radial_menu.get_meta("pivot_node")
			if fship != null and is_instance_valid(piv):
				var sv := _orbital_layer._project(fship, fship.orbit_angle)
				if _orbital_layer._is_occluded(sv):
					_close_radial_menu()
				else:
					piv.position = _orbital_layer._planet_center + Vector2(sv.x, sv.y)

	if current_data != null:
		var pp := GameState.get_planet(current_data.seed)
		if pp != null and _planet_upgrade_pbar != null and is_instance_valid(_planet_upgrade_pbar):
			_planet_upgrade_pbar.value = pp.upgrade_progress * 100.0

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
								AudioManager.play("building_done")
						pbar.value = poi.construct_progress * 100.0
						break
		if any_finished:
			GameState.planet_progress_changed.emit(current_data.seed)

	if not _rocket_anims.is_empty():
		_tick_rocket_anim(delta)

	if not _deploy_anims.is_empty():
		_tick_deploy_anims(delta)

var _was_dragging: bool = false
func _update_cursor() -> void:
	if planet_renderer == null or planet_renderer._planet_radius_px <= 0:
		return
	if planet_renderer._dragging:
		CursorManager.set_state(CursorManager.State.GRAB)
		_was_dragging = true
	elif _was_dragging:
		CursorManager.set_state(CursorManager.State.NORMAL)
		_was_dragging = false

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
	if _orbital_layer != null and is_instance_valid(_orbital_layer):
		_orbital_layer.deselect()
	if current_data != null:
		_build_planet_overview(current_data)
	
	var center := planet_renderer.size * 0.5
	var local_click := _screen_pos - center
	var ar: float = planet_renderer.size.x / planet_renderer.size.y if planet_renderer.size.y > 0 else 1.0
	var nx: float = (local_click.x * ar) / float(planet_renderer._planet_radius_px)
	var ny: float = local_click.y / float(planet_renderer._planet_radius_px)
	if nx*nx + ny*ny <= 1.0:
		var z := sqrt(1.0 - nx*nx - ny*ny)
		var lat_rad := asin(-ny)
		var lon_rad := atan2(nx, z)
		var actual_lon := fposmod(planet_renderer.get_rotation_offset() + lon_rad, TAU)

		var lat_d := rad_to_deg(lat_rad)
		var lon_d := rad_to_deg(actual_lon)

		if DevConsole.show_planet_coords:
			var text := "%.1f : %.1f" % [lon_d, lat_d]
			poi_layer.spawn_floating_text(lon_d, lat_d, text, Color(0.4, 1.0, 0.4), 7)

		# Terrain sound + particle burst based on planet type
		if current_data != null:
			_spawn_terrain_hit(_screen_pos, current_data.planet_type)

	poi_layer.deselect_all()
	_build_planet_overview(current_data)

func _show_colonize_popup(data: PlanetData, pp: PlanetProgress) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 250
	
	var popup := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.09, 0.18, 0.97)
	ps.border_color = Color(0.25, 0.45, 0.80, 0.55)
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(6)
	ps.content_margin_left = 20; ps.content_margin_right = 20
	ps.content_margin_top = 20; ps.content_margin_bottom = 20
	popup.add_theme_stylebox_override("panel", ps)
	
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	popup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	
	var title := Label.new()
	title.text = "Establish Outpost" if data.planet_type == PlanetData.Type.MOON else "Colonize Planet"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_orbitron(title, 14)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	vbox.add_child(title)
	
	var desc := Label.new()
	desc.text = "Cost: %s Credits\nTime: 30 Seconds" % HUDManager.fmt_credits(1000.0)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_orbitron(desc, 12)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(desc)
	
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	
	var confirm := Button.new()
	confirm.text = "CONFIRM"
	_apply_orbitron(confirm, 12)
	confirm.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	confirm.pressed.connect(func():
		overlay.queue_free()
		if GameState.colonize_planet(data.seed):
			_build_planet_overview(data)
	)
	if GameState.credits < 1000.0:
		confirm.disabled = true
	
	var cancel := Button.new()
	cancel.text = "CANCEL"
	_apply_orbitron(cancel, 12)
	cancel.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	cancel.pressed.connect(func(): overlay.queue_free())
	
	btn_row.add_child(confirm)
	btn_row.add_child(cancel)
	vbox.add_child(btn_row)
	
	popup.add_child(vbox)
	overlay.add_child(popup)
	get_viewport().add_child(overlay)

func _show_level_up_popup(pp: PlanetProgress) -> void:
	if pp.is_upgrading:
		return
		
	# Full-screen dim overlay
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 250
	
	var popup := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.09, 0.18, 0.97)
	ps.border_color = Color(0.25, 0.45, 0.80, 0.55)
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(6)
	ps.content_margin_left = 20; ps.content_margin_right = 20
	ps.content_margin_top = 20; ps.content_margin_bottom = 20
	popup.add_theme_stylebox_override("panel", ps)
	
	# Center popup inside overlay
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	popup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	
	var req_title := Label.new()
	req_title.text = "Level Up to %d" % (pp.level + 1)
	req_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_orbitron(req_title, 14)
	req_title.add_theme_color_override("font_color", Color(0.85, 0.90, 1.0))
	vbox.add_child(req_title)
	
	var cost := pp.get_upgrade_cost()
	var can_afford := true
	
	if cost.has("credits"):
		var has_amt: float = GameState.credits
		var cost_amt: float = cost["credits"]
		
		var cred_box := HBoxContainer.new()
		cred_box.alignment = BoxContainer.ALIGNMENT_CENTER
		cred_box.add_theme_constant_override("separation", 12)
		
		var c_lbl := Label.new()
		c_lbl.text = "Credits:"
		_apply_orbitron(c_lbl, 10)
		c_lbl.add_theme_color_override("font_color", Color(0.9, 0.82, 0.25))
		
		var v_lbl := Label.new()
		v_lbl.text = "%d / %d" % [has_amt, cost_amt]
		_apply_orbitron(v_lbl, 10)
		
		if has_amt >= cost_amt:
			v_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
		else:
			v_lbl.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
			can_afford = false
			
		cred_box.add_child(c_lbl)
		cred_box.add_child(v_lbl)
		vbox.add_child(cred_box)
		
	var res_flow := HFlowContainer.new()
	res_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	res_flow.add_theme_constant_override("h_separation", 8)
	res_flow.add_theme_constant_override("v_separation", 8)
	
	for k in cost.keys():
		var k_str: String = str(k)
		if k_str == "credits":
			continue
			
		var cost_amt: float = cost[k]
		var has_amt: float = 0.0
		var display_rd: ResourceData = null
		
		if k_str.begins_with("ANY_T"):
			var tier := k_str.trim_prefix("ANY_T").to_int()
			for rid: String in GameState.global_resources:
				var rd: ResourceData = GameState.known_resources.get(rid) as ResourceData
				if rd != null and rd.tag == ResourceData.Tag.RAW_MINERAL and rd.tier == tier:
					has_amt += GameState.global_resources[rid]

			display_rd = ResourceData.new()
			display_rd.tier = tier
			display_rd.rarity = 1
			display_rd.display_color = Color(0.65, 0.65, 0.70)
			display_rd.unique_name = "Any T%d Mineral" % tier
		else:
			has_amt = GameState.global_resources.get(k_str, 0.0)
			display_rd = GameState.known_resources.get(k_str) as ResourceData
		
		if has_amt < cost_amt:
			can_afford = false
			
		if display_rd != null:
			var card := _mineral_grid_card(display_rd, has_amt, true, "", pp)
			
			var card_vbox = card.get_child(0)
			var lbl = card_vbox.get_child(1) as Label
			lbl.text = "%d/%d" % [has_amt, cost_amt]
			if has_amt >= cost_amt:
				lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
			else:
				lbl.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
				
			res_flow.add_child(card)
			
	if res_flow.get_child_count() > 0:
		vbox.add_child(res_flow)
	
	var rew_lbl := Label.new()
	rew_lbl.text = "Upon Level Up:\n+2 Max Districts\n+1 Max District Level"
	rew_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_orbitron(rew_lbl, 9)
	rew_lbl.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3))
	vbox.add_child(rew_lbl)
	
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 24)
	
	var cancel := Button.new()
	cancel.text = "CANCEL"
	_apply_orbitron(cancel, 10)
	var cancel_sb := StyleBoxFlat.new()
	cancel_sb.bg_color = Color(0.15, 0.15, 0.2)
	cancel_sb.set_corner_radius_all(4)
	cancel_sb.content_margin_top = 6; cancel_sb.content_margin_bottom = 6
	cancel_sb.content_margin_left = 12; cancel_sb.content_margin_right = 12
	cancel.add_theme_stylebox_override("normal", cancel_sb)
	cancel.pressed.connect(func(): overlay.queue_free())
	btns.add_child(cancel)
	
	var up_btn := Button.new()
	up_btn.text = "CONFIRM"
	_apply_orbitron(up_btn, 10)
	var btn_sb := StyleBoxFlat.new()
	btn_sb.bg_color = Color(0.2, 0.45, 0.7) if can_afford else Color(0.2, 0.25, 0.35)
	btn_sb.set_corner_radius_all(4)
	btn_sb.content_margin_top = 6; btn_sb.content_margin_bottom = 6
	btn_sb.content_margin_left = 12; btn_sb.content_margin_right = 12
	up_btn.add_theme_stylebox_override("normal", btn_sb)
	up_btn.add_theme_color_override("font_color", Color.WHITE if can_afford else Color(0.5, 0.55, 0.6))
	up_btn.disabled = not can_afford
	up_btn.pressed.connect(func():
		for k in cost.keys():
			var k_str: String = str(k)
			if k_str == "credits":
				GameState.spend_credits(cost[k])
			elif k_str.begins_with("ANY_T"):
				var tier := k_str.trim_prefix("ANY_T").to_int()
				var remain: float = cost[k]
				var available: Array[ResourceData] = []
				for rid: String in GameState.global_resources:
					var rd: ResourceData = GameState.known_resources.get(rid) as ResourceData
					if rd != null and rd.tag == ResourceData.Tag.RAW_MINERAL and rd.tier == tier and GameState.global_resources[rid] > 0:
						available.append(rd)
				available.sort_custom(func(a: ResourceData, b: ResourceData) -> bool: return a.rarity < b.rarity)
				for rd: ResourceData in available:
					var rid := rd.resource_id()
					var take: float = minf(remain, GameState.global_resources.get(rid, 0.0))
					GameState.global_resources[rid] = GameState.global_resources.get(rid, 0.0) - take
					remain -= take
					if remain <= 0.01:
						break
				GameState.global_resources_changed.emit()
			else:
				GameState.consume_resource(k_str, cost[k])
		AudioManager.play("level_up")
		pp.is_upgrading = true
		pp.upgrade_progress = 0.0
		if current_data != null:
			_build_planet_overview(current_data)
		overlay.queue_free()
	)
	btns.add_child(up_btn)
	
	vbox.add_child(btns)
	
	# Close on dim click
	overlay.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			overlay.queue_free()
	)
	# But stop clicks from falling through the popup to the dim background
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	
	popup.add_child(vbox)
	
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(popup)
	overlay.add_child(c)
	
	get_viewport().add_child(overlay)

func _make_overview_tab_btn(label: String, is_active: bool) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.toggle_mode    = true
	btn.button_pressed = is_active
	btn.focus_mode     = Control.FOCUS_NONE
	_apply_orbitron(btn, 8)
	var s_on := StyleBoxFlat.new()
	s_on.bg_color            = Color(0.12, 0.18, 0.35, 0.95)
	s_on.border_color        = Color(1.0, 0.92, 0.30, 0.55)
	s_on.border_width_bottom = 2
	s_on.content_margin_top  = 5; s_on.content_margin_bottom = 5
	var s_off := StyleBoxFlat.new()
	s_off.bg_color            = Color(0.06, 0.08, 0.14, 0.0)
	s_off.border_color        = Color(0.3, 0.35, 0.55, 0.25)
	s_off.border_width_bottom = 1
	s_off.content_margin_top  = 5; s_off.content_margin_bottom = 5
	btn.add_theme_stylebox_override("normal",          s_off)
	btn.add_theme_stylebox_override("hover",           s_off)
	btn.add_theme_stylebox_override("pressed",         s_on)
	btn.add_theme_stylebox_override("hover_pressed",   s_on)
	btn.add_theme_color_override("font_color",         Color(0.45, 0.52, 0.75))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.92, 0.30))
	btn.add_theme_color_override("font_hover_color",   Color(0.75, 0.82, 1.0))
	return btn

func _on_colonize_progress_changed(planet_seed: int, key: String, progress: float, pbar: ProgressBar, bind_seed: int) -> void:
	if planet_seed == bind_seed and key == "colonize":
		if is_instance_valid(pbar):
			pbar.value = progress * 100.0

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
	if _orbital_layer != null and is_instance_valid(_orbital_layer):
		_orbital_layer.set_selected_station("")

	var pp := GameState.get_planet(data.seed)

	var root := VBoxContainer.new()
	root.name = "DistrictBuildPanel"
	root.add_theme_constant_override("separation", 8)
	root.add_child(HSeparator.new())



	# ── Top tabs: PLANET | INVENTORY ─────────────────────────────────────────
	var top_tab_row := HBoxContainer.new()
	top_tab_row.add_theme_constant_override("separation", 0)
	root.add_child(top_tab_row)
	var planet_tab_btn:    Button = _make_overview_tab_btn("DETAILS",   _top_tab_active == "DETAILS")
	var inventory_tab_btn: Button = _make_overview_tab_btn("INVENTORY", _top_tab_active == "INVENTORY")
	_inventory_tab_btn = inventory_tab_btn
	top_tab_row.add_child(planet_tab_btn)
	top_tab_row.add_child(inventory_tab_btn)

	# ── PLANET page ───────────────────────────────────────────────────────────
	var planet_page := VBoxContainer.new()
	planet_page.add_theme_constant_override("separation", 8)
	planet_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(planet_page)

	# ── INVENTORY page ────────────────────────────────────────────────────────
	var inv_scroll := ScrollContainer.new()
	inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inv_scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	inv_scroll.custom_minimum_size    = Vector2(0, 120)
	inv_scroll.clip_contents          = false
	inv_scroll.visible = false
	root.add_child(inv_scroll)

	var inv_vbox := VBoxContainer.new()
	inv_vbox.add_theme_constant_override("separation", 6)
	inv_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_scroll.add_child(inv_vbox)

	var _inv_grid: HFlowContainer
	var _build_inv_grid := func() -> void:
		for c in inv_vbox.get_children(): c.queue_free()
		var entries: Array[ResourceData] = []
		for rid: String in GameState.global_resources:
			var amt: float = GameState.global_resources[rid]
			if amt < 0.5: continue
			var rd: ResourceData = GameState.known_resources.get(rid, null)
			if rd == null: continue
			entries.append(rd)
		entries.sort_custom(func(a: ResourceData, b: ResourceData) -> bool:
			return a.rarity < b.rarity if a.rarity != b.rarity else a.tier < b.tier)
		const INV_COLS    := 5
		const INV_CELL_SZ := 56
		var grid := GridContainer.new()
		grid.columns = INV_COLS
		grid.add_theme_constant_override("h_separation", 5)
		grid.add_theme_constant_override("v_separation", 5)
		grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		for rd: ResourceData in entries:
			var stored: float = GameState.global_resources.get(rd.resource_id(), 0.0)
			var card := _mineral_grid_card(rd, stored, true, "", pp)
			card.custom_minimum_size = Vector2(INV_CELL_SZ, INV_CELL_SZ)
			grid.add_child(card)
		# Fill to complete the last row, minimum 3 full rows total
		var rows_needed: int = max(3, int(ceil(float(entries.size()) / INV_COLS)))
		var total_slots: int = rows_needed * INV_COLS
		var empty_count: int = total_slots - entries.size()
		for _ei in empty_count:
			var empty_pc := PanelContainer.new()
			empty_pc.custom_minimum_size = Vector2(INV_CELL_SZ, INV_CELL_SZ)
			var es := StyleBoxFlat.new()
			es.bg_color    = Color(0.07, 0.08, 0.14, 0.60)
			es.border_color = Color(0.18, 0.22, 0.36, 0.40)
			es.set_border_width_all(1)
			es.set_corner_radius_all(5)
			empty_pc.add_theme_stylebox_override("panel", es)
			empty_pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(empty_pc)
		inv_vbox.add_child(grid)

	_build_inv_grid.call()

	var _inv_refresh_conn: Callable = func() -> void:
		if is_instance_valid(inv_vbox) and inv_scroll.visible:
			_build_inv_grid.call()
	if not GameState.global_resources_changed.is_connected(_inv_refresh_conn):
		GameState.global_resources_changed.connect(_inv_refresh_conn)

	# Tab switching
	planet_tab_btn.toggled.connect(func(on: bool) -> void:
		if on:
			_top_tab_active = "DETAILS"
			inventory_tab_btn.button_pressed = false
			planet_page.visible  = true
			inv_scroll.visible   = false
		else:
			if _top_tab_active == "DETAILS":
				planet_tab_btn.set_pressed_no_signal(true))
	inventory_tab_btn.toggled.connect(func(on: bool) -> void:
		if on:
			_top_tab_active = "INVENTORY"
			planet_tab_btn.button_pressed = false
			planet_page.visible  = false
			inv_scroll.visible   = true
			_build_inv_grid.call()
		else:
			if _top_tab_active == "INVENTORY":
				inventory_tab_btn.set_pressed_no_signal(true))
	# Restore correct visibility based on saved state
	planet_page.visible = (_top_tab_active == "DETAILS")
	inv_scroll.visible  = (_top_tab_active == "INVENTORY")

	_overview_energy_val = null  # energy shown in top-center HUD

	# ── Pre-split POIs (needed for counts before tab section) ─────────────────
	var surface_pois: Array[POIData] = []
	var orbital_pois: Array[POIData] = []
	for poi: POIData in data.custom_pois:
		if poi.is_orbital():
			orbital_pois.append(poi)
		else:
			surface_pois.append(poi)

	# ── Planet info: modifiers + type/size/atm + deposits ────────────────────
	var p_mods := PlanetModifier.for_planet(data.planet_type)
	if not p_mods.is_empty():
		var mod_row := HFlowContainer.new()
		mod_row.add_theme_constant_override("h_separation", 4)
		mod_row.add_theme_constant_override("v_separation", 3)
		planet_page.add_child(mod_row)
		for m: PlanetModifier in p_mods:
			var positive := m.is_positive()
			var chip_lbl := Label.new()
			chip_lbl.text = "%s %s" % [m.display_name, m.value_label()]
			_apply_orbitron(chip_lbl, 7)
			chip_lbl.add_theme_color_override("font_color",
				Color(0.55, 0.96, 0.62) if positive else Color(1.0, 0.58, 0.58))
			var chip_pc := PanelContainer.new()
			var chip_s := StyleBoxFlat.new()
			chip_s.bg_color = Color(0.07, 0.18, 0.10, 0.88) if positive else Color(0.18, 0.06, 0.06, 0.88)
			chip_s.border_color = Color(0.35, 0.85, 0.48, 0.90) if positive else Color(0.88, 0.32, 0.32, 0.90)
			chip_s.set_border_width_all(1)
			chip_s.corner_radius_top_left = 4; chip_s.corner_radius_top_right = 4
			chip_s.corner_radius_bottom_left = 4; chip_s.corner_radius_bottom_right = 4
			chip_s.content_margin_left = 5; chip_s.content_margin_right = 5
			chip_s.content_margin_top = 1; chip_s.content_margin_bottom = 1
			chip_pc.add_theme_stylebox_override("panel", chip_s)
			chip_pc.mouse_filter = Control.MOUSE_FILTER_STOP
			chip_pc.add_child(chip_lbl)
			var cap_m := m
			chip_pc.mouse_entered.connect(func() -> void:
				CursorManager.set_state(CursorManager.State.POINTER)
				var body := cap_m.description + "\n\n" + cap_m.value_label()
				TooltipManager.show_tip(cap_m.display_name, body))
			chip_pc.mouse_exited.connect(func() -> void:
				CursorManager.set_state(CursorManager.State.NORMAL)
				TooltipManager.hide_tip())
			mod_row.add_child(chip_pc)

	var p_size_str := "Small" if data.planet_size < 0.8 else ("Large" if data.planet_size > 1.3 else "Medium")
	var p_atm_str: String
	if data.has_atmosphere:
		p_atm_str = "Thin" if data.atmosphere_density < 0.4 else ("Dense" if data.atmosphere_density > 0.7 else "Standard")
	else:
		p_atm_str = "None"
	for info_pair: Array in [
		["Type", PlanetData.Type.keys()[data.planet_type].capitalize()],
		["Size", p_size_str], ["Atm.", p_atm_str]
	]:
		var irow := HBoxContainer.new()
		var ik := Label.new(); ik.text = info_pair[0]
		ik.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_orbitron(ik, 8)
		ik.add_theme_color_override("font_color", Color(0.40, 0.45, 0.65))
		var iv := Label.new(); iv.text = info_pair[1]
		_apply_orbitron(iv, 8)
		iv.add_theme_color_override("font_color",
			Color(0.60, 0.40, 0.40) if info_pair[1] == "None" else Color(0.80, 0.85, 1.0))
		irow.add_child(ik); irow.add_child(iv)
		planet_page.add_child(irow)

	var p_br := GameState.get_body_resources_for(data)
	if not p_br.as_array().is_empty():
		var dep_hdr := Label.new(); dep_hdr.text = "DEPOSITS"
		_apply_orbitron(dep_hdr, 7)
		dep_hdr.add_theme_color_override("font_color", Color(0.4, 0.45, 0.65))
		planet_page.add_child(dep_hdr)
		var dep_grid := HFlowContainer.new()
		dep_grid.add_theme_constant_override("h_separation", 4)
		dep_grid.add_theme_constant_override("v_separation", 4)
		var dep_rng := RandomNumberGenerator.new()
		var total_dens: float = 0.0
		for rd: ResourceData in p_br.as_array():
			var rid := rd.resource_id()
			var d: float = 0.0
			if data.mineral_densities.has(rid):
				d = float(data.mineral_densities[rid])
			else:
				dep_rng.seed = data.seed ^ (rd.rarity * 0x4E3D)
				d = data.deposit_density * dep_rng.randf_range(0.75, 1.25)
			total_dens += d
		for rd: ResourceData in p_br.as_array():
			var rid := rd.resource_id()
			var p_density: float
			if data.mineral_densities.has(rid):
				p_density = float(data.mineral_densities[rid])
			else:
				dep_rng.seed = data.seed ^ (rd.rarity * 0x4E3D)
				p_density = data.deposit_density * dep_rng.randf_range(0.75, 1.25)
			var pct := 0
			if total_dens > 0: pct = int(round((p_density / total_dens) * 100.0))
			dep_grid.add_child(_mineral_grid_card(rd, 0.0, false, "%d%%" % pct))
		planet_page.add_child(dep_grid)

	if not pp.is_colonized:
		var unc_spacer := Control.new()
		unc_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		planet_page.add_child(unc_spacer)

		var col_sep := HSeparator.new()
		var col_sep_s := StyleBoxFlat.new(); col_sep_s.bg_color = Color(0.2, 0.25, 0.4, 0.35)
		col_sep.add_theme_stylebox_override("separator", col_sep_s)
		planet_page.add_child(col_sep)

		if pp.is_colonizing:
			var pbar := ProgressBar.new()
			pbar.custom_minimum_size = Vector2(0, 32)
			pbar.value = pp.colonize_progress * 100.0
			pbar.show_percentage = false
			
			var bg := StyleBoxFlat.new()
			bg.bg_color = Color(0.1, 0.15, 0.25)
			bg.corner_radius_top_left = 4; bg.corner_radius_top_right = 4
			bg.corner_radius_bottom_left = 4; bg.corner_radius_bottom_right = 4
			
			var fg := StyleBoxFlat.new()
			fg.bg_color = Color(0.3, 0.8, 0.4)
			fg.corner_radius_top_left = 4; fg.corner_radius_top_right = 4
			fg.corner_radius_bottom_left = 4; fg.corner_radius_bottom_right = 4
			
			pbar.add_theme_stylebox_override("background", bg)
			pbar.add_theme_stylebox_override("fill", fg)
			
			var plabel := Label.new()
			plabel.text = "Establishing..." if (data.planet_type == PlanetData.Type.MOON or data.planet_type == PlanetData.Type.ASTEROID) else "Colonizing..."
			plabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			plabel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			plabel.set_anchors_preset(Control.PRESET_FULL_RECT)
			_apply_orbitron(plabel, 12)
			pbar.add_child(plabel)
			
			planet_page.add_child(pbar)
			
			# Listen for progress updates
			for conn in ProductionManager.building_progress_changed.get_connections():
				if conn["callable"].get_object() == self and conn["callable"].get_method() == "_on_colonize_progress_changed":
					ProductionManager.building_progress_changed.disconnect(conn["callable"])
			ProductionManager.building_progress_changed.connect(_on_colonize_progress_changed.bind(pbar, data.seed))
		else:
			var col_btn := Button.new()
			if data.planet_type == PlanetData.Type.MOON or data.planet_type == PlanetData.Type.ASTEROID:
				col_btn.text = "BUILD OUTPOST"
			else:
				col_btn.text = "COLONIZE"
			_apply_orbitron(col_btn, 12)
			var col_sb := StyleBoxFlat.new()
			col_sb.bg_color = Color(0.10, 0.28, 0.45)
			col_sb.content_margin_top = 10; col_sb.content_margin_bottom = 10
			col_btn.add_theme_stylebox_override("normal", col_sb)
			var col_hb := col_sb.duplicate() as StyleBoxFlat
			col_hb.bg_color = Color(0.15, 0.42, 0.65)
			col_btn.add_theme_stylebox_override("hover", col_hb)
			col_btn.add_theme_color_override("font_color", Color.WHITE)
			col_btn.pressed.connect(func() -> void:
				_show_colonize_popup(data, pp)
			)
			planet_page.add_child(col_btn)
		
		root.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel_content.add_child(root)
		return

	# ── District slot indicators ─────────────────────────────────────────────
	var p_max_orbital := 0
	var st := get_node_or_null("/root/SkillTree")
	var has_orbital_unlocked := false
	for p_def: DistrictDef in DistrictDef.all():
		if p_def.is_orbital and p_def.max_per_planet > 0:
			if p_def.unlock_skill == "" or (st != null and st.is_unlocked(p_def.unlock_skill)):
				has_orbital_unlocked = true
				p_max_orbital += p_def.max_per_planet

	# Single row: [Surface group] [spacer] [Orbital group]
	# Each group is a VBox: slots on top, label below.
	var limits_row := HBoxContainer.new()
	limits_row.add_theme_constant_override("separation", 0)
	limits_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slot_info_arr: Array = [ ["Surface", surface_pois.size(), pp.max_districts] ]
	if has_orbital_unlocked:
		slot_info_arr.append(["Orbital", orbital_pois.size(), max(1, p_max_orbital)])
		
	for slot_info: Array in slot_info_arr:
		var group_vbox := VBoxContainer.new()
		group_vbox.add_theme_constant_override("separation", 3)
		group_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var slots_hbox := HBoxContainer.new()
		slots_hbox.add_theme_constant_override("separation", 3)
		slots_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not has_orbital_unlocked:
			slots_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		slots_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var filled: int = slot_info[1]; var total: int = slot_info[2]
		for idx in total:
			var slot_pc := PanelContainer.new()
			slot_pc.custom_minimum_size = Vector2(14, 10)
			var slot_s := StyleBoxFlat.new()
			if idx < filled:
				slot_s.bg_color    = Color(0.90, 0.75, 0.18, 0.85)
				slot_s.border_color = Color(0.95, 0.82, 0.25, 0.90)
			else:
				slot_s.bg_color    = Color(0.10, 0.12, 0.22, 0.70)
				slot_s.border_color = Color(0.28, 0.33, 0.52, 0.55)
			slot_s.set_border_width_all(1)
			slot_s.set_corner_radius_all(2)
			slot_pc.add_theme_stylebox_override("panel", slot_s)
			slot_pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slots_hbox.add_child(slot_pc)
		group_vbox.add_child(slots_hbox)
		var si_lbl := Label.new(); si_lbl.text = slot_info[0]
		_apply_orbitron(si_lbl, 9)
		si_lbl.add_theme_color_override("font_color", Color(0.50, 0.55, 0.70))
		si_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		si_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		si_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group_vbox.add_child(si_lbl)
		limits_row.add_child(group_vbox)
	root.add_child(limits_row)

	# ── Tab bar ───────────────────────────────────────────────────────────────
	var tab_sep := HSeparator.new()
	var tab_sep_s := StyleBoxFlat.new()
	tab_sep_s.bg_color = Color(0.2, 0.25, 0.4, 0.35)
	tab_sep.add_theme_stylebox_override("separator", tab_sep_s)
	root.add_child(tab_sep)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 0)
	root.add_child(tab_row)

	var dist_btn:    Button = _make_overview_tab_btn("SURFACE", _inner_tab_active == "SURFACE")
	var orbital_btn: Button = _make_overview_tab_btn("ORBITAL", _inner_tab_active == "ORBITAL")
	tab_row.add_child(dist_btn)
	if has_orbital_unlocked:
		tab_row.add_child(orbital_btn)

	# ── DISTRICTS scroll + page ───────────────────────────────────────────────
	var dist_scroll := ScrollContainer.new()
	dist_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dist_scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	root.add_child(dist_scroll)

	var districts_page := VBoxContainer.new()
	districts_page.add_theme_constant_override("separation", 8)
	districts_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dist_scroll.add_child(districts_page)

	_poi_overview_cards.clear()
	_stop_tut_panel_pulse()
	for poi: POIData in surface_pois:
		districts_page.add_child(_build_district_overview_card(poi, data, pp, panel_content, root))

	var can_add_surface := surface_pois.size() < pp.max_districts
	var add_dist_card := _build_add_district_card(data, can_add_surface, false)
	districts_page.add_child(add_dist_card)
	# Tutorial: highlight ADD DISTRICT card when district placement is the objective
	if can_add_surface and TutorialManager.get_action_step_type() == "district":
		_tut_highlight_node = add_dist_card.get_child(0) as Control
		_start_tut_node_pulse(_tut_highlight_node)

	# ── ORBITAL scroll + page ─────────────────────────────────────────────────
	var orb_scroll := ScrollContainer.new()
	orb_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	orb_scroll.size_flags_vertical    = Control.SIZE_EXPAND_FILL
	orb_scroll.visible = false
	root.add_child(orb_scroll)

	var orbital_page := VBoxContainer.new()
	orbital_page.add_theme_constant_override("separation", 8)
	orbital_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	orb_scroll.add_child(orbital_page)

	for poi: POIData in orbital_pois:
		orbital_page.add_child(_build_district_overview_card(poi, data, pp, panel_content, root))

	var can_add_orbital := true
	for def: DistrictDef in DistrictDef.all():
		if def.is_orbital and def.max_per_planet > 0:
			if DistrictDef.count_on_planet(def, data) >= def.max_per_planet:
				can_add_orbital = false
				break
	orbital_page.add_child(_build_add_district_card(data, can_add_orbital, true))

	# ── Tab switching ─────────────────────────────────────────────────────────
	if not has_orbital_unlocked and _inner_tab_active == "ORBITAL":
		_inner_tab_active = "SURFACE"

	dist_btn.toggled.connect(func(on: bool) -> void:
		if on:
			_inner_tab_active = "SURFACE"
			orbital_btn.button_pressed = false
			dist_scroll.visible = true
			orb_scroll.visible  = false
		else:
			if _inner_tab_active == "SURFACE":
				dist_btn.set_pressed_no_signal(true))
	orbital_btn.toggled.connect(func(on: bool) -> void:
		if on:
			_inner_tab_active = "ORBITAL"
			dist_btn.button_pressed = false
			dist_scroll.visible = false
			orb_scroll.visible  = true
		else:
			if _inner_tab_active == "ORBITAL":
				orbital_btn.set_pressed_no_signal(true))
	# Restore correct visibility based on saved state
	dist_scroll.visible = (_inner_tab_active == "SURFACE")
	orb_scroll.visible  = (_inner_tab_active == "ORBITAL") and has_orbital_unlocked

	root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# --- LEVEL UP SECTION ---
	var lvl_sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.2, 0.25, 0.4, 0.35)
	lvl_sep.add_theme_stylebox_override("separator", sep_style)
	root.add_child(lvl_sep)

	if pp.is_upgrading:
		var up_lbl := Label.new()
		up_lbl.text = "UPGRADING TO LV %d..." % (pp.level + 1)
		up_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_apply_orbitron(up_lbl, 10)
		up_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
		root.add_child(up_lbl)

		_planet_upgrade_pbar = ProgressBar.new()
		_planet_upgrade_pbar.custom_minimum_size.y = 12
		_planet_upgrade_pbar.show_percentage = false
		_planet_upgrade_pbar.value = pp.upgrade_progress * 100.0
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.1, 0.15)
		var sbf := StyleBoxFlat.new()
		sbf.bg_color = Color(0.4, 0.9, 0.4)
		_planet_upgrade_pbar.add_theme_stylebox_override("background", sb)
		_planet_upgrade_pbar.add_theme_stylebox_override("fill", sbf)
		root.add_child(_planet_upgrade_pbar)
	else:
		_planet_upgrade_pbar = null
		
		var up_btn := Button.new()
		up_btn.text = "LEVEL UP"
		_apply_orbitron(up_btn, 12)
		var btn_sb := StyleBoxFlat.new()
		btn_sb.bg_color = Color(0.15, 0.4, 0.15)
		btn_sb.content_margin_top = 10; btn_sb.content_margin_bottom = 10
		up_btn.add_theme_stylebox_override("normal", btn_sb)
		
		var h_sb := StyleBoxFlat.new()
		h_sb.bg_color = Color(0.2, 0.6, 0.2)
		h_sb.content_margin_top = 10; h_sb.content_margin_bottom = 10
		up_btn.add_theme_stylebox_override("hover", h_sb)
		
		up_btn.add_theme_color_override("font_color", Color.WHITE)
		up_btn.mouse_entered.connect(func(): AudioManager.play("hover"))
		up_btn.pressed.connect(func(): AudioManager.play("click"); _show_level_up_popup(pp))
		root.add_child(up_btn)

	panel_content.add_child(root)

## Compact card for a ship in the Orbital tab.
func _build_orbital_ship_card(ship: ShipData) -> PanelContainer:
	var card := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color     = Color(0.07, 0.10, 0.18, 0.85)
	s.border_color = Color(0.35, 0.42, 0.70, 0.40)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 10; s.content_margin_right  = 10
	s.content_margin_top  =  7; s.content_margin_bottom =  7
	card.add_theme_stylebox_override("panel", s)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	card.add_child(hbox)

	# Name + status column
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = ship.ship_name
	_apply_orbitron(name_lbl, 10)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.30))
	vbox.add_child(name_lbl)

	var status_lbl := Label.new()
	status_lbl.text = "En route…" if ship.is_travelling() else "In orbit"
	_apply_orbitron(status_lbl, 8)
	status_lbl.add_theme_color_override("font_color", Color(0.50, 0.68, 0.95, 0.75))
	vbox.add_child(status_lbl)

	# Cargo summary (icon count)
	if not ship.cargo.is_empty():
		var cargo_row := HBoxContainer.new()
		cargo_row.add_theme_constant_override("separation", 3)
		vbox.add_child(cargo_row)
		for rid: String in ship.cargo:
			var rd: ResourceData = GameState.known_resources.get(rid, null)
			if rd == null: continue
			cargo_row.add_child(_mineral_grid_card(rd, ship.cargo[rid], true))

	# Select button
	var sel_btn := Button.new()
	sel_btn.text = "Select"
	_apply_orbitron(sel_btn, 8)
	var bs := StyleBoxFlat.new()
	bs.bg_color     = Color(0.10, 0.18, 0.35, 0.85)
	bs.border_color = Color(1.0, 0.92, 0.30, 0.45)
	bs.set_border_width_all(1)
	bs.set_corner_radius_all(3)
	bs.content_margin_left = 8; bs.content_margin_right  = 8
	bs.content_margin_top  = 3; bs.content_margin_bottom = 3
	sel_btn.add_theme_stylebox_override("normal",  bs)
	sel_btn.add_theme_stylebox_override("hover",   bs)
	sel_btn.add_theme_stylebox_override("pressed", bs)
	sel_btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.30, 0.85))
	sel_btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	sel_btn.mouse_exited.connect(func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))

	var cap_ship := ship
	sel_btn.pressed.connect(func() -> void:
		if _orbital_layer != null and is_instance_valid(_orbital_layer):
			_orbital_layer.select_ship(cap_ship)
			# Rotate planet so the ship's current position faces the viewer (rz < 0)
			# px,pz = ship position in orbit plane (normalized)
			var px: float = cos(cap_ship.orbit_angle)
			var pz: float = sin(cap_ship.orbit_angle) * cos(cap_ship.orbit_inclination)
			# rot_target such that rx=0 and rz<0: atan2(-px, pz) + PI
			var rot_target: float = atan2(-px, pz) + PI
			_rotate_to_lon(rad_to_deg(rot_target - cap_ship.orbit_node)))
	hbox.add_child(sel_btn)

	return card

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

	# Collect global resources with amount > 0, resolved from known_resources
	var stored_entries: Array[ResourceData] = []
	for rid: String in GameState.global_resources:
		var amt: float = GameState.global_resources[rid]
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
		var stored: float = GameState.global_resources.get(rd.resource_id(), 0.0)
		grid.add_child(_mineral_grid_card(rd, stored, true, "", pp))
	parent.add_child(grid)

func _build_district_overview_card(poi: POIData, planet: PlanetData, pp: PlanetProgress,
		_panel_content: VBoxContainer, _root: VBoxContainer) -> PanelContainer:
	var card := PanelContainer.new()
	card.set_meta("poi_label", poi.label)
	_poi_overview_cards[poi.label] = card
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
		AudioManager.play("district_hover")
		cap_card.add_theme_stylebox_override("panel", hov_s2)
		if cap_poi.constructing:
			TooltipManager.show_tip("Constructing", "This District is not fully operational yet.\nBuild time: %.0fs" % cap_poi.construct_duration)
		CursorManager.set_state(CursorManager.State.POINTER))
	card.mouse_exited.connect(func() -> void:
		cap_card.add_theme_stylebox_override("panel", norm_s2)
		TooltipManager.hide_tip()
		CursorManager.set_state(CursorManager.State.NORMAL))
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			AudioManager.play("click")
			if cap_poi.is_orbital():
				# Rotate planet so station faces camera, then highlight
				if _orbital_layer != null and is_instance_valid(_orbital_layer):
					_orbital_layer.set_selected_station(cap_poi.label)
				var eq_lon: float = rad_to_deg(cap_poi.orbit_node + atan2(
					sin(cap_poi.orbit_angle) * cos(cap_poi.orbit_inclination),
					cos(cap_poi.orbit_angle)))
				_rotate_to_lon(eq_lon)
			else:
				_select_district_on_planet(cap_poi.label)
				_rotate_to_lon(cap_poi.lon_deg)
			if cap_poi.constructing:
				TooltipManager.show_tip("Constructing", "This District is not fully operational yet.\nBuild time: %.0fs" % cap_poi.construct_duration)
				return
			_build_district_panel(cap_poi, cap_planet))
	return card

func _select_district_on_planet(label: String) -> void:
	if _orbital_layer != null and is_instance_valid(_orbital_layer):
		_orbital_layer.set_selected_station("")
	for i in poi_layer._pois.size():
		if poi_layer._pois[i].get("label", "") == label:
			poi_layer.select_poi(i)
			return

func _build_add_district_card(data: PlanetData, enabled: bool, orbital_only: bool = false) -> VBoxContainer:
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
			AudioManager.play("hover")
			CursorManager.set_state(CursorManager.State.POINTER))
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
			AudioManager.play("click")
			# Toggle
			if dropdown_ref[0] != null and is_instance_valid(dropdown_ref[0]):
				dropdown_ref[0].queue_free()
				dropdown_ref[0] = null
				return
			var dd := _build_district_type_dropdown(cap_data, cap_wrap, dropdown_ref, orbital_only)
			cap_wrap.add_child(dd)
			dropdown_ref[0] = dd
			_notify_tutorial_district_type_dropdown(dd))

	return wrapper

func _build_district_type_dropdown(data: PlanetData, _anchor: VBoxContainer,
		dropdown_ref: Array[Control], orbital_only: bool = false) -> PanelContainer:
	var dd := PanelContainer.new()
	dd.add_theme_stylebox_override("panel", _make_hud_style(Color(0.06, 0.08, 0.16, 0.97), 6))
	dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	dd.add_child(vbox)

	var available := DistrictDef.for_planet(data.planet_type)
	for def: DistrictDef in available:
		if def.is_orbital != orbital_only:
			continue
		if def.unlock_skill != "" and not get_node("/root/SkillTree").unlocked_skills.has(def.unlock_skill):
			continue
		var row := _build_district_type_row(data, def, dropdown_ref)
		vbox.add_child(row)

	return dd

func _build_district_type_row(data: PlanetData, def: DistrictDef,
		dropdown_ref: Array[Control]) -> Control:
	var btn := Button.new()
	btn.flat = true
	btn.text = "%s  %s" % [def.icon, def.display_name]
	btn.set_meta("district_def_id", int(def.id))
	_apply_orbitron(btn, 9)
	var cost: float = DistrictDef.placement_cost(def, data)
	var can_afford: bool = GameState.credits >= cost
	var at_limit: bool = def.max_per_planet > 0 and \
		DistrictDef.count_on_planet(def, data) >= def.max_per_planet

	btn.disabled = not can_afford or at_limit
	if at_limit:
		btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.6))
	elif not can_afford:
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
		AudioManager.play("district_hover")
		CursorManager.set_state(CursorManager.State.POINTER)
		var t_title = def.display_name
		var t_desc = def.description
		if at_limit:
			t_desc += "\n\n[color=gray]Already built (limit: %d)[/color]" % def.max_per_planet
		elif not can_afford:
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
			AudioManager.play("error")
			return
		_spawn_district(cap_data, cap_def.suggest_name(cap_data), cap_def))

	return btn

func _on_district_clicked(index: int, _data: Dictionary) -> void:
	if index >= poi_layer._pois.size():
		return
	AudioManager.play("district_hover")
	if _orbital_layer != null and is_instance_valid(_orbital_layer):
		_orbital_layer.set_selected_station("")
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
	if poi.constructing:
		TooltipManager.show_tip("Constructing", "This District is not fully operational yet.\nBuild time: %.0fs" % poi.construct_duration)
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

func _on_resource_produced(planet_seed: int, poi_label: String, text: String, color: Color, icon: Texture2D) -> void:
	if current_data == null or current_data.seed != planet_seed:
		return
	for poi in current_data.custom_pois:
		if poi.label == poi_label:
			poi_layer.spawn_floating_text(poi.lon_deg, poi.lat_deg, text, color, 14, icon)
			break
	if _active_district_poi != null:
		_refresh_district_energy_lbl()
	else:
		_build_planet_overview(current_data)

func _on_production_update(_planet_seed: int, key: String, progress: float) -> void:
	if _district_pbars.has(key):
		var pbar: ProgressBar = _district_pbars[key]
		if is_instance_valid(pbar):

			pbar.value = progress * 100.0
		else:
			print("[UI Debug] pbar is invalid for ", key)
	else:
		if " " in key: # naive check for district names to see if we missed it
			pass

	if not _bar_meta.has(key):
		return
	var m: Dictionary = _bar_meta[key]
	if m.has("prog"):
		(m["prog"] as Array)[0] = progress
	var fc: Control = m.get("fill", null)
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
	var fc: Control = _bar_meta[key].get("fill", null)
	if fc != null and is_instance_valid(fc):
		fc.queue_redraw()
	_refresh_bar_label_status(key)

func _refresh_bar_label_status(key: String) -> void:
	if not _bar_meta.has(key):
		return
	var m: Dictionary = _bar_meta[key]
	if m.get("construction", false):
		return
	# Spaceport stub — no live labels to refresh
	if not m.has("out_lbl"):
		return
	var out_lbl: Label = m.get("out_lbl", null)
	var def: BuildingDef = m.get("def", null)
	var fc: Color = m.get("fc", Color.WHITE)
	if is_instance_valid(out_lbl) and def != null:
		var paused := ProductionManager.is_paused(key)
		var out_text := "⏸ waiting"
		if not paused:
			var sk := get_node("/root/SkillTree")
			var amount: int = m.get("entry", {}).get("amount", 1)
			var out_val := def.output_amount * float(amount)
			if def.output_type == BuildingDef.OutputType.CREDITS:
				out_val *= sk.get_credits_mult()
			elif def.output_type == BuildingDef.OutputType.ENERGY:
				if def.building_id == "solar_panel":
					out_val *= sk.get_solar_mult()
				elif def.building_id == "generator":
					out_val *= sk.get_generator_output_mult()
					var in_min: String = m.get("entry", {}).get("burning_mineral", "")
					if in_min != "":
						var rd: ResourceData = GameState.known_resources.get(in_min)
						if rd: out_val *= float(rd.rarity)
					else:
						out_val = 0.0
			elif def.output_type == BuildingDef.OutputType.RAW_MINERAL or def.output_type == BuildingDef.OutputType.REFINED_MINERAL:
				out_val *= sk.get_mine_output_mult()
			match def.output_type:
				BuildingDef.OutputType.ENERGY:          out_text = "+%.0f ⚡" % out_val
				BuildingDef.OutputType.CREDITS:         out_text = "+%.0f cr" % out_val
				BuildingDef.OutputType.RAW_MINERAL:     out_text = "+%.0f ore" % out_val
				BuildingDef.OutputType.REFINED_MINERAL: out_text = "+%.0f ref" % out_val
				BuildingDef.OutputType.SCIENCE:         out_text = "+%.0f sci" % out_val
		out_lbl.text = out_text
		out_lbl.add_theme_color_override("font_color",
			Color(0.45, 0.48, 0.60) if paused else fc)

		var slowed_lbl: Label = m.get("slowed_lbl", null)
		if is_instance_valid(slowed_lbl):
			var er := ProductionManager.get_energy_ratio(m.get("planet_seed", -1))
			slowed_lbl.text    = "⚡ Slowed %d%% — Energy Crisis" % [int((1.0 - er) * 100)]
			var is_user_paused := ProductionManager.is_user_paused(key)
			slowed_lbl.visible = not paused and not is_user_paused and er < 0.999

func _on_building_constructed(planet_seed: int, key: String) -> void:
	if current_data == null or current_data.seed != planet_seed:
		return
	AudioManager.play("building_done")

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

	# Keep station ship.buildings in sync when construction completes
	_sync_station_buildings()

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

## Starts a rocket launch animation. Multiple can run concurrently.
func _play_rocket_animation(planet_seed: int, poi: POIData, on_complete: Callable,
		sp_pm_key: String = "", ship_name: String = "Pioneer", ship_type: String = "shuttle",
		ship_cargo: Dictionary = {}, destination_ship_id: String = "",
		transfer_dir: String = "", transfer_resource: String = "", transfer_amount: int = 0,
		auto_land: bool = false, mission_tasks: Array = [],
		station_district_poi: POIData = null) -> void:
	var container: Control = planet_renderer.get_parent()
	var planet_r:  float   = planet_renderer._planet_radius_px
	const ORBIT_FRAC:       float = 1.06
	const BASE_LAUNCH_DUR:  float = 22.0   # seconds at reference planet radius
	const REF_RADIUS:       float = 200.0
	const LAUNCH_TIME_SCALE: float = 1.0   # hook here for upgrade (lower = faster)
	var launch_dur: float = (planet_r / REF_RADIUS) * BASE_LAUNCH_DUR * LAUNCH_TIME_SCALE

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

	# Orbit insertion point: random by default, intercepted to destination if set.
	var sweep_target: float = randf_range(PI * 0.15, PI * 0.75) * (1.0 if randf() > 0.5 else -1.0)
	var sweep_sign:   float = sign(sweep_target)
	var lat_target:   float = randf_range(-PI * 0.35, PI * 0.35)

	# Predictive intercept — aim for where the station will be when we arrive.
	if destination_ship_id != "":
		var dest: ShipData = null
		for s: ShipData in ShipManager.ships_for(planet_seed):
			if s.ship_id == destination_ship_id:
				dest = s; break
		if dest != null:
			var rot_at_launch: float = planet_renderer.get_rotation_offset()
			var pred_a: float = dest.orbit_angle + dest.orbit_speed * launch_dur
			var inc: float    = dest.orbit_inclination
			var rot: float    = rot_at_launch + dest.orbit_node
			# Project predicted station position (unit-radius normalized)
			var px: float = cos(pred_a)
			var py: float = sin(pred_a) * sin(inc)
			var pz: float = sin(pred_a) * cos(inc)
			var nx: float = px * cos(rot) + pz * sin(rot)
			var ny: float = py
			# Reverse the launch math:  ty = -sin(lat_final), tx = sin(lon_final)*cos(lat_final)
			lat_target   = -asin(clampf(ny, -1.0, 1.0))
			var cos_lat: float = cos(lat_target)
			if abs(cos_lat) > 0.01:
				var sin_lon: float = clampf(nx / cos_lat, -1.0, 1.0)
				var lon1: float = asin(sin_lon)
				var lon2: float = PI - lon1
				var sw1: float  = wrapf(lon1 - poi_lon + rot_at_launch, -PI, PI)
				var sw2: float  = wrapf(lon2 - poi_lon + rot_at_launch, -PI, PI)
				sweep_target = sw1 if absf(sw1) < absf(sw2) else sw2
				sweep_sign   = sign(sweep_target)
			print("[INTERCEPT] pred_a=%.2f° target sweep=%.1f° lat=%.1f°" % [
				rad_to_deg(pred_a), rad_to_deg(sweep_target), rad_to_deg(lat_target)])

	# ── Rocket node ──────────────────────────────────────────────────────────────
	var rocket := Control.new()
	rocket.mouse_filter = Control.MOUSE_FILTER_STOP
	rocket.z_index      = 12
	rocket.custom_minimum_size = Vector2(16, 16)
	container.add_child(rocket)

	# Set initial position directly from POI screen pos — no formula conversion needed
	if poi != null and poi_layer != null and is_instance_valid(poi_layer):
		var poi_global: Vector2 = poi_layer.get_poi_screen_pos(poi.label)
		if poi_global != Vector2.ZERO:
			rocket.position = poi_global - container.get_global_rect().position

	# anim_d will be set after dict creation below; use Array wrapper for closure capture
	var anim_ref: Array[Dictionary] = []
	rocket.draw.connect(func() -> void:
		if anim_ref.is_empty():
			return
		var ad: Dictionary = anim_ref[0]
		var flame_a:      float = ad.get("flame_alpha", 1.0)
		var boosters_gone: bool = ad.get("boosters_spawned", false)
		var travel: Vector2 = ad.get("travel_dir", Vector2.UP)
		var exhaust_dir: Vector2 = -travel
		if flame_a > 0.01 and not boosters_gone:
			var e := exhaust_dir
			var b1 := (e * 4.0).floor()
			var b2 := (e * 7.0).floor()
			var b3 := (e * 10.0).floor()
			var hue: float = 0.45 + randf() * 0.25
			rocket.draw_rect(Rect2(b1, Vector2(2, 2)), Color(1.0, hue, 0.05, flame_a * 0.95))
			rocket.draw_rect(Rect2(b2, Vector2(2, 2)), Color(1.0, hue * 0.6, 0.02, flame_a * 0.55))
			rocket.draw_rect(Rect2(b3, Vector2(1, 1)), Color(1.0, 0.3, 0.0,  flame_a * 0.25))
		var col  := Color(1, 1, 1, 0.95)
		var p    := Vector2.ZERO
		var stype: String = ad.get("ship_type", "shuttle")
		if stype == "station":
			# Station: 3×3 core + solar panel wings (hidden until boosters gone)
			var core_col   := Color(0.85, 0.90, 1.0, 0.95)
			var panel_col  := Color(0.30, 0.60, 1.0, 0.90)
			rocket.draw_rect(Rect2(p + Vector2(-2, -2), Vector2(6, 6)), core_col)
			if boosters_gone:
				# Solar panels extend once boosters are dropped
				rocket.draw_rect(Rect2(p + Vector2(-8, 0), Vector2(6, 2)), panel_col)
				rocket.draw_rect(Rect2(p + Vector2( 4, 0), Vector2(6, 2)), panel_col)
		else:
			# Shuttle: slightly larger cross sprite
			if boosters_gone:
				rocket.draw_rect(Rect2(p + Vector2(-2, -2), Vector2(2, 2)), col)
				rocket.draw_rect(Rect2(p + Vector2( 2, -2), Vector2(2, 2)), col)
				rocket.draw_rect(Rect2(p,                   Vector2(2, 2)), col)
			else:
				rocket.draw_rect(Rect2(p,                   Vector2(2, 2)), col)
				rocket.draw_rect(Rect2(p + Vector2(-2,  0), Vector2(2, 2)), col)
				rocket.draw_rect(Rect2(p + Vector2( 2,  0), Vector2(2, 2)), col)
				rocket.draw_rect(Rect2(p + Vector2( 0, -2), Vector2(2, 2)), col)
				rocket.draw_rect(Rect2(p + Vector2( 0,  2), Vector2(2, 2)), col)
				# Extra pixel to make it feel slightly bigger than before
				rocket.draw_rect(Rect2(p + Vector2(-2, -2), Vector2(2, 2)), Color(col, 0.55))
				rocket.draw_rect(Rect2(p + Vector2( 2, -2), Vector2(2, 2)), Color(col, 0.55)))

	var lbl := Label.new()
	var eta_secs: int = int(ceil(launch_dur))
	lbl.text = "eta %02d:%02d" % [eta_secs / 60, eta_secs % 60]
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_orbitron(lbl, 7)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.88, 1.0, 0.80))
	lbl.position = Vector2(6, -5)
	rocket.add_child(lbl)

	var anim_d: Dictionary = {
		"rocket":          rocket,
		"container":       container,
		"center_local":    center_local,
		"planet_r_frac":   start_r / maxf(planet_r, 1.0),
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
		"launch_dur":      launch_dur,
		"eta_lbl":         lbl,
		"hover_active":    false,
		"on_complete":     on_complete,
		"sp_pm_key":       sp_pm_key,
		"ship_name":            ship_name,
		"ship_type":            ship_type,
		"ship_cargo":           ship_cargo,
		"destination_ship_id":  destination_ship_id,
		"transfer_dir":         transfer_dir,
		"transfer_resource":    transfer_resource,
		"transfer_amount":      transfer_amount,
		"auto_land":            auto_land,
		"mission_tasks":        mission_tasks,
		"station_district_poi": station_district_poi,
	}
	anim_ref.append(anim_d)
	_rocket_anims.append(anim_d)
	AudioManager.play("rocket", -4.0)

	# Make rocket clickable — show a lightweight launch info panel
	rocket.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	rocket.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
	rocket.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_show_launch_info_panel(anim_ref[0], container))

## Called every _process frame while any rocket animations are active.
func _tick_rocket_anim(delta: float) -> void:
	var done: Array[Dictionary] = []
	for d: Dictionary in _rocket_anims:
		var rocket: Control = d["rocket"]
		if not is_instance_valid(rocket):
			done.append(d)
			continue
		_tick_one_rocket(d, delta)
		if d.get("_finished", false):
			done.append(d)
	for d: Dictionary in done:
		_rocket_anims.erase(d)

func _tick_one_rocket(d: Dictionary, delta: float) -> void:
	var rocket: Control = d["rocket"]

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

	var LAUNCH_DUR: float = d["launch_dur"]

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
			var _eta_sec: int = int(ceil((1.0 - t) * LAUNCH_DUR))
			var _eta_lbl: Label = d.get("eta_lbl")
			if _eta_lbl != null and is_instance_valid(_eta_lbl):
				_eta_lbl.text = "eta %02d:%02d" % [_eta_sec / 60, _eta_sec % 60]

			# Speed profile: ease-in [0→0.5], then linear decel to CRUISE_FRAC of peak [0.5→1].
			# Normalized so curve reaches exactly 1.0 at t=1 (no stopping short).
			# CRUISE_FRAC = velocity at orbit entry as fraction of peak.
			const CRUISE_FRAC: float = 0.10
			const D: float = (1.0 + CRUISE_FRAC) * 0.5
			var curve: float
			if t <= 0.5:
				# Quadratic ease-in: slow initial ramp, constant acceleration feel.
				# Lower initial jerk than sine (28% of sine's initial acceleration).
				curve = 2.0 * t * t
			else:
				var u: float     = (t - 0.5) / 0.5
				var integ: float = u - u * u * (1.0 - CRUISE_FRAC) * 0.5
				curve = 0.5 + (integ / D) * 0.5
			d["anim_r"]      = lerpf(start_r, orbit_r, curve)
			d["lon_sweep"]   = d["sweep_target"] * curve
			d["lat_sweep"]   = (d["lat_target"] - d["poi_lat"]) * curve
			d["flame_alpha"] = clampf(1.0 - t / 0.5, 0.0, 1.0) if t < 0.5 else 0.0

			# Booster separation particles at peak speed (t crosses 0.5)
			if not d.get("boosters_spawned", false) and t >= 0.5:
				d["boosters_spawned"] = true
				var lon_deg_bp := rad_to_deg(d["poi_lon"] + d["lon_sweep"])
				var lat_deg_bp := rad_to_deg(d["poi_lat"] + d["lat_sweep"])
				poi_layer.spawn_floating_text(lon_deg_bp, lat_deg_bp, "Booster dropped!", Color(0.95, 0.45, 0.15), 11)
				
				d["booster_particles"] = []
				var rot_bp:  float   = planet_renderer.get_rotation_offset()
				var lon_bp:  float   = d["poi_lon"] + d["lon_sweep"] - rot_bp
				var lat_bp:  float   = d["poi_lat"] + d["lat_sweep"]
				# abs_lon = planet-fixed longitude (no rot offset), so particle co-rotates with planet.
				var abs_lon_bp: float = d["poi_lon"] + d["lon_sweep"]
				var r_bp:       float = d["anim_r"]
				var vel_dir: Vector2 = Vector2(
					cos(lon_bp)*cos(lat_bp)*d["sweep_target"],
					-cos(lat_bp)*(d["lat_target"]-d["poi_lat"])
				).normalized()
				var perp: Vector2 = Vector2(-vel_dir.y, vel_dir.x)
				var is_station: bool = d.get("ship_type", "shuttle") == "station"
				var booster_signs: Array = [1.0, -1.0, 0.0, 0.3] if is_station else [1.0, -1.0]
				for sp: float in booster_signs:
					# Backward + lateral spread so both boosters separate visibly
					var vel_px: Vector2 = (-vel_dir * 0.7 + perp * sp * 0.7).normalized() * 10.0
					var bp_angle: float = atan2(-vel_dir.y, -vel_dir.x)
					var bp_data: Dictionary = {
						"abs_lon": abs_lon_bp,
						"lat":     lat_bp,
						"vel_lon": vel_px.x / r_bp,
						"vel_lat": -vel_px.y / r_bp,
						"r":       r_bp,
						"angle":   bp_angle,
						"alpha":   1.0
					}
					var bp_node := Control.new()
					bp_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
					bp_node.z_index = 11
					bp_node.size    = Vector2(4, 4)
					d["container"].add_child(bp_node)
					bp_data["node"] = bp_node
					var bp_ref: Dictionary = bp_data
					bp_node.draw.connect(func() -> void:
						if bp_ref["alpha"] > 0.0:
							var a: float = bp_ref["angle"]
							bp_node.draw_set_transform(Vector2.ZERO, a, Vector2.ONE)
							bp_node.draw_rect(Rect2(Vector2(-3, -1), Vector2(6, 2)),
								Color(1.0, 1.0, 1.0, bp_ref["alpha"]))
							bp_node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE))
					d["booster_particles"].append(bp_data)

	# ── Tick booster particles ────────────────────────────────────────────────────
	if d.get("booster_particles") != null:
		var alive: Array = []
		var bp_rot:    float   = planet_renderer.get_rotation_offset()
		var bp_center: Vector2 = planet_renderer.global_position + planet_renderer.size * 0.5 \
			- d["container"].get_global_rect().position
		var decay: float = pow(0.85, delta * 60.0)
		for bp: Dictionary in d["booster_particles"]:
			bp["abs_lon"] += bp["vel_lon"] * delta
			bp["lat"]     += bp["vel_lat"] * delta
			bp["vel_lon"] *= decay
			bp["vel_lat"] *= decay
			bp["alpha"]   -= delta * 0.55
			if bp["alpha"] > 0.0:
				var lon_eff_bp: float = bp["abs_lon"] - bp_rot
				var lat_bp:     float = bp["lat"]
				var r_bp:       float = bp["r"]
				if bp.get("node") != null and is_instance_valid(bp["node"]):
					bp["node"].position = bp_center + Vector2(sin(lon_eff_bp)*cos(lat_bp), -sin(lat_bp)) * r_bp
					bp["node"].queue_redraw()
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
	var prev_rpos: Vector2 = d.get("prev_rocket_pos", center + offset)
	rocket.position = center + offset
	# Travel direction: from previous position to current (velocity vector)
	var travel_delta: Vector2 = rocket.position - prev_rpos
	if travel_delta.length() > 0.1:
		d["travel_dir"] = travel_delta.normalized()
	d["prev_rocket_pos"] = rocket.position

	# ── Occlusion: hide when behind planet ────────────────────────────────────────
	var depth: float = cos(lon_eff) * cos(lat)
	rocket.visible = not (depth < -0.05 and offset.length() < planet_r * 0.99)

	rocket.queue_redraw()

	# ── Hover tooltip ────────────────────────────────────────────────────────────
	var ctr2: Control = d["container"]
	var mp:   Vector2 = get_viewport().get_mouse_position()
	var rp:   Vector2 = ctr2.get_global_rect().position + rocket.position
	var near: bool    = mp.distance_to(rp) < 12.0
	if near and not d["hover_active"]:
		d["hover_active"] = true
		CursorManager.set_state(CursorManager.State.POINTER)
		TooltipManager.show_tip("Shuttle", "· launching to orbit")
	elif not near and d["hover_active"]:
		d["hover_active"] = false
		CursorManager.set_state(CursorManager.State.NORMAL)
		TooltipManager.hide_tip()

	if finished:
		_finish_rocket_anim(d)
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
func _finish_rocket_anim(d: Dictionary) -> void:
	var rocket: Control = d.get("rocket")
	var container: Control = d["container"]

	var rocket_screen_pos: Vector2 = Vector2.ZERO
	if rocket != null and is_instance_valid(rocket):
		rocket_screen_pos = rocket.position   # position relative to container
		rocket.queue_free()
	TooltipManager.hide_tip()
	CursorManager.set_state(CursorManager.State.NORMAL)

	var rot_now: float = planet_renderer.get_rotation_offset()
	var orbit_r: float = planet_renderer._planet_radius_px * 1.06

	# Compute insertion point analytically at t=1 — avoids reading rocket.position
	# from the previous frame (t<1) which caused a visible teleport on spawn.
	var lon_final: float = d["poi_lon"] + d["sweep_target"] - rot_now
	var lat_final: float = d["lat_target"]
	
	var lon_deg := rad_to_deg(d["poi_lon"] + d["sweep_target"])
	var lat_deg := rad_to_deg(lat_final)
	if d.get("destination_ship_id", "") == "":
		poi_layer.spawn_floating_text(lon_deg, lat_deg, "Orbit reached!", Color(0.15, 0.95, 0.45), 11)
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

	# Full 3-DOF insertion that places the ship EXACTLY at the rocket's screen endpoint:
	#
	#   orbit_angle a = atan2(-ty, tx)
	#   orbit_inc  i  such that sin(a)*sin(i) = ty  →  i = arcsin(ty/sin(a))
	#   orbit_node n  such that cos(a)*cos(rot)+ty*sin(rot) = tx  →  solve for rot = rot_now+n
	#
	# _project uses rot = _planet_rotation + orbit_node, so at spawn (planet_rotation=rot_now)
	# we need rot_eff = rot_now + orbit_node → orbit_node = rot_eff - rot_now.
	orbit_angle = atan2(-ty, tx)

	var sin_a: float = sin(orbit_angle)
	if abs(sin_a) > 0.001:
		orbit_inc = asin(clampf(ty / sin_a, -1.0, 1.0))
	else:
		orbit_inc = 0.0

	# Solve: cos(a)*cos(rot) + sin(a)*cos(inc)*sin(rot) = tx
	# Two solutions exist; pick the one where rz < 0 (ship on front/visible side of planet).
	# rz = -cos(a)*sin(rot) + sin(a)*cos(inc)*cos(rot)
	var ca: float  = cos(orbit_angle)
	var sc: float  = sin(orbit_angle) * cos(orbit_inc)
	var mag: float = sqrt(ca * ca + sc * sc)
	if mag > 0.001:
		var phi: float  = atan2(sc, ca)
		var arc: float  = acos(clampf(tx / mag, -1.0, 1.0))
		var re1: float  = rot_now + wrapf(phi + arc - rot_now, -PI, PI)
		var re2: float  = rot_now + wrapf(phi - arc - rot_now, -PI, PI)
		var rz1: float  = -ca * sin(re1) + sc * cos(re1)
		var rz2: float  = -ca * sin(re2) + sc * cos(re2)
		# Prefer the solution that puts ship on front side (rz < 0)
		var use_re: float
		if rz1 < 0.0 and rz2 >= 0.0:
			use_re = re1
		elif rz2 < 0.0 and rz1 >= 0.0:
			use_re = re2
		else:
			# Both same side — pick smallest orbit_node deviation
			var n1: float = wrapf(re1 - rot_now, -PI, PI)
			var n2: float = wrapf(re2 - rot_now, -PI, PI)
			use_re = re1 if absf(n1) < absf(n2) else re2
		orbit_node = wrapf(use_re - rot_now, -PI, PI)
	else:
		orbit_node = 0.0

	var rdx_raw: float   = d["sweep_sign"] * cos(lat_final)
	var eff_rot2: float  = rot_now + orbit_node
	var p1: Vector2      = _orbital_project_2d(orbit_angle,         orbit_inc, orbit_r, eff_rot2)
	var p2: Vector2      = _orbital_project_2d(orbit_angle + 0.002, orbit_inc, orbit_r, eff_rot2)
	var speed_sign: float = 1.0 if (p2 - p1).x * rdx_raw >= 0.0 else -1.0
	const _CF: float = 0.10
	const _D:  float = (1.0 + _CF) * 0.5
	var _LD: float = d["launch_dur"]
	var exit_rate: float = (_CF / _D) * (2.0 / _LD)

	var st_poi: POIData = d.get("station_district_poi", null)
	if st_poi != null:
		# Orbital district — update POI with analytically computed orbit params
		st_poi.orbit_angle       = orbit_angle
		st_poi.orbit_inclination = orbit_inc
		st_poi.orbit_node        = orbit_node
		st_poi.orbit_speed       = speed_sign * exit_rate
		st_poi.orbit_radius      = 1.06
		if _orbital_layer != null and is_instance_valid(_orbital_layer):
			_spawn_station_deploy_poi(st_poi, d["container"])
			_orbital_layer.queue_redraw()
	else:
		var ship := ShipManager.launch(d["planet_seed"], d.get("ship_name", "Pioneer"))
		ship.ship_type         = d.get("ship_type", "shuttle")
		ship.cargo             = d.get("ship_cargo", {})
		ship.orbit_angle       = orbit_angle
		ship.orbit_inclination = orbit_inc
		ship.orbit_node        = orbit_node
		ship.orbit_speed       = speed_sign * exit_rate
		if _orbital_layer != null and is_instance_valid(_orbital_layer):
			_orbital_layer.queue_redraw()
		var tasks: Array = d.get("mission_tasks", [])
		ship.mission_tasks      = tasks.duplicate(true)
		ship.mission_task_index = 0
		var _skip_types: Array = ["move_orbit", "pick_planet"]
		while ship.mission_task_index < ship.mission_tasks.size() \
				and _skip_types.has((ship.mission_tasks[ship.mission_task_index] as Dictionary).get("type", "")):
			ship.mission_task_index += 1
		_advance_mission(ship)
		if ship.ship_type == "station" and _orbital_layer != null:
			_spawn_station_deploy(ship, d["container"])

	var cb: Callable = d["on_complete"]
	d["_finished"] = true
	cb.call()

# ── Station deploy animation ──────────────────────────────────────────────────

## Spawns a short solar-panel deploy animation at the ship's initial orbit position.
func _spawn_station_deploy(ship: ShipData, container: Control) -> void:
	if _orbital_layer == null or not is_instance_valid(_orbital_layer):
		return
	var ctrl := Control.new()
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl.z_index = 10
	container.add_child(ctrl)
	var da: Dictionary = {
		"ship":     ship,
		"ctrl":     ctrl,
		"t":        0.0,
		"duration": 2.2,
	}
	ctrl.draw.connect(func() -> void:
		var sv2 := _orbital_layer._project(ship, ship.orbit_angle)
		if _orbital_layer._is_occluded(sv2):
			return
		var origin: Vector2 = _orbital_layer._planet_center + Vector2(sv2.x, sv2.y)
		var p2 := ctrl.get_global_transform().affine_inverse() * origin
		var t2: float = da.get("t", 0.0)
		var progress: float = clampf(t2 / da["duration"], 0.0, 1.0)
		var ease_p: float   = ease(progress, -2.0)  # ease-out
		var alpha: float    = 1.0 - clampf((progress - 0.7) / 0.3, 0.0, 1.0)

		# Core remains visible throughout
		var core_col := Color(0.85, 0.90, 1.0, alpha)
		ctrl.draw_rect(Rect2(p2 + Vector2(-2,-2), Vector2(6,6)), core_col)

		# Panels extend outward as progress increases
		var panel_ext: float = ease_p * 10.0
		var panel_col2 := Color(0.30, 0.60, 1.0, alpha * 0.85)
		if panel_ext > 1.0:
			ctrl.draw_rect(Rect2(p2 + Vector2(-4.0 - panel_ext, 0), Vector2(panel_ext, 2)), panel_col2)
			ctrl.draw_rect(Rect2(p2 + Vector2( 4.0,             0), Vector2(panel_ext, 2)), panel_col2)

		# Deploy sparks: 4 pixels scatter outward then fade
		if progress < 0.5:
			var spark_alpha: float = 1.0 - (progress / 0.5)
			var spark_col := Color(0.70, 0.88, 1.0, spark_alpha * alpha)
			var spread: float = ease_p * 14.0
			for i in 4:
				var angle: float = (i / 4.0) * TAU + progress * PI
				var sp: Vector2  = p2 + Vector2(cos(angle), sin(angle)) * spread
				ctrl.draw_rect(Rect2(sp, Vector2(2, 2)), spark_col)
		)

	_deploy_anims.append(da)

func _spawn_station_deploy_poi(poi: POIData, container: Control) -> void:
	if _orbital_layer == null or not is_instance_valid(_orbital_layer):
		return
	var ctrl := Control.new()
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctrl.z_index = 10
	container.add_child(ctrl)
	var da: Dictionary = {
		"poi":      poi,
		"ctrl":     ctrl,
		"t":        0.0,
		"duration": 2.2,
	}
	ctrl.draw.connect(func() -> void:
		var sv2 := _orbital_layer._project_poi(poi, poi.orbit_angle)
		if _orbital_layer._is_occluded_r(sv2):
			return
		var origin: Vector2 = _orbital_layer._planet_center + Vector2(sv2.x, sv2.y)
		var p2 := ctrl.get_global_transform().affine_inverse() * origin
		var t2: float = da.get("t", 0.0)
		var progress: float = clampf(t2 / da["duration"], 0.0, 1.0)
		var ease_p: float   = ease(progress, -2.0)
		var alpha: float    = 1.0 - clampf((progress - 0.7) / 0.3, 0.0, 1.0)
		var core_col := Color(0.85, 0.90, 1.0, alpha)
		ctrl.draw_rect(Rect2(p2 + Vector2(-2,-2), Vector2(6,6)), core_col)
		var panel_ext: float = ease_p * 10.0
		var panel_col2 := Color(0.30, 0.60, 1.0, alpha * 0.85)
		if panel_ext > 1.0:
			ctrl.draw_rect(Rect2(p2 + Vector2(-4.0 - panel_ext, 0), Vector2(panel_ext, 2)), panel_col2)
			ctrl.draw_rect(Rect2(p2 + Vector2( 4.0,             0), Vector2(panel_ext, 2)), panel_col2)
		if progress < 0.5:
			var spark_alpha: float = 1.0 - (progress / 0.5)
			var spark_col := Color(0.70, 0.88, 1.0, spark_alpha * alpha)
			var spread: float = ease_p * 14.0
			for i in 4:
				var angle: float = (i / 4.0) * TAU + progress * PI
				var sp: Vector2  = p2 + Vector2(cos(angle), sin(angle)) * spread
				ctrl.draw_rect(Rect2(sp, Vector2(2, 2)), spark_col)
		)
	_deploy_anims.append(da)

func _tick_deploy_anims(delta: float) -> void:
	var done: Array[Dictionary] = []
	for da: Dictionary in _deploy_anims:
		da["t"] = da["t"] + delta
		var ctrl2: Control = da.get("ctrl", null)
		if not is_instance_valid(ctrl2):
			done.append(da)
			continue
		if da["t"] >= da["duration"]:
			ctrl2.queue_free()
			done.append(da)
		else:
			ctrl2.queue_redraw()
	for da: Dictionary in done:
		_deploy_anims.erase(da)

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
	var hud: Node = get_tree().root.find_child("HUDManager", true, false)
	var credits_h: float = 38.0
	var science_h: float = 38.0
	if hud != null:
		var cp = hud.get("credits_panel")
		if cp != null and is_instance_valid(cp as Node):
			var real_h: float = (cp as Control).size.y
			if real_h > 4.0:
				credits_h = real_h
		var sp = hud.get("science_panel")
		if sp != null and is_instance_valid(sp as Node):
			var real_h: float = (sp as Control).size.y
			if real_h > 4.0:
				science_h = real_h
	var hud_bar_h: float = maxf(credits_h, science_h)
	tc.offset_bottom = -(12.0 + hud_bar_h + 8.0)

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
	AudioManager.play("building_done", 2.0)

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
		return _build_spaceport_card(def, pm_key, pp, poi, entry)

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
	var b_lv: int = entry.get("level", 1)
	if count > 1 or b_lv > 1:
		var cnt_lbl := Label.new()
		var txt := ""
		if count > 1: txt += "×%d" % count
		if b_lv > 1: txt += (" " if txt != "" else "") + "Lv%d" % b_lv
		cnt_lbl.text = txt
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
	var out_val := def.output_amount * ProductionManager.get_building_level_mult(b_lv)
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
			icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
				CursorManager.set_state(CursorManager.State.POINTER)
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

	var tip_str := def.description + "\n\n"
	if not paused:
		if def.output_type != BuildingDef.OutputType.NONE:
			tip_str += "Output: " + out_text + "\n"
		var tip_etick := def.energy_per_tick
		if tip_etick != 0.0:
			if tip_etick > 0.0:
				tip_etick *= ProductionManager.get_building_level_mult(b_lv)
				if def.building_id == "solar_panel":
					tip_etick *= get_node("/root/SkillTree").get_solar_mult()
			else:
				tip_etick *= ProductionManager.get_building_consume_mult(b_lv)
				tip_etick *= get_node("/root/SkillTree").get_energy_consume_mult()
			tip_str += "Energy: " + ("+" if tip_etick > 0 else "") + "%.0f ⚡\n" % (tip_etick * count)
		if def.input_amount > 0.0:
			tip_str += "Consumes: %.0f units\n" % (def.input_amount * count)
			
	card.mouse_entered.connect(func() -> void:
		AudioManager.play("poi_hover")
		TooltipManager.show_tip(def.display_name, tip_str.strip_edges()))
	card.mouse_exited.connect(func() -> void:
		TooltipManager.hide_tip())
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
	add_btn.text     = "+"
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
		CursorManager.set_state(CursorManager.State.POINTER)
		TooltipManager.show_tip("+ " + def.display_name, tip_add))
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
	rem_btn.text = "-"
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
		CursorManager.set_state(CursorManager.State.POINTER)
		TooltipManager.show_tip("-", tip_rem))
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

## Spaceport card — phase-driven: idle → configuring → preparing → launch_ready → cooldown.
func _build_spaceport_card(def: BuildingDef, pm_key: String,
		pp: PlanetProgress, poi: POIData, entry: Dictionary = {}) -> PanelContainer:

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_panel_style())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",  10)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    7)
	margin.add_theme_constant_override("margin_bottom", 7)
	card.add_child(margin)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 2)
	margin.add_child(left_vbox)

	var name_lbl := Label.new()
	name_lbl.text = def.display_name
	_apply_orbitron(name_lbl, 10)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_vbox.add_child(name_lbl)

	var status_lbl := Label.new()
	status_lbl.text = "Operational"
	_apply_orbitron(status_lbl, 8)
	status_lbl.add_theme_color_override("font_color", Color(0.50, 0.65, 0.90, 0.70))
	status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_vbox.add_child(status_lbl)

	_bar_meta[pm_key] = {
		"planet_seed": pp.planet_seed,
	}

	return card

## Register all built-in mission task types into MissionTaskRegistry.
func _register_mission_tasks() -> void:
	# ── Move to Orbit ────────────────────────────────────────────────────────
	var move_orbit := MissionTaskDef.new()
	move_orbit.task_type       = "move_orbit"
	move_orbit.display_name    = "Move to Orbit"
	move_orbit.required_status = ["on_pad"]
	move_orbit.produced_status = "in_orbit"
	move_orbit.build_params_ui = func(_c: Control, _e: Dictionary, _oc: Callable, _ctx: Dictionary) -> void: pass
	move_orbit.estimate_cost   = func(_e: Dictionary, _ctx: Dictionary) -> float: return 80.0
	MissionTaskRegistry.register(move_orbit)

	# ── Move to Station ──────────────────────────────────────────────────────
	var move_station := MissionTaskDef.new()
	move_station.task_type       = "move_station"
	move_station.display_name    = "Move to Station"
	move_station.required_status = ["on_pad", "in_orbit"]
	move_station.produced_status = "at_station:{target_id}"
	move_station.build_params_ui = func(cont: Control, e: Dictionary, on_change: Callable, ctx: Dictionary) -> void:
		for ch in cont.get_children(): ch.queue_free()

		var rebuild_ms := func() -> void:
			move_station.build_params_ui.call(cont, e, on_change, ctx)

		var ms_vbox := VBoxContainer.new()
		ms_vbox.add_theme_constant_override("separation", 3)
		ms_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ms_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cont.add_child(ms_vbox)

		# ── Station selector ──────────────────────────────────────────────────────
		var stations: Array = (ctx.get("ships", []) as Array).filter(
			func(s: ShipData) -> bool: return s.ship_type == "station")
		var st_row := HBoxContainer.new()
		st_row.add_theme_constant_override("separation", 6)
		ms_vbox.add_child(st_row)

		if stations.is_empty():
			var lbl := Label.new()
			lbl.text = "No stations in orbit"
			lbl.add_theme_font_size_override("font_size", 7)
			lbl.add_theme_color_override("font_color", Color(0.70, 0.35, 0.35, 0.75))
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			st_row.add_child(lbl)
		else:
			if not e.has("target_id") or not stations.any(func(s: ShipData) -> bool: return s.ship_id == e["target_id"]):
				e["target_id"] = (stations[0] as ShipData).ship_id
				on_change.call()
			for st: ShipData in stations:
				var cap_st: ShipData = st
				var btn := Button.new()
				btn.text = st.ship_name
				btn.add_theme_font_size_override("font_size", 7)
				var is_sel: bool = e.get("target_id", "") == st.ship_id
				var bs := StyleBoxFlat.new()
				bs.bg_color     = Color(0.06, 0.24, 0.18, 0.95) if is_sel else Color(0.05, 0.07, 0.15, 0.75)
				bs.border_color = Color(0.20, 0.78, 0.52, 0.75) if is_sel else Color(0.28, 0.42, 0.35, 0.35)
				bs.set_border_width_all(1); bs.set_corner_radius_all(3)
				bs.content_margin_left = 6; bs.content_margin_right = 6
				bs.content_margin_top = 3; bs.content_margin_bottom = 3
				btn.add_theme_stylebox_override("normal", bs)
				btn.add_theme_stylebox_override("hover",  bs)
				btn.add_theme_color_override("font_color",
					Color(0.35, 0.95, 0.65) if is_sel else Color(0.45, 0.62, 0.55))
				btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
				btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
				btn.pressed.connect(func() -> void:
					e["target_id"] = cap_st.ship_id
					on_change.call()
					rebuild_ms.call())
				st_row.add_child(btn)

		# ── Rendezvous actions ────────────────────────────────────────────────────
		if not e.has("rendezvous_tasks"):
			e["rendezvous_tasks"] = []
		var rdv_tasks: Array = e["rendezvous_tasks"]

		# Simulate cargo through rdv tasks in order so each task sees correct remaining capacity.
		var rdv_base: Dictionary = ctx.get("state_before", {"status": "on_pad", "cargo": {}})
		var rdv_running_cargo: Dictionary = (rdv_base.get("cargo", {}) as Dictionary).duplicate()

		for i: int in rdv_tasks.size():
			var rt: Dictionary = rdv_tasks[i]
			var rdef: MissionTaskDef = MissionTaskRegistry.get_def(rt.get("type", ""))
			var rt_row := HBoxContainer.new()
			rt_row.add_theme_constant_override("separation", 4)
			ms_vbox.add_child(rt_row)
			var rt_lbl := Label.new()
			rt_lbl.text = rdef.display_name if rdef != null else rt.get("type", "?")
			rt_lbl.add_theme_font_size_override("font_size", 7)
			rt_lbl.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
			rt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rt_lbl.custom_minimum_size = Vector2(44, 0)
			rt_row.add_child(rt_lbl)
			var rt_params := HBoxContainer.new()
			rt_params.add_theme_constant_override("separation", 3)
			rt_params.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if rdef != null and rdef.build_params_ui.is_valid():
				var rdv_ctx: Dictionary = ctx.duplicate()
				rdv_ctx["rdv_station_id"] = e.get("target_id", "")
				rdv_ctx["state_before"] = {"status": rdv_base.get("status", "on_pad"), "cargo": rdv_running_cargo.duplicate()}
				rdef.build_params_ui.call(rt_params, rt, func() -> void: on_change.call(), rdv_ctx)
			rt_row.add_child(rt_params)
			# Advance running cargo for the next rdv task
			match rt.get("type", ""):
				"deliver":
					for k: String in (rt.get("cargo", {}) as Dictionary).keys():
						rdv_running_cargo[k] = maxi(0, rdv_running_cargo.get(k, 0) - int((rt["cargo"] as Dictionary)[k]))
				"pickup":
					var res: String = rt.get("transfer_resource", "")
					if res != "": rdv_running_cargo[res] = rdv_running_cargo.get(res, 0) + int(rt.get("transfer_amount", 0))
			var cap_i: int = i
			var del_btn := Button.new()
			del_btn.text = "×"
			del_btn.add_theme_font_size_override("font_size", 9)
			var dbs := StyleBoxFlat.new()
			dbs.bg_color = Color(0,0,0,0); dbs.set_border_width_all(0)
			dbs.content_margin_left = 4; dbs.content_margin_right = 4
			del_btn.add_theme_stylebox_override("normal", dbs)
			del_btn.add_theme_stylebox_override("hover",  dbs)
			del_btn.add_theme_color_override("font_color", Color(0.70, 0.35, 0.35, 0.80))
			del_btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
			del_btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
			del_btn.pressed.connect(func() -> void:
				rdv_tasks.remove_at(cap_i)
				on_change.call()
				rebuild_ms.call())
			rt_row.add_child(del_btn)

		# "+" Add — driven by the registry, same DI pattern as the main chain.
		# Any task registered with required_status containing "__nested__" shows up here.
		var add_btn := _make_mission_add_btn("+ Add")
		var cap_pv      := self   # explicit capture — nested lambdas can lose implicit self
		var cap_rdv     := rdv_tasks
		var cap_ctx     := ctx
		var cap_btn     := add_btn
		var cap_overlay := ctx.get("_overlay", null) as Control
		add_btn.pressed.connect(func() -> void:
			var stype: String = (cap_ctx.get("entry", {}) as Dictionary).get("ship_type", "shuttle")
			cap_pv._show_rdv_add_popup(cap_btn, cap_rdv, stype, cap_overlay, func() -> void:
				on_change.call()
				rebuild_ms.call()))
		ms_vbox.add_child(add_btn)
	move_station.estimate_cost = func(_e: Dictionary, _ctx: Dictionary) -> float: return 40.0
	MissionTaskRegistry.register(move_station)

	# ── Pick Up (nested inside Move to Station only — not shown in main chain) ──
	var pickup := MissionTaskDef.new()
	pickup.task_type       = "pickup"
	pickup.display_name    = "Take"
	pickup.required_status = ["__nested__"]
	pickup.produced_status = ""  # stays at same station
	pickup.build_params_ui = func(cont: Control, e: Dictionary, on_change: Callable, ctx: Dictionary) -> void:
		var res_id: String = e.get("transfer_resource", "")
		var rdv_id: String = ctx.get("rdv_station_id", "")
		var pp_ref: PlanetProgress = ctx.get("pp", null)
		var state_before: Dictionary = ctx.get("state_before", {"cargo": {}})
		var ship_cap: int = _sp_cargo_capacity((ctx.get("entry", {}) as Dictionary).get("ship_type", "shuttle"))
		var cargo_weight: int = 0
		for v in (state_before.get("cargo", {}) as Dictionary).values(): cargo_weight += int(v)
		var remaining_cap: int = maxi(0, ship_cap - cargo_weight)
		var station_has: int = remaining_cap
		if rdv_id != "" and pp_ref != null:
			for s: ShipData in ShipManager.ships_for(pp_ref.planet_seed):
				if s.ship_id == rdv_id:
					station_has = int(s.cargo.get(res_id, 0))
					break
		var max_amt: int = mini(station_has, remaining_cap)
		_build_res_icon_ui(cont, e, "transfer_resource", res_id,
			e.get("transfer_amount", 10), max_amt, on_change, ctx, null, rdv_id, {})
	pickup.estimate_cost = func(_e: Dictionary, _ctx: Dictionary) -> float: return 0.0
	MissionTaskRegistry.register(pickup)

	# ── Deliver (nested inside Move to Station only) ─────────────────────────
	var deliver := MissionTaskDef.new()
	deliver.task_type       = "deliver"
	deliver.display_name    = "Drop"
	deliver.required_status = ["__nested__"]
	deliver.produced_status = ""  # stays at same station
	deliver.build_params_ui = func(cont: Control, e: Dictionary, on_change: Callable, ctx: Dictionary) -> void:
		var cargo: Dictionary = e.get("cargo", {})
		var res_id: String = cargo.keys()[0] if not cargo.is_empty() else ""
		# state_before = what the ship carries at rendezvous = valid resources to drop
		var state_before: Dictionary = ctx.get("state_before", {"cargo": {}})
		var cargo_at_rdv: Dictionary = state_before.get("cargo", {})
		var max_amt: int = int(cargo_at_rdv.get(res_id, 0)) if res_id != "" else 0
		_build_res_icon_ui(cont, e, "_deliver_res", res_id,
			cargo.get(res_id, 10), max_amt, on_change, ctx, ctx.get("pp", null), "", cargo_at_rdv)
	deliver.estimate_cost = func(_e: Dictionary, _ctx: Dictionary) -> float: return 0.0
	MissionTaskRegistry.register(deliver)

	# ── Take from Planet Storage (top-level, loads resource at launch) ───────
	var pick_planet := MissionTaskDef.new()
	pick_planet.task_type       = "pick_planet"
	pick_planet.display_name    = "Take"
	pick_planet.required_status = ["on_pad"]
	pick_planet.produced_status = "on_pad"  # stays on pad, cargo loaded at launch
	pick_planet.build_params_ui = func(cont: Control, e: Dictionary, on_change: Callable, ctx: Dictionary) -> void:
		var pp_ref: PlanetProgress = ctx.get("pp", null)
		var cargo: Dictionary = e.get("cargo", {})
		var res_id: String = cargo.keys()[0] if not cargo.is_empty() else ""
		# state_before = cargo already loaded by prior pick_planet tasks
		var state_before: Dictionary = ctx.get("state_before", {"cargo": {}})
		var ship_cap: int = _sp_cargo_capacity((ctx.get("entry", {}) as Dictionary).get("ship_type", "shuttle"))
		var cargo_weight: int = 0
		for v in (state_before.get("cargo", {}) as Dictionary).values(): cargo_weight += int(v)
		var remaining_cap: int = maxi(0, ship_cap - cargo_weight)
		var stored_amt: int = int(GameState.global_resources.get(res_id, 0)) if res_id != "" else remaining_cap
		var max_amt: int = mini(stored_amt, remaining_cap)
		_build_res_icon_ui(cont, e, "_pick_planet_res", res_id,
			cargo.get(res_id, 10), max_amt, on_change, ctx, pp_ref)
	pick_planet.estimate_cost = func(_e: Dictionary, _ctx: Dictionary) -> float: return 0.0
	MissionTaskRegistry.register(pick_planet)

	# ── Land ─────────────────────────────────────────────────────────────────
	var land := MissionTaskDef.new()
	land.task_type       = "land"
	land.display_name    = "Land"
	land.required_status = ["in_orbit", "at_station:*"]
	land.produced_status = "on_pad"
	land.build_params_ui = func(_c: Control, _e: Dictionary, _oc: Callable, _ctx: Dictionary) -> void: pass
	land.estimate_cost   = func(_e: Dictionary, _ctx: Dictionary) -> float: return 30.0
	MissionTaskRegistry.register(land)

	# ── Deploy (Station only) ─────────────────────────────────────────────────
	var deploy := MissionTaskDef.new()
	deploy.task_type            = "deploy"
	deploy.display_name         = "Deploy Station"
	deploy.required_status      = ["in_orbit"]
	deploy.required_ship_types  = ["station"]
	deploy.produced_status      = "on_pad"  # mission ends — station stays in orbit
	deploy.build_params_ui = func(_c: Control, _e: Dictionary, _oc: Callable, _ctx: Dictionary) -> void: pass
	deploy.estimate_cost   = func(_e: Dictionary, _ctx: Dictionary) -> float: return 0.0
	MissionTaskRegistry.register(deploy)

## Builds the icon + slider row used by Take/Drop task params.
## cont       — parent HBox to add widgets into
## e          — task entry dict (mutated on change)
## res_key    — which popup key to use ("transfer_resource"|"_deliver_res"|"_pick_planet_res")
## amt_getter — Callable() → int   : reads current amount from e
## amt_setter — Callable(int)      : writes amount back to e
## max_amt    — upper bound for slider (0 = use ship capacity)
## on_change  — rebuild signal
## ctx        — task context (pp, _overlay, etc.)
## popup_pp   — PlanetProgress for popup filtering (planet storage)
## rdv_station_id, pending_cargo — forwarded to resource popup
func _build_res_icon_ui(cont: Control, e: Dictionary,
		res_key: String, res_id: String, amount: int, max_amt: int,
		on_change: Callable, ctx: Dictionary, popup_pp: PlanetProgress,
		rdv_station_id: String = "", pending_cargo: Dictionary = {}) -> void:
	var rd: ResourceData = GameState.known_resources.get(res_id, null) if res_id != "" else null
	var ph: Control = ctx.get("_overlay", null) as Control
	# For station-cargo filtering (pickup task), rdv_pp is the planet pp from ctx
	var rdv_pp: PlanetProgress = ctx.get("pp", null) if rdv_station_id != "" else null

	if rd == null:
		# No resource selected yet — show a plain "Pick…" button
		var pick_btn := _make_mission_add_btn("Pick resource…")
		pick_btn.pressed.connect(func() -> void:
			_mission_show_resource_popup(cont, e, res_key, on_change,
				popup_pp, ph, rdv_station_id, rdv_pp, pending_cargo, ctx))
		cont.add_child(pick_btn)
		return

	# ── Icon chip (clickable to reopen picker) ─────────────────────
	var icon_card := _mineral_grid_card(rd, 0.0, false)
	icon_card.custom_minimum_size = Vector2(30, 30)
	icon_card.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	icon_card.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
	icon_card.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton): return
		var mev := ev as InputEventMouseButton
		if not (mev.pressed and mev.button_index == MOUSE_BUTTON_LEFT): return
		_mission_show_resource_popup(cont, e, res_key, on_change,
			popup_pp, ph, rdv_station_id, rdv_pp, pending_cargo, ctx))
	cont.add_child(icon_card)

	# ── Slider ─────────────────────────────────────────────────────
	var real_max: int = maxi(1, max_amt)
	var slider := HSlider.new()
	slider.min_value  = 1
	slider.max_value  = real_max
	slider.step       = 1
	slider.value      = clamp(amount, 1, real_max)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size   = Vector2(70, 0)
	slider.add_theme_constant_override("grabber_offset", 0)
	cont.add_child(slider)

	# ── Amount label ───────────────────────────────────────────────
	var val_lbl := Label.new()
	val_lbl.text = str(int(slider.value))
	val_lbl.custom_minimum_size = Vector2(22, 0)
	val_lbl.add_theme_font_size_override("font_size", 7)
	val_lbl.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cont.add_child(val_lbl)

	slider.value_changed.connect(func(v: float) -> void:
		val_lbl.text = str(int(v))
		# Write back via res_key convention
		if res_key == "transfer_resource":
			e["transfer_amount"] = int(v)
		else:  # _deliver_res or _pick_planet_res → cargo dict
			e["cargo"] = {res_id: int(v)}
		on_change.call())

## Show a resource picker popup for mission task params.
## Small styled "+" button used to add nested (DI) mission sub-tasks.
func _make_mission_add_btn(label_text: String) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.add_theme_font_size_override("font_size", 7)
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.05, 0.10, 0.22, 0.80)
	bs.border_color = Color(0.20, 0.38, 0.65, 0.40)
	bs.set_border_width_all(1); bs.set_corner_radius_all(3)
	bs.content_margin_left = 5; bs.content_margin_right = 5
	bs.content_margin_top = 2; bs.content_margin_bottom = 2
	btn.add_theme_stylebox_override("normal", bs)
	btn.add_theme_stylebox_override("hover",  bs)
	btn.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
	return btn

## Dependency-injected dropdown for "On Rendezvous" sub-tasks — lists whatever
## is registered in MissionTaskRegistry under the "__nested__" status, same as
## the top-level chain's "+ Add Step" dropdown.
func _show_rdv_add_popup(anchor: Control, rdv_tasks: Array, ship_type: String,
		popup_host: Control, on_added: Callable) -> void:
	var available: Array = MissionTaskRegistry.get_available("__nested__", ship_type)
	if available.is_empty():
		return
	var popup := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.09, 0.18, 0.97)
	ps.border_color = Color(0.25, 0.45, 0.80, 0.55)
	ps.set_border_width_all(1); ps.set_corner_radius_all(5)
	ps.content_margin_left = 6; ps.content_margin_right = 6
	ps.content_margin_top = 6; ps.content_margin_bottom = 6
	popup.add_theme_stylebox_override("panel", ps)
	popup.z_index = 215

	var pvbox := VBoxContainer.new()
	pvbox.add_theme_constant_override("separation", 3)
	popup.add_child(pvbox)

	var rdv_backdrop: Control = null

	for def: MissionTaskDef in available:
		var cap_def: MissionTaskDef = def
		var btn := Button.new()
		btn.text = cap_def.display_name
		btn.add_theme_font_size_override("font_size", 7)
		var ibs := StyleBoxFlat.new()
		ibs.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		ibs.set_border_width_all(0)
		ibs.content_margin_left = 6; ibs.content_margin_right = 6
		ibs.content_margin_top = 3; ibs.content_margin_bottom = 3
		btn.add_theme_stylebox_override("normal", ibs)
		var ibs_h := ibs.duplicate()
		(ibs_h as StyleBoxFlat).bg_color = Color(0.12, 0.22, 0.45, 0.80)
		btn.add_theme_stylebox_override("hover", ibs_h)
		btn.add_theme_color_override("font_color", Color(0.80, 0.92, 1.0))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
		btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
		btn.pressed.connect(func() -> void:
			rdv_tasks.append({"type": cap_def.task_type})
			if is_instance_valid(rdv_backdrop): rdv_backdrop.queue_free()
			popup.queue_free()
			on_added.call())
		pvbox.add_child(btn)

	# Add popup inside the Mission Builder overlay so mouse_filter doesn't block it.
	# Fall back to viewport if overlay not available (e.g. called outside builder).
	var anchor_global: Vector2 = anchor.get_global_rect().position + Vector2(0, anchor.size.y + 2)
	if popup_host != null and is_instance_valid(popup_host):
		var backdrop := ColorRect.new()
		backdrop.color = Color(0, 0, 0, 0)
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		backdrop.z_index = 214
		backdrop.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
				if is_instance_valid(backdrop): backdrop.queue_free()
				if is_instance_valid(popup): popup.queue_free())
		popup_host.add_child(backdrop)
		rdv_backdrop = backdrop
		popup.position = anchor_global - popup_host.get_global_rect().position
		popup_host.add_child(popup)
	else:
		popup.global_position = anchor_global
		anchor.get_viewport().add_child(popup)

func _mission_show_resource_popup(anchor: Control, entry: Dictionary,
		key: String, on_change: Callable, pp_ref: PlanetProgress = null,
		popup_host: Control = null, rdv_station_id: String = "",
		rdv_pp: PlanetProgress = null, pending_cargo: Dictionary = {},
		orig_ctx: Dictionary = {}) -> void:
	var popup := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.09, 0.18, 0.97)
	ps.border_color = Color(0.25, 0.45, 0.80, 0.55)
	ps.set_border_width_all(1); ps.set_corner_radius_all(5)
	ps.content_margin_left = 8; ps.content_margin_right = 8
	ps.content_margin_top = 8; ps.content_margin_bottom = 8
	popup.add_theme_stylebox_override("panel", ps)
	popup.z_index = 220
	popup.custom_minimum_size = Vector2(220, 0)

	var pvbox := VBoxContainer.new()
	pvbox.add_theme_constant_override("separation", 6)
	popup.add_child(pvbox)

	# Resolve resource list — priority: pending_cargo > station filter > pp storage > all known
	var resources: Array = []
	if not pending_cargo.is_empty():
		resources = pending_cargo.keys()
	elif rdv_station_id != "" and rdv_pp != null:
		for s: ShipData in ShipManager.ships_for(rdv_pp.planet_seed):
			if s.ship_id == rdv_station_id:
				resources = s.cargo.keys()
				break
		if resources.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = "Station has no cargo"
			empty_lbl.add_theme_font_size_override("font_size", 7)
			empty_lbl.add_theme_color_override("font_color", Color(0.70, 0.40, 0.40, 0.75))
			pvbox.add_child(empty_lbl)
	elif pp_ref != null:
		resources = GameState.global_resources.keys()
		resources = resources.filter(func(r: String) -> bool: return GameState.global_resources.get(r, 0.0) >= 1.0)
	else:
		resources = GameState.known_resources.keys()

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 5)
	flow.add_theme_constant_override("v_separation", 5)
	pvbox.add_child(flow)

	for res_id: String in resources:
		var cap_id: String = res_id
		var rd: ResourceData = GameState.known_resources.get(res_id, null)
		if rd == null: continue

		var card := _mineral_grid_card(rd, 0.0, false)
		card.custom_minimum_size = Vector2(44, 44)
		# mouse_filter is STOP from _mineral_grid_card; gui_input gives us click detection.
		card.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
		card.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if not (ev is InputEventMouseButton): return
			var mev := ev as InputEventMouseButton
			if not (mev.pressed and mev.button_index == MOUSE_BUTTON_LEFT): return
			if key == "_deliver_res" or key == "_pick_planet_res":
				var old_cargo: Dictionary = entry.get("cargo", {})
				var old_amt: int = old_cargo.values()[0] if not old_cargo.is_empty() else 10
				entry["cargo"] = {cap_id: old_amt}
			else:
				entry[key] = cap_id
			on_change.call()
			popup.queue_free()
			if not is_instance_valid(anchor): return
			for ch in anchor.get_children(): ch.queue_free()
			var def: MissionTaskDef = MissionTaskRegistry.get_def(entry.get("type", ""))
			if def != null and def.build_params_ui.is_valid():
				# Preserve full orig_ctx (includes state_before) so capacity limits survive rebuild
				var rebuild_ctx: Dictionary = orig_ctx.duplicate() if not orig_ctx.is_empty() \
					else ({} if popup_host == null else {"_overlay": popup_host})
				if popup_host != null and not rebuild_ctx.has("_overlay"):
					rebuild_ctx["_overlay"] = popup_host
				def.build_params_ui.call(anchor, entry, on_change, rebuild_ctx))
		flow.add_child(card)

	# Host popup inside the builder overlay so it's above the mouse_filter=STOP overlay.
	var anchor_global: Vector2 = anchor.get_global_rect().position + Vector2(0, 18)
	if popup_host != null and is_instance_valid(popup_host):
		popup.position = anchor_global - popup_host.get_global_rect().position
		popup_host.add_child(popup)
	else:
		popup.global_position = anchor_global
		anchor.get_viewport().add_child(popup)

## Convert a task chain into legacy entry fields for the launch system.
func _sp_apply_mission_to_entry(entry: Dictionary, tasks: Array) -> void:
	entry.erase("destination_ship_id")
	entry.erase("transfer_dir")
	entry.erase("transfer_resource")
	entry.erase("transfer_amount")
	entry.erase("cargo")
	for t: Dictionary in tasks:
		match t.get("type", ""):
			"pick_planet":
				# Merge into cargo so multiple take tasks stack
				var cur: Dictionary = entry.get("cargo", {})
				for k: String in (t.get("cargo", {}) as Dictionary).keys():
					cur[k] = (t["cargo"] as Dictionary)[k]
				entry["cargo"] = cur
			"move_station":
				entry["destination_ship_id"] = t.get("target_id", "")
				# Apply first pickup/deliver from rendezvous_tasks as legacy fields
				for rt: Dictionary in t.get("rendezvous_tasks", []):
					match rt.get("type", ""):
						"pickup":
							entry["transfer_dir"]      = "pickup"
							entry["transfer_resource"] = rt.get("transfer_resource", "")
							entry["transfer_amount"]   = rt.get("transfer_amount", 0)
						"deliver":
							entry["transfer_dir"] = "deliver"
							entry["cargo"]        = rt.get("cargo", {}).duplicate()
			"deploy":
				pass
			"land":
				entry["auto_land"] = true

## Execute the current task in ship.mission_tasks at mission_task_index.
func _advance_mission(ship: ShipData) -> void:
	if _orbital_layer == null or not is_instance_valid(_orbital_layer):
		return
	if ship.mission_task_index >= ship.mission_tasks.size():
		return
	var task: Dictionary = ship.mission_tasks[ship.mission_task_index]
	var ttype: String = task.get("type", "")
	match ttype:
		"move_station":
			var dest_id: String = task.get("target_id", "")
			if dest_id != "":
				ship.rendezvous_base_speed = ship.orbit_speed
				ship.rendezvous_target_id  = dest_id
				_orbital_layer._reveal[ship.ship_id] = {"progress": 1.0, "spawn_angle": ship.orbit_angle}
		"land":
			_orbital_layer._reveal[ship.ship_id] = {"progress": 1.0, "spawn_angle": ship.orbit_angle}
			_orbital_layer.start_landing(ship)
		"deploy":
			pass

## Helper: generate next ship name (Pioneer I, II, …) based on how many ships exist.
func _sp_next_ship_name(planet_seed: int) -> String:
	var n := ShipManager.ships_for(planet_seed).size() + 1
	return "Pioneer " + _roman_numeral(n)

func _roman_numeral(n: int) -> String:
	const NUMS := [1000,900,500,400,100,90,50,40,10,9,5,4,1]
	const SYMS := ["M","CM","D","CD","C","XC","L","XL","X","IX","V","IV","I"]
	var r := ""
	for i in NUMS.size():
		while n >= NUMS[i]:
			r += SYMS[i]
			n -= NUMS[i]
	return r

## Shared button style for spaceport actions.
func _sp_btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left   = 10
	s.content_margin_right  = 10
	s.content_margin_top    = 4
	s.content_margin_bottom = 4
	return s

## Idle phase: "Prep Launch" button.
func _sp_build_idle(left_vbox: VBoxContainer, hbox: HBoxContainer,
		_def: BuildingDef, pm_key: String, pp: PlanetProgress,
		_poi: POIData, entry: Dictionary, rebuild_sp: Callable) -> void:
	# Auto-dequeue: if missions are queued, start the next one immediately
	var queue: Array = entry.get("mission_queue", [])
	if not queue.is_empty():
		var item: Dictionary = queue.pop_front()
		entry["mission_queue"] = queue
		entry["ship_name"]     = item.get("ship_name", _sp_next_ship_name(pp.planet_seed))
		entry["ship_type"]     = item.get("ship_type", "shuttle")
		entry["mission_tasks"] = item.get("mission_tasks", [])
		entry["repeat_cycle"]  = item.get("repeat_cycle", 0.0)
		_sp_apply_mission_to_entry(entry, entry["mission_tasks"])
		var used_q: int = _sp_cargo_used(entry)
		var cost_q: int = _sp_launch_cost(entry.get("ship_type", "shuttle"), used_q)
		if GameState.spend_credits(float(cost_q)):
			var src_pq := GameState.get_planet(pp.planet_seed)
			if src_pq != null:
				for res_q: String in entry.get("cargo", {}):
					GameState.global_resources[res_q] = maxf(0.0,
						GameState.global_resources.get(res_q, 0.0) - float(entry["cargo"][res_q]))
			entry["phase"] = "preparing"
			entry["effective_duration"] = 20.0
			entry.erase("cooldown_only")
			_bar_meta.erase(pm_key)
			if ProductionManager.is_user_paused(pm_key):
				ProductionManager.toggle_user_pause(pm_key)
			rebuild_sp.call()
		return

	var status := Label.new()
	status.text = "Ready"
	_apply_orbitron(status, 8)
	status.add_theme_color_override("font_color", Color(0.35, 0.90, 0.55, 0.80))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_vbox.add_child(status)

	var btn := Button.new()
	btn.text = "Prepare Mission"
	_apply_orbitron(btn, 9)
	var bs := _sp_btn_style(Color(0.10, 0.22, 0.42, 0.90), Color(0.30, 0.60, 1.0, 0.75))
	btn.add_theme_stylebox_override("normal",  bs)
	btn.add_theme_stylebox_override("hover",   bs)
	btn.add_theme_stylebox_override("pressed", bs)
	btn.add_theme_color_override("font_color", Color(0.60, 0.88, 1.0))
	btn.custom_minimum_size = Vector2(100, 0)
	btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
	btn.pressed.connect(func() -> void:
		# Toggle: if already open, close it
		if _mission_builder_overlay != null and is_instance_valid(_mission_builder_overlay):
			_mission_builder_overlay.queue_free()
			_mission_builder_overlay = null
			return
		if not entry.has("ship_name"):
			entry["ship_name"] = _sp_next_ship_name(pp.planet_seed)
		entry["ship_type"] = "shuttle"
		var planet_cont: Control = planet_renderer.get_parent()
		var ctx := {
			"planet_seed":   pp.planet_seed,
			"pp":            pp,
			"font":          _orbitron,
			"entry":         entry,
			"ships":         ShipManager.ships_for(pp.planet_seed),
			"default_name":  entry.get("ship_name", _sp_next_ship_name(pp.planet_seed)),
			"initial_tasks": entry.get("mission_tasks", []),
			"on_close":      func() -> void: _mission_builder_overlay = null,
		}
		_mission_builder_overlay = MissionBuilderPanel.open(planet_cont, ctx, func(tasks: Array, repeat: float) -> void:
			_mission_builder_overlay = null

			entry["mission_tasks"] = tasks
			entry["repeat_cycle"]  = repeat
			_sp_apply_mission_to_entry(entry, tasks)
			# Go straight to preparing
			var used: int = _sp_cargo_used(entry)
			var launch_cost: int = _sp_launch_cost(entry.get("ship_type", "shuttle"), used)
			if not GameState.spend_credits(float(launch_cost)):
				return
			var src_pp := GameState.get_planet(pp.planet_seed)
			if src_pp != null:
				for res_id2: String in entry.get("cargo", {}):
					GameState.global_resources[res_id2] = maxf(0.0, GameState.global_resources.get(res_id2, 0.0) - float(entry["cargo"][res_id2]))
			entry["phase"] = "preparing"
			entry["effective_duration"] = 20.0
			entry.erase("cooldown_only")
			_bar_meta.erase(pm_key)
			if ProductionManager.is_user_paused(pm_key):
				ProductionManager.toggle_user_pause(pm_key)
			rebuild_sp.call()))
	hbox.add_child(btn)

## Config phase: ship name + type selection.
func _sp_cargo_capacity(ship_type: String) -> int:
	match ship_type:
		"station":      return 60
		"heavy_hauler": return 60
		"hauler":       return 20
		_:              return 5   # shuttle

func _sp_cargo_used(entry: Dictionary) -> int:
	var total := 0
	for res_id: String in entry.get("cargo", {}):
		var rd: ResourceData = GameState.known_resources.get(res_id, null)
		if rd != null:
			total += (rd.rarity + rd.tier - 1) * int(entry["cargo"][res_id])
	return total

func _sp_launch_cost(ship_type: String, cargo_weight: int) -> int:
	match ship_type:
		"station":      return 5000
		"heavy_hauler": return 2500 + cargo_weight * 5
		"hauler":       return 800 + cargo_weight * 8
		_:              return 200 + cargo_weight * 12  # shuttle

func _sp_build_config(_card: PanelContainer, stack: Control, left_vbox: VBoxContainer,
		_hbox: HBoxContainer, _def: BuildingDef, pm_key: String, pp: PlanetProgress,
		_poi: POIData, entry: Dictionary, rebuild_sp: Callable) -> void:

	# Station limit check — 1 station per planet (SkillTree-upgradeable later)
	var station_count: int = 0
	for s: ShipData in ShipManager.ships_for(pp.planet_seed):
		if s.ship_type == "station":
			station_count += 1
	var station_locked: bool = station_count >= 1
	if station_locked and entry.get("ship_type", "shuttle") == "station":
		entry["ship_type"] = "shuttle"

	# Config height: title + name + type + cargo header + one grid row (56px) + bottom row
	stack.custom_minimum_size = Vector2(0, 230)
	left_vbox.add_theme_constant_override("separation", 4)

	var sub := Label.new()
	sub.text = "Mission Configuration"
	_apply_orbitron(sub, 7)
	sub.add_theme_color_override("font_color", Color(0.50, 0.70, 1.0, 0.60))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_vbox.add_child(sub)

	# ── Name row ────────────────────────────────────────────────────────────
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	left_vbox.add_child(name_row)

	var name_hint := Label.new()
	name_hint.text = "Name"
	_apply_orbitron(name_hint, 7)
	name_hint.add_theme_color_override("font_color", Color(0.50, 0.62, 0.82, 0.70))
	name_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_hint.custom_minimum_size = Vector2(32, 0)
	name_row.add_child(name_hint)

	var name_edit := LineEdit.new()
	name_edit.text = entry.get("ship_name", _sp_next_ship_name(pp.planet_seed))
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", 9)
	name_edit.add_theme_color_override("font_color", Color(0.90, 0.92, 1.0))
	var le_style := StyleBoxFlat.new()
	le_style.bg_color = Color(0.07, 0.09, 0.18, 0.90)
	le_style.border_color = Color(0.22, 0.42, 0.75, 0.55)
	le_style.set_border_width_all(1); le_style.set_corner_radius_all(3)
	le_style.content_margin_left = 5; le_style.content_margin_right = 5
	le_style.content_margin_top = 3; le_style.content_margin_bottom = 3
	name_edit.add_theme_stylebox_override("normal", le_style)
	name_edit.add_theme_stylebox_override("focus",  le_style)
	name_edit.text_changed.connect(func(t: String) -> void: entry["ship_name"] = t)
	name_row.add_child(name_edit)

	# ── Type row ─────────────────────────────────────────────────────────────
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 5)
	left_vbox.add_child(type_row)

	var type_hint := Label.new()
	type_hint.text = "Type"
	_apply_orbitron(type_hint, 7)
	type_hint.add_theme_color_override("font_color", Color(0.50, 0.62, 0.82, 0.70))
	type_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_hint.custom_minimum_size = Vector2(32, 0)
	type_row.add_child(type_hint)

	const SP_SHIP_LABELS: Dictionary = {
		"shuttle": "Shuttle", "hauler": "Hauler",
		"heavy_hauler": "Heavy", "station": "Station",
	}
	for ttype in ["shuttle", "hauler", "heavy_hauler", "station"]:
		var tb := Button.new()
		tb.text = SP_SHIP_LABELS.get(ttype, ttype.capitalize())
		_apply_orbitron(tb, 7)
		var is_sel: bool = (entry.get("ship_type", "shuttle") == ttype)
		var is_locked: bool = (ttype == "station" and station_locked)
		var tbg := Color(0.10, 0.28, 0.50, 0.95) if is_sel else Color(0.05, 0.07, 0.15, 0.75)
		if is_locked:
			tbg = Color(0.08, 0.08, 0.12, 0.60)
		var tbs := _sp_btn_style(tbg, Color(0.35, 0.65, 1.0, 0.65 if is_sel else (0.15 if is_locked else 0.28)))
		tb.add_theme_stylebox_override("normal", tbs)
		tb.add_theme_stylebox_override("hover",  tbs)
		tb.add_theme_color_override("font_color",
			Color(0.75, 0.92, 1.0) if is_sel else (Color(0.35, 0.38, 0.45) if is_locked else Color(0.45, 0.60, 0.80)))
		tb.custom_minimum_size = Vector2(54, 0)
		tb.disabled = is_locked
		if not is_locked:
			tb.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
			tb.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
		var cap_t: String = ttype
		tb.pressed.connect(func() -> void:
			entry["ship_type"] = cap_t
			entry.erase("cargo")  # reset cargo when type changes (capacity differs)
			rebuild_sp.call())
		type_row.add_child(tb)

	if station_locked:
		var lock_lbl := Label.new()
		lock_lbl.text = " (limit 1)"
		_apply_orbitron(lock_lbl, 6)
		lock_lbl.add_theme_color_override("font_color", Color(0.55, 0.35, 0.35, 0.70))
		lock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		type_row.add_child(lock_lbl)

	# ── Station vs Shuttle split ──────────────────────────────────────────────
	var is_station_type: bool = entry.get("ship_type", "shuttle") == "station"

	var sep := HSeparator.new()
	left_vbox.add_child(sep)

	if is_station_type:
		var no_cargo_lbl := Label.new()
		no_cargo_lbl.text = "No cargo — station is too heavy"
		_apply_orbitron(no_cargo_lbl, 6)
		no_cargo_lbl.add_theme_color_override("font_color", Color(0.50, 0.55, 0.70, 0.55))
		no_cargo_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		left_vbox.add_child(no_cargo_lbl)

	# ── Shuttle: mission summary + Plan Mission button ────────────────────────
	if not is_station_type:
		var orbit_stations: Array[ShipData] = []
		for s: ShipData in ShipManager.ships_for(pp.planet_seed):
			if s.ship_type == "station":
				orbit_stations.append(s)

		# Show current mission summary if tasks were already planned
		var mission_tasks: Array = entry.get("mission_tasks", [])
		if not mission_tasks.is_empty():
			var sum_lbl := Label.new()
			sum_lbl.text = "%d step mission planned" % mission_tasks.size()
			_apply_orbitron(sum_lbl, 7)
			sum_lbl.add_theme_color_override("font_color", Color(0.50, 0.88, 0.65))
			sum_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			left_vbox.add_child(sum_lbl)
		else:
			var hint_lbl := Label.new()
			hint_lbl.text = "No mission — plan one below"
			_apply_orbitron(hint_lbl, 6)
			hint_lbl.add_theme_color_override("font_color", Color(0.55, 0.45, 0.45, 0.70))
			hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			left_vbox.add_child(hint_lbl)

		var plan_btn := Button.new()
		plan_btn.text = "Plan Mission" if mission_tasks.is_empty() else "Edit Mission"
		_apply_orbitron(plan_btn, 7)
		var pbs := _sp_btn_style(Color(0.06, 0.14, 0.30, 0.90), Color(0.28, 0.52, 0.90, 0.55))
		plan_btn.add_theme_stylebox_override("normal", pbs)
		plan_btn.add_theme_stylebox_override("hover",  pbs)
		plan_btn.add_theme_color_override("font_color", Color(0.60, 0.82, 1.0))
		plan_btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
		plan_btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
		plan_btn.pressed.connect(func() -> void:
			var planet_cont: Control = planet_renderer.get_parent()
			var ctx := {
				"planet_seed": pp.planet_seed,
				"pp": pp,
				"font": _orbitron,
				"entry": entry,
				"ships": ShipManager.ships_for(pp.planet_seed),
			}
			if not mission_tasks.is_empty():
				ctx["initial_tasks"] = mission_tasks.duplicate(true)
			MissionBuilderPanel.open(planet_cont, ctx, func(tasks: Array, repeat: float) -> void:
				entry["mission_tasks"] = tasks
				entry["repeat_cycle"]  = repeat
				_sp_apply_mission_to_entry(entry, tasks)
				rebuild_sp.call()))
		left_vbox.add_child(plan_btn)

	# ── Bottom row: cost / Cancel / Start Prep ──────────────────────────────
	var used: int   = _sp_cargo_used(entry)
	var launch_cost: int = _sp_launch_cost(entry.get("ship_type", "shuttle"), used)
	var has_mission: bool = is_station_type or not entry.get("mission_tasks", []).is_empty()
	var can_afford: bool  = GameState.credits >= launch_cost and has_mission

	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 6)
	left_vbox.add_child(bottom_row)

	var cost_lbl := Label.new()
	cost_lbl.text = "%d cr" % launch_cost
	_apply_orbitron(cost_lbl, 7)
	cost_lbl.add_theme_color_override("font_color",
		Color(0.90, 0.75, 0.20) if can_afford else Color(0.90, 0.35, 0.25))
	cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_row.add_child(cost_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_row.add_child(spacer)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	_apply_orbitron(cancel_btn, 7)
	var cbs := _sp_btn_style(Color(0.10, 0.07, 0.12, 0.80), Color(0.48, 0.28, 0.32, 0.55))
	cancel_btn.add_theme_stylebox_override("normal", cbs)
	cancel_btn.add_theme_stylebox_override("hover",  cbs)
	cancel_btn.add_theme_color_override("font_color", Color(0.80, 0.50, 0.52))
	cancel_btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	cancel_btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
	cancel_btn.pressed.connect(func() -> void:
		entry["phase"] = "idle"
		entry.erase("cargo")
		entry.erase("mission_tasks")
		_bar_meta.erase(pm_key)
		rebuild_sp.call())
	bottom_row.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = "Start Prep"
	_apply_orbitron(confirm_btn, 7)
	var fbs_col := Color(0.07, 0.28, 0.16, 0.92) if can_afford else Color(0.18, 0.12, 0.12, 0.85)
	var fbs_brd := Color(0.22, 0.78, 0.42, 0.75) if can_afford else Color(0.48, 0.28, 0.28, 0.55)
	var fbs := _sp_btn_style(fbs_col, fbs_brd)
	confirm_btn.add_theme_stylebox_override("normal", fbs)
	confirm_btn.add_theme_stylebox_override("hover",  fbs)
	confirm_btn.add_theme_color_override("font_color",
		Color(0.35, 0.95, 0.58) if can_afford else Color(0.55, 0.40, 0.40))
	confirm_btn.disabled = not can_afford
	confirm_btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	confirm_btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
	confirm_btn.pressed.connect(func() -> void:
		if not GameState.spend_credits(float(launch_cost)):
			return
		# Deduct cargo from planet storage upfront
		var src_pp2 := GameState.get_planet(pp.planet_seed)
		if src_pp2 != null:
			for res_id2: String in entry.get("cargo", {}):
				GameState.global_resources[res_id2] = maxf(0.0,
					GameState.global_resources.get(res_id2, 0.0) - float(entry["cargo"][res_id2]))
		entry["phase"] = "preparing"
		entry["effective_duration"] = 20.0
		entry.erase("cooldown_only")
		_bar_meta.erase(pm_key)
		if ProductionManager.is_user_paused(pm_key):
			ProductionManager.toggle_user_pause(pm_key)
		rebuild_sp.call())
	bottom_row.add_child(confirm_btn)

## Progress bar view — used for both "preparing" and "cooldown" phases.
func _sp_build_progress(left_vbox: VBoxContainer, hbox: HBoxContainer,
		pm_key: String, pp: PlanetProgress, entry: Dictionary,
		label_text: String, lbl_color: Color, rebuild_sp: Callable) -> void:
	var ship_desc: String = entry.get("ship_name", "")
	if ship_desc == "":
		ship_desc = label_text
	else:
		ship_desc = label_text + "  " + ship_desc

	var status := Label.new()
	status.text = ship_desc
	_apply_orbitron(status, 8)
	status.add_theme_color_override("font_color", lbl_color)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_vbox.add_child(status)

	# Queue display
	var queue: Array = entry.get("mission_queue", [])
	if not queue.is_empty():
		var q_lbl := Label.new()
		q_lbl.text = "Queue: %d" % queue.size()
		_apply_orbitron(q_lbl, 7)
		q_lbl.add_theme_color_override("font_color", Color(0.70, 0.75, 1.0, 0.75))
		q_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		left_vbox.add_child(q_lbl)
		for i: int in mini(queue.size(), 2):
			var qi: Dictionary = queue[i]
			var qi_lbl := Label.new()
			qi_lbl.text = "  %d. %s" % [i + 1, qi.get("ship_name", "–")]
			_apply_orbitron(qi_lbl, 6)
			qi_lbl.add_theme_color_override("font_color", Color(0.55, 0.65, 0.85, 0.60))
			qi_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			left_vbox.add_child(qi_lbl)

	# Queue Mission button
	var q_btn := Button.new()
	q_btn.text = "Queue Mission"
	_apply_orbitron(q_btn, 7)
	var qbs := _sp_btn_style(Color(0.08, 0.16, 0.32, 0.85), Color(0.25, 0.45, 0.80, 0.55))
	q_btn.add_theme_stylebox_override("normal", qbs)
	q_btn.add_theme_stylebox_override("hover",  qbs)
	q_btn.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
	q_btn.custom_minimum_size = Vector2(100, 0)
	q_btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	q_btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
	var cap_pm := pm_key; var cap_pp := pp; var cap_entry := entry; var cap_rebuild := rebuild_sp
	q_btn.pressed.connect(func() -> void:
		if _mission_builder_overlay != null and is_instance_valid(_mission_builder_overlay):
			_mission_builder_overlay.queue_free()
			_mission_builder_overlay = null
			return
		var qe: Dictionary = {"ship_name": _sp_next_ship_name(cap_pp.planet_seed), "ship_type": "shuttle"}
		var planet_cont: Control = planet_renderer.get_parent()
		var qctx := {
			"planet_seed": cap_pp.planet_seed, "pp": cap_pp, "font": _orbitron,
			"entry": qe, "ships": ShipManager.ships_for(cap_pp.planet_seed),
			"default_name": qe["ship_name"],
			"on_close": func() -> void: _mission_builder_overlay = null,
		}
		_mission_builder_overlay = MissionBuilderPanel.open(planet_cont, qctx, func(tasks: Array, repeat: float) -> void:
			_mission_builder_overlay = null
			var mq: Array = cap_entry.get("mission_queue", [])
			mq.append({
				"ship_name": qe.get("ship_name", ""),
				"ship_type": qe.get("ship_type", "shuttle"),
				"mission_tasks": tasks,
				"repeat_cycle": repeat,
			})
			cap_entry["mission_queue"] = mq
			cap_rebuild.call()))
	hbox.add_child(q_btn)

## Launch-ready phase: prominent Launch button.
func _sp_build_launch_ready(left_vbox: VBoxContainer, hbox: HBoxContainer,
		_def: BuildingDef, pm_key: String, pp: PlanetProgress,
		poi: POIData, entry: Dictionary, rebuild_sp: Callable) -> void:
	var ship_name: String = entry.get("ship_name", "Shuttle")
	var status := Label.new()
	status.text = ship_name + " — ready"
	_apply_orbitron(status, 8)
	status.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55, 0.90))
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_vbox.add_child(status)

	var btn := Button.new()
	btn.text = "Launch ▶"
	_apply_orbitron(btn, 9)
	var bs := _sp_btn_style(Color(0.08, 0.30, 0.15, 0.92), Color(0.20, 0.85, 0.40, 0.80))
	btn.add_theme_stylebox_override("normal",  bs)
	btn.add_theme_stylebox_override("hover",   bs)
	btn.add_theme_stylebox_override("pressed", bs)
	btn.add_theme_color_override("font_color", Color(0.35, 0.98, 0.55))
	btn.custom_minimum_size = Vector2(90, 0)
	btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))

	var cap_pp := pp; var cap_poi := poi; var cap_entry := entry
	btn.pressed.connect(func() -> void:
		btn.text     = "Launching…"
		btn.disabled = true
		cap_pp.has_spaceport = true
		cap_entry["cooldown_only"] = true
		cap_entry["phase"] = "cooldown"
		cap_entry.erase("effective_duration")
		_bar_meta.erase(pm_key)  # erase before toggle so signal handler ignores this key
		if ProductionManager.is_user_paused(pm_key):
			ProductionManager.toggle_user_pause(pm_key)
		rebuild_sp.call()
		_play_rocket_animation(cap_pp.planet_seed, cap_poi, func() -> void: pass,
			pm_key,
			cap_entry.get("ship_name", "Pioneer"),
			cap_entry.get("ship_type", "shuttle"),
			cap_entry.get("cargo", {}),
			cap_entry.get("destination_ship_id", ""),
			cap_entry.get("transfer_dir", ""),
			cap_entry.get("transfer_resource", ""),
			cap_entry.get("transfer_amount", 0),
			cap_entry.get("auto_land", false),
			cap_entry.get("mission_tasks", [])))

	hbox.add_child(btn)

## Cargo resource selector popup — floating panel over the container.
func _sp_show_cargo_popup(entry: Dictionary, pp: PlanetProgress,
		capacity: int, rebuild_sp: Callable) -> void:
	var container: Control = planet_renderer.get_parent()

	# Full-screen overlay
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 60
	container.add_child(overlay)

	var close_popup := func() -> void:
		overlay.queue_free()
		rebuild_sp.call()

	# Dim backdrop
	var dim := Control.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.draw.connect(func() -> void:
		dim.draw_rect(Rect2(Vector2.ZERO, dim.size), Color(0, 0, 0, 0.55)))
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			close_popup.call())
	overlay.add_child(dim)

	# Popup panel
	var panel := PanelContainer.new()
	panel.z_index = 1
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.08, 0.16, 0.97)
	ps.border_color = Color(0.28, 0.48, 0.80, 0.70)
	ps.set_border_width_all(1); ps.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", ps)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Center in overlay
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(260, 0)
	overlay.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",  10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top",    8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	# Header
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 6)
	vbox.add_child(hdr)

	var hdr_lbl := Label.new()
	hdr_lbl.text = "Add Cargo"
	_apply_orbitron(hdr_lbl, 9)
	hdr_lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	hdr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr.add_child(hdr_lbl)

	var used_now := _sp_cargo_used(entry)
	var cap_lbl2 := Label.new()
	cap_lbl2.text = "%d/%d" % [used_now, capacity]
	_apply_orbitron(cap_lbl2, 7)
	cap_lbl2.add_theme_color_override("font_color",
		Color(0.40, 0.88, 0.55) if used_now <= capacity else Color(0.95, 0.38, 0.28))
	cap_lbl2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr.add_child(cap_lbl2)

	vbox.add_child(HSeparator.new())

	# ── Build resource list ───────────────────────────────────────────────────
	var available_res2: Array[String] = []
	for res_id: String in GameState.global_resources:
		if GameState.global_resources.get(res_id, 0.0) >= 1.0 and GameState.known_resources.has(res_id):
			available_res2.append(res_id)
	available_res2.sort()

	if available_res2.is_empty():
		var no_res := Label.new()
		no_res.text = "No resources in storage"
		_apply_orbitron(no_res, 7)
		no_res.add_theme_color_override("font_color", Color(0.45, 0.50, 0.60, 0.65))
		no_res.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(no_res)
	else:
		# ── Dropdown ─────────────────────────────────────────────────────────
		var dropdown := OptionButton.new()
		_apply_orbitron(dropdown, 8)
		dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(dropdown)

		for res_id: String in available_res2:
			var rd: ResourceData = GameState.known_resources[res_id]
			var avail_amt: int = int(GameState.global_resources.get(res_id, 0.0))
			var wt: int = rd.rarity + rd.tier - 1
			dropdown.add_item("%s  (stk:%d  %dw)" % [rd.unique_name, avail_amt, wt])

		# ── Slider row ───────────────────────────────────────────────────────
		var slider_row := HBoxContainer.new()
		slider_row.add_theme_constant_override("separation", 8)
		vbox.add_child(slider_row)

		var slider := HSlider.new()
		slider.min_value = 1
		slider.max_value = 1
		slider.step      = 1
		slider.value     = 1
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider_row.add_child(slider)

		var amt_lbl3 := Label.new()
		amt_lbl3.text = "1"
		_apply_orbitron(amt_lbl3, 9)
		amt_lbl3.custom_minimum_size = Vector2(28, 0)
		amt_lbl3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amt_lbl3.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
		amt_lbl3.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slider_row.add_child(amt_lbl3)

		# Info label: stock + weight per unit
		var info_lbl := Label.new()
		info_lbl.text = ""
		_apply_orbitron(info_lbl, 6)
		info_lbl.add_theme_color_override("font_color", Color(0.42, 0.55, 0.75, 0.65))
		info_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(info_lbl)

		# Shared state for callbacks
		var sel_res_id: Array[String] = [available_res2[0]]

		var update_slider := func() -> void:
			var rid: String = sel_res_id[0]
			var rd2: ResourceData = GameState.known_resources.get(rid, null)
			if rd2 == null: return
			var avail2: int  = int(GameState.global_resources.get(rid, 0.0))
			var wt2: int     = rd2.rarity + rd2.tier - 1
			var cur_used2: int = _sp_cargo_used(entry)
			var free_weight: int = capacity - cur_used2
			var max_by_weight: int = free_weight / max(wt2, 1)
			var max_amt: int = min(avail2, max_by_weight)
			slider.max_value = max(max_amt, 1)
			slider.value     = clamp(slider.value, 1, slider.max_value)
			amt_lbl3.text = str(int(slider.value))
			info_lbl.text = "stock: %d  |  %dw/unit  |  fits: %d" % [avail2, wt2, max_amt]
			slider.editable = max_amt >= 1

		dropdown.item_selected.connect(func(idx: int) -> void:
			sel_res_id[0] = available_res2[idx]
			update_slider.call())

		slider.value_changed.connect(func(_v: float) -> void:
			amt_lbl3.text = str(int(slider.value)))

		update_slider.call()

		vbox.add_child(HSeparator.new())

		# ── Add button ────────────────────────────────────────────────────────
		var add_btn2 := Button.new()
		add_btn2.text = "Add to Cargo"
		_apply_orbitron(add_btn2, 8)
		var abs3 := _sp_btn_style(Color(0.07, 0.22, 0.12, 0.92), Color(0.22, 0.72, 0.38, 0.75))
		add_btn2.add_theme_stylebox_override("normal", abs3)
		add_btn2.add_theme_stylebox_override("hover",  abs3)
		add_btn2.add_theme_color_override("font_color", Color(0.38, 0.95, 0.55))
		add_btn2.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
		add_btn2.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
		add_btn2.pressed.connect(func() -> void:
			var rid2: String = sel_res_id[0]
			var amt2: int    = int(slider.value)
			if not entry.has("cargo"): entry["cargo"] = {}
			entry["cargo"][rid2] = entry["cargo"].get(rid2, 0) + amt2
			close_popup.call())
		vbox.add_child(add_btn2)

## Pick-up resource selector popup — picks what the shuttle should collect from the station.
func _sp_show_pickup_popup(entry: Dictionary, pp: PlanetProgress, rebuild_sp: Callable) -> void:
	var container: Control = planet_renderer.get_parent()
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 60
	container.add_child(overlay)
	var close_popup := func() -> void:
		overlay.queue_free()
		rebuild_sp.call()
	var dim := Control.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.draw.connect(func() -> void:
		dim.draw_rect(Rect2(Vector2.ZERO, dim.size), Color(0, 0, 0, 0.55)))
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			close_popup.call())
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.z_index = 1
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.10, 0.08, 0.97)
	ps.border_color = Color(0.22, 0.70, 0.38, 0.70)
	ps.set_border_width_all(1); ps.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", ps)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(240, 0)
	overlay.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",  10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top",    8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)
	var hdr_lbl := Label.new()
	hdr_lbl.text = "Pick Up From Station"
	_apply_orbitron(hdr_lbl, 9)
	hdr_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.70))
	hdr_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hdr_lbl)
	vbox.add_child(HSeparator.new())
	# Resource list — show all known resources
	var all_res: Array[String] = []
	for res_id: String in GameState.known_resources:
		all_res.append(res_id)
	all_res.sort()
	if all_res.is_empty():
		var no_lbl := Label.new()
		no_lbl.text = "No known resources"
		_apply_orbitron(no_lbl, 7)
		no_lbl.add_theme_color_override("font_color", Color(0.45, 0.50, 0.45, 0.65))
		no_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(no_lbl)
	else:
		var dropdown := OptionButton.new()
		_apply_orbitron(dropdown, 8)
		dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(dropdown)
		for res_id: String in all_res:
			var rd: ResourceData = GameState.known_resources[res_id]
			dropdown.add_item(rd.unique_name)
		var sel_res: Array[String] = [all_res[0]]
		var cur_res: String = entry.get("transfer_resource", "")
		if cur_res != "" and cur_res in all_res:
			dropdown.selected = all_res.find(cur_res)
			sel_res[0] = cur_res
		var slider_row := HBoxContainer.new()
		slider_row.add_theme_constant_override("separation", 8)
		vbox.add_child(slider_row)
		var slider := HSlider.new()
		slider.min_value = 1
		slider.max_value = _sp_cargo_capacity("shuttle")
		slider.step = 1
		slider.value = entry.get("transfer_amount", _sp_cargo_capacity("shuttle"))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider_row.add_child(slider)
		var amt_lbl := Label.new()
		amt_lbl.text = str(int(slider.value))
		_apply_orbitron(amt_lbl, 9)
		amt_lbl.custom_minimum_size = Vector2(28, 0)
		amt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amt_lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
		amt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slider_row.add_child(amt_lbl)
		slider.value_changed.connect(func(v: float) -> void: amt_lbl.text = str(int(v)))
		dropdown.item_selected.connect(func(idx: int) -> void: sel_res[0] = all_res[idx])
		var confirm_btn := Button.new()
		confirm_btn.text = "Set Pick-up"
		_apply_orbitron(confirm_btn, 8)
		var cbs2 := _sp_btn_style(Color(0.07, 0.22, 0.12, 0.92), Color(0.22, 0.72, 0.38, 0.75))
		confirm_btn.add_theme_stylebox_override("normal", cbs2)
		confirm_btn.add_theme_stylebox_override("hover",  cbs2)
		confirm_btn.add_theme_color_override("font_color", Color(0.38, 0.95, 0.55))
		confirm_btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
		confirm_btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
		confirm_btn.pressed.connect(func() -> void:
			entry["transfer_resource"] = sel_res[0]
			entry["transfer_amount"]   = int(slider.value)
			close_popup.call())
		vbox.add_child(confirm_btn)

## Empty slot card — shows "+" and opens a build dropdown on click.
func _build_slot_card(poi: POIData, planet: PlanetData, pp: PlanetProgress,
		root: VBoxContainer, slot_idx: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.set_meta("is_slot_card", true)
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

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 24)
	card.add_child(margin)

	var plus := Label.new()
	plus.text = "+ Empty Slot"
	plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_orbitron(plus, 10)
	plus.add_theme_color_override("font_color", Color(0.30, 0.38, 0.65, 0.70))
	margin.add_child(plus)

	card.mouse_entered.connect(func() -> void:
		AudioManager.play("poi_hover")
		CursorManager.set_state(CursorManager.State.POINTER)
		plus.add_theme_color_override("font_color", Color(0.55, 0.65, 1.0, 0.9)))
	card.mouse_exited.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.NORMAL)
		plus.add_theme_color_override("font_color", Color(0.30, 0.38, 0.65, 0.70)))
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			AudioManager.play("click")
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
			# Tutorial: restore slot card highlight when dropdown is closed
			var tut_bid := TutorialManager.get_action_building_target()
			if tut_bid != "" and is_instance_valid(card):
				_tut_highlight_node = card as Control
				_start_tut_node_pulse(_tut_highlight_node)
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
		row_panel.set_meta("building_id", def.building_id)
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
		
		var b_time: float = def.construct_duration if def.construct_duration > 0.0 else def.tick_duration
		tip_body_parts.append("Build    %.0fs\n" % b_time)
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
			AudioManager.play("poi_hover")
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
						AudioManager.play("construct")
						AchievementManager.notify_trigger(AchievementDef.Trigger.FIRST_BUILDING)
						pp.build_in_district(cap_poi, cap_def.building_id)
						ProductionManager.building_queued.emit(cap_planet.seed, cap_def.building_id)
						if is_instance_valid(cap_overlay):
							cap_overlay.queue_free()
						_active_slot_dropdown = null
						GameState.planet_progress_changed.emit(cap_planet.seed)
						_refresh_overview_energy()
						_build_district_panel(cap_poi, cap_planet))

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			if is_instance_valid(_dd_layer):
				_dd_layer.queue_free()
				_dd_layer = null
			_active_slot_dropdown = null
			# Tutorial: restore slot card highlight when dropdown is closed
			var tut_bid := TutorialManager.get_action_building_target()
			if tut_bid != "" and is_instance_valid(card):
				_tut_highlight_node = card as Control
				_start_tut_node_pulse(_tut_highlight_node)
	)
	_dd_layer.add_child(bg)
	_dd_layer.add_child(outer)
	# CanvasLayer children use screen-space coordinates directly
	await get_tree().process_frame
	if not is_instance_valid(outer):
		return
	var card_rect := card.get_global_rect()
	outer.position            = Vector2(card_rect.position.x, card_rect.end.y)
	outer.custom_minimum_size = Vector2(card_rect.size.x, 0)
	_active_slot_dropdown = outer
	# Tutorial: highlight target building row
	var tut_bid := TutorialManager.get_action_building_target()
	if tut_bid != "":
		for row in list.get_children():
			if row.has_meta("building_id") and row.get_meta("building_id") == tut_bid:
				_tut_highlight_node = row as Control
				_start_tut_node_pulse(_tut_highlight_node)
				break

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
		alt_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
			CursorManager.set_state(CursorManager.State.POINTER)
			TooltipManager.show_tip("Switch to:", cap_alternative.unique_name))
		alt_btn.mouse_exited.connect(func() -> void:
			CursorManager.set_state(CursorManager.State.NORMAL)
			TooltipManager.hide_tip())

		tray_h.add_child(alt_btn)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			if is_instance_valid(_dd_layer):
				_dd_layer.queue_free()
				_dd_layer = null
			_active_slot_dropdown = null
	)
	_dd_layer.add_child(bg)
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
	upg_btn.text    = "^"
	upg_btn.flat    = true
	upg_btn.disabled = GameState.credits < upg_cost
	_apply_orbitron(upg_btn, 10)
	upg_btn.custom_minimum_size = Vector2(22, 22)
	upg_btn.add_theme_color_override("font_color",
		Color(0.9, 0.82, 0.45) if GameState.credits >= upg_cost else Color(0.35, 0.38, 0.50))
	upg_btn.mouse_entered.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.POINTER)
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
	_notify_tutorial_district_opened(poi, root)

## Opens a district-style build panel for an orbiting station.
func _open_station_district(ship: ShipData, _planet_cont: Control) -> void:
	if current_data == null: return
	# Build a synthetic POI that represents the station
	var poi := POIData.new()
	poi.label    = ship.ship_name
	poi.poi_type = POIData.POIType.STATION
	poi.level    = 1

	# Ensure ship buildings are mirrored into pp.buildings under this district id
	var pp := GameState.get_planet(ship.orbit_seed)
	if pp == null: return

	# Remove any stale entries for this station district, then re-add from ship.buildings
	var kept: Array[Dictionary] = []
	for b2: Dictionary in pp.buildings:
		if b2.get("district_id", "") != ship.ship_name:
			kept.append(b2)
	pp.buildings = kept
	for b in ship.buildings:
		if b is Dictionary:
			var entry: Dictionary = (b as Dictionary).duplicate()
			entry["district_id"] = ship.ship_name
			pp.buildings.append(entry)

	# Hook: keep ship.buildings in sync when the district panel modifies pp.buildings
	# (handled by storing ship ref in _active_station_ship and syncing in _on_building_constructed)
	_active_station_ship = ship

	_build_district_panel(poi, current_data)

var _active_station_ship: ShipData = null

## Rendezvous picker — full-screen overlay listing other ships in orbit.
func _show_rendezvous_picker(ship: ShipData, layer: OrbitalLayer) -> void:
	if current_data == null:
		return
	var others: Array[ShipData] = []
	for s: ShipData in ShipManager.ships_for(current_data.seed):
		if s.ship_id != ship.ship_id and s.rendezvous_target_id == "":
			others.append(s)
	if others.is_empty():
		return

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	planet_renderer.get_parent().add_child(overlay)

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.08, 0.16, 0.96)
	ps.border_color = Color(0.28, 0.55, 1.0, 0.60)
	ps.set_border_width_all(1); ps.set_corner_radius_all(8)
	ps.content_margin_left = 16; ps.content_margin_right = 16
	ps.content_margin_top = 14; ps.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", ps)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.custom_minimum_size = Vector2(220, 0)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Select Rendezvous Target"
	_apply_orbitron(title, 8)
	title.add_theme_color_override("font_color", Color(0.55, 0.80, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	for tgt: ShipData in others:
		var btn := Button.new()
		var type_icon: String = "◈" if tgt.ship_type == "station" else "▶"
		btn.text = "%s  %s" % [type_icon, tgt.ship_name]
		_apply_orbitron(btn, 8)
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(0.08, 0.12, 0.24, 0.90)
		bs.border_color = Color(0.30, 0.55, 0.90, 0.50)
		bs.set_border_width_all(1); bs.set_corner_radius_all(5)
		bs.content_margin_left = 10; bs.content_margin_right = 10
		bs.content_margin_top = 6; bs.content_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", bs)
		btn.add_theme_stylebox_override("hover",  bs)
		btn.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
		btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
		btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
		var cap_tgt := tgt
		btn.pressed.connect(func() -> void:
			overlay.queue_free()
			ship.rendezvous_base_speed = ship.orbit_speed
			ship.rendezvous_target_id  = cap_tgt.ship_id
			layer.deselect())
		vbox.add_child(btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	_apply_orbitron(cancel_btn, 7)
	var cbs := StyleBoxFlat.new()
	cbs.bg_color = Color(0.10, 0.06, 0.10, 0.80)
	cbs.border_color = Color(0.45, 0.25, 0.30, 0.50)
	cbs.set_border_width_all(1); cbs.set_corner_radius_all(5)
	cbs.content_margin_left = 10; cbs.content_margin_right = 10
	cbs.content_margin_top = 6; cbs.content_margin_bottom = 6
	cancel_btn.add_theme_stylebox_override("normal", cbs)
	cancel_btn.add_theme_stylebox_override("hover",  cbs)
	cancel_btn.add_theme_color_override("font_color", Color(0.75, 0.45, 0.45))
	cancel_btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	cancel_btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
	cancel_btn.pressed.connect(func() -> void: overlay.queue_free())
	vbox.add_child(cancel_btn)

## Transfer panel — shown when rendezvous is complete. Floating panel next to the ships.
func _show_transfer_panel(ship: ShipData, target: ShipData, layer: OrbitalLayer) -> void:
	# Re-select the shuttle so the user can see the panel
	layer.select_ship(ship)

	var cont: Control = planet_renderer.get_parent()

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.04, 0.07, 0.14, 0.96)
	ps.border_color = Color(0.30, 0.82, 1.0, 0.65)
	ps.set_border_width_all(1); ps.set_corner_radius_all(8)
	ps.content_margin_left = 14; ps.content_margin_right = 14
	ps.content_margin_top = 12; ps.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", ps)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	cont.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.custom_minimum_size = Vector2(280, 0)
	panel.add_child(vbox)

	# Header
	var hdr := Label.new()
	hdr.text = "⟐  %s  ↔  %s" % [ship.ship_name, target.ship_name]
	_apply_orbitron(hdr, 7)
	hdr.add_theme_color_override("font_color", Color(0.40, 0.85, 1.0))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(hdr)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Two-column layout: shuttle | station
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	vbox.add_child(cols)

	# Array wrapper so the lambda can reference itself after assignment
	var rebuild_ref: Array[Callable] = []

	var _build_transfer_cols := func() -> void:
		for c: Node in cols.get_children():
			c.queue_free()
		await get_tree().process_frame

		for side: int in 2:
			var src: ShipData = ship if side == 0 else target
			var dst: ShipData = target if side == 0 else ship
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 4)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cols.add_child(col)

			var col_lbl := Label.new()
			col_lbl.text = src.ship_name
			_apply_orbitron(col_lbl, 7)
			col_lbl.add_theme_color_override("font_color", Color(0.65, 0.80, 1.0))
			col_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(col_lbl)

			if src.cargo.is_empty():
				var empty_lbl := Label.new()
				empty_lbl.text = "(empty)"
				_apply_orbitron(empty_lbl, 6)
				empty_lbl.add_theme_color_override("font_color", Color(0.40, 0.45, 0.60, 0.60))
				empty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				col.add_child(empty_lbl)
			else:
				for res_id: String in src.cargo.keys():
					var rd: ResourceData = GameState.known_resources.get(res_id, null)
					if rd == null: continue
					var amt: int = int(src.cargo[res_id])

					var row := HBoxContainer.new()
					row.add_theme_constant_override("separation", 6)
					col.add_child(row)

					var sq := _mineral_grid_card(rd, float(amt), false)
					sq.custom_minimum_size = Vector2(36, 36)
					row.add_child(sq)

					var info := VBoxContainer.new()
					info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					info.mouse_filter = Control.MOUSE_FILTER_IGNORE
					row.add_child(info)

					var res_lbl := Label.new()
					res_lbl.text = rd.unique_name
					_apply_orbitron(res_lbl, 6)
					res_lbl.add_theme_color_override("font_color", Color(0.80, 0.85, 1.0))
					res_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
					info.add_child(res_lbl)

					var amt_lbl := Label.new()
					amt_lbl.text = "x%d" % amt
					_apply_orbitron(amt_lbl, 6)
					amt_lbl.add_theme_color_override("font_color", Color(0.55, 0.65, 0.85, 0.70))
					amt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
					info.add_child(amt_lbl)

					var xfer_btn := Button.new()
					var arrow: String = "→" if side == 0 else "←"
					xfer_btn.text = "%s Transfer" % arrow
					_apply_orbitron(xfer_btn, 6)
					var xbs := StyleBoxFlat.new()
					xbs.bg_color = Color(0.06, 0.14, 0.26, 0.90)
					xbs.border_color = Color(0.25, 0.55, 0.85, 0.50)
					xbs.set_border_width_all(1); xbs.set_corner_radius_all(4)
					xbs.content_margin_left = 6; xbs.content_margin_right = 6
					xbs.content_margin_top = 3; xbs.content_margin_bottom = 3
					xfer_btn.add_theme_stylebox_override("normal", xbs)
					xfer_btn.add_theme_stylebox_override("hover",  xbs)
					xfer_btn.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
					xfer_btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
					xfer_btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
					var cap_rid := res_id; var cap_src := src; var cap_dst := dst
					xfer_btn.pressed.connect(func() -> void:
						var move_amt: int = int(cap_src.cargo.get(cap_rid, 0))
						if move_amt <= 0: return
						cap_src.cargo.erase(cap_rid)
						cap_dst.cargo[cap_rid] = cap_dst.cargo.get(cap_rid, 0) + move_amt
						if not rebuild_ref.is_empty(): rebuild_ref[0].call())
					col.add_child(xfer_btn)

	rebuild_ref.append(_build_transfer_cols)
	_build_transfer_cols.call()

	var close_row := HBoxContainer.new()
	vbox.add_child(close_row)
	var close_sp := Control.new()
	close_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	close_row.add_child(close_sp)
	var close_btn := Button.new()
	close_btn.text = "Done"
	_apply_orbitron(close_btn, 7)
	var dbs := StyleBoxFlat.new()
	dbs.bg_color = Color(0.06, 0.18, 0.08, 0.90)
	dbs.border_color = Color(0.22, 0.68, 0.35, 0.60)
	dbs.set_border_width_all(1); dbs.set_corner_radius_all(5)
	dbs.content_margin_left = 12; dbs.content_margin_right = 12
	dbs.content_margin_top = 5; dbs.content_margin_bottom = 5
	close_btn.add_theme_stylebox_override("normal", dbs)
	close_btn.add_theme_stylebox_override("hover",  dbs)
	close_btn.add_theme_color_override("font_color", Color(0.40, 0.92, 0.55))
	close_btn.mouse_entered.connect(func() -> void: CursorManager.set_state(CursorManager.State.POINTER))
	close_btn.mouse_exited.connect( func() -> void: CursorManager.set_state(CursorManager.State.NORMAL))
	close_btn.pressed.connect(func() -> void: panel.queue_free())
	close_row.add_child(close_btn)

func _sync_station_buildings() -> void:
	if _active_station_ship == null or not is_instance_valid(_active_station_ship):
		return
	var pp := GameState.get_planet(_active_station_ship.orbit_seed)
	if pp == null: return
	var dist_id: String = _active_station_ship.ship_name
	_active_station_ship.buildings.clear()
	for b: Dictionary in pp.buildings:
		if b.get("district_id", "") == dist_id:
			_active_station_ship.buildings.append(b)

func _spawn_terrain_hit(screen_pos: Vector2, ptype: int) -> void:
	# Map planet type → sound key and particle color
	var sound_key: String
	var particle_color: Color
	match ptype:
		PlanetData.Type.TERRAN:
			sound_key      = "terrain_earth"
			particle_color = Color(0.18, 0.40, 0.15)   # grass green
		PlanetData.Type.ARID:
			sound_key      = "terrain_sand"
			particle_color = Color(0.68, 0.52, 0.22)   # sand ochre
		PlanetData.Type.ICE:
			sound_key      = "terrain_ice"
			particle_color = Color(0.82, 0.92, 1.00)   # ice blue-white
		PlanetData.Type.VOLCANIC:
			sound_key      = "terrain_fire"
			particle_color = Color(1.00, 0.32, 0.05)   # lava orange
		PlanetData.Type.GAS_GIANT:
			sound_key      = "terrain_gas"
			particle_color = Color(0.72, 0.58, 0.38)   # gas amber
		PlanetData.Type.MOON, PlanetData.Type.ASTEROID:
			sound_key      = "terrain_dust"
			particle_color = Color(0.55, 0.53, 0.49)   # grey dust
		_:
			sound_key      = "terrain_earth"
			particle_color = Color(0.40, 0.36, 0.28)

	# TERRAN: deeper inside the circle, bias toward water vs land by longitude (simple heuristic)
	if ptype == PlanetData.Type.TERRAN:
		var local_pos := screen_pos - planet_renderer.global_position - planet_renderer.size * 0.5
		if local_pos.x < 0:
			sound_key      = "terrain_water"
			particle_color = Color(0.08, 0.42, 0.72)

	AudioManager.play(sound_key, -3.0)
	_burst_particles(screen_pos, particle_color)

func _burst_particles(pos: Vector2, col: Color) -> void:
	var particles := CPUParticles2D.new()
	particles.position = pos
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 3
	particles.lifetime = 0.55
	particles.speed_scale = 1.0

	particles.direction = Vector2(0, -1)
	particles.spread = 180.0
	particles.gravity = Vector2(0, 280)
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 140.0
	particles.scale_amount_min = 2.5
	particles.scale_amount_max = 5.0
	particles.color = col

	# Slight color variation
	var gradient := Gradient.new()
	gradient.set_color(0, col)
	gradient.set_color(1, Color(col.r, col.g, col.b, 0.0))
	particles.color_ramp = gradient

	add_child(particles)
	particles.emitting = true
	# Auto-free after particles finish
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free())

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

func _spawn_fly_icon(lon_deg: float, lat_deg: float, icon: Texture2D) -> void:
	if icon == null or poi_layer == null or _inventory_tab_btn == null: return
	
	if not poi_layer.has_method("_get_planet_params") or not poi_layer.has_method("_get_rotation"):
		return

	var p2 = poi_layer.call("_get_planet_params")
	if typeof(p2) != TYPE_DICTIONARY or p2.is_empty(): return
	
	var center: Vector2 = p2.get("center", Vector2.ZERO)
	var r_px: float     = p2.get("r_px", 0.0)
	var rot: float      = poi_layer.call("_get_rotation")
	
	var lon: float = deg_to_rad(lon_deg) - rot
	var lat: float = deg_to_rad(lat_deg)
	
	# If behind the planet, maybe don't spawn or spawn faded
	var sz: float = cos(lon) * cos(lat)
	if sz <= 0.0: return
	
	var sx: float  = sin(lon) * cos(lat)
	var sy: float  = -sin(lat)
	
	var start_pos: Vector2 = center + Vector2(sx * r_px, sy * r_px)
	
	var tr := TextureRect.new()
	tr.texture = icon
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.custom_minimum_size = Vector2(24, 24)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Use self.add_child so it renders on top of the UI
	add_child(tr)
	tr.global_position = start_pos - Vector2(12, 12)
	
	var tw := create_tween()
	tw.set_parallel(true)
	var end_pos: Vector2 = _inventory_tab_btn.global_position + _inventory_tab_btn.size * 0.5 - Vector2(12, 12)
	
	# Animate in an arc: X is linear/ease-in-out, Y goes up then down
	tw.tween_property(tr, "global_position:x", end_pos.x, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# For Y, we use a custom tween method to create a bezier arc
	var ctrl_y: float = minf(start_pos.y, end_pos.y) - 150.0
	var start_y: float = start_pos.y
	var end_y: float = end_pos.y
	var t_y = func(t: float):
		var y = (1.0 - t) * (1.0 - t) * start_y + 2.0 * (1.0 - t) * t * ctrl_y + t * t * end_y
		tr.global_position.y = y
		
	tw.tween_method(t_y, 0.0, 1.0, 0.8)
	
	tw.tween_property(tr, "scale", Vector2(0.6, 0.6), 0.8)
	tw.tween_property(tr, "modulate:a", 0.0, 0.2).set_delay(0.6)
	
	tw.chain().tween_callback(tr.queue_free)
	
	# Pulse the inventory tab at the end of the animation
	var tw2 := create_tween()
	tw2.tween_interval(0.7)
	tw2.tween_property(_inventory_tab_btn, "scale", Vector2(1.05, 1.05), 0.1)
	tw2.tween_property(_inventory_tab_btn, "scale", Vector2(1.0, 1.0), 0.1)
