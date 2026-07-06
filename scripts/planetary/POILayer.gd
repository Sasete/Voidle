extends Node2D

signal poi_clicked(index: int, data: Dictionary)

const DOT_RADIUS       := 5.0
const DOT_HOVER_RADIUS := 8.0
const LINE_DIAG_LEN    := 28.0
const LINE_HORIZ_LEN   := 52.0
const FONT_SIZE        := 15
const NIGHT_GLOW_MAX   := 5.0   # max glow radius in pixels
const NIGHT_GLOW_MIN   := 0.8   # glow radius for a single active building

var _planet: ColorRect
var _pois: Array[Dictionary] = []
var _hovered_index:  int = -1
var _selected_index: int = -1

func setup(renderer: ColorRect) -> void:
	_planet = renderer
	set_process_input(true)

func clear_pois() -> void:
	_pois.clear()
	_hovered_index  = -1
	_selected_index = -1

func deselect_all() -> void:
	_hovered_index  = -1
	_selected_index = -1
	queue_redraw()

func select_poi(index: int) -> void:
	_selected_index = index
	queue_redraw()

func add_poi(lon_deg: float, lat_deg: float, label: String, data: Dictionary = {}) -> void:
	_pois.append({
		"lon":    deg_to_rad(lon_deg),
		"lat":    deg_to_rad(lat_deg),
		"label":  label,
		"data":   data,
		"screen": Vector2.ZERO,
		"visible": false,
		"alpha":  0.0,
	})

func _get_planet_params() -> Dictionary:
	if not _planet or not _planet.material:
		return {}
	var center := _planet.global_position + _planet.size * 0.5
	var radius_frac: float = _planet.material.get_shader_parameter("planet_radius")
	var aspect: float      = _planet.material.get_shader_parameter("aspect_ratio")
	var r_px := _planet.size.y * radius_frac  # radius in screen pixels (based on height)
	return {"center": center, "r_px": r_px, "aspect": aspect}

func _get_rotation() -> float:
	if _planet and _planet.has_method("get_rotation_offset"):
		return _planet.get_rotation_offset()
	return 0.0

func _process(_delta: float) -> void:
	if not _planet:
		return
	var p := _get_planet_params()
	if p.is_empty():
		return
	var center: Vector2 = p["center"]
	var r_px: float     = p["r_px"]
	var rot: float      = _get_rotation()

	for poi in _pois:
		var lon: float = poi["lon"] - rot
		var lat: float = poi["lat"]
		var sx  := sin(lon) * cos(lat)
		var sy  := -sin(lat)
		var sz  := cos(lon) * cos(lat)

		poi["screen"]  = center + Vector2(sx * r_px, sy * r_px)
		poi["sz"]      = sz            # store raw depth for glow culling
		poi["alpha"]   = clamp(sz * 4.0, 0.0, 1.0)
		poi["visible"] = sz > -0.05
		poi["lat_f"]   = lat   # store for direction

	var keep_texts: Array[Dictionary] = []
	for ft in _floating_texts:
		ft.time += _delta
		if ft.time < ft.max_time:
			var lon: float = ft.lon - rot
			var lat: float = ft.lat
			var sx  := sin(lon) * cos(lat)
			var sy  := -sin(lat)
			var sz  := cos(lon) * cos(lat)
			ft.screen  = center + Vector2(sx * r_px, sy * r_px)
			ft.visible = sz > -0.05
			ft.alpha   = clamp(sz * 4.0, 0.0, 1.0)
			keep_texts.append(ft)
	_floating_texts = keep_texts

	queue_redraw()

var _orbitron: Font
var _floating_texts: Array[Dictionary] = []

func spawn_floating_text(lon_deg: float, lat_deg: float, text: String, color: Color = Color.WHITE, font_size: int = 14, icon: Texture2D = null) -> void:
	_floating_texts.append({
		"lon": deg_to_rad(lon_deg),
		"lat": deg_to_rad(lat_deg),
		"text": text,
		"color": color,
		"time": 0.0,
		"max_time": 2.5,
		"visible": true,
		"screen": Vector2.ZERO,
		"alpha": 1.0,
		"font_size": font_size,
		"icon": icon
	})

func _ready() -> void:
	_orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")

