extends Control

signal planet_selected(planet_data: PlanetData)
signal back_pressed

@export var solar_data: SolarData       # inject from parent scene / inspector
@export var random_on_start: bool = true
@export var debug_seed: int = 99999

@onready var _space:        Control      = $SpaceContainer
@onready var _system_name:  Label        = $UICanvas/RightPanel/PanelContent/SystemName
@onready var _star_type:    Label        = $UICanvas/RightPanel/PanelContent/StarType
@onready var _planet_list:  VBoxContainer = $UICanvas/RightPanel/PanelContent/PlanetList
@onready var _panel_content: VBoxContainer = $UICanvas/RightPanel/PanelContent

var _survey_btn: Button = null
var _scan_wrap: VBoxContainer = null

var _current:      SolarData
var _star:         ColorRect
var _star2:        ColorRect   # binary companion, null if not binary
var _star2_angle:  float = 0.0
var _pivot:        Node2D
var _orbit_lines:  OrbitLines
var _orbit_lines_local_back: OrbitLines
var _orbit_lines_local_front: OrbitLines
var _orbits:       Array[PlanetOrbitNode] = []
var _belts:        Array[AsteroidBelt]    = []
var _belt_configs: Array[Dictionary]     = []   # {slot, rx, seed} per belt

var _view_angle:      float     = 0.0
var _orbit_tilt:      float     = 0.38
var _solar_view_angle: float    = 0.0
var _solar_orbit_tilt: float    = 0.38
var _local_view_angle: float    = 0.0
var _local_orbit_tilt: float    = 0.38
var _max_orbit_px:    float     = 200.0  # updated after build_planets
var _dragging:        bool      = false
var _left_drag_from:  Vector2   = Vector2.ZERO
var _right_dragging:  bool      = false
var _right_drag_from: Vector2   = Vector2.ZERO
var _hovered_planet:  PlanetData = null
var _active_orbit:    PlanetOrbitNode = null   # tracks which orbit node is hovered
var _enter_charge:    int        = 0   # scroll-in on hovered planet
var _back_charge:     int        = 0   # scroll-out to go back to galaxy
var _is_ready:        bool       = false

enum Mode { SOLAR, LOCAL }
var _mode:         Mode = Mode.SOLAR
var _current_local: PlanetData = null

const ORBIT_Y_RATIO := 0.38   # must match OrbitLines.y_ratio and PlanetOrbitNode

# visual diameter in pixels per star type (corona included)
const STAR_PX: Dictionary = {
	SolarData.StarType.WHITE_DWARF:     100,
	SolarData.StarType.RED_DWARF:       140,
	SolarData.StarType.YELLOW_DWARF:    210,
	SolarData.StarType.ORANGE_SUBGIANT: 260,
	SolarData.StarType.BLUE_GIANT:      340,
}

func _process(_delta: float) -> void:
	if _dragging or _right_dragging:
		CursorManager.set_state(CursorManager.State.GRAB)
		return
	if _active_orbit != null:
		CursorManager.set_state(CursorManager.State.POINTER)
		return
	CursorManager.set_state(CursorManager.State.NORMAL)

func _ready() -> void:
	CursorManager.set_state(CursorManager.State.NORMAL)
	
	# back button removed — right-click navigates back
	get_tree().root.size_changed.connect(_on_resize)
	planet_selected.connect(_on_planet_selected)
	
	_pivot = Node2D.new()
	_space.add_child(_pivot)
	GameState.asteroid_discovered.connect(_on_asteroid_discovered)

	# wait one frame so Control sizes are computed
	await get_tree().process_frame

	var pending = SceneTransition.pending_data
	SceneTransition.pending_data = null
	if pending is PlanetData:
		var pd := pending as PlanetData
		if pd.has_meta("__solar_data"):
			_current = pd.get_meta("__solar_data") as SolarData
		else:
			_current = GameState.get_home_solar()
		if pd.planet_type == PlanetData.Type.ASTEROID:
			load_system(_current)
		else:
			load_local(pd)
	elif pending is SolarData:
		load_system(pending as SolarData)
	elif solar_data != null:
		load_system(solar_data)
	elif random_on_start:
		load_system(SolarData.from_seed(randi() % 99999))
	else:
		load_system(SolarData.from_seed(debug_seed))

	_is_ready = true

func _save_current_angles_to_game_state() -> void:
	if not _is_ready:
		return
	if _mode == Mode.SOLAR and _current != null:
		GameState.set_meta("solar_view_angle_%d" % _current.seed, _view_angle)
		GameState.set_meta("solar_orbit_tilt_%d" % _current.seed, _orbit_tilt)
	elif _mode == Mode.LOCAL and _current_local != null:
		GameState.set_meta("local_view_angle_%d" % _current_local.seed, _view_angle)
		GameState.set_meta("local_orbit_tilt_%d" % _current_local.seed, _orbit_tilt)

func _load_current_angles_from_game_state() -> void:
	if _mode == Mode.SOLAR and _current != null:
		_view_angle = GameState.get_meta("solar_view_angle_%d" % _current.seed, 0.0)
		_orbit_tilt = GameState.get_meta("solar_orbit_tilt_%d" % _current.seed, 0.38)
	elif _mode == Mode.LOCAL and _current_local != null:
		_view_angle = GameState.get_meta("local_view_angle_%d" % _current_local.seed, 0.0)
		_orbit_tilt = GameState.get_meta("local_orbit_tilt_%d" % _current_local.seed, 0.38)

