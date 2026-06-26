class_name GalaxyCanvas
extends Node2D

var view: Node   # GalaxyView reference, set after add_child

func _draw() -> void:
	if view and view.has_method("_on_canvas_draw"):
		view._on_canvas_draw()