func _draw() -> void:
	if _pois.is_empty() and _floating_texts.is_empty():
		return
	var font: Font = _orbitron if _orbitron else ThemeDB.fallback_font

	for ft in _floating_texts:
		if not ft.visible: continue
		
		var progress: float = ft.time / ft.max_time
		var text_alpha: float = (1.0 - progress * progress) * ft.alpha
		if text_alpha <= 0.0: continue
		
		var float_up_offset := Vector2(0, -progress * 40.0)
		var pos: Vector2 = ft.screen + float_up_offset
		
		var c: Color = ft.color
		c.a *= text_alpha
		
		var f_size: int = ft.get("font_size", 14)
		var text_width := font.get_string_size(ft.text, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size).x
		
		var icon_tex: Texture2D = ft.get("icon")
		var total_w := text_width
		var icon_size := 16.0
		if icon_tex != null:
			total_w += icon_size + 4.0
			
		var start_x := pos.x - total_w * 0.5
		
		var text_x := start_x
		if icon_tex != null:
			var icon_pos := Vector2(start_x, pos.y - icon_size * 0.8)
			draw_texture_rect(icon_tex, Rect2(icon_pos, Vector2(icon_size, icon_size)), false, Color(1, 1, 1, c.a))
			text_x += icon_size + 4.0
			
		var text_pos := Vector2(text_x, pos.y)
		
		draw_string_outline(font, text_pos, ft.text, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size, 1, Color(0, 0, 0, c.a * 0.8))
		draw_string(font, text_pos, ft.text, HORIZONTAL_ALIGNMENT_LEFT, -1, f_size, c)

	for i in _pois.size():
		var poi: Dictionary = _pois[i]

		# ── Night-side glow ──────────────────────────────────────────────────────
		# Draw city-light glow only for POIs that face the camera (sz > 0)
		# but have low alpha (near the terminator / in shadow from the light).
		# Back-facing POIs (sz ≤ 0) project inside the planet disc and must
		# NOT draw anything — otherwise they appear as stray 1-px yellow dots.
		var poi_sz: float = poi.get("sz", 1.0)
		var data_dict: Dictionary = poi.get("data", {}) as Dictionary
		var night_size: int = data_dict.get("night_size", 0)
		if night_size > 0 and poi_sz > 0.05 and poi["alpha"] < 0.55:
			var p2 := _get_planet_params()
			if not p2.is_empty():
				var center2: Vector2 = p2["center"]
				var r_px2: float     = p2["r_px"]
				var rot2: float      = _get_rotation()
				var lon2: float = poi["lon"] - rot2
				var lat2: float = poi["lat"]
				var sx2  := sin(lon2) * cos(lat2)
				var sy2  := -sin(lat2)
				# Fade glow as POI approaches the terminator (alpha rising toward 0.55)
				var night_a: float = clampf((0.55 - poi["alpha"]) * 3.0, 0.0, 1.0)
				var glow_r: float  = clampf(
					NIGHT_GLOW_MIN + float(night_size - 1) * 0.8,
					NIGHT_GLOW_MIN, NIGHT_GLOW_MAX)
				var sp2: Vector2 = center2 + Vector2(sx2 * r_px2, sy2 * r_px2) - global_position
				draw_circle(sp2, glow_r + 2.5, Color(1.0, 0.72, 0.28, night_a * 0.07))
				draw_circle(sp2, glow_r + 1.2, Color(1.0, 0.85, 0.45, night_a * 0.18))
				draw_circle(sp2, glow_r,        Color(1.0, 0.95, 0.65, night_a * 0.38))
				draw_circle(sp2, maxf(glow_r * 0.5, 0.5),
					Color(1.0, 1.0, 0.92, night_a * 0.65))

		if not poi["visible"]:
			continue

		var alpha: float  = poi["alpha"]
		var sp: Vector2   = poi["screen"] - global_position
		var lat: float    = poi["lat_f"]
		var hovered: bool = (i == _hovered_index)

		# direction: away from equator (north→up, south→down)
		var vert_dir: float = -sign(lat) if abs(lat) > 0.05 else -1.0
		# horizontal: use sine of effective longitude — positive lon half → right
		# This avoids screen-space center flip when POI crosses center
		var eff_lon: float = poi["lon"] - _get_rotation()
		var horiz_dir: float = sign(sin(eff_lon))
		if horiz_dir == 0.0:
			horiz_dir = 1.0

		var diag_end := sp + Vector2(horiz_dir * LINE_DIAG_LEN * 0.7, vert_dir * LINE_DIAG_LEN)
		var horiz_end := diag_end + Vector2(horiz_dir * LINE_HORIZ_LEN, 0.0)

		var col := Color(0.85, 0.85, 0.85, alpha * 0.9)
		var selected: bool = (i == _selected_index)
		var active: bool   = hovered or selected
		var dot_col := Color(1.0, 0.95, 0.5, alpha) if active else Color(1.0, 0.82, 0.25, alpha)
		var dot_r   := DOT_HOVER_RADIUS if active else DOT_RADIUS

		# dot — circle normally, filled square when hovered or selected
		if active:
			var half := dot_r
			draw_rect(Rect2(sp - Vector2(half + 1.5, half + 1.5), Vector2((half + 1.5) * 2, (half + 1.5) * 2)),
				Color(0, 0, 0, alpha * 0.55))
			draw_rect(Rect2(sp - Vector2(half, half), Vector2(half * 2, half * 2)), dot_col)
			var ring := half + 3.5
			var ring_col := Color(1.0, 0.95, 0.5, alpha * 0.80) if selected else Color(1.0, 0.95, 0.5, alpha * 0.55)
			draw_rect(Rect2(sp - Vector2(ring, ring), Vector2(ring * 2, ring * 2)),
				ring_col, false, 1.2 if hovered else 1.5)
		else:
			draw_circle(sp, dot_r + 1.5, Color(0, 0, 0, alpha * 0.5))
			draw_circle(sp, dot_r, dot_col)

		# leader lines
		draw_line(sp, diag_end, col, 1.0, true)
		draw_line(diag_end, horiz_end, col, 1.0, true)

		# label
		var label: String = poi["label"]
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		var label_pos := horiz_end + Vector2(horiz_dir * 3.0, text_size.y * 0.35)
		if horiz_dir < 0.0:
			label_pos.x -= text_size.x

		# thick outline
		var oc := Color(0.0, 0.0, 0.0, alpha * 0.90)
		for ox: int in [-1, 0, 1]:
			for oy: int in [-1, 0, 1]:
				if ox == 0 and oy == 0:
					continue
				draw_string(font, label_pos + Vector2(ox * 1.5, oy * 1.5), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, oc)
		# foreground
		var fc := Color(1.0, 0.95, 0.5, alpha) if hovered else Color(1.0, 1.0, 1.0, alpha)
		draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, fc)

		# district level sub-label
		var dist_lv: int = poi["data"].get("district_level", 0)
		if dist_lv > 0:
			const LV_SIZE := 10
			var lv_str := "Lv %d" % dist_lv
			var lv_pos := label_pos + Vector2(0, text_size.y * 0.9)
			if horiz_dir < 0.0:
				var lv_w := font.get_string_size(lv_str, HORIZONTAL_ALIGNMENT_LEFT, -1, LV_SIZE).x
				lv_pos.x = label_pos.x + text_size.x - lv_w
			draw_string(font, lv_pos + Vector2(1, 1), lv_str,
				HORIZONTAL_ALIGNMENT_LEFT, -1, LV_SIZE, Color(0, 0, 0, alpha * 0.7))
			draw_string(font, lv_pos, lv_str,
				HORIZONTAL_ALIGNMENT_LEFT, -1, LV_SIZE, Color(0.65, 0.85, 1.0, alpha * 0.85))

