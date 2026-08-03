## SkillTreeView — Graph representation of the Skill/Upgrade Tree.
## Renders nodes, draws connections procedurally, and allows credits purchase.
class_name SkillTreeView
extends Control

signal tree_opened
signal tree_closed

static var is_open: bool = false
static var _saved_position: Vector2 = Vector2.ZERO
static var _saved_zoom:     float   = 1.0

var _font: Font
var _nodes_container: Control
var _connections_draw: Control
var _close_btn: Button

# Keep track of active nodes for drawing connections
var _ui_nodes: Dictionary = {} # id -> PanelContainer

# Drag state variables
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _center_ctrl: Control
var _bg: ColorRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	SkillTreeView.is_open = true
	tree_opened.emit()
	
	# Put it on top of other HUD layers
	z_as_relative = false
	z_index = 200

	# Dark fully opaque fullscreen background with blueprint dots
	_bg = ColorRect.new()
	_bg.color = Color(0.04, 0.05, 0.09, 1.0) # Tam opak (arkayı göstermez)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Blueprint Grid Effect (moves with the camera and scales with zoom)
	_bg.draw.connect(func() -> void:
		var dot_color := Color(0.2, 0.25, 0.35, 0.5)
		var grid_size: int = maxi(10, int(40.0 * self._zoom))
		var dot_size: float = maxf(1.0, 2.0 * self._zoom)
		
		var w := int(_bg.size.x)
		var h := int(_bg.size.y)
		
		var offset_x = int(self._center_ctrl.position.x) % grid_size
		var offset_y = int(self._center_ctrl.position.y) % grid_size
		if offset_x < 0: offset_x += grid_size
		if offset_y < 0: offset_y += grid_size
		
		for x in range(offset_x - grid_size, w + grid_size, grid_size):
			for y in range(offset_y - grid_size, h + grid_size, grid_size):
				_bg.draw_rect(Rect2(x, y, dot_size, dot_size), dot_color)
	)
	
	# Background captures click so we can drag the whole canvas by clicking on empty space
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_font = load("res://Fonts/Orbitron-VariableFont_wght.ttf")

	# Graph container centered in screen
	_center_ctrl = Control.new()
	_center_ctrl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_center_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center_ctrl)

	# Drawing layer for connecting lines (underneath nodes)
	_connections_draw = Control.new()
	_connections_draw.custom_minimum_size = Vector2(20000, 20000)
	_connections_draw.position = Vector2(-10000, -10000)
	_connections_draw.draw.connect(_draw_connections)
	_connections_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_ctrl.add_child(_connections_draw)

	# Node buttons container
	_nodes_container = Control.new()
	_nodes_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_ctrl.add_child(_nodes_container)

	# Restore last pan/zoom position from this session
	if _saved_position != Vector2.ZERO or _saved_zoom != 1.0:
		_center_ctrl.position = _saved_position
		_zoom = _saved_zoom
		_center_ctrl.scale = Vector2(_zoom, _zoom)

	# Build all nodes and position them
	_build_tree_graph()

	# Title at the top center
	var title := Label.new()
	title.text = "✦ TECHNOLOGY ARCHITECTURE ✦"
	if _font: title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.offset_top = 24.0
	add_child(title)

	# Subtitle
	var sub := Label.new()
	sub.text = "Invest credits to upgrade colony systems"
	if _font: sub.add_theme_font_override("font", _font)
	sub.add_theme_font_size_override("font_size", 9)
	sub.add_theme_color_override("font_color", Color(0.4, 0.48, 0.65))
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.offset_top = 48.0
	add_child(sub)

	# Close button at the bottom center
	_close_btn = Button.new()
	_close_btn.text = "CLOSE"
	if _font: _close_btn.add_theme_font_override("font", _font)
	_close_btn.add_theme_font_size_override("font_size", 10)
	_close_btn.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0))
	_close_btn.custom_minimum_size = Vector2(100, 30)
	_close_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_close_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_close_btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_close_btn.offset_bottom = -20.0
	
	var btn_s := StyleBoxFlat.new()
	btn_s.bg_color = Color(0.12, 0.16, 0.28, 0.9)
	btn_s.border_color = Color(0.28, 0.42, 0.72, 0.55)
	btn_s.set_border_width_all(1)
	btn_s.corner_radius_top_left = 4
	btn_s.corner_radius_top_right = 4
	btn_s.corner_radius_bottom_left = 4
	btn_s.corner_radius_bottom_right = 4
	_close_btn.add_theme_stylebox_override("normal", btn_s)
	
	var btn_h := btn_s.duplicate() as StyleBoxFlat
	btn_h.bg_color = Color(0.18, 0.24, 0.42, 1.0)
	btn_h.border_color = Color(0.42, 0.62, 1.0, 0.85)
	_close_btn.add_theme_stylebox_override("hover", btn_h)
	_close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	_close_btn.pressed.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.NORMAL)
		SkillTreeView._saved_position = _center_ctrl.position
		SkillTreeView._saved_zoom     = _zoom
		SkillTreeView.is_open = false
		tree_closed.emit()
		queue_free())
	_close_btn.mouse_entered.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.POINTER))
	_close_btn.mouse_exited.connect(func() -> void:
		CursorManager.set_state(CursorManager.State.NORMAL))
	add_child(_close_btn)

	# Listen to skill unlocks to redraw connections & button states
	get_node("/root/SkillTree").skill_unlocked.connect(_on_skill_unlocked)