func _go_to_galaxy() -> void:
	if not GameState.galaxy_unlocked:
		return
	_save_current_angles_to_game_state()
	var gd: GalaxyData = null
	if _current != null and _current.has_meta("__galaxy_data"):
		gd = _current.get_meta("__galaxy_data") as GalaxyData
	if gd == null:
		gd = GameState.home_galaxy
	SceneTransition.go("res://scenes/galaxy/GalaxyView.tscn", gd)

func _can_access(pd: PlanetData) -> bool:
	if pd.planet_type == PlanetData.Type.MOON:
		if not GameState.moon_unlocked:
			return false
		if not GameState.solar_unlocked:
			var home_pd: PlanetData = null
			if _current != null:
				for p in _current.planets:
					if p.seed == GameState.home_planet_seed:
						home_pd = p
						break
			if home_pd != null:
				var is_home_moon := false
				for m in home_pd.moons:
					if m.seed == pd.seed:
						is_home_moon = true
						break
				if not is_home_moon:
					return false
	else:
		if not GameState.solar_unlocked and pd.seed != GameState.home_planet_seed:
			return false
	return true

func _on_planet_selected(pd: PlanetData) -> void:
	if not _can_access(pd):
		print("[SolarView] Access denied to planet/moon: ", pd.planet_name)
		_show_access_denied_text()
		return
		
	if _mode == Mode.SOLAR:
		if pd.planet_type == PlanetData.Type.MOON or pd.planet_type == PlanetData.Type.ASTEROID:
			# Direct jump to moon/asteroid surface if somehow clicked from Solar View
			_save_current_angles_to_game_state()
			pd.set_meta("__solar_data", _current)
			SceneTransition.go("res://scenes/planetary/PlanetaryView.tscn", pd)
		else:
			# Enter LOCAL mode for this planet
			load_local(pd)
	else:
		# In LOCAL mode, clicking the central planet or any moon goes to the surface
		_save_current_angles_to_game_state()
		pd.set_meta("__solar_data", _current)
		SceneTransition.go("res://scenes/planetary/PlanetaryView.tscn", pd)

func _show_access_denied_text() -> void:
	var lbl := Label.new()
	lbl.text = "ACCESS DENIED"
	lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 4)
	var orbitron := load("res://Fonts/Orbitron-VariableFont_wght.ttf") as Font
	if orbitron:
		lbl.add_theme_font_override("font", orbitron)
		lbl.add_theme_font_size_override("font_size", 14)
	lbl.global_position = get_viewport().get_mouse_position() + Vector2(-40, -20)
	lbl.z_index = 1000
	add_child(lbl)
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "position", lbl.global_position + Vector2(0, -40), 1.2)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.2)
	tw.chain().tween_callback(lbl.queue_free)

func load_system(data: SolarData) -> void:
	_save_current_angles_to_game_state()
	_current = data

	if data.planets.size() > 0 and not GameState.solar_unlocked and not data.is_home:
		var target_p: PlanetData = data.planets[0]
		for p in data.planets:
			if p.seed == GameState.home_planet_seed:
				target_p = p
				break
		load_local(target_p)
		return

	_mode = Mode.SOLAR
	_current_local = null
	_load_current_angles_from_game_state()
	get_tree().root.set_meta("__active_solar", data)
	# auto-unlock if any planet already has a POI (e.g. returned from PlanetaryView)
	_check_poi_unlock(data)
	_clear()
	_build_star(data)
	_build_planets(data)
	_update_panel()
	_apply_current_angles()
	queue_redraw()

func load_local(data: PlanetData) -> void:
	_save_current_angles_to_game_state()
		
	_mode = Mode.LOCAL
	_current_local = data
	_load_current_angles_from_game_state()
	_clear()
	_build_local_star(data)
	_build_local_moons(data)
	_update_panel()
	_apply_current_angles()
	queue_redraw()

func _apply_current_angles() -> void:
	for node in _orbits:
		node.set_view_angle(_view_angle)
		node.set_tilt(_orbit_tilt)
	for belt in _belts:
		belt.set_view_angle(_view_angle)
		belt.set_tilt(_orbit_tilt)
	if _orbit_lines:
		_orbit_lines.set_tilt(_orbit_tilt)
	if _orbit_lines_local_back:
		_orbit_lines_local_back.set_tilt(_orbit_tilt)
	if _orbit_lines_local_front:
		_orbit_lines_local_front.set_tilt(_orbit_tilt)

func _check_poi_unlock(data: SolarData) -> void:
	if data.is_home:
		return
	var gd: GalaxyData = data.get_meta("__galaxy_data") as GalaxyData if data.has_meta("__galaxy_data") else null
	var idx: int       = data.get_meta("__galaxy_star_idx") as int     if data.has_meta("__galaxy_star_idx") else -1
	if gd == null or idx < 0 or gd.is_unlocked(idx):
		return
	for pd in data.planets:
		if pd.custom_pois.size() > 0:
			gd.unlock(idx)
			return

func _clear() -> void:
	for node in _orbits:
		node.queue_free()
	_orbits.clear()
	if _star:
		_star.queue_free()
		_star = null
	if _star2:
		_star2.queue_free()
		_star2 = null
	if _pivot:
		_pivot.queue_free()
		_pivot = null
	_orbit_lines = null
	_belts.clear()
	_belt_configs.clear()
	for child in _planet_list.get_children():
		child.queue_free()

