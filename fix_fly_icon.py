import re

with open("scripts/planetary/PlanetaryView.gd", "r") as f:
    content = f.read()

target = """func _on_resource_produced(planet_seed: int, poi_label: String, text: String, color: Color, icon: Texture2D) -> void:
	if current_data == null or current_data.seed != planet_seed:
		return
	for poi in current_data.custom_pois:
		if poi.label == poi_label:
			poi_layer.spawn_floating_text(poi.lon_deg, poi.lat_deg, text, color, 14, icon)
			break"""

replacement = """func _on_resource_produced(planet_seed: int, poi_label: String, text: String, color: Color, icon: Texture2D) -> void:
	if current_data == null or current_data.seed != planet_seed:
		return
	for poi in current_data.custom_pois:
		if poi.label == poi_label:
			poi_layer.spawn_floating_text(poi.lon_deg, poi.lat_deg, text, color, 14, icon)
			_spawn_fly_icon(poi.lon_deg, poi.lat_deg, icon)
			break"""

content = content.replace(target, replacement)

new_func = """
func _spawn_fly_icon(lon_deg: float, lat_deg: float, icon: Texture2D) -> void:
	if icon == null or poi_layer == null or inventory_tab_btn == null: return
	
	if not poi_layer.has_method("_get_planet_params") or not poi_layer.has_method("_get_rotation"):
		return

	var p2 = poi_layer.call("_get_planet_params")
	if typeof(p2) != TYPE_DICTIONARY or p2.is_empty(): return
	
	var center: Vector2 = p2.get("center", Vector2.ZERO)
	var r_px: float     = p2.get("r_px", 0.0)
	var rot: float      = poi_layer.call("_get_rotation")
	
	var lon: float = deg_to_rad(lon_deg) - rot
	var lat: float = deg_to_rad(lat_deg)
	
	# If behind the planet, maybe don't spawn or spawn faded
	var sz: float = cos(lon) * cos(lat)
	if sz <= 0.0: return
	
	var sx: float  = sin(lon) * cos(lat)
	var sy: float  = -sin(lat)
	
	var start_pos: Vector2 = center + Vector2(sx * r_px, sy * r_px)
	
	var tr := TextureRect.new()
	tr.texture = icon
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.custom_minimum_size = Vector2(24, 24)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Use self.add_child so it renders on top of the UI
	add_child(tr)
	tr.global_position = start_pos - Vector2(12, 12)
	
	var tw := create_tween()
	tw.set_parallel(true)
	var end_pos: Vector2 = inventory_tab_btn.global_position + inventory_tab_btn.size * 0.5 - Vector2(12, 12)
	
	# Animate in an arc: X is linear/ease-in-out, Y goes up then down
	tw.tween_property(tr, "global_position:x", end_pos.x, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# For Y, we use a custom tween method to create a bezier arc
	var ctrl_y: float = minf(start_pos.y, end_pos.y) - 150.0
	var start_y: float = start_pos.y
	var end_y: float = end_pos.y
	var t_y = func(t: float):
		var y = (1.0 - t) * (1.0 - t) * start_y + 2.0 * (1.0 - t) * t * ctrl_y + t * t * end_y
		tr.global_position.y = y
		
	tw.tween_method(t_y, 0.0, 1.0, 0.8)
	
	tw.tween_property(tr, "scale", Vector2(0.6, 0.6), 0.8)
	tw.tween_property(tr, "modulate:a", 0.0, 0.2).set_delay(0.6)
	
	tw.chain().tween_callback(tr.queue_free)
	
	# Pulse the inventory tab at the end of the animation
	var tw2 := create_tween()
	tw2.tween_interval(0.7)
	tw2.tween_property(inventory_tab_btn, "scale", Vector2(1.05, 1.05), 0.1)
	tw2.tween_property(inventory_tab_btn, "scale", Vector2(1.0, 1.0), 0.1)
"""

content += new_func

with open("scripts/planetary/PlanetaryView.gd", "w") as f:
    f.write(content)

print("Done")