func _build_tree_graph() -> void:
	print("DEBUG SkillTree: BuildingDef.all().size() = ", BuildingDef.all().size())
	for c in _nodes_container.get_children():
		c.queue_free()
	_ui_nodes.clear()

	var st: Node = get_node("/root/SkillTree")
	for id in st.get("nodes").keys():
		var node = st.get("nodes")[id]
		
		# Kilitli ve görünmezse hiç oluşturma (açıldıkça etrafı görünür)
		if not st.call("is_visible", id):
			continue

		var cur_lv: int = st.call("get_skill_level", id)
		var max_lv: int = node.max_level
		var is_max_level := cur_lv >= max_lv
		var unlocked: bool = cur_lv > 0
		var purchasable: bool = st.call("can_purchase", id)

		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		var shape_type: int = node.get("shape") if "shape" in node else 0
		var card_size := 48.0
		if shape_type == 2:
			card_size = 72.0
			
		card.custom_minimum_size = Vector2(card_size, card_size)
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		# Style based on status (Cyberpunk Theme)
		var st_ref = st
		var id_ref = id

		card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

		# Add a wrapper Control inside the PanelContainer to escape Container alignment rules
		var wrapper := Control.new()
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Fill the PanelContainer space completely
		wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.add_child(wrapper)

		# Custom Shape Drawing Layer
		var bg_shape := Control.new()
		bg_shape.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_shape.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg_shape.draw.connect(func() -> void:
			var c := Vector2(card_size * 0.5, card_size * 0.5)
			var r := 22.0
			
			var pts := PackedVector2Array()
			var glow_pts := PackedVector2Array()
			
			if shape_type == 2: # CIRCLE (Large)
				r = 30.0
				for i in range(13):
					var angle = i * PI * 2.0 / 12.0
					pts.append(c + Vector2(cos(angle), sin(angle)) * r)
					glow_pts.append(c + Vector2(cos(angle), sin(angle)) * (r + 2.0))
			elif shape_type == 1: # DIAMOND (Small)
				r = 16.0
				for i in range(5):
					var angle = i * PI / 2.0
					pts.append(c + Vector2(cos(angle), sin(angle)) * r)
					glow_pts.append(c + Vector2(cos(angle), sin(angle)) * (r + 2.0))
			else: # HEXAGON
				for i in range(7):
					var angle = i * PI / 3.0 + PI / 6.0
					pts.append(c + Vector2(cos(angle), sin(angle)) * r)
					glow_pts.append(c + Vector2(cos(angle), sin(angle)) * (r + 2.0))
			
			var d_cur_lv: int = st_ref.call("get_skill_level", id_ref)
			var d_max_lv: int = st_ref.get("nodes")[id_ref].max_level
			var d_is_max: bool = d_cur_lv >= d_max_lv
			var d_purchasable: bool = st_ref.call("can_purchase", id_ref)
			
			var bg_color := Color(0.08, 0.09, 0.12, 0.9)
			var border_color := Color(0.5, 0.6, 0.7, 0.8)
			var shadow_color := Color(0.0, 0.0, 0.0, 0.0)
			var border_width := 1.0
			
			if d_is_max:
				bg_color = Color(0.02, 0.1, 0.05, 0.95)
				border_color = Color(0.25, 0.95, 0.45, 1.0)
				shadow_color = Color(0.25, 0.95, 0.45, 0.3)
				border_width = 2.0
			elif d_cur_lv > 0:
				bg_color = Color(0.1, 0.08, 0.02, 0.95)
				border_color = Color(0.95, 0.65, 0.25, 0.9)
				shadow_color = Color(0.95, 0.65, 0.25, 0.2)
				border_width = 2.0
			elif d_purchasable:
				bg_color = Color(0.04, 0.08, 0.15, 0.95)
				border_color = Color(0.15, 0.85, 0.95, 0.85)
				shadow_color = Color(0.15, 0.85, 0.95, 0.2)
				border_width = 2.0

			# Draw Glow (Shadow)
			if shadow_color.a > 0:
				bg_shape.draw_polyline(glow_pts, shadow_color, 4.0, true)
			
			# Draw Fill & Outline
			bg_shape.draw_colored_polygon(pts, bg_color)
			bg_shape.draw_polyline(pts, border_color, border_width, true)
		)
		wrapper.add_child(bg_shape)

		# Add procedural icon in center of the wrapper
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		wrapper.add_child(center)

		var texture_rect := TextureRect.new()
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		
		# Generate custom color & tier icons based on tech type
		var icon_col := Color(0.5, 0.5, 0.5)
		var icon_tier := 1
		
		# Define unique colors and shapes per upgrade type (T1-T5 base shapes)
		match id:
			"root":
				icon_col = Color(0.9, 0.8, 0.4) # Gold
				icon_tier = 5 # Core
			"unlock_solar_panel":
				icon_col = Color(1.0, 0.9, 0.2) # Sun Yellow
				icon_tier = 3 # Energy
			"unlock_residential":
				icon_col = Color(0.2, 0.95, 0.4) # Green
				icon_tier = 1 # Data/Node
			"unlock_lab":
				icon_col = Color(0.2, 0.6, 1.0) # Science Blue
				icon_tier = 2 # Flask
			# Energy
			"unlock_thermal_plant":
				icon_col = Color(1.0, 0.4, 0.1) # Fire Orange
				icon_tier = 3 # Energy
			"solar_efficiency":
				icon_col = Color(1.0, 0.9, 0.2) # Sun Yellow
				icon_tier = 4 # Grid
			"generator_efficiency":
				icon_col = Color(1.0, 0.3, 0.0) # Deep Orange
				icon_tier = 3 # Energy
			"supercharged_generators":
				icon_col = Color(1.0, 0.5, 0.0) # Bright Orange
				icon_tier = 5 # Core
			"power_transmission":
				icon_col = Color(0.4, 0.9, 1.0) # Light Cyan
				icon_tier = 4 # Grid
			"energy_efficiency":
				icon_col = Color(0.2, 1.0, 0.8) # Bright Cyan
				icon_tier = 4 # Grid
			"unlock_fusion_reactor":
				icon_col = Color(0.4, 0.9, 1.0) # Cyan/Blue plasma
				icon_tier = 5 # Core
			"dyson_swarm":
				icon_col = Color(1.0, 0.8, 0.0) # Bright Sun Gold
				icon_tier = 9 # Sun
			# Mining
			"unlock_mining":
				icon_col = Color(0.9, 0.6, 0.2) # Amber/Gold — mining operations
				icon_tier = 2 # Drill
			"unlock_deep_drill":
				icon_col = Color(1.0, 0.5, 0.2) # Industrial Orange
				icon_tier = 2 # Drill
			"mine_speed":
				icon_col = Color(0.8, 0.7, 0.6) # Copper/Bronze
				icon_tier = 2 # Drill
			"unlock_refinery":
				icon_col = Color(0.5, 0.5, 0.5) # Steel/Iron
				icon_tier = 3 # Energy/Furnace
			"deep_mining":
				icon_col = Color(0.6, 0.4, 0.2) # Deep Brown
				icon_tier = 2 # Drill
			"core_extractor":
				icon_col = Color(0.9, 0.3, 0.1) # Magma Orange
				icon_tier = 2 # Drill
			"deep_core_drilling":
				icon_col = Color(1.0, 0.1, 0.0) # Bright Red
				icon_tier = 5 # Core
			"mineral_compression":
				icon_col = Color(0.6, 0.3, 1.0) # Deep Purple
				icon_tier = 1 # Data
			"omega_drill":
				icon_col = Color(1.0, 0.0, 0.0) # Pure Red
				icon_tier = 5 # Core
			"unlock_commercial":
				icon_col = Color(0.2, 0.95, 0.4) # Emerald Green (Money)
				icon_tier = 1 # Data/Node
			"unlock_luxury_complex":
				icon_col = Color(0.9, 0.2, 0.6) # Pink/Magenta (Luxury)
				icon_tier = 1 # Data
			"credit_boost":
				icon_col = Color(0.4, 1.0, 0.5) # Bright Green
				icon_tier = 1 # Data
			"unlock_trade_hub":
				icon_col = Color(0.1, 0.8, 0.6) # Turquoise
				icon_tier = 4 # Cargo/Trade -> Grid
			"planetary_architecture":
				icon_col = Color(0.8, 0.6, 1.0) # Light Purple
				icon_tier = 4 # Grid
			"global_logistics":
				icon_col = Color(0.2, 0.8, 1.0) # Bright Cyan
				icon_tier = 4 # Grid
			"unlock_commercial_hub":
				icon_col = Color(0.2, 1.0, 0.5) # Neon Green
				icon_tier = 4 # Grid
			"unlock_logistics_center":
				icon_col = Color(0.8, 0.8, 0.2) # Yellow
				icon_tier = 4 # Grid
			"unlock_command_center":
				icon_col = Color(0.9, 0.1, 0.3) # Deep Red
				icon_tier = 5 # Core
			"unlock_research_academy":
				icon_col = Color(0.5, 0.2, 1.0) # Deep Purple
				icon_tier = 3 # Data
			# Science/Space
			"unlock_advanced_lab":
				icon_col = Color(0.2, 0.6, 1.0) # Science Blue
				icon_tier = 2 # Flask/Data
			"unlock_space_station":
				icon_col = Color(0.8, 0.8, 0.8) # Silver/White
				icon_tier = 3 # Station/Core
			"unlock_orbital_shipyard":
				icon_col = Color(0.4, 0.6, 1.0) # Steel Blue
				icon_tier = 4 # Grid
			"unlock_moon":
				icon_col = Color(0.7, 0.7, 0.75) # Moon Grey
				icon_tier = 3 # Moon
			"unlock_lunar_observatory":
				icon_col = Color(0.2, 0.6, 1.0) # Science Blue
				icon_tier = 4 # Grid
			"unlock_asteroids":
				icon_col = Color(0.5, 0.4, 0.3) # Asteroid Brown
				icon_tier = 4 # Asteroid
			"unlock_asteroid_harvester":
				icon_col = Color(1.0, 0.5, 0.2) # Industrial Orange
				icon_tier = 4 # Grid
			"colonize_ice":
				icon_col = Color(0.5, 0.9, 1.0) # Ice Blue
				icon_tier = 5 # Planet
			"unlock_cryo_vault":
				icon_col = Color(0.2, 0.8, 1.0) # Deep Ice Blue
				icon_tier = 4 # Grid
			"colonize_desert":
				icon_col = Color(0.9, 0.8, 0.4) # Sand Yellow
				icon_tier = 5 # Planet
			"unlock_solar_matrix":
				icon_col = Color(1.0, 0.9, 0.2) # Sun Yellow
				icon_tier = 4 # Grid
			"colonize_gas":
				icon_col = Color(0.8, 0.4, 0.9) # Gas Purple
				icon_tier = 5 # Planet
			"unlock_atmospheric_siphon":
				icon_col = Color(0.6, 0.2, 1.0) # Deep Purple
				icon_tier = 4 # Grid
			"colonize_volcanic":
				icon_col = Color(1.0, 0.3, 0.1) # Magma Orange
				icon_tier = 5 # Planet
			"unlock_geothermal_plant":
				icon_col = Color(1.0, 0.1, 0.0) # Bright Red
				icon_tier = 4 # Grid
			"unlock_interstellar":
				icon_col = Color(1.0, 1.0, 1.0) # Pure White (Star)
				icon_tier = 5 # Star -> Core

		# Store base properties for dynamic refresh
		texture_rect.set_meta("base_color", icon_col)
		texture_rect.set_meta("tier", icon_tier)

		# De-saturate color slightly if locked/unpurchasable
		if not unlocked and not purchasable:
			icon_col = icon_col.lerp(Color(0.25, 0.27, 0.32), 0.4)
		elif purchasable:
			icon_col = icon_col.lightened(0.1)

		texture_rect.texture = TechIcon.make(icon_tier, icon_col)
		center.add_child(texture_rect)

		# Display level badge at the bottom-center of the wrapper
		if max_lv > 1 and cur_lv > 0:
			var lv_badge := Label.new()
			if cur_lv >= max_lv:
				lv_badge.text = "MAX"
				lv_badge.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55)) # Green
			else:
				lv_badge.text = "%d" % cur_lv
				lv_badge.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3)) # Bright Gold/Amber
				
			if _font: lv_badge.add_theme_font_override("font", _font)
			lv_badge.add_theme_font_size_override("font_size", 12) # Enlarged Level Text (12 pt)
			lv_badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
			lv_badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
			lv_badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
			# Sit nicely at the bottom edge, bold
			lv_badge.offset_top = -15
			lv_badge.offset_bottom = 2
			lv_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wrapper.add_child(lv_badge)

		# Position absolute coordinate
		card.position = node.pos - Vector2(card_size * 0.5, card_size * 0.5)
		_nodes_container.add_child(card)
		_ui_nodes[id] = card

		# Tooltip definitions
		cur_lv = st.call("get_skill_level", id)
		max_lv = node.max_level
		
		# Show title. If it is leveled, we will put the level info at the top right inside body
		var tip_title: String = node.name
		var tip_body: Array = []
		var sub_body: Array = []
		var tip_cost := ""
		
		# Root is a dummy central core - format clean
		if id == "root":
			tip_body.append(node.description)
		else:
			var body_str := ""
			# Format level information to show at the right top of the tooltip body
			if max_lv > 1:
				if cur_lv >= max_lv:
					body_str += "[right][color=#55f58c]MAX LEVEL[/color][/right]\n"
				else:
					body_str += "[right][color=#e5c24b]Level %d/%d[/color][/right]\n" % [cur_lv, max_lv]
				
			# Normal nodes
			body_str += node.description
			
			var effect_text: String = node.effect_desc
			var def: BuildingDef = null
			if (id as String).begins_with("unlock_"):
				var bid: String = (id as String).trim_prefix("unlock_")
				if bid == "mining": bid = "mine"
				def = BuildingDef.find(bid)
				if def:
					effect_text = effect_text.replace(def.display_name, "[color=#fce205]" + def.display_name + "[/color]")
					var cycle := " / %ds" % def.tick_duration
					sub_body.append("[color=#fce205]" + def.display_name + " Blueprint[/color]\n\n")
					
					if def.description != "":
						sub_body.append("[color=#c0c0c0]" + def.description + "[/color]\n\n")
					
					if def.input_type != BuildingDef.OutputType.NONE:
						sub_body.append("[color=#99aab5]Consumes -%.0f [/color]" % def.input_amount)
						sub_body.append(MineralIcon.make(def.input_tier, Color.WHITE))
						sub_body.append("[color=#99aab5]%s\n[/color]" % cycle)
					
					if def.output_type != BuildingDef.OutputType.NONE:
						var disp_o := absf(def.output_amount - floorf(def.output_amount)) > 0.01
						var o_fmt := "Produces +%.1f " if disp_o else "Produces +%.0f "
						
						if def.output_type == BuildingDef.OutputType.ENERGY:
							sub_body.append("[color=#99aab5]%s[/color][color=#fce205]⚡[/color][color=#99aab5]%s[/color]\n" % [o_fmt % def.output_amount, cycle])
						elif def.output_type == BuildingDef.OutputType.CREDITS:
							sub_body.append("[color=#99aab5]%s[/color][color=#55f58c]cr[/color][color=#99aab5]%s[/color]\n" % [o_fmt % def.output_amount, cycle])
						elif def.output_type == BuildingDef.OutputType.SCIENCE:
							sub_body.append("[color=#99aab5]%s[/color][color=#55aaff]sci[/color][color=#99aab5]%s[/color]\n" % [o_fmt % def.output_amount, cycle])
						else:
							sub_body.append("[color=#99aab5]%s[/color]" % (o_fmt % def.output_amount))
							var out_tier: int = def.input_tier + 1 if def.output_type == BuildingDef.OutputType.REFINED_MINERAL else def.input_tier
							sub_body.append(MineralIcon.make(out_tier, Color.WHITE))
							sub_body.append("[color=#99aab5]%s[/color]\n" % cycle)

			if max_lv > 1:
				# Leveled Upgrades
				if cur_lv > 0:
					body_str += "\n\n[color=#55f58c]Current Level: %d/%d[/color]" % [cur_lv, max_lv]
				if cur_lv < max_lv:
					body_str += "\n[color=#55aaff]Effect: %s[/color]" % effect_text
				else:
					body_str += "\n\n[color=#55f58c]✦ MAX LEVEL ✦[/color]"
			else:
				# Single purchase upgrades
				body_str += "\n\n[color=#55aaff]Effect: " + effect_text + "[/color]"
				if unlocked:
					body_str += "\n\n[color=#55f58c]✦ UNLOCKED ✦[/color]"
			
			# Cost handling
			if cur_lv < max_lv:
				var next_cost: float = st.call("get_next_cost", id)
				tip_cost = "%.0f Science" % next_cost
			
			# Requirements checking
			if cur_lv == 0:
				var missing_parents: Array[String] = []
				for p in node.parents:
					if st.call("get_skill_level", p) == 0:
						if st.get("nodes").has(p):
							missing_parents.append(st.get("nodes")[p].name)
						else:
							missing_parents.append("???")
				
				if missing_parents.size() > 0:
					body_str += "\n\n[color=#ff5544]Requires: " + ", ".join(missing_parents) + "[/color]"
			
			tip_body.append(body_str)

		# Pivot offset at center for clean scaling
		card.pivot_offset = Vector2(24, 24)

		var cap_cost := tip_cost
		var cap_sub := sub_body.duplicate()
		card.mouse_entered.connect(func() -> void:
			AudioManager.play("hover")
			if unlocked or purchasable:
				CursorManager.set_state(CursorManager.State.POINTER)
			else:
				CursorManager.set_state(CursorManager.State.NORMAL)

			# Smooth scale up animation (Juicy Hover)
			var tween := create_tween()
			tween.tween_property(card, "scale", Vector2(1.15, 1.15), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

			TooltipManager.show_tip(tip_title, tip_body, cap_cost, cap_sub))
			
		card.mouse_exited.connect(func() -> void:
			CursorManager.set_state(CursorManager.State.NORMAL)
			
			# Smooth scale down animation
			var tween := create_tween()
			tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			
			TooltipManager.hide_tip())

		# Input logic for purchase click
		var cap_id: String = id
		card.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				card.accept_event() # Stop propagation to canvas drag
				# During tutorial skill step, only unlock_mining is allowed
				var tm := get_node_or_null("/root/TutorialManager")
				if tm != null and tm._active and not tm._tutorial_done \
						and tm.get_action_step_type() == "skill" and cap_id != "unlock_mining":
					AudioManager.play("error")
					return
				if st.call("can_purchase", cap_id):
					TooltipManager.hide_tip()
					AudioManager.play("skill_buy")
					st.call("purchase_skill", cap_id)
				else:
					AudioManager.play("error"))

	_apply_tutorial_skill_overlay()

