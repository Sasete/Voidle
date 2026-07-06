import re

with open("scripts/planetary/PlanetaryView.gd", "r") as f:
    content = f.read()

target = """	_upload_poi_lights(pois_fresh, data)"""
replace = """	_upload_poi_lights(pois_fresh, data)
	
	if planet_renderer and planet_renderer.planet_material:
		var base_city := data.city_lights
		if pp and pp.is_colonized:
			var total_lv := pp.get_total_building_levels()
			base_city = clampf(base_city + (total_lv * 0.05), 0.0, 5.0)
		planet_renderer.planet_material.set_shader_parameter("city_lights", base_city)"""

content = content.replace(target, replace)

with open("scripts/planetary/PlanetaryView.gd", "w") as f:
    f.write(content)

print("Patched _refresh_poi_lights")
