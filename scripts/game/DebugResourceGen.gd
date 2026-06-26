## DebugResourceGen — @tool script for testing resource generation in editor.
## Add as a child node anywhere in a scene, then use the Inspector buttons.
@tool
extends Node

@export_group("Body Settings")
@export var body_seed: int = 12345
@export var tier_min:  int = 1
@export var tier_max:  int = 3

@export_group("Actions")
@export var generate: bool = false : set = _do_generate
@export var generate_multiple_bodies: bool = false : set = _do_multi

@export_group("Output (read-only)")
@export var last_result: String = ""

func _do_generate(v: bool) -> void:
	generate = false
	if not v: return

	var br := BodyResources.generate(body_seed, tier_min, tier_max)
	var lines: Array[String] = []
	lines.append("=== Body seed %d | T%d–T%d ===" % [body_seed, tier_min, tier_max])
	lines.append("Resources found: %d" % br.resources.size())
	lines.append("")

	for rd: ResourceData in br.as_array():
		var tag_name := ResourceData.TAG_NAMES[rd.tag]
		lines.append("  [T%d] %s" % [rd.tier, rd.unique_name])
		lines.append("       Tag:        %s" % tag_name)
		lines.append("       Value:      %.2f cr/unit" % rd.base_value)
		lines.append("       Stack size: %.0f units" % rd.stack_size)
		lines.append("       ID:         %s" % rd.resource_id())
		lines.append("")

	last_result = "\n".join(lines)
	print(last_result)

func _do_multi(v: bool) -> void:
	generate_multiple_bodies = false
	if not v: return

	# Simulate 5 bodies with escalating tiers — shows discovery tracking
	var seeds := [body_seed, body_seed + 1, body_seed + 2, body_seed + 3, body_seed + 4]
	var tiers  := [[1,1], [2,3], [2,4], [3,6], [5,8]]

	var all_known: Dictionary = {}
	var lines: Array[String] = []
	lines.append("=== Multi-body discovery simulation ===")

	for i in seeds.size():
		var br := BodyResources.generate(seeds[i], tiers[i][0], tiers[i][1])
		lines.append("\nBody %d (seed %d, T%d–T%d):" % [i + 1, seeds[i], tiers[i][0], tiers[i][1]])
		for rd: ResourceData in br.as_array():
			var key := rd.resource_id()
			var is_new := not all_known.has(key)
			if is_new:
				all_known[key] = 1
			else:
				all_known[key] += 1
			var marker := "★ NEW" if is_new else ("⊕ x%d deposit" % all_known[key])
			lines.append("  [T%d] %-30s %s" % [rd.tier, rd.unique_name, marker])

	lines.append("\n--- Total unique resource types discovered: %d ---" % all_known.size())
	last_result = "\n".join(lines)
	print(last_result)