func _build_star(data: SolarData) -> void:
	var colors           := SolarData.get_star_colors(data.star_type)
	# binary pairs share the same footprint as a single star — scale both down
	var binary_scale: float = 0.62 if data.is_binary else 1.0
	var px_size: float    = float(STAR_PX.get(data.star_type, 210)) * binary_scale

	_star               = ColorRect.new()
	_star.size          = Vector2(px_size, px_size)
	_star.position      = _star_center() - _star.size * 0.5
	_star.z_as_relative = false
	_star.z_index       = 50   # between back-planets(20) and front-planets(80)

	var mat    := ShaderMaterial.new()
	mat.shader  = load("res://shaders/star.gdshader")
	# star_radius = 0.35 means star fills 70% of ColorRect radius; corona fills the rest
	mat.set_shader_parameter("star_radius",   0.35)
	mat.set_shader_parameter("corona_size",   0.14)
	mat.set_shader_parameter("pixel_count",   clamp(px_size * 0.55, 64.0, 256.0))
	mat.set_shader_parameter("aspect_ratio",  1.0)
	mat.set_shader_parameter("flicker_speed", 0.35)
	mat.set_shader_parameter("seed",          data.seed % 99999)
	mat.set_shader_parameter("color_core",    colors["core"])
	mat.set_shader_parameter("color_surface", colors["surface"])
	mat.set_shader_parameter("color_corona",  colors["corona"])
	_star.material = mat
	_space.add_child(_star)

	# binary companion star
	if data.is_binary:
		var s2_px: float = float(STAR_PX.get(data.secondary_type, 100)) * 0.65
		_star2               = ColorRect.new()
		_star2.size          = Vector2(s2_px, s2_px)
		_star2.z_as_relative = false
		_star2.z_index       = 48
		var mat2    := ShaderMaterial.new()
		mat2.shader  = load("res://shaders/star.gdshader")
		var c2       := SolarData.get_star_colors(data.secondary_type)
		mat2.set_shader_parameter("star_radius",   0.35)
		mat2.set_shader_parameter("corona_size",   0.14)
		mat2.set_shader_parameter("pixel_count",   clamp(s2_px * 0.55, 48.0, 180.0))
		mat2.set_shader_parameter("aspect_ratio",  1.0)
		mat2.set_shader_parameter("flicker_speed", 0.28)
		mat2.set_shader_parameter("seed",          (data.seed ^ 0xCAFE) % 99999)
		mat2.set_shader_parameter("color_core",    c2["core"])
		mat2.set_shader_parameter("color_surface", c2["surface"])
		mat2.set_shader_parameter("color_corona",  c2["corona"])
		_star2.material = mat2
		_space.add_child(_star2)
		# position: side by side with primary at center, slight Y offset for depth
		var center := _star_center()
		var gap    := (px_size * 0.5 + s2_px * 0.5) * 0.30   # heavily overlapping
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = data.seed ^ 0xB1A2
		var side: float = 1.0 if rng2.randf() > 0.5 else -1.0
		var s2_offset := Vector2(side * gap, px_size * 0.12)
		_star2.position = center + s2_offset - _star2.size * 0.5
		# push primary slightly the other way so they share a center of mass visually
		_star.position = center + Vector2(-side * gap * (s2_px / px_size) * 0.5, 0.0) - _star.size * 0.5
		# whichever star is lower on screen (higher Y) is closer to camera — give it higher z
		if s2_offset.y > 0.0:
			_star2.z_index = 52   # companion is lower → in front
			_star.z_index  = 50
		else:
			_star2.z_index = 48   # companion is higher → behind
			_star.z_index  = 50

func _build_local_star(data: PlanetData) -> void:
	var px_size: float = 240.0
	
	_star               = ColorRect.new()
	_star.size          = Vector2(px_size, px_size)
	_star.position      = _star_center() - _star.size * 0.5
	_star.z_as_relative = false
	_star.z_index       = 50
	
	var shader_path := PlanetData.get_shader_path(data.planet_type)
	var mat         := ShaderMaterial.new()
	mat.shader       = load(shader_path)
	
	mat.set_shader_parameter("planet_radius",     0.40)
	mat.set_shader_parameter("pixel_count",       px_size)
	mat.set_shader_parameter("aspect_ratio",      1.0)
	mat.set_shader_parameter("seed",              data.seed)
	mat.set_shader_parameter("terrain_roughness", data.terrain_roughness)
	mat.set_shader_parameter("rotation_offset",   0.0)
	
	var stype := PlanetData.get_shader_type(data.planet_type)
	match stype:
		PlanetData.ShaderType.ROCKY:
			mat.set_shader_parameter("sea_level",          data.sea_level)
			mat.set_shader_parameter("continent_scale",    data.continent_scale)
			mat.set_shader_parameter("has_clouds",         0.0)
			mat.set_shader_parameter("atmosphere_density", data.atmosphere_density if data.has_atmosphere else 0.0)
			mat.set_shader_parameter("specular_strength",  data.specular_strength)
			mat.set_shader_parameter("city_lights",        0.0)
			mat.set_shader_parameter("poi_count",          0)
			for key in PlanetData.get_colors(data.planet_type):
				mat.set_shader_parameter(key, PlanetData.get_colors(data.planet_type)[key])
		PlanetData.ShaderType.GAS:
			mat.set_shader_parameter("cloud_speed",        0.0)
			mat.set_shader_parameter("atmosphere_density", data.atmosphere_density)
			var c := PlanetData.get_colors(data.planet_type)
			mat.set_shader_parameter("color_band_a",    c.get("color_sand",       Vector3(0.72,0.55,0.35)))
			mat.set_shader_parameter("color_band_b",    c.get("color_forest",     Vector3(0.50,0.32,0.18)))
			mat.set_shader_parameter("color_storm",     c.get("color_snow",       Vector3(0.88,0.82,0.72)))
			mat.set_shader_parameter("color_atmosphere",c.get("color_atmosphere", Vector3(0.72,0.55,0.35)))
		PlanetData.ShaderType.MOON:
			var c := PlanetData.get_colors(data.planet_type)
			mat.set_shader_parameter("color_highland", c.get("color_mountain",   Vector3(0.62,0.60,0.56)))
			mat.set_shader_parameter("color_mare",     c.get("color_deep_ocean", Vector3(0.22,0.21,0.20)))
			mat.set_shader_parameter("color_rim",      c.get("color_snow",       Vector3(0.78,0.76,0.72)))
			mat.set_shader_parameter("color_floor",    c.get("color_ocean",      Vector3(0.16,0.15,0.14)))
		PlanetData.ShaderType.ASTEROID:
			mat.set_shader_parameter("irregularity", data.irregularity)
			mat.set_shader_parameter("elongation",   1.0 + data.irregularity * 0.8)

	_star.material = mat
	_space.add_child(_star)
	
	_star.mouse_filter = Control.MOUSE_FILTER_STOP
	_star.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_star.mouse_entered.connect(func() -> void:
		_hovered_planet = data
	)
	_star.mouse_exited.connect(func() -> void:
		if _hovered_planet == data:
			_hovered_planet = null
	)

