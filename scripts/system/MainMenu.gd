extends Control

const PLANET_SIZE   := 680.0
const ROTATE_SPEED  := 0.018
const ORBITRON      := "res://Fonts/Orbitron-VariableFont_wght.ttf"

const CREDITS_LINES := [
	"Developed by Tufan T. Iskender",
	"Thanks to Irem Iskender",
	"Mira Iskender",
	"Ada Iskender",
	"Adem Ozcan",
	"InEv Games",
]
const CREDITS_HOLD     := 4.2   # seconds per line
const GLITCH_CHARS     := "!@#$%^&*<>?/\\|[]{}~±§"
const GLITCH_STEPS     := 16
const GLITCH_STEP_DUR  := 0.06

var _planet_rect:   ColorRect
var _rotation_off:  float = 0.0
var _light_angle:   float = 0.8
var _font:          Font
var _credits_lbl:   Label
var _credits_idx:   int   = 0
var _cont_btn:      Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	anchor_right  = 1.0
	anchor_bottom = 1.0
	HUDManager.set_game_hud(false)
	_font = load(ORBITRON) as Font

	_build_bg()
	_build_stars()
	_build_planet()
	_build_menu()
	_build_credits()

# ── Background ─────────────────────────────────────────────────────────────

func _build_bg() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.02, 0.06)
	add_child(bg)

# ── Drifting stars ─────────────────────────────────────────────────────────

func _build_stars() -> void:
	var vp := get_viewport().get_visible_rect().size

	# Slow background layer
	_make_star_layer(vp, 180, 8.0,  Color(0.7, 0.75, 1.0, 0.45), 1.0)
	# Medium layer
	_make_star_layer(vp, 80,  18.0, Color(0.85, 0.90, 1.0, 0.65), 1.6)
	# Fast bright layer
	_make_star_layer(vp, 30,  32.0, Color(1.0,  1.0,  1.0, 0.90), 2.0)

func _make_star_layer(vp: Vector2, count: int, speed: float, col: Color, size: float) -> void:
	var p := CPUParticles2D.new()
	p.emitting              = true
	p.amount                = count
	p.lifetime              = (vp.x + 60.0) / speed
	p.preprocess            = p.lifetime          # start full
	p.explosiveness         = 0.0
	p.randomness            = 1.0

	p.emission_shape        = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(vp.x * 0.5 + 40.0, vp.y * 0.5)
	p.position              = Vector2(vp.x * 0.5, vp.y * 0.5)

	p.direction             = Vector2(-1.0, 0.0)
	p.spread                = 3.0
	p.gravity               = Vector2.ZERO
	p.initial_velocity_min  = speed * 0.8
	p.initial_velocity_max  = speed * 1.2
	p.scale_amount_min      = size * 0.6
	p.scale_amount_max      = size * 1.4

	# Twinkle: vary alpha over lifetime with a curve
	var grad := Gradient.new()
	grad.set_color(0, Color(col.r, col.g, col.b, 0.0))
	grad.set_color(1, col)
	grad.add_point(0.05, col)
	grad.add_point(0.95, col)
	p.color_ramp = grad

	add_child(p)

# ── Planet ─────────────────────────────────────────────────────────────────

