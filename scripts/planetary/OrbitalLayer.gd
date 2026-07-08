## Draws orbital ships with proper Y-axis (longitude) rotation.
## Ships on the far side of the planet are hidden behind it.
class_name OrbitalLayer
extends Control

var _planet_seed:     int     = -1
var _planet_radius:   float   = 0.0
var _planet_rotation: float   = 0.0   # Y-axis rotation (longitude) from planet drag
var _planet_center:   Vector2 = Vector2.ZERO   # actual planet center in local coords
var _hovered_ship:    ShipData = null
var _selected_ship:   ShipData = null
var suppress_label:   bool     = false   # true when ship panel is open

var _drag_ship:   ShipData = null
var _drag_last_x: float    = 0.0
var _drag_anchor: Vector2  = Vector2.ZERO  # ship 2D pos (in orbit-radius units) at drag start

## Per-ship orbit-reveal: ship_id -> {progress: float, spawn_angle: float}
var _reveal: Dictionary = {}

## Per-POI orbit-reveal: poi_label -> {progress: float, spawn_angle: float}
var _reveal_poi: Dictionary = {}

## Per-ship landing animation state
var _landing: Dictionary = {}

const _LAND_COLLAPSE_DUR: float = 1.20
const _LAND_CURVE_DUR:    float = 2.80
const _LAND_EXPLODE_DUR:  float = 1.40

signal ship_hovered(ship: ShipData, screen_pos: Vector2)
signal ship_unhovered()
signal ship_clicked(ship: ShipData)
signal ship_right_clicked(ship: ShipData, screen_pos: Vector2)
signal ship_deselected()
signal ship_landed(ship: ShipData)
signal rendezvous_reached(ship: ShipData, target: ShipData)

func setup(planet_seed: int) -> void:
	_planet_seed = planet_seed
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ShipManager.ship_changed.connect(_on_ship_changed)

func deselect() -> void:
	if _selected_ship != null:
		_selected_ship = null
		queue_redraw()
		ship_deselected.emit()

func select_ship(ship: ShipData) -> void:
	_selected_ship = ship
	queue_redraw()
	ship_clicked.emit(ship)

func start_landing(ship: ShipData) -> void:
	if _landing.has(ship.ship_id):
		return
	var center := _planet_center if _planet_center != Vector2.ZERO else size * 0.5
	var sv     := _project(ship, ship.orbit_angle)
	var spos   := center + Vector2(sv.x, sv.y)
	# Impact point on planet surface in the direction of the ship
	var impact: Vector2 = center + (spos - center).normalized() * _planet_radius * 0.88
	# Skip orbit-reveal animation for ships that immediately land.
	_reveal[ship.ship_id] = {"progress": 1.0, "spawn_angle": ship.orbit_angle}

	# Freeze position: compute arc from current speed then zero it so the ship
	# doesn't drift during the animation phases.
	var arc: float = ship.orbit_speed * _LAND_CURVE_DUR * 6.0
	ship.orbit_speed = 0.0
	_landing[ship.ship_id] = {
		"phase":       0,
		"progress":    0.0,
		"ship":        ship,
		"spos":        spos,
		"impact":      impact,
		"start_angle": ship.orbit_angle,
		"start_r":     ship.orbit_radius,
		"arc":         arc,
		"sparks":      [],
	}
	if _selected_ship == ship:
		_selected_ship = null
		queue_redraw()
		ship_deselected.emit()

func _process(delta: float) -> void:
	if _planet_seed < 0:
		return
	for ship_id: String in _reveal:
		var rv: Dictionary = _reveal[ship_id]
		if rv["progress"] < 1.0:
			rv["progress"] = minf(rv["progress"] + delta * 1.8, 1.0)
	for poi_label: String in _reveal_poi:
		var rv: Dictionary = _reveal_poi[poi_label]
		if rv["progress"] < 1.0:
			rv["progress"] = minf(rv["progress"] + delta * 0.6, 1.0)
	_tick_landing(delta)
	_tick_rendezvous(delta)
	queue_redraw()