func _build_local_moons(data: PlanetData) -> void:
	_pivot          = Node2D.new()
	_pivot.position = _star_center()
	_space.add_child(_pivot)

	_orbit_lines_local_back = OrbitLines.new()
	_orbit_lines_local_back.draw_mode = OrbitLines.DrawMode.BACK
	_pivot.add_child(_orbit_lines_local_back)

	_orbit_lines_local_front = OrbitLines.new()
	_orbit_lines_local_front.draw_mode = OrbitLines.DrawMode.FRONT
	_pivot.add_child(_orbit_lines_local_front)

	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed ^ 0x6969
	
	_orbits.clear()
	var base_rx: float = 160.0
	var radii: Array[float] = []
	for i in data.moons.size():
		var md: PlanetData = data.moons[i]
		var rx    := base_rx + i * 60.0
		var start := rng.randf_range(0.0, TAU)
		
		var node := PlanetOrbitNode.new()
		_pivot.add_child(node)
		node.setup(md, rx, start)
		node._height = 0.0   # moons follow orbit ellipse exactly, no vertical scatter
		node._update_position()
		
		node.hover_start.connect(func(pd: PlanetData) -> void: _hovered_planet = pd)
		node.hover_end.connect(func() -> void:
			if _hovered_planet == md:
				_hovered_planet = null
		)
		
		node.clicked.connect(func(pd: PlanetData) -> void: planet_selected.emit(pd))
		
		_orbits.append(node)
		radii.append(rx)
		
	_orbit_lines_local_back.refresh(radii)
	_orbit_lines_local_front.refresh(radii)
		
	_orbit_lines_local_back.z_as_relative = false
	_orbit_lines_local_back.z_index       = 10
	
	_orbit_lines_local_front.z_as_relative = false
	_orbit_lines_local_front.z_index       = 60
	
	_pivot.z_as_relative       = false
	_pivot.z_index             = 20
	
	_max_orbit_px = base_rx + data.moons.size() * 60.0

func _build_planets(data: SolarData) -> void:
	_pivot          = Node2D.new()
	_pivot.position = _star_center()
	_pivot.z_index  = 1
	_space.add_child(_pivot)

	var star_px:   float = float(STAR_PX.get(data.star_type, 210))
	var min_orbit: float = star_px * 0.5 + 40.0

	# max orbit: fits inside SpaceContainer; clamp tightly so system doesn't sprawl
	var margin:    float = 60.0
	var max_by_x:  float = _space.size.x * 0.44 - margin
	var max_by_y:  float = (_space.size.y * 0.42) / ORBIT_Y_RATIO
	var max_orbit: float = min(max_by_x, max_by_y)
	max_orbit = clamp(max_orbit, min_orbit + 60.0, 420.0)

	var count: int = data.planets.size()

	# Build per-gap step sizes: belt gaps are 2.2x wider than planet gaps.
	# Total weighted slots = (count-1) gaps where belt gaps count as 2.2
	const BELT_FACTOR := 2.2
	var total_weight: float = 0.0
	for gap in count - 1:
		total_weight += BELT_FACTOR if gap in data.asteroid_belt_slots else 1.0
	total_weight = max(total_weight, 1.0)
	var base_step: float = clamp((max_orbit - min_orbit) / total_weight, 55.0, 100.0)

	# Pre-compute each planet's orbit radius
	var orbit_radii_arr: Array[float] = []
	var cur: float = min_orbit
	orbit_radii_arr.append(cur)
	for gap in count - 1:
		var w: float = BELT_FACTOR if gap in data.asteroid_belt_slots else 1.0
		cur += base_step * w
		orbit_radii_arr.append(cur)

	# orbit lines: absolute z=10 so they're behind star(50) and all planets
	_orbit_lines               = OrbitLines.new()
	_orbit_lines.z_as_relative = false
	_orbit_lines.z_index       = 10
	_pivot.add_child(_orbit_lines)
	_orbit_lines.refresh(orbit_radii_arr)

	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed ^ 0xABCD

	for i in count:
		var radius_x:    float = orbit_radii_arr[i]
		var start_angle: float = rng.randf_range(0.0, TAU)
		var node := PlanetOrbitNode.new()
		node.clicked.connect(func(pd: PlanetData) -> void: planet_selected.emit(pd))
		node.hover_start.connect(func(pd: PlanetData) -> void:
			# force-close any other hovered node before activating this one
			if _active_orbit != null and _active_orbit != node and _active_orbit._hover:
				_active_orbit._on_hover_end()
			_active_orbit   = node
			_hovered_planet = pd
			_enter_charge   = 0)
		node.hover_end.connect(func() -> void:
			if _active_orbit == node:
				_active_orbit   = null
				_hovered_planet = null
				_enter_charge   = 0)
		_pivot.add_child(node)
		node.setup(data.planets[i], radius_x, start_angle)
		if data.planets[i].has_meta("__is_home"):
			node.mark_as_home()
		if not data.planets[i].custom_pois.is_empty():
			var lv := GameState.get_planet(data.planets[i].seed).level
			node.set_settlement_level(lv)
		_orbits.append(node)

	# asteroid belts — always visible; asteroids only appear after discovery
	for slot in data.asteroid_belt_slots:
		if slot < 0 or slot >= count - 1:
			continue
		var inner:   float = orbit_radii_arr[slot]
		var outer:   float = orbit_radii_arr[slot + 1]
		var belt_rx: float = (inner + outer) * 0.5
		var belt_seed: int = data.seed ^ (slot * 0x1337)
		var belt := AsteroidBelt.new()
		_pivot.add_child(belt)
		var ast_count: int = GameState.asteroid_scan_counts.get(slot, 0)
		belt.setup(belt_rx, belt_seed, ast_count)
		_belts.append(belt)
		_belt_configs.append({"slot": slot, "rx": belt_rx, "seed": belt_seed})

	_max_orbit_px = orbit_radii_arr.back() if orbit_radii_arr.size() > 0 else 200.0

