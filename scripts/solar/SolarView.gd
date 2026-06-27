extends Control

signal planet_selected(planet_data: PlanetData)
signal back_pressed

@export var solar_data: SolarData       # inject from parent scene / inspector
@export var random_on_start: bool = true
@export var debug_seed: int = 99999

@onready var _space:        Control      = $SpaceContainer
@onready var _system_name:  Label        = $RightPanel/PanelContent/SystemName
@onready var _star_type:    Label        = $RightPanel/PanelContent/StarType
@onready var _planet_list:  VBoxContainer = $RightPanel/PanelContent/PlanetList
@onready var _panel_content: VBoxContainer = $RightPanel/PanelContent

var _survey_btn: Button = null

var _current:      SolarData
var _star:         ColorRect
var _star2:        ColorRect   # binary companion, null if not binary
var _star2_angle:  float = 0.0
var _pivot:        Node2D
var _orbit_lines:  OrbitLines
var _orbits:       Array[PlanetOrbitNode] = []
var _belts:        Array[AsteroidBelt]    = []

var _view_angle:      float     = 0.0
var _orbit_tilt:      float     = 0.38
var _max_orbit_px:    float     = 200.0  # updated after build_planets
var _dragging:        bool      = false
var _right_dragging:  bool      = false
var _right_drag_from: Vector2   = Vector2.ZERO
var _hovered_planet:  PlanetData = null
var _active_orbit:    PlanetOrbitNode = null   # tracks which orbit node is hovered
var _enter_charge:    int        = 0   # scroll-in on hovered planet
var _back_charge:     int        = 0   # scroll-out to go back to galaxy

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
	var mouse := get_viewport().get_mouse_position()
	var vp    := get_viewport().get_visible_rect().size
	const EDGE := 40.0
	if mouse.x < EDGE or mouse.y < EDGE or mouse.x > vp.x - EDGE or mouse.y > vp.y - EDGE:
		CursorManager.set_state(CursorManager.State.EXIT)
		return
	CursorManager.set_state(CursorManager.State.NORMAL)

func _ready() -> void:
	CursorManager.set_state(CursorManager.State.NORMAL)
	# back button removed — right-click navigates back
	get_tree().root.size_changed.connect(_on_resize)
	planet_selected.connect(_on_planet_selected)

	# wait one frame so Control sizes are computed
	await get_tree().process_frame

	# data injected from GalaxyView (star selected) or PlanetaryView (back)
	var sd: SolarData = SceneTransition.pending_data as SolarData
	SceneTransition.pending_data = null
	if sd != null:
		load_system(sd)
	elif solar_data != null:
		load_system(solar_data)
	elif random_on_start:
		load_system(SolarData.from_seed(randi() % 99999))
	else:
		load_system(SolarData.from_seed(debug_seed))

	# restore saved view angle so entering/leaving doesn't reset the orbit view
	if _current != null:
		var angle_key := "solar_angle_%d" % _current.seed
		if GameState.has_meta(angle_key):
			_view_angle = GameState.get_meta(angle_key)
			for node in _orbits:
				node.set_view_angle(_view_angle)
			for belt in _belts:
				belt.set_view_angle(_view_angle)

func _save_view_angle() -> void:
	if _current != null:
		GameState.set_meta("solar_angle_%d" % _current.seed, _view_angle)

func _go_to_galaxy() -> void:
	if not GameState.galaxy_unlocked:
		return
	_save_view_angle()
	var gd: GalaxyData = null
	if _current != null and _current.has_meta("__galaxy_data"):
		gd = _current.get_meta("__galaxy_data") as GalaxyData
	if gd == null:
		gd = GameState.home_galaxy
	SceneTransition.go("res://scenes/galaxy/GalaxyView.tscn", gd)

func _on_planet_selected(pd: PlanetData) -> void:
	_save_view_angle()
	pd.set_meta("__solar_data", _current)
	SceneTransition.go("res://scenes/planetary/PlanetaryView.tscn", pd)

func load_system(data: SolarData) -> void:
	_current = data
	get_tree().root.set_meta("__active_solar", data)
	# auto-unlock if any planet already has a POI (e.g. returned from PlanetaryView)
	_check_poi_unlock(data)
	_clear()
	_build_star(data)
	_build_planets(data)
	_update_panel(data)
	queue_redraw()

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
		var belt := AsteroidBelt.new()
		_pivot.add_child(belt)
		var ast_count: int = 3 if GameState.discovered_asteroids.has(slot) else 0
		belt.setup(belt_rx, data.seed ^ (slot * 0x1337), ast_count)
		_belts.append(belt)

	_max_orbit_px = orbit_radii_arr.back() if orbit_radii_arr.size() > 0 else 200.0