func _unhandled_input(event: InputEvent) -> void:
	if not _planet:
		return

	if event is InputEventMouseMotion:
		var prev := _hovered_index
		_hovered_index = _get_poi_at(event.global_position)
		if _hovered_index != prev:
			queue_redraw()
			if _hovered_index >= 0:
				AudioManager.play("poi_ping")
				CursorManager.set_state(CursorManager.State.POINTER)
			else:
				CursorManager.set_state(CursorManager.State.NORMAL)

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var idx := _get_poi_at(event.global_position)
		if idx >= 0:
			AudioManager.play("poi_select")
			_selected_index = idx
			queue_redraw()
			poi_clicked.emit(idx, _pois[idx]["data"])
			get_viewport().set_input_as_handled()

## Returns the global screen position of the POI with the given label, or Vector2.ZERO.
func get_poi_screen_pos(label: String) -> Vector2:
	for poi: Dictionary in _pois:
		if poi["label"] == label:
			return poi["screen"]
	return Vector2.ZERO

## Returns the (lon, lat) in radians for the given label, or Vector2.ZERO.
func get_poi_lon_lat(label: String) -> Vector2:
	for poi: Dictionary in _pois:
		if poi["label"] == label:
			return Vector2(poi["lon"], poi["lat"])
	return Vector2.ZERO

func _get_poi_at(global_pos: Vector2) -> int:
	for i in _pois.size():
		var poi: Dictionary = _pois[i]
		if not poi["visible"] or poi["alpha"] < 0.3:
			continue
		var sp: Vector2 = poi["screen"]
		if global_pos.distance_to(sp) <= DOT_HOVER_RADIUS + 4.0:
			return i
	return -1