func _on_asteroid_discovered(slot: int, count: int) -> void:
	for i in _belt_configs.size():
		if _belt_configs[i]["slot"] == slot:
			_belts[i].queue_free()
			var cfg := _belt_configs[i]
			var belt := AsteroidBelt.new()
			_pivot.add_child(belt)
			belt.setup(cfg["rx"], cfg["seed"], count)
			belt.set_view_angle(_view_angle)
			belt.set_tilt(ORBIT_Y_RATIO)
			_belts[i] = belt
			return

func _update_panel() -> void:
	if _mode == Mode.SOLAR:
		_system_name.text = _current.system_name
		_star_type.text   = SolarData.get_star_type_name(_current.star_type)
		for child in _planet_list.get_children():
			child.queue_free()
		for i in _current.planets.size():
			var pd: PlanetData = _current.planets[i]
			var btn := Button.new()
			btn.text        = "%d. %s" % [i + 1, pd.planet_name]
			btn.flat        = true
			btn.alignment   = HORIZONTAL_ALIGNMENT_LEFT
			if not _can_access(pd):
				btn.disabled = true
				btn.modulate.a = 0.5
			btn.pressed.connect(func() -> void: planet_selected.emit(pd))
			_planet_list.add_child(btn)
	else:
		_system_name.text = _current_local.planet_name + " System"
		_star_type.text   = "Planet"
		for child in _planet_list.get_children():
			child.queue_free()
		for i in _current_local.moons.size():
			var md: PlanetData = _current_local.moons[i]
			var btn := Button.new()
			btn.text        = "%s" % md.planet_name
			btn.flat        = true
			btn.alignment   = HORIZONTAL_ALIGNMENT_LEFT
			if not _can_access(md):
				btn.disabled = true
				btn.modulate.a = 0.5
			btn.pressed.connect(func() -> void: planet_selected.emit(md))
			_planet_list.add_child(btn)

	# remove old survey / scan buttons
	if _survey_btn and is_instance_valid(_survey_btn):
		_survey_btn.queue_free()
		_survey_btn = null
	if _scan_wrap and is_instance_valid(_scan_wrap):
		_scan_wrap.queue_free()
		_scan_wrap = null

	var is_surveyed := _current.is_home
	var gd: GalaxyData = null
	var star_idx: int = -1

	if not is_surveyed:
		gd = _current.get_meta("__galaxy_data") as GalaxyData if _current.has_meta("__galaxy_data") else null
		star_idx = _current.get_meta("__galaxy_star_idx") as int if _current.has_meta("__galaxy_star_idx") else -1
		if gd != null and star_idx >= 0 and gd.is_unlocked(star_idx):
			is_surveyed = true

	if is_surveyed:
		# Scan Asteroid button — only in SOLAR mode, only if skill unlocked, only if belts exist
		if _mode == Mode.SOLAR and _current != null \
				and not _current.asteroid_belt_slots.is_empty() \
				and SkillTree.call("is_unlocked", "unlock_asteroids"):
			_build_scan_asteroid_section()
		return

	if gd == null or star_idx < 0:
		return

	const SURVEY_CREDITS: float = 200_000.0
	const SURVEY_SCIENCE: float = 50_000.0

	var orbitron := load("res://Fonts/Orbitron-VariableFont_wght.ttf") as Font

	# Container for the whole survey section (separator + cost + button)
	var survey_wrap := VBoxContainer.new()
	survey_wrap.add_theme_constant_override("separation", 6)
	_panel_content.add_child(survey_wrap)

	var sep := HSeparator.new()
	var sep_s := StyleBoxFlat.new()
	sep_s.bg_color = Color(0.2, 0.25, 0.4, 0.35)
	sep.add_theme_stylebox_override("separator", sep_s)
	survey_wrap.add_child(sep)

	# Survey button styled like Level Up (always green)
	_survey_btn = Button.new()
	_survey_btn.text = "SURVEY SYSTEM"
	_survey_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if orbitron: _survey_btn.add_theme_font_override("font", orbitron)
	_survey_btn.add_theme_font_size_override("font_size", 12)

	var nb := StyleBoxFlat.new()
	nb.bg_color = Color(0.10, 0.32, 0.12)
	nb.content_margin_top = 10; nb.content_margin_bottom = 10
	nb.set_border_width_all(1)
	nb.border_color = Color(0.25, 0.75, 0.30, 0.8)
	nb.set_corner_radius_all(3)
	_survey_btn.add_theme_stylebox_override("normal", nb)
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(0.15, 0.48, 0.18)
	hb.content_margin_top = 10; hb.content_margin_bottom = 10
	hb.set_border_width_all(1)
	hb.border_color = Color(0.30, 0.90, 0.38, 0.9)
	hb.set_corner_radius_all(3)
	_survey_btn.add_theme_stylebox_override("hover", hb)
	_survey_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_survey_btn.add_theme_color_override("font_color", Color(0.80, 1.0, 0.82))

	_survey_btn.mouse_entered.connect(func() -> void:
		AudioManager.play("hover")
		CursorManager.set_state(CursorManager.State.POINTER))
	_survey_btn.mouse_exited.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.NORMAL))
	_survey_btn.pressed.connect(func() -> void: _show_survey_popup(gd, star_idx, SURVEY_CREDITS, SURVEY_SCIENCE))

	survey_wrap.add_child(_survey_btn)

