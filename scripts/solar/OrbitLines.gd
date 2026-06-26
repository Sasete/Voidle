class_name OrbitLines
extends Node2D

# Positioned at star center. Draws orbit ellipses centered at (0,0).
var orbit_radii: Array[float] = []
var y_ratio: float = 0.38

func refresh(radii: Array[float]) -> void:
	orbit_radii = radii
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
			pts.append(Vector2(cos(a) * rx, sin(a) * ry))
		draw_polyline(pts, Color(0.50, 0.62, 0.88, alpha), 1.0, true)
