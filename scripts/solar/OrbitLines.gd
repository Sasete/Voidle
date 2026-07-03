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
		var col := Color(0.50, 0.62, 0.88, alpha)

		if draw_mode == DrawMode.FULL:
			var pts := PackedVector2Array()
			for j in 97:
				var a: float = float(j) / 96.0 * TAU
				pts.append(Vector2(cos(a) * rx, sin(a) * ry))
			if pts.size() > 1:
				draw_polyline(pts, col, 1.0, false)
		else:
			# Split orbit into continuous segments; include boundary points in both
			# segments so there is no gap at the front/back seam.
			var seg := PackedVector2Array()
			for j in 193:
				var a: float = float(j) / 192.0 * TAU
				var s: float = sin(a)
				var is_front: bool = s >= 0.0
				var want: bool = (draw_mode == DrawMode.FRONT) == is_front
				var on_boundary: bool = absf(s) < 0.0001
				if want or on_boundary:
					seg.append(Vector2(cos(a) * rx, s * ry))
				if (not want and not on_boundary) or j == 192:
					if seg.size() > 1:
						draw_polyline(seg, col, 1.0, false)
					seg.clear()
					# Re-add the last boundary point to start the next segment cleanly
					if on_boundary:
						seg.append(Vector2(cos(a) * rx, s * ry))