func _tick_rendezvous(delta: float) -> void:
	var ships := ShipManager.ships_for(_planet_seed)
	for ship: ShipData in ships:
		if ship.rendezvous_target_id == "":
			continue
		var target: ShipData = null
		for s: ShipData in ships:
			if s.ship_id == ship.rendezvous_target_id:
				target = s
				break
		if target == null:
			ship.orbit_speed          = ship.rendezvous_base_speed
			ship.rendezvous_target_id = ""
			ship.rendezvous_base_speed = 0.0
			continue

		# Project both ships to 2D screen space and measure distance
		var sv := _project(ship,   ship.orbit_angle)
		var tv := _project(target, target.orbit_angle)
		var spos := Vector2(sv.x, sv.y)
		var tpos := Vector2(tv.x, tv.y)
		var dist := (tpos - spos).length()

		if dist < _planet_radius * 0.07:
			# Arrived — restore original speed
			ship.orbit_speed          = ship.rendezvous_base_speed
			ship.rendezvous_target_id = ""
			ship.rendezvous_base_speed = 0.0
			rendezvous_reached.emit(ship, target)
			continue

		# Boost to 2× speed during rendezvous so shuttle closes the angle gap faster.
		ship.orbit_speed = ship.rendezvous_base_speed * 2.0

		# Rotate orbit_node so the ship's projected position drifts toward the target.
		# Try +step and -step, pick the direction that reduces distance — no U-turns needed.
		var node_step: float = 1.2 * delta
		var sv_plus  := _project_at_node(ship, ship.orbit_node + node_step)
		var sv_minus := _project_at_node(ship, ship.orbit_node - node_step)
		var d_plus   := (Vector2(sv_plus.x,  sv_plus.y)  - tpos).length()
		var d_minus  := (Vector2(sv_minus.x, sv_minus.y) - tpos).length()
		ship.orbit_node += node_step if d_plus < d_minus else -node_step

## Projects ship to 2D using its current orbit_node. Used by drag to keep ship position fixed.
func _project_2d(ship: ShipData, angle: float) -> Vector2:
	var r: float   = _planet_radius * ship.orbit_radius
	var inc: float = ship.orbit_inclination
	var px: float  = r * cos(angle)
	var py: float  = r * sin(angle) * sin(inc)
	var pz: float  = r * sin(angle) * cos(inc)
	var rot: float = _planet_rotation + ship.orbit_node
	var rx: float  = px * cos(rot) + pz * sin(rot)
	return Vector2(rx, py)

func _project_at_node(ship: ShipData, node: float) -> Vector3:
	var r: float   = _planet_radius * ship.orbit_radius
	var inc: float = ship.orbit_inclination
	var a: float   = ship.orbit_angle
	var px: float  = r * cos(a)
	var py: float  = r * sin(a) * sin(inc)
	var pz: float  = r * sin(a) * cos(inc)
	var rot: float = _planet_rotation + node
	var rx: float  =  px * cos(rot) + pz * sin(rot)
	var rz: float  = -px * sin(rot) + pz * cos(rot)
	return Vector3(rx, py, rz)

func _tick_landing(delta: float) -> void:
	var finished: Array[String] = []
	for sid: String in _landing:
		var ld: Dictionary = _landing[sid]
		var dur: float
		match int(ld["phase"]):
			0: dur = _LAND_COLLAPSE_DUR
			1: dur = _LAND_CURVE_DUR
			_: dur = _LAND_EXPLODE_DUR
		ld["progress"] = minf(ld["progress"] + delta / dur, 1.0)

		# Tick spark physics — store as screen offset so planet rotation stays anchored
		if int(ld["phase"]) == 2:
			for spark: Dictionary in ld["sparks"]:
				spark["offset"] = (spark["offset"] as Vector2) + (spark["vel"] as Vector2) * delta
				spark["vel"]    = (spark["vel"] as Vector2) + Vector2(0, 40.0) * delta
				spark["life"]   = (spark["life"] as float) - delta / _LAND_EXPLODE_DUR

		if ld["progress"] >= 1.0:
			ld["phase"]    = int(ld["phase"]) + 1
			ld["progress"] = 0.0
			var ls: ShipData = ld["ship"]
			if int(ld["phase"]) == 1:
				ld["start_angle"] = ls.orbit_angle  # same as initial since speed=0
				ld["start_r"]     = ls.orbit_radius
				# arc already set at start_landing; don't recalculate (orbit_speed is 0)
			elif int(ld["phase"]) == 2:
				# Store impact angle/radius instead of fixed Vector2
				# ep at p=1: 1*(1+1)/2 = 1.0
				ld["impact_angle"] = (ld["start_angle"] as float) + (ld["arc"] as float) * 1.0
				var sparks: Array = []
				for _i in 3:
					sparks.append({
						"offset": Vector2(randf_range(-22.0, 22.0), randf_range(-26.0, -6.0)) * 0.0,
						"vel":    Vector2(randf_range(-22.0, 22.0), randf_range(-26.0, -6.0)),
						"life":   1.0,
					})
				ld["sparks"] = sparks
			elif int(ld["phase"]) >= 3:
				finished.append(sid)
	for sid: String in finished:
		var ship: ShipData = _landing[sid]["ship"]
		_landing.erase(sid)
		ShipManager.remove_ship(ship.orbit_seed, ship.ship_id)
		ship_landed.emit(ship)

