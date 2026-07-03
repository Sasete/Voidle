## SkillTreeView — Graph representation of the Skill/Upgrade Tree.
## Renders nodes, draws connections procedurally, and allows credits purchase.
class_name SkillTreeView
extends Control

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

func _ready() -> void:
	# Ensure the tree block input to anything behind it
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Put it on top of other HUD layers
	z_as_relative = false
	z_index = 200

	# Dark semi-transparent fullscreen background
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09, 0.94)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Background captures click so we can drag the whole canvas by clicking on empty space
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_bg_gui_input)
	add_child(bg)

	_font = load("res://Fonts/Orbitron-VariableFont_wght.ttf")

	# Graph container centered in screen
	_center_ctrl = Control.new()
	_center_ctrl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_center_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center_ctrl)

	# Drawing layer for connecting lines (underneath nodes)
	_connections_draw = Control.new()
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
		card.custom_minimum_size = Vector2(48, 48)
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		card.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		# Style based on status
		var s := StyleBoxFlat.new()
		s.corner_radius_top_left = 6
		s.corner_radius_top_right = 6
		s.corner_radius_bottom_left = 6
		s.corner_radius_bottom_right = 6
		
		if is_max_level:
			# Fully upgraded: Thick Glowing Green border
			s.bg_color = Color(0.04, 0.16, 0.08, 0.95)
			s.border_color = Color(0.25, 0.95, 0.45, 0.95)
			s.set_border_width_all(3)
		elif cur_lv > 0:
			# Partially upgraded (e.g. Lv. 3/10): Glowing Orange / Amber border
			s.bg_color = Color(0.14, 0.12, 0.06, 0.9)
			s.border_color = Color(0.95, 0.65, 0.25, 0.85)
			s.set_border_width_all(2)
		elif purchasable:
			# Purchasable: Cyan border
			s.bg_color = Color(0.06, 0.12, 0.22, 0.9)
			s.border_color = Color(0.3, 0.65, 0.95, 0.75)
			s.set_border_width_all(2)
		else:
			# Locked / Unpurchasable: Dark / Grey border
			s.bg_color = Color(0.08, 0.09, 0.12, 0.9)
			s.border_color = Color(0.2, 0.22, 0.28, 0.5)
			s.set_border_width_all(1)

		card.add_theme_stylebox_override("panel", s)

		# Add a wrapper Control inside the PanelContainer to escape Container alignment rules
		var wrapper := Control.new()
		wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Fill the PanelContainer space completely
		wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.add_child(wrapper)

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
				icon_col = Color(0.9, 0.8, 0.4) # Gold Core
				icon_tier = 5 # Hollow Diamond
			"solar_efficiency":
				icon_col = Color(1.0, 0.9, 0.2) # Sun Yellow
				icon_tier = 4 # Cross (Solar grid)
			"mine_speed":
				icon_col = Color(0.8, 0.4, 0.9) # Laser Pink
				icon_tier = 2 # Hex Crystal (Drill shard)
			"generator_efficiency":
				icon_col = Color(1.0, 0.4, 0.1) # Fire Orange
				icon_tier = 3 # Rhombus Gem (Thermal)
			"credit_boost":
				icon_col = Color(0.2, 0.95, 0.4) # Emerald Green (Money)
				icon_tier = 3 # Gem
			"deep_mining":
				icon_col = Color(0.3, 0.85, 1.0) # Diamond Cyan
				icon_tier = 2 # Crystal
			"power_transmission":
				icon_col = Color(0.9, 0.5, 1.0) # Violet plasma
				icon_tier = 4 # Cross
			"omega_core":
				icon_col = Color(1.0, 0.2, 0.3) # Crimson core
				icon_tier = 5 # Hollow Diamond

		# De-saturate color slightly if locked/unpurchasable
		if not unlocked and not purchasable:
			icon_col = icon_col.lerp(Color(0.25, 0.27, 0.32), 0.75)
		elif purchasable:
			icon_col = icon_col.lightened(0.1)

		texture_rect.texture = MineralIcon.make(icon_tier, icon_col)
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

		# Display type badge on the bottom-right of the wrapper itself (overlapping/floating)
		var type_symbol := "⚡"
		match id:
			"root":
				type_symbol = "✦"
			"solar_efficiency", "generator_efficiency":
				type_symbol = "⚡"
			"mine_speed", "omega_core":
				type_symbol = "⚡"
			"credit_boost":
				type_symbol = "◈"
			"deep_mining":
				type_symbol = "🔓" if unlocked else "🔒"
			"power_transmission":
				type_symbol = "▼"

		# Uniform iconography style colors: ALWAYS sleek flat white-grey (grimtrak iconography)
		var symbol_color := Color(0.8, 0.82, 0.85)

		# Build type label (enlarged iconography badge)
		var type_badge := Label.new()
		type_badge.text = type_symbol
		if _font: type_badge.add_theme_font_override("font", _font)
		type_badge.add_theme_font_size_override("font_size", 16) # Further enlarged Badge Icon (16 pt)
		type_badge.add_theme_color_override("font_color", symbol_color)
		type_badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		type_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		type_badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
		# Offset slightly down and right to overflow the card boundary nicely
		type_badge.offset_left = -3
		type_badge.offset_right = 6
		type_badge.offset_top = -3
		type_badge.offset_bottom = 6
		type_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrapper.add_child(type_badge)

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
				var next_lv := mini(cur_lv + 1, max_lv)
				var bonus_per_lv := 5.0 # For Excavation Drills: +5% speed per lv
				var current_bonus := cur_lv * bonus_per_lv
				var next_bonus := next_lv * bonus_per_lv
				
				tip_body = node.description
				if cur_lv > 0:
					tip_body += "\n\n[color=#55f58c]Current: +%.0f%% Mining speed[/color]" % current_bonus
				if cur_lv < max_lv:
					tip_body += "\n[color=#55aaff]Next Level: +%.0f%% Mining speed[/color]" % next_bonus
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
			if cur_lv == 0 and not purchasable:
				var parents_list: Array[String] = []
				for p in node.parents:
					parents_list.append(st.get("nodes")[p].name)
				tip_body += "\n\n[color=#ff5544]Requires: " + ", ".join(parents_list) + "[/color]"

		# Pivot offset at center for clean scaling
		card.pivot_offset = Vector2(24, 24)

		var cap_cost := tip_cost
		card.mouse_entered.connect(func() -> void:
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
				if st.call("can_purchase", cap_id):
					TooltipManager.hide_tip()
					st.call("purchase_skill", cap_id))

