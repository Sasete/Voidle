class_name OrbitLines
extends Node2D

enum DrawMode { FULL, BACK, FRONT }

var orbit_radii: Array[float] = []
var y_ratio: float = 0.38
var draw_mode: DrawMode = DrawMode.FULL

func refresh(radii: Array[float]) -> void:
	orbit_radii = radii
	queue_redraw()

func set_tilt(ratio: float) -> void:
	y_ratio = ratio
	queue_redraw()

func _draw() -> void:
	var count := orbit_radii.size()
	for i in count:
		var rx: float    = orbit_radii[i]
		var ry: float    = rx * y_ratio
		var alpha: float = lerp(0.60, 0.20, float(i) / float(max(count - 1, 1)))
		var pts := PackedVector2Array()
		for j in 97:
			var a: float = float(j) / 96.0 * TAU
			var is_front: bool = sin(a) >= 0.0
			
			if draw_mode == DrawMode.BACK and is_front:
				continue
			if draw_mode == DrawMode.FRONT and not is_front:
				continue
			
			pts.append(Vector2(cos(a) * rx, sin(a) * ry))
			
		if pts.size() > 1:
			draw_polyline(pts, Color(0.50, 0.62, 0.88, alpha), 1.0, false)