const SCAN_SCIENCE: float = 5_000.0

func _build_scan_asteroid_section() -> void:
	var orbitron := load("res://Fonts/Orbitron-VariableFont_wght.ttf") as Font

	_scan_wrap = VBoxContainer.new()
	_scan_wrap.add_theme_constant_override("separation", 6)
	_panel_content.add_child(_scan_wrap)

	var sep := HSeparator.new()
	var sep_s := StyleBoxFlat.new()
	sep_s.bg_color = Color(0.2, 0.25, 0.4, 0.35)
	sep.add_theme_stylebox_override("separator", sep_s)
	_scan_wrap.add_child(sep)

	# Show scan status per belt
	var st_lbl := Label.new()
	var belts: Array = _current.asteroid_belt_slots
	var scanned_total: int = 0
	for slot: int in belts:
		scanned_total += GameState.asteroid_scan_counts.get(slot, 0)
	var max_total: int = belts.size() * 3
	st_lbl.text = "Asteroids: %d / %d scanned" % [scanned_total, max_total]
	st_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if orbitron: st_lbl.add_theme_font_override("font", orbitron)
	st_lbl.add_theme_font_size_override("font_size", 8)
	st_lbl.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	_scan_wrap.add_child(st_lbl)

	var scan_btn := Button.new()
	scan_btn.text = "SCAN ASTEROID BELT"
	scan_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if orbitron: scan_btn.add_theme_font_override("font", orbitron)
	scan_btn.add_theme_font_size_override("font_size", 11)

	# Find next unsaturated belt
	var next_slot: int = -1
	for slot: int in belts:
		if GameState.asteroid_scan_counts.get(slot, 0) < 3:
			next_slot = slot
			break

	var all_scanned := next_slot < 0
	var can_afford  := GameState.science_points >= SCAN_SCIENCE

	var nb := StyleBoxFlat.new()
	nb.bg_color = Color(0.08, 0.28, 0.22) if (can_afford and not all_scanned) else Color(0.10, 0.12, 0.18)
	nb.content_margin_top = 10; nb.content_margin_bottom = 10
	nb.set_border_width_all(1)
	nb.border_color = Color(0.20, 0.75, 0.55, 0.8) if (can_afford and not all_scanned) else Color(0.25, 0.30, 0.40, 0.5)
	nb.set_corner_radius_all(3)
	scan_btn.add_theme_stylebox_override("normal", nb)
	var hb := nb.duplicate() as StyleBoxFlat
	hb.bg_color = Color(0.12, 0.42, 0.32) if (can_afford and not all_scanned) else Color(0.12, 0.14, 0.22)
	scan_btn.add_theme_stylebox_override("hover", hb)
	scan_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	scan_btn.add_theme_color_override("font_color",
		Color(0.65, 1.0, 0.85) if (can_afford and not all_scanned) else Color(0.35, 0.42, 0.55))

	if all_scanned:
		scan_btn.disabled = true
		scan_btn.text = "ALL BELTS SCANNED"
	elif not can_afford:
		scan_btn.disabled = true

	var cost_lbl := Label.new()
	cost_lbl.text = "○ %s Science" % HUDManager.fmt_science(SCAN_SCIENCE)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if orbitron: cost_lbl.add_theme_font_override("font", orbitron)
	cost_lbl.add_theme_font_size_override("font_size", 8)
	cost_lbl.add_theme_color_override("font_color",
		Color(0.45, 0.78, 1.0) if can_afford else Color(0.80, 0.30, 0.30))
	_scan_wrap.add_child(cost_lbl)
	_scan_wrap.add_child(scan_btn)

	scan_btn.mouse_entered.connect(func() -> void: AudioManager.play("hover"))
	scan_btn.pressed.connect(func() -> void:
		if not GameState.spend_science(SCAN_SCIENCE):
			AudioManager.play("error")
			return
		AudioManager.play("survey", -2.0)
		GameState.discover_asteroid(next_slot)
		_update_panel())