func _on_ship_changed(ship: ShipData) -> void:
	if ship.orbit_seed == _planet_seed:
		if not _reveal.has(ship.ship_id):
			_reveal[ship.ship_id] = {"progress": 0.0, "spawn_angle": ship.orbit_angle}
		queue_redraw()

## Projects a ship's 3D orbital position to screen (x,y) and returns depth z.
## z > 0 = behind planet, z < 0 = in front.
func _project(ship: ShipData, angle: float) -> Vector3:
	var r: float   = _planet_radius * ship.orbit_radius
	var inc: float = ship.orbit_inclination
	var px: float  = r * cos(angle)
	var py: float  = r * sin(angle) * sin(inc)
	var pz: float  = r * sin(angle) * cos(inc)
	var rot: float = _planet_rotation + ship.orbit_node
	var rx: float  =  px * cos(rot) + pz * sin(rot)
	var rz: float  = -px * sin(rot) + pz * cos(rot)
	return Vector3(rx, py, rz)

func _is_occluded(proj: Vector3) -> bool:
	return proj.z > 0.0 and Vector2(proj.x, proj.y).length() < _planet_radius

## Pixel-art shuttle: T shape (post-booster-separation look).
func _draw_pixel_ship(pos: Vector2, col: Color) -> void:
	var p  := (pos - Vector2.ONE).floor()
	var sz := Vector2(2, 2)
	draw_rect(Rect2(p + Vector2(-2, -2), sz), col)
	draw_rect(Rect2(p + Vector2( 0, -2), sz), col)
	draw_rect(Rect2(p,                   sz), col)

## Pixel-art ISS: horizontal truss + solar panels + center node.
func _draw_pixel_station(pos: Vector2, col: Color) -> void:
	var p  := (pos - Vector2.ONE).floor()
	var sz := Vector2(2, 2)
	for ox: int in [-4, -2, 0, 2, 4]:
		draw_rect(Rect2(p + Vector2(ox, 0), sz), col)
	draw_rect(Rect2(p + Vector2(0, -2), sz), col)
	draw_rect(Rect2(p + Vector2(0,  2), sz), col)
	draw_rect(Rect2(p + Vector2(-6, -2), sz), col)
	draw_rect(Rect2(p + Vector2(-6,  2), sz), col)
	draw_rect(Rect2(p + Vector2( 6, -2), sz), col)
	draw_rect(Rect2(p + Vector2( 6,  2), sz), col)

