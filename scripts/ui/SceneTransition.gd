extends CanvasLayer

var pending_data:   Variant = null
var _overlay:       ColorRect
var _transitioning: bool = false

func _ready() -> void:
	layer  = 128
	_overlay                  = ColorRect.new()
	_overlay.color            = Color(0, 0, 0, 1)   # start fully black
	_overlay.anchor_right     = 1.0
	_overlay.anchor_bottom    = 1.0
	_overlay.grow_horizontal  = 2
	_overlay.grow_vertical    = 2
	_overlay.mouse_filter     = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	_fade_to_clear()           # reveal the first scene

func _fade_to_clear() -> void:
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_overlay, "color:a", 0.0, 0.40)
	tw.tween_callback(func() -> void: _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE)

func go(path: String, data: Variant = null) -> void:
	if _transitioning:
		return
	_transitioning             = true
	pending_data               = data
	_overlay.mouse_filter      = Control.MOUSE_FILTER_STOP
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_overlay, "color:a", 1.0, 0.35)
	tw.tween_callback(func() -> void:
		get_tree().change_scene_to_file(path)
		_transitioning = false
		_fade_to_clear()         # reveal the new scene
	)