func _build_planet() -> void:
	var vp := get_viewport().get_visible_rect().size

	_planet_rect = ColorRect.new()
	_planet_rect.custom_minimum_size = Vector2(PLANET_SIZE, PLANET_SIZE)
	_planet_rect.size                = Vector2(PLANET_SIZE, PLANET_SIZE)
	# Center sits just inside top-right; bottom-left half peeks into view
	_planet_rect.position = Vector2(
		vp.x - PLANET_SIZE * 0.78,
		-PLANET_SIZE * 0.32
	)
	_planet_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_planet_rect)

	var data := PlanetData.from_seed_no_minor(7331)
	# Force a nice terran planet for the main menu
	data.planet_type        = PlanetData.Type.TERRAN
	data.has_atmosphere     = true
	data.atmosphere_density = 1.0
	data.has_clouds         = true
	data.cloud_speed        = 0.025
	data.cloud_coverage     = 0.50
	data.sea_level          = 0.0
	data.continent_scale    = 1.0
	data.terrain_roughness  = 1.0
	data.specular_strength  = 0.4
	data.city_lights        = 0.2

	var shader := load(PlanetData.get_shader_path(data.planet_type)) as Shader
	var mat    := ShaderMaterial.new()
	mat.shader  = shader

	var sz          : float = clamp(float(data.planet_size), 0.2, 2.0)
	var base_radius : float = clamp(0.42 * sz, 0.10, 0.48)
	var pcount       := 160.0

	mat.set_shader_parameter("rotation_offset",   0.0)
	mat.set_shader_parameter("planet_radius",     base_radius)
	mat.set_shader_parameter("pixel_count",       pcount)
	mat.set_shader_parameter("seed",              data.seed)
	mat.set_shader_parameter("terrain_roughness", data.terrain_roughness)
	mat.set_shader_parameter("aspect_ratio",      1.0)
	mat.set_shader_parameter("cloud_speed",       data.cloud_speed)
	mat.set_shader_parameter("cloud_coverage",    data.cloud_coverage)
	mat.set_shader_parameter("has_clouds",        1.0)
	mat.set_shader_parameter("atmosphere_density",data.atmosphere_density)
	mat.set_shader_parameter("sea_level",         data.sea_level)
	mat.set_shader_parameter("continent_scale",   data.continent_scale)
	mat.set_shader_parameter("specular_strength", data.specular_strength)
	mat.set_shader_parameter("city_lights",       data.city_lights)

	var colors := PlanetData.get_colors(data.planet_type)
	for key in colors:
		mat.set_shader_parameter(key, colors[key])

	_update_light(mat)
	_planet_rect.material = mat

# ── Menu UI ────────────────────────────────────────────────────────────────

func _build_menu() -> void:
	var vp := get_viewport().get_visible_rect().size

	var root := VBoxContainer.new()
	root.position               = Vector2(vp.x * 0.07, vp.y * 0.22)
	root.custom_minimum_size    = Vector2(vp.x * 0.38, 0.0)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	# Title
	var title := Label.new()
	title.text = "VOIDLE"
	if _font: title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(0.92, 0.88, 1.0))
	root.add_child(title)

	# Subtitle
	var sub := Label.new()
	sub.text = "An idle space empire"
	if _font: sub.add_theme_font_override("font", _font)
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.55, 0.55, 0.75))
	root.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 28)
	root.add_child(gap)

	# Buttons
	_cont_btn = _add_button(root, "CONTINUE", _on_continue)
	_update_continue_btn()
	GameState.save_deleted.connect(_update_continue_btn)

	_add_button(root, "NEW GAME",  _on_new_game)

	_add_button(root, "SETTINGS",  _on_settings)
	_add_button(root, "QUIT",      _on_quit)

	# Version
	var ver := Label.new()
	ver.text = "v0.1  –  Early Access"
	if _font: ver.add_theme_font_override("font", _font)
	ver.add_theme_font_size_override("font_size", 8)
	ver.add_theme_color_override("font_color", Color(0.35, 0.35, 0.5))
	var vgap := Control.new()
	vgap.custom_minimum_size = Vector2(0, 32)
	root.add_child(vgap)
	root.add_child(ver)