## Leader line + name label, like POILayer districts.
func _draw_ship_label(spos: Vector2, ship: ShipData) -> void:
	var font: Font = ThemeDB.fallback_font
	const FONT_SIZE: int = 10
	const DIAG_LEN:  float = 14.0
	const HORIZ_LEN: float = 20.0

	# Pick direction away from planet center
	var center := _planet_center if _planet_center != Vector2.ZERO else size * 0.5
	var horiz_dir: float = 1.0 if spos.x >= center.x else -1.0
	var vert_dir:  float = -1.0 if spos.y >= center.y else 1.0

	var diag_end  := spos + Vector2(horiz_dir * DIAG_LEN * 0.7, vert_dir * DIAG_LEN)
	var horiz_end := diag_end + Vector2(horiz_dir * HORIZ_LEN, 0.0)

	var accent := Color(1.0, 0.92, 0.30, 1.0)   # gold, matches district hover
	var line_col := Color(accent, 0.75)

	# Corner bracket reticle — only the 4 corners, ship sprite stays visible
	const R: float = 10.0   # half-size of bracket box
	const C: float = 4.0    # corner arm length
	const W: float = 1.5    # line width
	var shadow := Color(0, 0, 0, 0.55)
	for ox: int in [-1, 1]:
		for oy: int in [-1, 1]:
			var cx: float = spos.x + ox * R
			var cy: float = spos.y + oy * R
			# Horizontal arm
			draw_line(Vector2(cx, cy), Vector2(cx - ox * C, cy), shadow, W + 1.0, true)
			draw_line(Vector2(cx, cy), Vector2(cx - ox * C, cy), accent, W, true)
			# Vertical arm
			draw_line(Vector2(cx, cy), Vector2(cx, cy - oy * C), shadow, W + 1.0, true)
			draw_line(Vector2(cx, cy), Vector2(cx, cy - oy * C), accent, W, true)

	# Leader lines — start from the corner bracket closest to label direction
	var line_start := spos + Vector2(horiz_dir * R, vert_dir * R)
	draw_line(line_start, diag_end,  line_col, 1.0, true)
	draw_line(diag_end, horiz_end, line_col, 1.0, true)

	# Label
	var label := ship.ship_name
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var label_pos := horiz_end + Vector2(horiz_dir * 3.0, text_size.y * 0.35)
	if horiz_dir < 0.0:
		label_pos.x -= text_size.x

	# Shadow
	for ox: int in [-1, 0, 1]:
		for oy: int in [-1, 0, 1]:
			if ox == 0 and oy == 0:
				continue
			draw_string(font, label_pos + Vector2(ox, oy), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0, 0, 0, 0.85))
	draw_string(font, label_pos, label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, accent)

func _draw() -> void:
	if _planet_seed < 0 or _planet_radius <= 0.0:
		return
	var center := _planet_center if _planet_center != Vector2.ZERO else size * 0.5

	for ship: ShipData in ShipManager.ships_for(_planet_seed):
		if _landing.has(ship.ship_id):
			continue  # drawn by _draw_landing below

		var is_selected: bool = ship == _selected_ship
		var is_hovered:  bool = ship == _hovered_ship

		# ── Orbit path ───────────────────────────────────────────────────────────
		var steps := 90
		var orbit_col: Color
		if is_selected:
			orbit_col = Color(1.0, 0.92, 0.30, 0.75)   # gold, matches district hover
		elif is_hovered:
			orbit_col = Color(1.0, 0.95, 0.5, 0.55)    # warm gold
		elif ship.is_travelling():
			orbit_col = Color(1, 1, 1, 0.45)
		else:
			orbit_col = Color(1, 1, 1, 0.30)

		var rv: Dictionary = _reveal.get(ship.ship_id, {})
		var arc_frac:    float = rv.get("progress",    1.0)
		var spawn_angle: float = rv.get("spawn_angle", 0.0)
		var dir: float = sign(ship.orbit_speed) if ship.orbit_speed != 0.0 else 1.0
		var arc_total: float   = arc_frac * TAU
		var prev_v   := _project(ship, spawn_angle)
		var prev_pos := center + Vector2(prev_v.x, prev_v.y)
		for s in range(1, steps + 1):
			var frac: float = float(s) / float(steps)
			if frac * TAU > arc_total:
				break
			var a: float = spawn_angle + dir * frac * TAU
			var v        := _project(ship, a)
			var cur_pos  := center + Vector2(v.x, v.y)
			var in_dash: bool = (s % 6) < 3
			if in_dash and not _is_occluded(prev_v) and not _is_occluded(v):
				draw_line(prev_pos, cur_pos, orbit_col, 1.5 if is_selected else 1.2, true)
			prev_v   = v
			prev_pos = cur_pos

		# ── Ship pixel art ───────────────────────────────────────────────────────
		var sv := _project(ship, ship.orbit_angle)
		if _is_occluded(sv):
			continue
		var spos := center + Vector2(sv.x, sv.y)
		var col: Color
		if is_selected:
			col = Color(1.0, 0.92, 0.30, 1.0)   # gold
		elif is_hovered:
			col = Color(1.0, 0.92, 0.40)
		else:
			col = Color(1, 1, 1, 0.92)

		if ship.ship_type == "station":
			_draw_pixel_station(spos, col)
		else:
			_draw_pixel_ship(spos, col)

		# ── Selected: bracket reticle + label (suppressed when panel open)
		# ── Hovered (not selected): leader line + name, like districts
		if is_selected:
			if suppress_label:
				_draw_brackets_only(spos)
			else:
				_draw_ship_label(spos, ship)
		elif is_hovered:
			_draw_hover_label(spos, ship)

	# ── Landing animations ───────────────────────────────────────────────────
	for sid: String in _landing:
		_draw_landing(_landing[sid])

	# ── Space station districts ───────────────────────────────────────────────
	_draw_station_pois(center)