func _show_survey_popup(gd: GalaxyData, star_idx: int, cost_cr: float, cost_sci: float) -> void:
	var orbitron := load("res://Fonts/Orbitron-VariableFont_wght.ttf") as Font

	var popup_layer := CanvasLayer.new()
	popup_layer.layer = 400
	get_tree().root.add_child(popup_layer)

	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	popup_layer.add_child(overlay)

	var popup := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.09, 0.18, 0.97)
	ps.border_color = Color(0.25, 0.45, 0.80, 0.55)
	ps.set_border_width_all(1); ps.set_corner_radius_all(6)
	ps.content_margin_left = 24; ps.content_margin_right = 24
	ps.content_margin_top  = 24; ps.content_margin_bottom = 24
	popup.add_theme_stylebox_override("panel", ps)
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	popup.grow_vertical   = Control.GROW_DIRECTION_BOTH
	popup.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	popup.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	overlay.add_child(popup)

	# Close on overlay click (but not popup click)
	overlay.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			if not popup.get_global_rect().has_point((ev as InputEventMouseButton).global_position):
				popup_layer.queue_free())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	popup.add_child(vbox)

	var title := Label.new()
	title.text = "SURVEY SYSTEM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if orbitron: title.add_theme_font_override("font", orbitron)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "Reveal all planets and moons in this system."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 240
	if orbitron: desc.add_theme_font_override("font", orbitron)
	desc.add_theme_font_size_override("font_size", 9)
	desc.add_theme_color_override("font_color", Color(0.55, 0.65, 0.80))
	vbox.add_child(desc)

	# Cost rows
	var cost_box := VBoxContainer.new()
	cost_box.add_theme_constant_override("separation", 8)
	vbox.add_child(cost_box)

	var _make_cost_row := func(label: String, have: float, need: float, color: Color) -> void:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 10)
		cost_box.add_child(row)
		var lbl := Label.new()
		lbl.text = label
		if orbitron: lbl.add_theme_font_override("font", orbitron)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", color)
		row.add_child(lbl)
		var val := Label.new()
		val.text = "%s / %s" % [HUDManager.fmt_credits(have) if label.begins_with("◈") else "%.0f" % have,
								HUDManager.fmt_credits(need) if label.begins_with("◈") else "%.0f" % need]
		if orbitron: val.add_theme_font_override("font", orbitron)
		val.add_theme_font_size_override("font_size", 10)
		val.add_theme_color_override("font_color",
			Color(0.35, 0.90, 0.45) if have >= need else Color(0.90, 0.35, 0.35))
		row.add_child(val)

	_make_cost_row.call("◈  Credits", GameState.credits, cost_cr, Color(0.95, 0.82, 0.35))
	_make_cost_row.call("○  Science", GameState.science_points, cost_sci, Color(0.55, 0.85, 1.0))

	var can_afford := GameState.credits >= cost_cr and GameState.science_points >= cost_sci

	if not can_afford:
		var warn := Label.new()
		warn.text = "Insufficient resources to survey."
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if orbitron: warn.add_theme_font_override("font", orbitron)
		warn.add_theme_font_size_override("font_size", 9)
		warn.add_theme_color_override("font_color", Color(0.90, 0.35, 0.35))
		vbox.add_child(warn)

	# Buttons row
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "CANCEL"
	if orbitron: cancel_btn.add_theme_font_override("font", orbitron)
	cancel_btn.add_theme_font_size_override("font_size", 10)
	cancel_btn.custom_minimum_size = Vector2(100, 36)
	var cb_s := StyleBoxFlat.new()
	cb_s.bg_color = Color(0.10, 0.10, 0.16)
	cb_s.border_color = Color(0.30, 0.30, 0.45, 0.6); cb_s.set_border_width_all(1); cb_s.set_corner_radius_all(4)
	cb_s.content_margin_top = 8; cb_s.content_margin_bottom = 8
	cancel_btn.add_theme_stylebox_override("normal", cb_s)
	var cb_h := cb_s.duplicate() as StyleBoxFlat; cb_h.bg_color = Color(0.16, 0.16, 0.24)
	cancel_btn.add_theme_stylebox_override("hover", cb_h)
	cancel_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	cancel_btn.add_theme_color_override("font_color", Color(0.65, 0.68, 0.80))
	cancel_btn.pressed.connect(func() -> void: popup_layer.queue_free())
	btn_row.add_child(cancel_btn)

	var confirm_btn := Button.new()
	confirm_btn.text = "SURVEY"
	if orbitron: confirm_btn.add_theme_font_override("font", orbitron)
	confirm_btn.add_theme_font_size_override("font_size", 11)
	confirm_btn.custom_minimum_size = Vector2(120, 36)
	var fb_s := StyleBoxFlat.new()
	fb_s.bg_color = Color(0.15, 0.4, 0.15)
	fb_s.content_margin_top = 10; fb_s.content_margin_bottom = 10
	confirm_btn.add_theme_stylebox_override("normal", fb_s)
	var fb_h := StyleBoxFlat.new()
	fb_h.bg_color = Color(0.2, 0.6, 0.2)
	fb_h.content_margin_top = 10; fb_h.content_margin_bottom = 10
	confirm_btn.add_theme_stylebox_override("hover", fb_h)
	confirm_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	confirm_btn.add_theme_color_override("font_color", Color.WHITE)
	if not can_afford:
		confirm_btn.disabled = true
		var db_s := StyleBoxFlat.new()
		db_s.bg_color = Color(0.10, 0.18, 0.10)
		db_s.content_margin_top = 10; db_s.content_margin_bottom = 10
		db_s.set_border_width_all(1); db_s.border_color = Color(0.20, 0.35, 0.20, 0.5)
		db_s.set_corner_radius_all(3)
		confirm_btn.add_theme_stylebox_override("disabled", db_s)
		confirm_btn.add_theme_color_override("font_disabled_color", Color(0.35, 0.50, 0.35))
	confirm_btn.pressed.connect(func() -> void:
		AudioManager.play("survey")
		popup_layer.queue_free()
		_survey_system(gd, star_idx, cost_cr, cost_sci))
	btn_row.add_child(confirm_btn)

	cancel_btn.pressed.connect(func() -> void: overlay.queue_free())