func _add_button(parent: Control, label: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text                    = label
	btn.flat                    = true
	btn.alignment               = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size     = Vector2(260, 36)
	if _font: btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color",        Color(0.78, 0.78, 1.0))
	btn.add_theme_color_override("font_hover_color",  Color(1.0,  1.0,  1.0))
	btn.add_theme_color_override("font_focus_color",  Color(1.0,  1.0,  1.0))
	btn.add_theme_color_override("font_pressed_color",Color(0.55, 0.55, 0.85))

	# Hover: show a dim left-border accent via StyleBoxFlat
	var sbn := StyleBoxEmpty.new()
	var sbh := StyleBoxFlat.new()
	sbh.bg_color              = Color(1, 1, 1, 0.05)
	sbh.border_width_left     = 3
	sbh.border_color          = Color(0.6, 0.5, 1.0, 0.9)
	sbh.corner_radius_top_right    = 3
	sbh.corner_radius_bottom_right = 3
	btn.add_theme_stylebox_override("normal",  sbn)
	btn.add_theme_stylebox_override("hover",   sbh)
	btn.add_theme_stylebox_override("pressed", sbh)
	btn.add_theme_stylebox_override("focus",   StyleBoxEmpty.new())

	btn.pressed.connect(cb)
	parent.add_child(btn)
	return btn

# ── Glitch credits ────────────────────────────────────────────────────────

func _build_credits() -> void:
	var vp := get_viewport().get_visible_rect().size

	_credits_lbl = Label.new()
	_credits_lbl.text = CREDITS_LINES[0]
	if _font: _credits_lbl.add_theme_font_override("font", _font)
	_credits_lbl.add_theme_font_size_override("font_size", 9)
	_credits_lbl.add_theme_color_override("font_color", Color(0.38, 0.38, 0.55, 0.75))
	_credits_lbl.anchor_left   = 1.0
	_credits_lbl.anchor_right  = 1.0
	_credits_lbl.anchor_top    = 1.0
	_credits_lbl.anchor_bottom = 1.0
	_credits_lbl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_credits_lbl.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	_credits_lbl.offset_right  = -18.0
	_credits_lbl.offset_bottom = -14.0
	_credits_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_credits_lbl)

	_cycle_credits()

func _cycle_credits() -> void:
	await get_tree().create_timer(CREDITS_HOLD).timeout
	if not is_instance_valid(_credits_lbl):
		return
	_credits_idx = (_credits_idx + 1) % CREDITS_LINES.size()
	await _glitch_to(CREDITS_LINES[_credits_idx])
	_cycle_credits()

func _glitch_to(target: String) -> void:
	var rng   := RandomNumberGenerator.new()
	var chars := GLITCH_CHARS
	var orig  := _credits_lbl.text
	var max_len := maxi(orig.length(), target.length())

	for step in GLITCH_STEPS:
		var t    := float(step) / float(GLITCH_STEPS)
		var out  := ""
		for i in max_len:
			if i < target.length() and t > float(i) / float(max_len):
				out += target[i]
			elif i < orig.length():
				out += chars[rng.randi() % chars.length()]
			else:
				out += chars[rng.randi() % chars.length()]
		_credits_lbl.text = out
		await get_tree().create_timer(GLITCH_STEP_DUR).timeout

	if is_instance_valid(_credits_lbl):
		_credits_lbl.text = target

# ── Planet animation ───────────────────────────────────────────────────────

func _update_light(mat: ShaderMaterial) -> void:
	var lx := cos(_light_angle) * 0.85
	var lz := sin(_light_angle) * 0.55
	mat.set_shader_parameter("light_direction", Vector3(lx, -0.45, lz).normalized())

func _process(delta: float) -> void:
	if _planet_rect == null or _planet_rect.material == null:
		return
	_rotation_off = fposmod(_rotation_off + ROTATE_SPEED * delta, TAU)
	_light_angle  = fposmod(_light_angle  + 0.004 * delta, TAU)
	var mat := _planet_rect.material as ShaderMaterial
	mat.set_shader_parameter("rotation_offset", _rotation_off)
	_update_light(mat)

# ── Button callbacks ────────────────────────────────────────────────────────

func _update_continue_btn() -> void:
	if not is_instance_valid(_cont_btn): return
	var has := GameState.has_save()
	_cont_btn.disabled = not has
	_cont_btn.modulate = Color(1, 1, 1, 1.0 if has else 0.3)

func _on_new_game() -> void:
	AudioManager.play("click", 0.0)
	GameState.delete_save()
	SceneTransition.go("res://scenes/galaxy/GalaxyView.tscn")

func _on_continue() -> void:
	AudioManager.play("click", 0.0)
	SceneTransition.go("res://scenes/galaxy/GalaxyView.tscn")

func _on_settings() -> void:
	HUDManager.show_settings_popup()

func _on_quit() -> void:
	get_tree().quit()