func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
	var mt := 1.0 - t
	return mt * mt * p0 + 2.0 * mt * t * p1 + t * t * p2

## Like _project but with a custom orbit_radius fraction (for landing spiral).
func _project_r(ship: ShipData, angle: float, orbit_r: float) -> Vector2:
	var center := _planet_center if _planet_center != Vector2.ZERO else size * 0.5
	var r: float   = _planet_radius * orbit_r
	var inc: float = ship.orbit_inclination
	var px: float  = r * cos(angle)
	var py: float  = r * sin(angle) * sin(inc)
	var pz: float  = r * sin(angle) * cos(inc)
	var rot: float = _planet_rotation + ship.orbit_node
	var rx: float  =  px * cos(rot) + pz * sin(rot)
	return center + Vector2(rx, py)

func _draw_landing(ld: Dictionary) -> void:
	var phase:    int   = int(ld["phase"])
	var progress: float = ld["progress"]
	var ship:     ShipData = ld["ship"]
	var center := _planet_center if _planet_center != Vector2.ZERO else size * 0.5

	match phase:
		0:
			# ── Orbit collapse: arc shrinks from tail, HEAD stays locked to ship position
			var dir: float    = sign(ship.orbit_speed) if ship.orbit_speed != 0.0 else 1.0
			var remaining: float = (1.0 - progress) * TAU
			# HEAD = ship's current angle, TAIL = head - dir * remaining
			var head_a: float  = ship.orbit_angle
			var tail_a: float  = head_a - dir * remaining
			var col := Color(1, 1, 1, (1.0 - progress) * 0.30)
			var steps := 60
			var prev_v  := _project(ship, tail_a)
			var prev_p  := center + Vector2(prev_v.x, prev_v.y)
			for s in range(1, steps + 1):
				var frac: float = float(s) / float(steps)
				if frac * TAU > remaining:
					break
				var a: float = tail_a + dir * frac * TAU
				var v        := _project(ship, a)
				var cur_p    := center + Vector2(v.x, v.y)
				if (s % 6) < 3 and not _is_occluded(prev_v) and not _is_occluded(v):
					draw_line(prev_p, cur_p, col, 1.2, true)
				prev_v = v
				prev_p = cur_p
			# Ship at its current orbit position
			var sv := _project(ship, ship.orbit_angle)
			if not _is_occluded(sv):
				var sp := center + Vector2(sv.x, sv.y)
				if ship.ship_type == "station":
					_draw_pixel_station(sp, Color(1, 1, 1, 0.92))
				else:
					_draw_pixel_ship(sp, Color(1, 1, 1, 0.92))

		1:
			# ── Orbital descent: accelerating spiral, projection line ahead of ship
			var start_angle: float = ld["start_angle"]
			var start_r: float     = ld["start_r"]
			var arc: float         = ld["arc"]
			const RADIUS_DROP: float = 0.12  # total inward drop over full descent

			# Easing: p*(1+p)/2 → starts at orbital speed, smoothly accelerates
			var ep: float = progress * (1.0 + progress) / 2.0
			var angle: float = start_angle + arc * ep
			var cur_r: float = start_r - RADIUS_DROP * ep

			# ── Projection line: dashed, shows remaining path, fades as ship advances
			var proj_steps := 28
			var prev_proj  := _project_r(ship, angle, cur_r)
			for s in range(1, proj_steps + 1):
				var pt: float  = progress + float(s) / float(proj_steps) * (1.0 - progress)
				var pet: float = pt * (1.0 + pt) / 2.0
				var pa: float  = start_angle + arc * pet
				var pr: float  = start_r - RADIUS_DROP * pet
				var pv         := _project_r(ship, pa, pr)
				if (s % 5) < 3:
					draw_line(prev_proj, pv,
						Color(1.0, 0.65, 0.25, 0.35 * (1.0 - progress)), 1.0, true)
				prev_proj = pv

			# ── Trail behind ship
			for ti in 6:
				var tt: float  = maxf(0.0, progress - float(ti + 1) * 0.032)
				var tet: float = tt * (1.0 + tt) / 2.0
				var ta: float  = start_angle + arc * tet
				var tr: float  = start_r - RADIUS_DROP * tet
				var tp         := _project_r(ship, ta, tr)
				var alpha: float = (1.0 - float(ti) / 6.0) * 0.50
				draw_circle(tp, 1.3, Color(1.0, 0.55, 0.15, alpha))

			var ship_pos := _project_r(ship, angle, cur_r)
			var col       := Color(1.0, 0.88, 0.55, 1.0 - progress * 0.25)
			if ship.ship_type == "station":
				_draw_pixel_station(ship_pos, col)
			else:
				_draw_pixel_ship(ship_pos, col)

		2:
			# ── Explosion sparks — anchor re-projected each frame so planet rotation is tracked
			var imp_angle: float = ld["impact_angle"]
			var imp: Vector2     = _project_r(ship, imp_angle, (ld["start_r"] as float) - 0.12)
			for spark: Dictionary in ld["sparks"]:
				var life: float   = maxf(0.0, spark["life"] as float)
				var sp: Vector2   = imp + (spark["offset"] as Vector2)
				draw_rect(Rect2(sp.floor(), Vector2(2, 2)),
					Color(1.0, 0.15 + life * 0.2, 0.05, life))