func _update_panel(data: SolarData) -> void:
	_system_name.text = data.system_name
	_star_type.text   = SolarData.get_star_type_name(data.star_type)

	for i in data.planets.size():
		var btn := Button.new()
		btn.text        = "%d. %s" % [i + 1, data.planets[i].planet_name]
		btn.flat        = true
		btn.alignment   = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func() -> void: planet_selected.emit(data.planets[i]))
		_planet_list.add_child(btn)

	# remove old survey button if any
	if _survey_btn and is_instance_valid(_survey_btn):
		_survey_btn.queue_free()
		_survey_btn = null

	# home system is already unlocked — no button needed
	if data.is_home:
		return

	var gd: GalaxyData = data.get_meta("__galaxy_data") as GalaxyData if data.has_meta("__galaxy_data") else null
	if gd == null:
		return

	var star_idx: int = data.get_meta("__galaxy_star_idx") as int if data.has_meta("__galaxy_star_idx") else -1
	if star_idx < 0:
		return

	if gd.is_unlocked(star_idx):
		return   # already surveyed

	var orbitron := load("res://Fonts/Orbitron-VariableFont_wght.ttf") as Font
	_survey_btn = Button.new()
	_survey_btn.text      = "▶  SURVEY SYSTEM"
	_survey_btn.flat      = false
	_survey_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if orbitron:
		_survey_btn.add_theme_font_override("font", orbitron)
	_survey_btn.add_theme_font_size_override("font_size", 10)
	_survey_btn.add_theme_color_override("font_color",        Color(0.90, 0.82, 0.45))
	_survey_btn.add_theme_color_override("font_hover_color",  Color(1.00, 0.95, 0.60))
	_survey_btn.add_theme_color_override("font_pressed_color",Color(1.00, 1.00, 0.80))
	_survey_btn.pressed.connect(func() -> void: _survey_system(gd, star_idx))
	# insert before BackButton (second-to-last child)
	_panel_content.add_child(_survey_btn)
	_panel_content.move_child(_survey_btn, _panel_content.get_child_count() - 2)

func _survey_system(gd: GalaxyData, star_idx: int) -> void:
	gd.unlock(star_idx)
	if is_instance_valid(_survey_btn):
		_survey_btn.queue_free()
		_survey_btn = null


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_right_dragging  = true
				_right_drag_from = mb.position
			else:
				_right_dragging = false
				if mb.position.distance_to(_right_drag_from) < 5.0:
					_go_to_galaxy()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _space.get_global_rect().has_point(mb.global_position):
				_dragging = true
			elif not mb.pressed:
				if mb.double_click and _hovered_planet != null:
					planet_selected.emit(_hovered_planet)
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			if _hovered_planet != null:
				_enter_charge += 1
				_back_charge   = 0
				if _enter_charge >= 3:
					_enter_charge = 0
					planet_selected.emit(_hovered_planet)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_enter_charge  = 0
			_back_charge  += 1
			if _back_charge >= 4:
				_back_charge = 0
				_go_to_galaxy()
	elif event is InputEventMagnifyGesture:
		if event.factor > 1.0 and _hovered_planet != null:
			_enter_charge += 1
			_back_charge   = 0
			if _enter_charge >= 3:
				_enter_charge = 0
				planet_selected.emit(_hovered_planet)
		elif event.factor < 1.0:
			_enter_charge  = 0
			_back_charge  += 1
			if _back_charge >= 4:
				_back_charge = 0
				_go_to_galaxy()
	elif event is InputEventPanGesture:
		var dy: float = event.delta.y
		if dy < -0.5 and _hovered_planet != null:   # scroll up = zoom in
			_enter_charge += 1
			_back_charge   = 0
			if _enter_charge >= 3:
				_enter_charge = 0
				planet_selected.emit(_hovered_planet)
		elif dy > 0.5:                               # scroll down = zoom out
			_enter_charge  = 0
			_back_charge  += 1
			if _back_charge >= 4:
				_back_charge = 0
				_go_to_galaxy()
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
