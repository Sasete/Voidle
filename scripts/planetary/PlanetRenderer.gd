extends ColorRect

signal planet_clicked(screen_pos: Vector2)

@export var momentum_decay: float = 0.88

var _dragging := false
var _drag_velocity := 0.0
var _drag_total_px := 0.0
var _rotation_offset := 0.0
var _last_mouse_x := 0.0
var _planet_radius_px := 0.0
## Global light angle (shared time-of-day clock, advances in PlanetaryView._process)
var light_angle: float = 0.0
## Per-planet offset so each world has its own "local noon" position
var local_time_offset: float = 0.0

func _ready() -> void:
	pass  # material assigned externally

func _update_radius() -> void:
	if material == null:
		return
	var r: float = material.get_shader_parameter("planet_radius")
	# radius in screen pixels = height * planet_radius (aspect-corrected circle)
	_planet_radius_px = size.y * r

func get_rotation_offset() -> float:
	return _rotation_offset

func set_rotation_offset(val: float) -> void:
	_rotation_offset = fposmod(val, TAU)
	if material:
		(material as ShaderMaterial).set_shader_parameter("rotation_offset", _rotation_offset)
		# Note: light_direction is recomputed every frame in _process;
		# calling _update_light_direction here too ensures tweens stay in sync.
		_update_light_direction()

func _update_light_direction() -> void:
	if material == null:
		return
	# eff = global_time + planet_local_offset + surface_rotation
	# Adding rotation_offset means the light rotates WITH the terrain:
	# a landmass that's in night stays in night as you spin the planet,
	# giving the feel of a camera orbiting a stationary world.
	var eff: float = light_angle + local_time_offset + _rotation_offset
	var lx := cos(eff) * 0.85
	var lz := sin(eff) * 0.55
	var ld := Vector3(lx, -0.45, lz).normalized()
	(material as ShaderMaterial).set_shader_parameter("light_direction", ld)

func _unhandled_input(event: InputEvent) -> void:
	# Absolutely block and ignore any click, drag, or hover events if SkillTreeView is active
	var root := get_tree().root
	var is_tree_open := false
	for child in root.get_children():
		var script = child.get_script()
		if script != null and script.resource_path.ends_with("SkillTreeView.gd"):
			is_tree_open = true
			break
			
	if is_tree_open:
		_dragging = false
		_drag_velocity = 0.0
		return
			
	_update_radius()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var local := get_local_mouse_position()
		var center := size * 0.5
		# account for aspect ratio when hit-testing the circle
		var ar: float = size.x / size.y if size.y > 0 else 1.0
		var corrected := Vector2((local.x - center.x) * ar, local.y - center.y)
		var dist := corrected.length()
		if event.pressed and dist < _planet_radius_px:
			_dragging = true
			_drag_velocity = 0.0
			_drag_total_px = 0.0
			_last_mouse_x = float(event.position.x)
		elif not event.pressed:
			# Only treat as a tap if total drag distance was small
			if _dragging and _drag_total_px < 8.0:
				planet_clicked.emit(event.position)
			_dragging = false
			_drag_total_px = 0.0

	if event is InputEventMouseMotion and _dragging:
		root = get_tree().root
		is_tree_open = false
		for child in root.get_children():
			var script = child.get_script()
			if script != null and script.resource_path.ends_with("SkillTreeView.gd"):
				is_tree_open = true
				break
				
		if is_tree_open:
			_dragging = false
			_drag_velocity = 0.0
			return
				
		var delta_x: float = float(event.position.x) - _last_mouse_x
		_drag_total_px += abs(delta_x)
		_last_mouse_x = float(event.position.x)
		# 1:1 surface mapping: dragging by r_px = π radians rotation
		var delta_rot: float = delta_x / _planet_radius_px
		_rotation_offset = fposmod(_rotation_offset - delta_rot, TAU)
		_drag_velocity = -delta_rot
		if material:
			material.set_shader_parameter("rotation_offset", _rotation_offset)
			# light_direction synced at end of _process every frame

func _process(_delta: float) -> void:
	if not _dragging and abs(_drag_velocity) > 0.0001:
		_drag_velocity *= momentum_decay
		_rotation_offset = fposmod(_rotation_offset + _drag_velocity, TAU)
		if material:
			material.set_shader_parameter("rotation_offset", _rotation_offset)
	# Always sync light direction at the END of every frame so both
	# rotation_offset (updated above or in _input) and light_angle
	# (updated by PlanetaryView._process which runs before us as the parent)
	# are fully up-to-date before the GPU renders.
	_update_light_direction()