## Hover nameplate: leader line + name only, no bracket reticle. Like districts on hover.
func _draw_hover_label(spos: Vector2, ship: ShipData) -> void:
	var font: Font = ThemeDB.fallback_font
	const FONT_SIZE: int = 10
	var center := _planet_center if _planet_center != Vector2.ZERO else size * 0.5
	var horiz_dir: float = 1.0 if spos.x >= center.x else -1.0
	var vert_dir:  float = -1.0 if spos.y >= center.y else 1.0
	var diag_end  := spos + Vector2(horiz_dir * 9.8,   vert_dir * 14.0)
	var horiz_end := diag_end + Vector2(horiz_dir * 20.0, 0.0)
	var accent := Color(1.0, 0.95, 0.55, 0.85)
	draw_line(spos, diag_end,  Color(accent, 0.65), 1.0, true)
	draw_line(diag_end, horiz_end, Color(accent, 0.65), 1.0, true)
	var label := ship.ship_name
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var label_pos := horiz_end + Vector2(horiz_dir * 3.0, text_size.y * 0.35)
	if horiz_dir < 0.0:
		label_pos.x -= text_size.x
	for ox: int in [-1, 0, 1]:
		for oy: int in [-1, 0, 1]:
			if ox == 0 and oy == 0: continue
			draw_string(font, label_pos + Vector2(ox, oy), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0, 0, 0, 0.75))
	draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, accent)

