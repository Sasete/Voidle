## DebugResourceGen — @tool script for testing resource generation in editor.
## Add as a child node anywhere in a scene, then use the Inspector buttons.
@tool
extends Node

@export_group("Body Settings")
@export var body_seed:   int = 12345
@export var rarity_min:  int = 1
@export var rarity_max:  int = 3

@export_group("Actions")
@export var generate: bool = false : set = _do_generate
@export var generate_multiple_bodies: bool = false : set = _do_multi

@export_group("Output (read-only)")
@export var last_result: String = ""

func _do_generate(v: bool) -> void:
	generate = false
	if not v: return

	var br := BodyResources.generate(body_seed, rarity_min, rarity_max)
	var lines: Array[String] = []
	lines.append("=== Body seed %d | R%d–R%d ===" % [body_seed, rarity_min, rarity_max])
	lines.append("Resources found: %d" % br.resources.size())
	lines.append("")

	for rd: ResourceData in br.as_array():
		var tag_name := ResourceData.TAG_NAMES[rd.tag]
		lines.append("  [R%d T%d] %s" % [rd.rarity, rd.tier, rd.unique_name])
		lines.append("          Tag:    %s" % tag_name)
		lines.append("          Power:  %.2f" % rd.power)
		lines.append("          Value:  %.2f cr/unit" % rd.base_value)
		lines.append("          Stack:  %.0f units" % rd.stack_size)
		lines.append("          ID:     %s" % rd.resource_id())
		lines.append("")

	last_result = "\n".join(lines)
	print(last_result)

func _do_multi(v: bool) -> void:
	generate_multiple_bodies = false
	if not v: return

	# Simulate 5 bodies with escalating tiers — shows discovery tracking
	var seeds    := [body_seed, body_seed + 1, body_seed + 2, body_seed + 3, body_seed + 4]
	var rarities := [[1,1], [1,2], [2,3], [3,4], [4,5]]

	var all_known: Dictionary = {}
	var lines: Array[String] = []
	lines.append("=== Multi-body discovery simulation ===")

	for i in seeds.size():
		var br := BodyResources.generate(seeds[i], rarities[i][0], rarities[i][1])
		lines.append("\nBody %d (seed %d, R%d–R%d):" % [i + 1, seeds[i], rarities[i][0], rarities[i][1]])
		for rd: ResourceData in br.as_array():
			var key := rd.resource_id()
			var is_new := not all_known.has(key)
			if is_new:
				all_known[key] = 1
			else:
				all_known[key] += 1
			var marker := "★ NEW" if is_new else ("⊕ x%d deposit" % all_known[key])
			lines.append("  [R%d T%d] %-28s %s" % [rd.rarity, rd.tier, rd.unique_name, marker])

	lines.append("\n--- Total unique resource types discovered: %d ---" % all_known.size())
	last_result = "\n".join(lines)
	print(last_result)