func _draw_connections() -> void:
	# Draw all connection lines between parent/child nodes
	var st: Node = get_node("/root/SkillTree")
	for id in st.get("nodes").keys():
		var node = st.get("nodes")[id]
		# Only draw if child node is visible
		if not st.call("is_visible", id):
			continue
			
		for parent_id in node.parents:
			if not st.call("is_visible", parent_id):
				continue
				
			var start_pos: Vector2 = st.get("nodes")[parent_id].pos
			var end_pos: Vector2 = node.pos

			# Determine line color
			var is_active: bool = parent_id in (st.get("unlocked_skills") as Array) and id in (st.get("unlocked_skills") as Array)
			var line_col := Color(0.25, 0.85, 0.45, 0.8) if is_active else Color(0.2, 0.25, 0.35, 0.4)
			var line_width := 3.0 if is_active else 1.5

			_connections_draw.draw_line(start_pos, end_pos, line_col, line_width, true)

func _on_skill_unlocked(_id: String) -> void:
	# Rebuild tree to show newly unlocked nodes & connections
	_build_tree_graph()
	_connections_draw.queue_redraw()

func _on_bg_gui_input(event: InputEvent) -> void:
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
	elif event is InputEventMouseMotion and _is_dragging:
		var mm := event as InputEventMouseMotion
		_center_ctrl.position = mm.global_position + _drag_offset
		_connections_draw.queue_redraw()