func _draw_brackets_only(spos: Vector2) -> void:
	const R: float = 10.0
	const C: float = 4.0
	const W: float = 1.5
	var accent := Color(1.0, 0.92, 0.30, 1.0)
	var shadow := Color(0, 0, 0, 0.55)
	for ox: int in [-1, 1]:
		for oy: int in [-1, 1]:
			var cx: float = spos.x + ox * R
			var cy: float = spos.y + oy * R
			draw_line(Vector2(cx, cy), Vector2(cx - ox * C, cy), shadow, W + 1.0, true)
			draw_line(Vector2(cx, cy), Vector2(cx - ox * C, cy), accent, W, true)
			draw_line(Vector2(cx, cy), Vector2(cx, cy - oy * C), shadow, W + 1.0, true)
			draw_line(Vector2(cx, cy), Vector2(cx, cy - oy * C), accent, W, true)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _drag_ship != null:
			var dx: float = event.global_position.x - _drag_last_x
			_drag_last_x = event.global_position.x
			_drag_ship.orbit_node += dx * 0.012
			# Re-find orbit_angle so ship stays at anchor screen position (ring rotates, ship fixed).
			var a: float = _drag_ship.orbit_angle
			for _i in 10:
				var p0: Vector2 = _project_2d(_drag_ship, a)
				var p1: Vector2 = _project_2d(_drag_ship, a + 0.005)
				var tangent: Vector2 = (p1 - p0) / 0.005
				var err: Vector2 = p0 - _drag_anchor
				if tangent.length_squared() < 0.0001:
					break
				a -= err.dot(tangent) / tangent.length_squared()
			_drag_ship.orbit_angle = a
			# Dragging manually cancels any active rendezvous
			if _drag_ship.rendezvous_target_id != "":
				_drag_ship.orbit_speed          = _drag_ship.rendezvous_base_speed
				_drag_ship.rendezvous_target_id  = ""
				_drag_ship.rendezvous_base_speed = 0.0
			queue_redraw()
			accept_event()
			return
		var prev := _hovered_ship
		_hovered_ship = _ship_at(event.global_position)
		if _hovered_ship != prev:
			queue_redraw()
			if _hovered_ship != null:
				ship_hovered.emit(_hovered_ship, event.global_position)
				CursorManager.set_state(CursorManager.State.POINTER)
			else:
				ship_unhovered.emit()
				CursorManager.set_state(CursorManager.State.NORMAL)
		# Station hover
		var local_pos := get_local_mouse_position()
		var prev_st := _hovered_station
		_hovered_station = _station_poi_at(local_pos)
		if _hovered_station != prev_st:
			queue_redraw()
			if _hovered_station != "":
				AudioManager.play("district_hover")
				CursorManager.set_state(CursorManager.State.POINTER)
			else:
				CursorManager.set_state(CursorManager.State.NORMAL)

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _selected_station != "":
				_selected_station = ""
				queue_redraw()
				accept_event()
				return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Check station click first
				var local_pos := get_local_mouse_position()
				var st := _station_poi_at(local_pos)
				if st != "":
					AudioManager.play("click")
					station_poi_clicked.emit(st)
					accept_event()
					return
				var clicked := _ship_at(mb.global_position)
				if clicked != null:
					_selected_ship = clicked
					_drag_ship     = clicked
					_drag_last_x   = mb.global_position.x
					var sv := _project(clicked, clicked.orbit_angle)
					_drag_anchor   = Vector2(sv.x, sv.y)
					queue_redraw()
					ship_clicked.emit(clicked)
					accept_event()
			else:
				if _drag_ship != null:
					_drag_ship = null

## ── Space Station POI drawing ────────────────────────────────────────────────

signal station_poi_clicked(poi_label: String)

var _hovered_station:  String = ""
var _selected_station: String = ""

func set_selected_station(label: String) -> void:
	_selected_station = label
	queue_redraw()

func _draw_station_pois(center: Vector2) -> void:
	var pd := GameState.get_planet_data(_planet_seed)
	if pd == null:
		return
	for poi: POIData in pd.custom_pois:
		if not poi.is_orbital():
			continue
		if poi.constructing:
			continue   # hidden while rocket is in flight; deploy anim plays on arrival
		var is_selected: bool = poi.label == _selected_station
		var is_hovered:  bool = poi.label == _hovered_station
		var col: Color
		if is_selected:
			col = Color(1.0, 0.92, 0.30, 1.0)   # gold — matches ship selected
		elif is_hovered:
			col = Color(1.0, 0.95, 0.5, 0.90)
		else:
			col = Color(0.65, 0.75, 1.0, 0.85)
		# Dashed orbit trail (progressive reveal on first appearance)
		var orbit_col: Color
		if is_selected:
			orbit_col = Color(1.0, 0.92, 0.30, 0.75)
		elif is_hovered:
			orbit_col = Color(1.0, 0.95, 0.5, 0.55)
		else:
			orbit_col = Color(col, 0.30)
		if not _reveal_poi.has(poi.label):
			_reveal_poi[poi.label] = {"progress": 0.0, "spawn_angle": poi.orbit_angle}
		var rv_poi: Dictionary = _reveal_poi[poi.label]
		var arc_frac: float = rv_poi["progress"]
		var spawn_a:  float = rv_poi["spawn_angle"]
		var dir_p:    float = sign(poi.orbit_speed) if poi.orbit_speed != 0.0 else 1.0
		var arc_total: float = arc_frac * TAU
		const STEPS := 72
		var prev_v  := _project_poi(poi, spawn_a)
		var prev_p  := center + Vector2(prev_v.x, prev_v.y)
		for s in range(1, STEPS + 1):
			var frac: float = float(s) / float(STEPS)
			if frac * TAU > arc_total:
				break
			var a := spawn_a + dir_p * frac * TAU
			var v := _project_poi(poi, a)
			var p := center + Vector2(v.x, v.y)
			if (s % 6) < 3 and not _is_occluded_r(prev_v) \
					and not _is_occluded_r(v):
				draw_line(prev_p, p, orbit_col, 1.5 if is_selected else 1.2, true)
			prev_v = v; prev_p = p
		# Icon
		var sv := _project_poi(poi, poi.orbit_angle)
		if _is_occluded_r(sv):
			continue
		var spos := center + Vector2(sv.x, sv.y)
		_draw_pixel_station(spos, col)
		if is_selected:
			_draw_station_label(spos, poi.label)
		elif is_hovered and not suppress_label:
			_draw_station_label(spos, poi.label)