func _apply_tutorial_skill_overlay() -> void:
	var tm := get_node_or_null("/root/TutorialManager")
	if tm == null or not tm._active or tm._tutorial_done or tm.get_action_step_type() != "skill":
		return
	var target_id := "unlock_mining"
	for nid in _ui_nodes:
		var card: PanelContainer = _ui_nodes[nid]
		if not is_instance_valid(card): continue
		if nid == target_id:
			var tw := create_tween().set_loops()
			tw.tween_property(card, "modulate", Color(1.6, 1.55, 0.7, 1.0), 0.55)
			tw.tween_property(card, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.55)
		elif nid != "root":
			card.modulate = Color(0.35, 0.35, 0.35, 0.6)

func _draw_connections() -> void:
	# Draw all connection lines between parent/child nodes
	var st: Node = get_node("/root/SkillTree")
	var draw_offset := Vector2(10000, 10000)
	
	for id in st.get("nodes").keys():
		var node = st.get("nodes")[id]
		# Only draw if child node is visible
		if not st.call("is_visible", id):
			continue
			
		for parent_id in node.parents:
			if not st.call("is_visible", parent_id):
				continue
			if not st.get("nodes").has(parent_id):
				continue
				
			# Offset drawing coordinates to account for _connections_draw's -10000 position shift
			var start_pos: Vector2 = st.get("nodes")[parent_id].pos + draw_offset
			var end_pos: Vector2 = node.pos + draw_offset

			# Determine line color
			var is_active: bool = parent_id in (st.get("unlocked_skills") as Array) and id in (st.get("unlocked_skills") as Array)
			var line_col := Color(0.15, 0.9, 0.85, 0.9) if is_active else Color(0.15, 0.2, 0.3, 0.5)
			if is_active and id in (st.get("unlocked_skills") as Array):
				# If both are fully upgraded, maybe make it green? Nah, Cyan is very cyberpunk.
				line_col = Color(0.15, 0.85, 0.95, 0.9) # Cyan active circuit
			
			var p_shape: int = st.get("nodes")[parent_id].get("shape") if "shape" in st.get("nodes")[parent_id] else 0
			var c_shape: int = node.get("shape") if "shape" in node else 0
			var is_main_path: bool = p_shape != 1 and c_shape != 1 # 1 is DIAMOND

			var line_width := (8.0 if is_main_path else 4.0) if is_active else (4.0 if is_main_path else 2.0)

			# Circuit Board 45-Degree Chamfer Routing
			var dx = end_pos.x - start_pos.x
			var dy = end_pos.y - start_pos.y
			var pts := PackedVector2Array()

			if absf(dx) < 2.0 or absf(dy) < 2.0 or absf(absf(dx) - absf(dy)) < 2.0:
				# Zaten tam yatay, tam dikey veya tam 45 dereceyse düz çizgi çek
				pts.append(start_pos)
				pts.append(end_pos)
			else:
				var p1 = start_pos
				var p4 = end_pos
				
				# 45 Derecelik PCB Traces (Merkezden çapraz çıkıp sonra düze dönen)
				if absf(dx) > absf(dy):
					var p2 = p1 + Vector2(signf(dx) * absf(dy), dy)
					pts.append_array([p1, p2, p4])
					_connections_draw.draw_circle(p2, line_width * 1.2, line_col)
				else:
					var p2 = p1 + Vector2(dx, signf(dy) * absf(dx))
					pts.append_array([p1, p2, p4])
					_connections_draw.draw_circle(p2, line_width * 1.2, line_col)

			_connections_draw.draw_polyline(pts, line_col, line_width, true)

