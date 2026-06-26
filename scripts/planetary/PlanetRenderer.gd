extends ColorRect

signal planet_clicked(screen_pos: Vector2)

@export var momentum_decay: float = 0.88

var _dragging := false
var _drag_velocity := 0.0
var _rotation_offset := 0.0
var _last_mouse_x := 0.0
var _planet_radius_px := 0.0

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

func _input(event: InputEvent) -> void:
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
			_last_mouse_x = float(event.position.x)
		elif not event.pressed:
			if _dragging and abs(_drag_velocity) < 0.002:
				planet_clicked.emit(event.position)
			_dragging = false

	if event is InputEventMouseMotion and _dragging:
		var delta_x: float = float(event.position.x) - _last_mouse_x
		_last_mouse_x = float(event.position.x)
		# 1:1 surface mapping: dragging by r_px = π radians rotation
		var delta_rot: float = delta_x / _planet_radius_px
		_rotation_offset = fposmod(_rotation_offset - delta_rot, TAU)
		_drag_velocity = -delta_rot
		if material:
			material.set_shader_parameter("rotation_offset", _rotation_offset)

func _process(_delta: float) -> void:
	if not _dragging and abs(_drag_velocity) > 0.0001:
		_drag_velocity *= momentum_decay
		_rotation_offset = fposmod(_rotation_offset + _drag_velocity, TAU)
		if material:
			material.set_shader_parameter("rotation_offset", _rotation_offset)