func _draw_station_label(spos: Vector2, label: String) -> void:
	var font := ThemeDB.fallback_font
	const FS := 10; const DL := 14.0; const HL := 20.0
	var center  := _planet_center if _planet_center != Vector2.ZERO else size * 0.5
	var hd      := 1.0 if spos.x >= center.x else -1.0
	var vd      := -1.0 if spos.y >= center.y else 1.0
	var de      := spos + Vector2(hd * DL * 0.7, vd * DL)
	var he      := de + Vector2(hd * HL, 0.0)
	var accent  := Color(1.0, 0.92, 0.30, 1.0)
	var lc      := Color(accent, 0.75)
	const R := 10.0; const C := 4.0; const W := 1.5
	var shadow := Color(0, 0, 0, 0.55)
	for ox: int in [-1, 1]:
		for oy: int in [-1, 1]:
			var cx := spos.x + ox * R; var cy := spos.y + oy * R
			draw_line(Vector2(cx, cy), Vector2(cx - ox * C, cy), shadow, W + 1, true)
			draw_line(Vector2(cx, cy), Vector2(cx - ox * C, cy), accent, W, true)
			draw_line(Vector2(cx, cy), Vector2(cx, cy - oy * C), shadow, W + 1, true)
			draw_line(Vector2(cx, cy), Vector2(cx, cy - oy * C), accent, W, true)
	draw_line(spos, de, lc, 1.0, true); draw_line(de, he, lc, 1.0, true)
	var ts  := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FS)
	var lp  := he + Vector2(hd * 3.0, ts.y * 0.35)
	if hd < 0.0: lp.x -= ts.x
	for ox: int in [-1, 0, 1]:
		for oy: int in [-1, 0, 1]:
			if ox == 0 and oy == 0: continue
			draw_string(font, lp + Vector2(ox, oy), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, Color(0,0,0,0.85))
	draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, FS, accent)

## Projects POIData orbital position to 3D (z > 0 = behind planet).
func _project_poi(poi: POIData, angle: float) -> Vector3:
	var r   := _planet_radius * poi.orbit_radius
	var inc := poi.orbit_inclination
	var px  := r * cos(angle)
	var py  := r * sin(angle) * sin(inc)
	var pz  := r * sin(angle) * cos(inc)
	var rot := _planet_rotation + poi.orbit_node
	var rx  :=  px * cos(rot) + pz * sin(rot)
	var rz  := -px * sin(rot) + pz * cos(rot)
	return Vector3(rx, py, rz)

func _is_occluded_r(proj: Vector3) -> bool:
	return proj.z > 0.0 and Vector2(proj.x, proj.y).length() < _planet_radius

func _station_poi_at(local_pos: Vector2) -> String:
	if _planet_seed < 0 or _planet_radius <= 0.0:
		return ""
	var center := _planet_center if _planet_center != Vector2.ZERO else size * 0.5
	var pd := GameState.get_planet_data(_planet_seed)
	if pd == null:
		return ""
	for poi: POIData in pd.custom_pois:
		if not poi.is_orbital():
			continue
		var sv := _project_poi(poi, poi.orbit_angle)
		if _is_occluded_r(sv):
			continue
		if local_pos.distance_to(center + Vector2(sv.x, sv.y)) <= 12.0:
			return poi.label
	return ""

func _ship_at(global_pos: Vector2) -> ShipData:
	if _planet_seed < 0 or _planet_radius <= 0.0:
		return null
	var center := get_global_rect().position + (_planet_center if _planet_center != Vector2.ZERO else size * 0.5)
	for ship: ShipData in ShipManager.ships_for(_planet_seed):
		var sv := _project(ship, ship.orbit_angle)
		if _is_occluded(sv):
			continue
		var spos := center + Vector2(sv.x, sv.y)
		if global_pos.distance_to(spos) <= 8.0:
			return ship
	return null