func force_refresh_node(id: String) -> void:
	if not _ui_nodes.has(id): return
	var card = _ui_nodes[id]
	var wrapper = card.get_child(0)
	var bg_shape = wrapper.get_child(0)
	bg_shape.queue_redraw()
	
	var center = wrapper.get_child(1)
	var texture_rect = center.get_child(0)
	if texture_rect.has_meta("base_color") and texture_rect.has_meta("tier"):
		var base_color = texture_rect.get_meta("base_color")
		var tier = texture_rect.get_meta("tier")
		
		var st: Node = get_node("/root/SkillTree")
		var cur_lv: int = st.call("get_skill_level", id)
		var unlocked: bool = cur_lv > 0
		var purchasable: bool = st.call("can_purchase", id)
		
		var icon_col = base_color
		if not unlocked and not purchasable:
			icon_col = icon_col.lerp(Color(0.25, 0.27, 0.32), 0.4)
		elif purchasable:
			icon_col = icon_col.lightened(0.1)
			
		texture_rect.texture = TechIcon.make(tier, icon_col)

var _zoom: float = 1.0

func _on_skill_unlocked(_id: String) -> void:
	# Rebuild tree to show newly unlocked nodes & connections
	_build_tree_graph()
	_connections_draw.queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_dragging = true
				_drag_offset = _center_ctrl.position - mb.global_position
				CursorManager.set_state(CursorManager.State.GRAB)
			else:
				_is_dragging = false
				CursorManager.set_state(CursorManager.State.NORMAL)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			var old_zoom = _zoom
			_zoom *= 1.15
			_zoom = clampf(_zoom, 0.25, 2.0)
			# Mouse bazlı zoom için offset düzeltmesi (center_ctrl.scale)
			var mouse_pos = mb.global_position
			_center_ctrl.position = mouse_pos + (_center_ctrl.position - mouse_pos) * (_zoom / old_zoom)
			_center_ctrl.scale = Vector2(_zoom, _zoom)
			_bg.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			var old_zoom = _zoom
			_zoom /= 1.15
			_zoom = clampf(_zoom, 0.25, 2.0)
			var mouse_pos = mb.global_position
			_center_ctrl.position = mouse_pos + (_center_ctrl.position - mouse_pos) * (_zoom / old_zoom)
			_center_ctrl.scale = Vector2(_zoom, _zoom)
			_bg.queue_redraw()
			
	elif event is InputEventMagnifyGesture:
		# Trackpad Pinch to Zoom
		var mag := event as InputEventMagnifyGesture
		var old_zoom = _zoom
		_zoom *= mag.factor
		_zoom = clampf(_zoom, 0.25, 2.0)
		var mouse_pos = mag.position
		_center_ctrl.position = mouse_pos + (_center_ctrl.position - mouse_pos) * (_zoom / old_zoom)
		_center_ctrl.scale = Vector2(_zoom, _zoom)
		_bg.queue_redraw()

	elif event is InputEventPanGesture:
		# Trackpad Two Finger Scroll (Panning)
		var pan := event as InputEventPanGesture
		# Pan delta is usually very small, needs a multiplier
		_center_ctrl.position -= pan.delta * 25.0
		_connections_draw.queue_redraw()
		_bg.queue_redraw()
		
	elif event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		_center_ctrl.position = mm.global_position + _drag_offset
		_connections_draw.queue_redraw()
