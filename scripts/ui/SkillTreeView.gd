## SkillTreeView — Graph representation of the Skill/Upgrade Tree.
## Renders nodes, draws connections procedurally, and allows credits purchase.
class_name SkillTreeView
extends Control

signal tree_opened
signal tree_closed

static var is_open: bool = false

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
		card.custom_minimum_size = Vector2(48, 48)
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		# Style based on status (Cyberpunk Hexagon)
		var bg_color := Color(0.08, 0.09, 0.12, 0.9)
		var border_color := Color(0.5, 0.6, 0.7, 0.8) # <--- Brighter border for locked nodes
		var shadow_color := Color(0.0, 0.0, 0.0, 0.0)
		var border_width := 1.0
		
		if is_max_level:
			bg_color = Color(0.02, 0.1, 0.05, 0.95)
			border_color = Color(0.25, 0.95, 0.45, 1.0)
			shadow_color = Color(0.25, 0.95, 0.45, 0.3)
			border_width = 2.0
		elif cur_lv > 0:
			bg_color = Color(0.1, 0.08, 0.02, 0.95)
			border_color = Color(0.95, 0.65, 0.25, 0.9)
			shadow_color = Color(0.95, 0.65, 0.25, 0.2)
			border_width = 2.0
		elif purchasable:
			bg_color = Color(0.04, 0.08, 0.15, 0.95)
			border_color = Color(0.15, 0.85, 0.95, 0.85)
			shadow_color = Color(0.15, 0.85, 0.95, 0.2)
			border_width = 2.0

		card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

		# Add a wrapper Control inside the PanelContainer to escape Container alignment rules
		var wrapper := Control.new()
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Fill the PanelContainer space completely
		wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.add_child(wrapper)

		# Custom Hexagon Drawing Layer
		var hex_bg := Control.new()
		hex_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hex_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hex_bg.draw.connect(func() -> void:
			var r := 22.0 # Radius for 48x48 box
			var c := Vector2(24.0, 24.0)
			
			var pts := PackedVector2Array()
			var glow_pts := PackedVector2Array()
			# Flat-topped hexagon (points at 30, 90, 150, 210, 270, 330 degrees)
			for i in range(7):
				var angle = i * PI / 3.0 + PI / 6.0
				pts.append(c + Vector2(cos(angle), sin(angle)) * r)
				glow_pts.append(c + Vector2(cos(angle), sin(angle)) * (r + 2.0))
			
			# Draw Glow (Shadow)
			if shadow_color.a > 0:
				hex_bg.draw_polyline(glow_pts, shadow_color, 4.0, true)
			
			# Draw Fill & Outline
			hex_bg.draw_colored_polygon(pts, bg_color)
			hex_bg.draw_polyline(pts, border_color, border_width, true)
		)
		wrapper.add_child(hex_bg)

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
		card.position = node.pos - Vector2(24, 24)
		_nodes_container.add_child(card)
		_ui_nodes[id] = card

		# Tooltip definitions
		cur_lv = st.call("get_skill_level", id)
		max_lv = node.max_level
		
		# Show title. If it is leveled, we will put the level info at the top right inside body
		var tip_title: String = node.name
		var tip_body := ""
		var tip_cost := ""
		
		# Root is a dummy central core - format clean
		if id == "root":
			tip_body = node.description
		else:
			# Format level information to show at the right top of the tooltip body
			if max_lv > 1:
				if cur_lv >= max_lv:
					tip_body += "[right][color=#55f58c]MAX LEVEL[/color][/right]\n"
				else:
					tip_body += "[right][color=#e5c24b]Level %d/%d[/color][/right]\n" % [cur_lv, max_lv]
				
			# Normal nodes
			if max_lv > 1:
				# Leveled Upgrades
				tip_body = node.description
				if cur_lv > 0:
					tip_body += "\n\n[color=#55f58c]Current Level: %d/%d[/color]" % [cur_lv, max_lv]
				if cur_lv < max_lv:
					tip_body += "\n[color=#55aaff]Effect: %s[/color]" % node.effect_desc
				else:
					tip_body += "\n\n[color=#55f58c]✦ MAX LEVEL ✦[/color]"
			else:
				# Single purchase upgrades
				tip_body = node.description + "\n\n[color=#55aaff]Effect: " + node.effect_desc + "[/color]"
				if unlocked:
					tip_body += "\n\n[color=#55f58c]✦ UNLOCKED ✦[/color]"
			
			# Cost handling
			if cur_lv < max_lv:
				var next_cost: float = st.call("get_next_cost", id)
				tip_cost = "%.0f Science" % next_cost
			
			# Requirements checking
			if cur_lv == 0:
				var missing_parents: Array[String] = []
				for p in node.parents:
					if st.call("get_skill_level", p) == 0:
						missing_parents.append(st.get("nodes")[p].name)
				
				if missing_parents.size() > 0:
					tip_body += "\n\n[color=#ff5544]Requires: " + ", ".join(missing_parents) + "[/color]"

		# Pivot offset at center for clean scaling
		card.pivot_offset = Vector2(24, 24)

		var cap_cost := tip_cost
		card.mouse_entered.connect(func() -> void:
			AudioManager.play("hover")
			if unlocked or purchasable:
				CursorManager.set_state(CursorManager.State.POINTER)
			else:
				CursorManager.set_state(CursorManager.State.NORMAL)

			# Smooth scale up animation (Juicy Hover)
			var tween := create_tween()
			tween.tween_property(card, "scale", Vector2(1.15, 1.15), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

			TooltipManager.show_tip(tip_title, tip_body, cap_cost))
			
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
				if st.call("can_purchase", cap_id):
					TooltipManager.hide_tip()
					AudioManager.play("skill_buy")
					st.call("purchase_skill", cap_id)
				else:
					AudioManager.play("error"))

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
				
			# Offset drawing coordinates to account for _connections_draw's -10000 position shift
			var start_pos: Vector2 = st.get("nodes")[parent_id].pos + draw_offset
			var end_pos: Vector2 = node.pos + draw_offset

			# Determine line color
			var is_active: bool = parent_id in (st.get("unlocked_skills") as Array) and id in (st.get("unlocked_skills") as Array)
			var line_col := Color(0.15, 0.9, 0.85, 0.9) if is_active else Color(0.15, 0.2, 0.3, 0.5)
			if is_active and id in (st.get("unlocked_skills") as Array):
				# If both are fully upgraded, maybe make it green? Nah, Cyan is very cyberpunk.
				line_col = Color(0.15, 0.85, 0.95, 0.9) # Cyan active circuit
			
			var line_width := 4.0 if is_active else 2.0

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
