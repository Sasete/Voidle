extends SceneTree
func _init():
	print("Test started")
	var total_production: float = 0.0
	var total_demand: float = 2.0
	var energy_ratio: float = 1.0
	if total_demand > 0.0:
		energy_ratio = clampf(total_production / total_demand, 0.0, 1.0)
	print("Ratio: ", energy_ratio)
	quit()