func _survey_system(gd: GalaxyData, star_idx: int, cost_cr: float, cost_sci: float) -> void:
	if GameState.credits < cost_cr or GameState.science_points < cost_sci:
		return
	GameState.credits -= cost_cr
	GameState.credits_changed.emit(GameState.credits)
	if not GameState.spend_science(cost_sci):
		GameState.credits += cost_cr
		GameState.credits_changed.emit(GameState.credits)
		return
	gd.unlock(star_idx)
	AchievementManager.notify_trigger(AchievementDef.Trigger.FIRST_SURVEY)
	_update_panel()


func _input(event: InputEvent) -> void:
	if SkillTreeView.is_open:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_right_dragging  = true
				_right_drag_from = mb.position
			else:
				_right_dragging = false
				if mb.position.distance_to(_right_drag_from) < 5.0:
					if _mode == Mode.LOCAL:
						if not GameState.solar_unlocked:
							print("[SolarView] Access denied to exit Local System.")
							_show_access_denied_text()
						else:
							load_system(_current)
					else:
						_go_to_galaxy()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _space.get_global_rect().has_point(mb.global_position):
				_dragging = true
				_left_drag_from = mb.position
			elif not mb.pressed:
				_dragging = false
				if mb.position.distance_to(_left_drag_from) < 5.0:
					var target_pd: PlanetData = _hovered_planet
					if target_pd == null and _mode == Mode.LOCAL and _star != null and _star.get_global_rect().has_point(mb.global_position):
						target_pd = _current_local
					if target_pd != null:
						planet_selected.emit(target_pd)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			var target_pd: PlanetData = _hovered_planet
			if target_pd == null and _mode == Mode.LOCAL and _star != null and _star.get_global_rect().has_point(mb.global_position):
				target_pd = _current_local
			if target_pd != null:
				_enter_charge += 1
				_back_charge   = 0
				if _enter_charge >= 2:
					_enter_charge = 0
					planet_selected.emit(target_pd)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_enter_charge  = 0
			_back_charge  += 1
			if _back_charge >= 3:
				_back_charge = 0
				if _mode == Mode.LOCAL:
					if not GameState.solar_unlocked:
						print("[SolarView] Access denied to exit Local System.")
						_show_access_denied_text()
					else:
						load_system(_current)
				else:
					_go_to_galaxy()
	elif event is InputEventMagnifyGesture:
		if event.factor > 1.0:
			var target_pd: PlanetData = _hovered_planet
			if target_pd == null and _mode == Mode.LOCAL and _star != null and _star.get_global_rect().has_point(event.position):
				target_pd = _current_local
			if target_pd != null:
				_enter_charge += 1
				_back_charge   = 0
				if _enter_charge >= 2:
					_enter_charge = 0
					planet_selected.emit(target_pd)
		elif event.factor < 1.0:
			_enter_charge  = 0
			_back_charge  += 1
			if _back_charge >= 3:
				_back_charge = 0
				if _mode == Mode.LOCAL:
					load_system(_current)
				else:
					_go_to_galaxy()
	elif event is InputEventPanGesture:
		# 2-finger trackpad swipe → rotate (horizontal) / tilt (vertical)
		_view_angle += event.delta.x * 0.012
		_orbit_tilt  = clamp(_orbit_tilt - event.delta.y * 0.006, 0.28, 0.50)
		for node in _orbits:
			node.set_view_angle(_view_angle)
			node.set_tilt(_orbit_tilt)
		for belt in _belts:
			belt.set_view_angle(_view_angle)
			belt.set_tilt(_orbit_tilt)
		if _orbit_lines:
			_orbit_lines.set_tilt(_orbit_tilt)
		if _orbit_lines_local_back:
			_orbit_lines_local_back.set_tilt(_orbit_tilt)
		if _orbit_lines_local_front:
			_orbit_lines_local_front.set_tilt(_orbit_tilt)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and (_dragging or _right_dragging):
		var mm  := event as InputEventMouseMotion
		if mm.relative.length() < 1.5:
			return
		if _right_dragging:
			# vertical drag → subtle orbit tilt, clamped to a narrow range
			_orbit_tilt = clamp(_orbit_tilt + mm.relative.y * 0.0008, 0.28, 0.50)
			for node in _orbits:
				node.set_tilt(_orbit_tilt)
			for belt in _belts:
				belt.set_tilt(_orbit_tilt)
			if _orbit_lines:
				_orbit_lines.set_tilt(_orbit_tilt)
			if _orbit_lines_local_back:
				_orbit_lines_local_back.set_tilt(_orbit_tilt)
			if _orbit_lines_local_front:
				_orbit_lines_local_front.set_tilt(_orbit_tilt)
		else:
			_view_angle -= mm.relative.x * 0.0042
		for node in _orbits:
			node.set_view_angle(_view_angle)
		for belt in _belts:
			belt.set_view_angle(_view_angle)
		get_viewport().set_input_as_handled()


func _star_center() -> Vector2:
	return _space.size * Vector2(0.5, 0.52)

func _on_resize() -> void:
	await get_tree().process_frame
	if _current:
		_build_star(_current)
	if _pivot:
		_pivot.position = _star_center()
	if _star:
		_star.position = _star_center() - _star.size * 0.5
	queue_redraw()
