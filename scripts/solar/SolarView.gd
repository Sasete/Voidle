extends Control

signal planet_selected(planet_data: PlanetData)
signal back_pressed

@export var solar_data: SolarData       # inject from parent scene / inspector
@export var random_on_start: bool = true
@export var debug_seed: int = 99999

@onready var _space:       Control  = $SpaceContainer
@onready var _system_name: Label    = $RightPanel/PanelContent/SystemName
@onready var _star_type:   Label    = $RightPanel/PanelContent/StarType
@onready var _planet_list: VBoxContainer = $RightPanel/PanelContent/PlanetList

var _current:      SolarData
var _star:         ColorRect
var _pivot:        Node2D
var _orbit_lines:  OrbitLines
var _orbits:       Array[PlanetOrbitNode] = []
var _belts:        Array[AsteroidBelt]    = []

var _view_angle:      float     = 0.0
var _dragging:        bool      = false
var _hovered_planet:  PlanetData = null
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

func _ready() -> void:
	($RightPanel/PanelContent/BackButton as Button).pressed.connect(_go_to_galaxy)
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

func _go_to_galaxy() -> void:
	var gd: GalaxyData = null
	if _current != null and _current.has_meta("__galaxy_data"):
		gd = _current.get_meta("__galaxy_data") as GalaxyData
	SceneTransition.go("res://scenes/galaxy/GalaxyView.tscn", gd)

func _on_planet_selected(pd: PlanetData) -> void:
	pd.set_meta("__solar_data", _current)   # carry solar system for the back-button
	SceneTransition.go("res://scenes/planetary/PlanetaryView.tscn", pd)

func load_system(data: SolarData) -> void:
	_current = data
	get_tree().root.set_meta("__active_solar", data)
	_clear()
	_build_star(data)
	_build_planets(data)
	_update_panel(data)
	queue_redraw()

func _clear() -> void:
	for node in _orbits:
		node.queue_free()
	_orbits.clear()
	if _star:
		_star.queue_free()
		_star = null
	if _pivot:
		_pivot.queue_free()
		_pivot = null
	_orbit_lines = null
	_belts.clear()
	for child in _planet_list.get_children():
		child.queue_free()

func _build_star(data: SolarData) -> void:
	var colors           := SolarData.get_star_colors(data.star_type)
	var px_size: float    = float(STAR_PX.get(data.star_type, 210))

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

func _build_planets(data: SolarData) -> void:
	_pivot          = Node2D.new()
	_pivot.position = _star_center()
	_pivot.z_index  = 1
	_space.add_child(_pivot)

	var star_px:   float = float(STAR_PX.get(data.star_type, 210))
	var min_orbit: float = star_px * 0.5 + 40.0

	# max orbit: fits inside SpaceContainer on both axes (star center at 50%/52%)
	var margin:    float = 36.0
	var max_by_x:  float = _space.size.x * 0.50 - margin
	var max_by_y:  float = (_space.size.y * 0.46) / ORBIT_Y_RATIO   # ry = rx * ratio
	var max_orbit: float = min(max_by_x, max_by_y)
	max_orbit = max(max_orbit, min_orbit + 60.0)   # always room for at least one orbit

	var count: int = data.planets.size()

	# Build per-gap step sizes: belt gaps are 2.2x wider than planet gaps.
	# Total weighted slots = (count-1) gaps where belt gaps count as 2.2
	const BELT_FACTOR := 2.2
	var total_weight: float = 0.0
	for gap in count - 1:
		total_weight += BELT_FACTOR if gap in data.asteroid_belt_slots else 1.0
	total_weight = max(total_weight, 1.0)
	var base_step: float = clamp((max_orbit - min_orbit) / total_weight, 50.0, 110.0)

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
			_hovered_planet = pd
			_enter_charge   = 0)
		node.hover_end.connect(func() -> void:
			_hovered_planet = null
			_enter_charge   = 0)
		_pivot.add_child(node)
		node.setup(data.planets[i], radius_x, start_angle)
		_orbits.append(node)

	# asteroid belts — centered in their wide gap
	for slot in data.asteroid_belt_slots:
		if slot < 0 or slot >= count - 1:
			continue
		var inner:   float = orbit_radii_arr[slot]
		var outer:   float = orbit_radii_arr[slot + 1]
		var belt_rx: float = (inner + outer) * 0.5
		var belt := AsteroidBelt.new()
		_pivot.add_child(belt)
		belt.setup(belt_rx, data.seed ^ (slot * 0x1337))
		_belts.append(belt)

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


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
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
	elif event is InputEventMouseMotion and _dragging:
		var mm  := event as InputEventMouseMotion
		# skip tiny motion so single planet clicks still fire
		if mm.relative.length() < 1.5:
			return
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
