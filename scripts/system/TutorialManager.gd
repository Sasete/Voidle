## Tutorial: narrative-driven guided tutorial → optional quest panel.
## Phase 1 (new game): blocking narrative with action prompts.
## Phase 2 (optional): non-blocking quest panel.
## If tutorial already done, only the quest panel appears.
extends CanvasLayer

signal highlight_changed(target_id: String)
signal highlight_cleared()

class _PulseRing extends Control:
	var time: float = 0.0
	func _process(dt: float) -> void:
		time += dt
		queue_redraw()
	func _draw() -> void:
		var r1 := 22.0 + 5.0 * sin(time * 3.5)
		var r2 := r1 + 14.0
		var alpha := 0.7 + 0.25 * cos(time * 3.5)
		draw_arc(Vector2.ZERO, r1, 0.0, TAU, 52, Color(0.25, 0.80, 1.0, alpha), 2.5)
		draw_arc(Vector2.ZERO, r2, 0.0, TAU, 52, Color(0.25, 0.80, 1.0, alpha * 0.30), 1.5)

const DISTRICT_GENERATOR := 1

# ── Guided tutorial steps ──────────────────────────────────────────────────────
# Each step is {type, ...}:
#   type "narr"   → pages: Array of line-arrays (blocking dialog)
#   type "action" → instruction: String, targets: Array of {type, id}, reward_*
const GUIDED_STEPS: Array = [
	{
		"type":  "narr",
		"pages": [
			[
				"Year 2387. Earth is a memory.",
				"Humanity fractured into thousands of arks. Generation ships hurled into the dark.",
				"Yours made it. Barely.",
			],
			[
				"You are the Governor of a single, fragile colony.",
				"Your people need shelter, power, and knowledge to survive.",
				"The galaxy does not care whether you succeed.",
			],
			[
				"But you do.",
				"Your Capital district is already established. Your first task:",
				"Give your people somewhere to live.",
			],
		],
	},
	{
		"type":        "action",
		"instruction": "Click your Capital district  →  Build  →  Residential House",
		"targets":     [{"type": "building", "id": "residential"}],
		"reward_credits": 250.0,
		"reward_science": 0.0,
		"reward_text":   "+250 cr",
	},
	{
		"type":  "narr",
		"pages": [
			[
				"Your first residents move in.",
				"Cramped quarters, recycled air. But they're alive.",
				"Power is next. Without it, everything stops.",
			],
			[
				"You need a Generator Facility district and a Solar Array inside it.",
				"Place the district anywhere on the surface,",
				"then build the Solar Array from within it.",
			],
		],
	},
	{
		"type":        "action",
		"instruction": "Place a Generator Facility district  →  Build  →  Solar Array",
		"targets": [
			{"type": "district", "id": DISTRICT_GENERATOR},
			{"type": "building", "id": "solar_panel"},
		],
		"reward_credits": 300.0,
		"reward_science": 0.0,
		"reward_text":   "+300 cr",
	},
	{
		"type":  "narr",
		"pages": [
			[
				"The solar arrays hum to life.",
				"A fragile grid, but it's yours.",
				"Knowledge will determine whether this colony survives or merely exists.",
			],
			[
				"A University lets your colonists research and develop new technologies.",
				"You can build one inside any City district.",
				"Your Capital counts as a City district.",
			],
		],
	},
	{
		"type":        "action",
		"instruction": "Click your Capital district  →  Build  →  University",
		"targets":     [{"type": "building", "id": "lab"}],
		"reward_credits": 0.0,
		"reward_science": 25.0,
		"reward_text":   "+25 sci",
	},
	{
		"type":  "narr",
		"pages": [
			[
				"Minds at work. The university lights burn late into the night.",
				"Knowledge compounds. Every discovery unlocks the next.",
				"But knowledge without resources is just theory.",
			],
			[
				"Beneath the surface lie veins of raw minerals.",
				"The foundation of every structure, every ship, every future.",
				"Research Mining Operations in the Upgrade Tree to begin extraction.",
			],
		],
	},
	{
		"type":        "action",
		"instruction": "Open  ✦ Upgrade Tree  →  Research  Mining Operations",
		"targets":     [{"type": "skill", "id": "unlock_mining"}],
		"reward_credits": 500.0,
		"reward_science": 0.0,
		"reward_text":   "+500 cr",
	},
	{
		"type":  "narr",
		"pages": [
			[
				"Your colony grows stronger.",
				"But a frontier world cannot remain at the mercy of its circumstances.",
				"It is time to expand — to level up your planet itself.",
			],
			[
				"Planet upgrades unlock new district slots and raise your technology ceiling.",
				"Open the Planet panel and press the Level Up button.",
				"The first upgrade is fast. Future ones will demand more.",
			],
		],
	},
	{
		"type":        "action",
		"instruction": "Open Planet Panel  →  Press  LEVEL UP",
		"targets":     [{"type": "planet_level_up"}],
		"reward_credits": 300.0,
		"reward_science": 0.0,
		"reward_text":   "+300 cr",
	},
	{
		"type":  "narr",
		"pages": [
			[
				"Your planet just got bigger.",
				"More room. More potential. More pressure.",
				"Now let's put that to use.",
			],
			[
				"Your Energy district can be upgraded to hold more buildings.",
				"Open your Generator Facility district and press Upgrade District.",
				"A stronger energy grid means a stronger colony.",
			],
		],
	},
	{
		"type":        "action",
		"instruction": "Open Generator Facility  →  Press  UPGRADE DISTRICT",
		"targets":     [{"type": "district_upgrade"}],
		"reward_credits": 400.0,
		"reward_science": 10.0,
		"reward_text":   "+400 cr  +10 sci",
		"finale":        true,
	},
]

# ── Optional quest panel (shown after guided tutorial OR if already done) ───────
# First TUTORIAL_QUEST_COUNT entries mirror the guided tutorial steps.
# They are shown only when the tutorial was skipped / not played.
const TUTORIAL_QUEST_COUNT := 6

const QUESTS := [
	# ── Tutorial-equivalent quests ──────────────────────────────────────────────
	{
		"id":           "first_residents",
		"title":        "First Residents",
		"desc":         "Build a Residential House for your colonists.",
		"sub_steps":    [{"type": "building", "target": "residential"}],
		"reward_credits": 250.0,
		"reward_science": 0.0,
		"reward_text":  "+250 cr",
	},
	{
		"id":           "power_grid",
		"title":        "Power Grid",
		"desc":         "Place a Generator Facility and build a Solar Array.",
		"sub_steps":    [
			{"type": "district", "target": DISTRICT_GENERATOR},
			{"type": "building", "target": "solar_panel"},
		],
		"reward_credits": 300.0,
		"reward_science": 0.0,
		"reward_text":  "+300 cr",
	},
	{
		"id":           "research_wing",
		"title":        "Research Wing",
		"desc":         "Build a University to advance your colony's knowledge.",
		"sub_steps":    [{"type": "building", "target": "lab"}],
		"reward_credits": 0.0,
		"reward_science": 25.0,
		"reward_text":  "+25 sci",
	},
	{
		"id":           "mining_ops",
		"title":        "Mining Operations",
		"desc":         "Research Mining Operations in the Upgrade Tree.",
		"sub_steps":    [{"type": "skill", "target": "unlock_mining"}],
		"reward_credits": 500.0,
		"reward_science": 0.0,
		"reward_text":  "+500 cr",
	},
	{
		"id":           "planet_level_up",
		"title":        "Level Up",
		"desc":         "Upgrade your planet to Level 2.",
		"sub_steps":    [{"type": "planet_level_up"}],
		"reward_credits": 300.0,
		"reward_science": 0.0,
		"reward_text":  "+300 cr",
	},
	{
		"id":           "district_upgrade",
		"title":        "Expand the Grid",
		"desc":         "Upgrade your Generator Facility district.",
		"sub_steps":    [{"type": "district_upgrade"}],
		"reward_credits": 400.0,
		"reward_science": 10.0,
		"reward_text":  "+400 cr  +10 sci",
	},
	# ── Post-tutorial quests ────────────────────────────────────────────────────
	{
		"id":           "build_solar_2",
		"title":        "More Power!",
		"desc":         "Build a second Solar Array.",
		"sub_steps":    [{"type": "building", "target": "solar_panel"}],
		"reward_credits": 500.0,
		"reward_science": 5.0,
		"reward_text":  "+500 cr  +5 sci",
	},
	{
		"id":           "build_mine",
		"title":        "Into the Earth",
		"desc":         "Build a Mine to harvest raw minerals.",
		"sub_steps":    [{"type": "building", "target": "mine"}],
		"reward_credits": 400.0,
		"reward_science": 0.0,
		"reward_text":  "+400 cr",
	},
]

const SKIP_MINERAL_AMOUNT := 30.0

# ── Typewriter ─────────────────────────────────────────────────────────────────
const TW_NARR  := 0.028

# ── State ──────────────────────────────────────────────────────────────────────
var _tutorial_done: bool = false   # guided narrative complete
var _quest_done:    bool = false   # quest panel dismissed

var _guided_step:   int  = 0       # index into GUIDED_STEPS
var _action_sub:    int  = 0       # sub-target within current action step
var _solar_count:   int  = 0       # solar_panel builds total
var _active:        bool = false

var _quest_step:    int  = 0
var _quest_sub:     int  = 0

var _inventory_shown: bool = false
var tutorial_enabled: bool = true  # set false in Settings to skip tutorial entirely

# ── Narrative UI ───────────────────────────────────────────────────────────────
var _dim:         ColorRect      = null
var _narr_panel:  PanelContainer = null
var _narr_lbl:    RichTextLabel  = null
var _narr_btn:    Button         = null
var _narr_page:   int            = 0
var _narr_pages:  Array          = []
var _narr_done_cb: Callable      = Callable()
var _narr_typing: bool           = false
var _narr_instant: bool          = false

# ── Action banner (non-blocking) ───────────────────────────────────────────────
var _action_bar:  PanelContainer = null
var _action_lbl:  Label          = null
var _pulse_ring:      Control = null
var _action_block_on: bool   = false  # whether input blocking is active
var _allowed_rects:   Array[Rect2]  = []      # clicks inside any of these pass through
var _waiting_for_bid: String        = ""      # if set, waiting for this building to finish constructing
var _construction_lbl: Label        = null    # non-blocking "under construction" label

# ── Quest UI ───────────────────────────────────────────────────────────────────
var _quest_panel:    PanelContainer   = null
var _skip_btn:       Button           = null
var _title_lbl:      Label            = null
var _desc_lbl:       Label            = null
var _sub_lbl:        Label            = null
var _reward_lbl:     Label            = null
var _tracker_items:  Array[Dictionary] = []

var _orbitron: Font = null

# ═══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_orbitron = load("res://Fonts/Orbitron-VariableFont_wght.ttf")
	GameState.save_deleted.connect(_on_new_game)
	ProductionManager.building_queued.connect(_on_building_queued)
	ProductionManager.building_constructed.connect(_on_building_constructed)
	GameState.district_placed.connect(_on_district_placed)
	GameState.global_resources_changed.connect(_on_resources_changed)
	GameState.planet_progress_changed.connect(_on_planet_progress_changed)
	get_tree().root.get_node("SkillTree").skill_unlocked.connect(_on_skill_unlocked)
	get_tree().root.child_entered_tree.connect(_on_root_child_entered)

func start() -> void:
	if not tutorial_enabled or _active: return
	_active = true
	if _tutorial_done:
		if not _quest_done:
			_build_quest_ui()
			_show_quest_step(_quest_step)
	else:
		_run_guided_step()

func _on_root_child_entered(node: Node) -> void:
	# Hide tutorial UI whenever a new top-level scene is added (scene transition)
	if node.scene_file_path.ends_with("MainMenu.tscn"):
		for n in [_dim, _narr_panel, _action_bar, _quest_panel, _pulse_ring, _construction_lbl]:
			if is_instance_valid(n): (n as CanvasItem).visible = false
		_active = false

func _on_new_game() -> void:
	_tutorial_done = SettingsManager.tutorial_ever_done
	_quest_done    = false
	_guided_step   = 0
	_action_sub    = 0
	_solar_count   = 0
	_quest_step    = 0
	_quest_sub     = 0
	_active          = false
	_action_block_on = false
	_allowed_rects   = []
	_waiting_for_bid = ""
	_inventory_shown = false
	_hide_construction_wait()
	_narr_instant     = false
	_narr_pages    = []
	_narr_done_cb  = Callable()
	for n in [_dim, _narr_panel, _action_bar, _quest_panel, _pulse_ring]:
		if is_instance_valid(n): n.queue_free()
	_dim = null; _narr_panel = null; _action_bar = null; _quest_panel = null; _pulse_ring = null

# ── Signal handlers ────────────────────────────────────────────────────────────
## Fired when player clicks BUILD — advances guided tutorial immediately (don't wait for construction).
func _on_building_queued(_seed: int, bid: String) -> void:
	if not _active or _tutorial_done or _guided_step >= GUIDED_STEPS.size(): return
	var step: Dictionary = GUIDED_STEPS[_guided_step]
	if step["type"] != "action": return
	var tgt: Dictionary = step["targets"][_action_sub]
	if tgt["type"] == "building" and tgt["id"] == bid:
		if bid == "solar_panel": _solar_count += 1
		_hide_action_bar()
		_waiting_for_bid = bid
		_action_block_on  = true   # re-enable: PlanetaryView sets wait rects each frame
		highlight_changed.emit("construction_wait")
		_show_construction_wait()

func _on_building_constructed(_seed: int, _key: String, bid: String) -> void:
	# Guided tutorial — advance when the waited building finishes
	if _waiting_for_bid != "" and _waiting_for_bid == bid:
		_waiting_for_bid = ""
		_hide_construction_wait()
		_advance_action()
	# Quest panel
	if not _quest_done and _quest_step < QUESTS.size() and is_instance_valid(_quest_panel):
		var q: Dictionary = QUESTS[_quest_step]
		var ss: Dictionary = q["sub_steps"][_quest_sub]
		if ss["type"] == "building" and ss["target"] == bid:
			_advance_quest_sub()

func _on_skill_unlocked(id: String) -> void:
	# Guided tutorial
	if _active and not _tutorial_done and _guided_step < GUIDED_STEPS.size():
		var step: Dictionary = GUIDED_STEPS[_guided_step]
		if step["type"] == "action":
			var tgt: Dictionary = step["targets"][_action_sub]
			if tgt["type"] == "skill" and tgt["id"] == id:
				_close_skill_tree()
				await get_tree().create_timer(0.3).timeout
				_advance_action()
	# Quest panel
	if not _quest_done and _quest_step < QUESTS.size() and is_instance_valid(_quest_panel):
		var q: Dictionary = QUESTS[_quest_step]
		var ss: Dictionary = q["sub_steps"][_quest_sub]
		if ss["type"] == "skill" and ss["target"] == id:
			_advance_quest_sub()

func _on_district_placed(_seed: int, dtype: int) -> void:
	if _active and not _tutorial_done and _guided_step < GUIDED_STEPS.size():
		var step: Dictionary = GUIDED_STEPS[_guided_step]
		if step["type"] == "action":
			var tgt: Dictionary = step["targets"][_action_sub]
			if tgt["type"] == "district" and tgt["id"] == dtype:
				_advance_action()

	if not _quest_done and _quest_step < QUESTS.size():
		var q: Dictionary = QUESTS[_quest_step]
		var ss: Dictionary = q["sub_steps"][_quest_sub]
		if ss["type"] == "district" and ss["target"] == dtype:
			_advance_quest_sub()

func _on_planet_progress_changed(planet_seed: int) -> void:
	var pp: PlanetProgress = GameState.get_planet(planet_seed)
	if pp == null: return
	# Guided tutorial — planet level up / district upgrade
	if _active and not _tutorial_done and _guided_step < GUIDED_STEPS.size():
		var step: Dictionary = GUIDED_STEPS[_guided_step]
		if step["type"] == "action":
			var tgt: Dictionary = step["targets"][_action_sub]
			if tgt["type"] == "planet_level_up" and not pp.is_upgrading and pp.level >= 2:
				_advance_action()
			elif tgt["type"] == "district_upgrade" and _district_any_upgraded(pp):
				_advance_action()
	# Quest panel
	if not _quest_done and _quest_step < QUESTS.size() and is_instance_valid(_quest_panel):
		var q: Dictionary = QUESTS[_quest_step]
		var ss: Dictionary = q["sub_steps"][_quest_sub]
		if ss["type"] == "planet_level_up" and not pp.is_upgrading and pp.level >= 2:
			_advance_quest_sub()
		elif ss["type"] == "district_upgrade" and _district_any_upgraded(pp):
			_advance_quest_sub()

func _check_freeform_action_step(step: Dictionary) -> void:
	if step["type"] != "action": return
	var targets: Array = step["targets"]
	if _action_sub >= targets.size(): return
	var tgt: Dictionary = targets[_action_sub]
	if tgt["type"] not in ["planet_level_up", "district_upgrade"]: return
	# Check against all colonized planets
	for pp: PlanetProgress in GameState._planet_progress.values():
		if not pp.is_colonized: continue
		if tgt["type"] == "planet_level_up" and not pp.is_upgrading and pp.level >= 2:
			_advance_action(); return
		if tgt["type"] == "district_upgrade" and _district_any_upgraded(pp):
			_advance_action(); return

func _district_any_upgraded(pp: PlanetProgress) -> bool:
	for dlabel in pp.district_levels:
		if pp.district_levels[dlabel] >= 2 and not pp.district_upgrading.has(dlabel):
			return true
	return false

func _on_resources_changed() -> void:
	if _inventory_shown: return
	for key in GameState.global_resources:
		if GameState.global_resources[key] > 0.0:
			_inventory_shown = true
			_show_inventory_hint()
			return

# ── Guided tutorial state machine ──────────────────────────────────────────────
func _run_guided_step() -> void:
	if _guided_step >= GUIDED_STEPS.size():
		_end_guided_tutorial()
		return
	var step: Dictionary = GUIDED_STEPS[_guided_step]
	if step["type"] == "narr":
		_show_narr(step["pages"], func() -> void:
			_guided_step += 1
			_run_guided_step())
	else:  # action
		_action_sub = 0
		_hide_dim()
		_show_action_bar(step)
		# Unblock input for steps that need free navigation
		var first_tgt: Dictionary = step["targets"][0]
		if first_tgt["type"] in ["skill", "planet_level_up", "district_upgrade"]:
			_action_block_on = false
		# Immediately advance if condition already met (e.g. player acted during narration)
		_check_freeform_action_step(step)

func _advance_action() -> void:
	if _guided_step >= GUIDED_STEPS.size(): return
	var step: Dictionary = GUIDED_STEPS[_guided_step]
	_action_sub += 1
	if _action_sub >= step["targets"].size():
		# Action complete
		if step.get("reward_credits", 0.0) > 0.0: GameState.credits     += step["reward_credits"]
		if step.get("reward_science", 0.0) > 0.0: GameState.add_science(step["reward_science"])
		if step.has("reward_text"): _flash_reward(step["reward_text"])
		_hide_action_bar()
		if step.get("finale", false):
			_run_finale()
			return
		_guided_step += 1
		_run_guided_step()
	else:
		# Update sub-target label and highlight
		var tgt: Dictionary = step["targets"][_action_sub]
		if is_instance_valid(_action_lbl):
			_action_lbl.text = "✓ Done!  Now:  " + _target_hint(tgt)
		highlight_changed.emit(_highlight_id_for(tgt))

## Called by PlanetaryView to query what building the current action step wants.
func get_action_building_target() -> String:
	if _tutorial_done or _guided_step >= GUIDED_STEPS.size(): return ""
	var step: Dictionary = GUIDED_STEPS[_guided_step]
	if step["type"] != "action": return ""
	var sz: int = (step["targets"] as Array).size()
	var sub_idx: int = _action_sub if _action_sub < sz else sz - 1
	var tgt: Dictionary = step["targets"][sub_idx]
	return tgt["id"] if tgt["type"] == "building" else ""

## Returns "building" or "district" for the current action sub-target.
func get_action_district_target() -> int:
	if _tutorial_done or _guided_step >= GUIDED_STEPS.size(): return -1
	var step: Dictionary = GUIDED_STEPS[_guided_step]
	if step["type"] != "action": return -1
	var sz: int = (step["targets"] as Array).size()
	var sub_idx: int = _action_sub if _action_sub < sz else sz - 1
	var tgt: Dictionary = step["targets"][sub_idx]
	return int(tgt["id"]) if tgt["type"] == "district" else -1

func get_action_step_type() -> String:
	if _tutorial_done or _guided_step >= GUIDED_STEPS.size(): return ""
	var step: Dictionary = GUIDED_STEPS[_guided_step]
	if step["type"] != "action": return ""
	var sz: int = (step["targets"] as Array).size()
	var sub_idx: int = _action_sub if _action_sub < sz else sz - 1
	return GUIDED_STEPS[_guided_step]["targets"][sub_idx]["type"]

func set_allowed_rects(rects: Array[Rect2]) -> void:
	_allowed_rects = rects

## Input blocker — only clicks inside _allowed_rects pass through.
func _process(_delta: float) -> void:
	if not _active or _tutorial_done or _guided_step >= GUIDED_STEPS.size(): return
	var step: Dictionary = GUIDED_STEPS[_guided_step]
	if step["type"] == "action":
		_check_freeform_action_step(step)

func _input(event: InputEvent) -> void:
	if not _action_block_on: return
	if not (event is InputEventMouseButton): return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT: return
	var click := mb.position
	for r in _allowed_rects:
		if r.has_point(click): return
	get_viewport().set_input_as_handled()
	_flash_deny(click)

func _flash_deny(pos: Vector2) -> void:
	var lbl := Label.new()
	lbl.text = "✗"
	if _orbitron: lbl.add_theme_font_override("font", _orbitron)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25, 1.0))
	lbl.position = pos + Vector2(-10, -20)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 28, 0.5)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.5)
	tw.tween_callback(lbl.queue_free).set_delay(0.5)

func _highlight_id_for(tgt: Dictionary) -> String:
	match tgt["type"]:
		"district":        return "add_district"
		"skill":           return "skill_tree_btn"
		"planet_level_up": return "planet_level_up_btn"
		"district_upgrade": return "district_upgrade_btn"
	match tgt.get("id", ""):
		"residential", "lab": return "capital"
		"solar_panel":        return "generator_district"
	return ""

func _spawn_pulse_ring() -> void:
	if is_instance_valid(_pulse_ring): return
	_pulse_ring = _PulseRing.new()
	_pulse_ring.position = Vector2(-999, -999)  # off-screen until positioned
	_pulse_ring.custom_minimum_size = Vector2(80, 80)
	_pulse_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pulse_ring.modulate.a = 0.0
	add_child(_pulse_ring)
	create_tween().tween_property(_pulse_ring, "modulate:a", 1.0, 0.4)

func _clear_pulse_ring() -> void:
	if not is_instance_valid(_pulse_ring): return
	var r := _pulse_ring; _pulse_ring = null
	var tw := create_tween()
	tw.tween_property(r, "modulate:a", 0.0, 0.3)
	tw.tween_callback(r.queue_free)

func set_highlight_pos(screen_pos: Vector2) -> void:
	if is_instance_valid(_pulse_ring):
		_pulse_ring.position = screen_pos

func _target_hint(tgt: Dictionary) -> String:
	match tgt["type"]:
		"district":         return "Place a Generator Facility district"
		"planet_level_up":  return "Open Planet Panel  →  Press  LEVEL UP"
		"district_upgrade": return "Open Generator Facility  →  Press  UPGRADE DISTRICT"
	match tgt.get("id", ""):
		"residential": return "Build  →  Residential House"
		"solar_panel":  return "Build  →  Solar Array inside the district"
		"lab":          return "Build  →  University"
		_:              return "Build: " + tgt.get("id", "")

func _close_skill_tree() -> void:
	var root := get_tree().root
	for child: Node in root.get_children():
		if not (child is CanvasLayer): continue
		for gc: Node in child.get_children():
			var sc = gc.get_script()
			if sc != null and (sc as Script).resource_path.ends_with("SkillTreeView.gd"):
				if gc.has_signal("tree_closed"):
					gc.emit_signal("tree_closed")
				child.queue_free()
				return

func _run_finale() -> void:
	# Close SkillTree and return to planet view
	_close_skill_tree()
	await get_tree().create_timer(0.55).timeout

	# Reward was already given by _advance_action before _run_finale — nothing extra needed here

	# Big "Tutorial Complete" banner at top of planet area
	var banner := PanelContainer.new()
	var sb := _panel_style(Color(0.02, 0.04, 0.10, 0.96), Color(0.35, 0.70, 1.0, 0.85))
	banner.add_theme_stylebox_override("panel", sb)
	banner.custom_minimum_size = Vector2(520, 0)
	var _ca := _planet_area_center_anchor()
	banner.anchor_left   = _ca;  banner.anchor_right  = _ca
	banner.anchor_top    = 0.0;  banner.anchor_bottom = 0.0
	banner.offset_left   = -260; banner.offset_right  = 260
	banner.offset_top    = 52
	banner.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a    = 0.0
	add_child(banner)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	banner.add_child(vbox)

	var tag := Label.new()
	tag.text = "◈  TUTORIAL COMPLETE  ◈"
	if _orbitron: tag.add_theme_font_override("font", _orbitron)
	tag.add_theme_font_size_override("font_size", 9)
	tag.add_theme_color_override("font_color", Color(0.45, 0.78, 1.0))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tag)

	var title := Label.new()
	title.text = "The void is no longer empty."
	if _orbitron: title.add_theme_font_override("font", _orbitron)
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "You have shelter. Power. Knowledge. Minerals.\nFrom this foothold, the stars are reachable."
	if _orbitron: sub.add_theme_font_override("font", _orbitron)
	sub.add_theme_font_size_override("font_size", 10)
	sub.add_theme_color_override("font_color", Color(0.60, 0.72, 0.90))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(460, 0)
	vbox.add_child(sub)

	create_tween().tween_property(banner, "modulate:a", 1.0, 0.7)
	await get_tree().create_timer(4.2).timeout

	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 0.0, 0.8)
	await tw.finished
	if is_instance_valid(banner): banner.queue_free()
	_end_guided_tutorial()

func _end_guided_tutorial() -> void:
	_tutorial_done = true
	_hide_dim()
	AchievementManager.notify_trigger(AchievementDef.Trigger.TUTORIAL_COMPLETE)
	SettingsManager.tutorial_ever_done = true
	SettingsManager.save_settings()
	# Tutorial quests already completed — start from the post-tutorial quests
	_quest_step = TUTORIAL_QUEST_COUNT
	_quest_sub  = 0
	await get_tree().create_timer(0.4).timeout
	if not _quest_done:
		_build_quest_ui()
		_show_quest_step(_quest_step)

func _planet_area_center_anchor() -> float:
	var vp_w: float = get_viewport().get_visible_rect().size.x
	if vp_w <= 0.0: return 0.35
	var right_panel := get_tree().root.find_child("RightPanel", true, false) as Control
	var rp_w: float = right_panel.size.x if is_instance_valid(right_panel) else vp_w * 0.30
	return (vp_w - rp_w) * 0.5 / vp_w

# ── Dim overlay ────────────────────────────────────────────────────────────────
func _show_dim() -> void:
	if is_instance_valid(_dim): return
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	move_child(_dim, 0)   # behind panel
	create_tween().tween_property(_dim, "color", Color(0, 0, 0, 0.68), 0.35)

func _hide_dim() -> void:
	if not is_instance_valid(_dim): return
	var d := _dim; _dim = null
	var tw := create_tween()
	tw.tween_property(d, "color", Color(0, 0, 0, 0), 0.30)
	tw.tween_callback(d.queue_free)

# ── Narrative dialog ───────────────────────────────────────────────────────────
func _show_narr(pages: Array, on_done: Callable) -> void:
	_narr_pages   = pages
	_narr_done_cb = on_done
	_narr_page    = 0
	_show_dim()
	_build_narr_ui()
	_type_page(0)

func _build_narr_ui() -> void:
	if is_instance_valid(_narr_panel): _narr_panel.queue_free()

	_narr_panel = PanelContainer.new()
	var sb := _panel_style(Color(0.04, 0.04, 0.10, 0.97), Color(0.35, 0.45, 0.80, 0.50))
	_narr_panel.add_theme_stylebox_override("panel", sb)
	_narr_panel.custom_minimum_size = Vector2(600, 0)
	# Top-center
	var _na := _planet_area_center_anchor()
	_narr_panel.anchor_left   = _na;  _narr_panel.anchor_right  = _na
	_narr_panel.anchor_top    = 0.0;  _narr_panel.anchor_bottom = 0.0
	_narr_panel.offset_left   = -300; _narr_panel.offset_right  = 300
	_narr_panel.offset_top    = 52
	_narr_panel.modulate.a    = 0.0
	add_child(_narr_panel)
	create_tween().tween_property(_narr_panel, "modulate:a", 1.0, 0.35)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	_narr_panel.add_child(vbox)

	_narr_lbl = RichTextLabel.new()
	_narr_lbl.bbcode_enabled = true
	_narr_lbl.scroll_active  = false
	_narr_lbl.fit_content    = true
	_narr_lbl.custom_minimum_size = Vector2(528, 80)
	if _orbitron:
		_narr_lbl.add_theme_font_override("normal_font", _orbitron)
		_narr_lbl.add_theme_font_override("bold_font",   _orbitron)
	_narr_lbl.add_theme_font_size_override("normal_font_size", 13)
	_narr_lbl.add_theme_font_size_override("bold_font_size",   13)
	_narr_lbl.add_theme_color_override("default_color", Color(0.82, 0.86, 0.95))
	vbox.add_child(_narr_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 0)
	vbox.add_child(btn_row)

	var hint := Label.new()
	hint.text = "[ click anywhere to continue ]"
	if _orbitron: hint.add_theme_font_override("font", _orbitron)
	hint.add_theme_font_size_override("font_size", 8)
	hint.add_theme_color_override("font_color", Color(0.35, 0.40, 0.55))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(hint)

	_narr_btn = _mk_btn("Continue  ›", Color(0.65, 0.82, 1.0))
	_narr_btn.pressed.connect(_on_narr_btn)
	btn_row.add_child(_narr_btn)

	# Full-panel invisible click catcher (behind button row — but same z, so add first)
	# We catch _unhandled from the panel's gui_input instead:
	_narr_panel.gui_input.connect(_on_narr_panel_click)
	_narr_panel.mouse_filter = Control.MOUSE_FILTER_STOP

func _on_narr_panel_click(event: InputEvent) -> void:
	if not (event is InputEventMouseButton): return
	var mb := event as InputEventMouseButton
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		if _narr_typing:
			_narr_instant = true
		else:
			_on_narr_btn()

func _on_narr_btn() -> void:
	if _narr_typing:
		_narr_instant = true
		return
	_narr_page += 1
	if _narr_page >= _narr_pages.size():
		_close_narr()
	else:
		_type_page(_narr_page)

func _close_narr() -> void:
	var cb := _narr_done_cb; _narr_done_cb = Callable()
	_narr_instant = true
	if is_instance_valid(_narr_panel):
		var tw := create_tween()
		tw.tween_property(_narr_panel, "modulate:a", 0.0, 0.28)
		await tw.finished
	if is_instance_valid(_narr_panel): _narr_panel.queue_free(); _narr_panel = null
	if cb.is_valid(): cb.call()

func _type_page(page: int) -> void:
	if not is_instance_valid(_narr_lbl): return
	_narr_btn.disabled = true
	_narr_typing   = true
	_narr_instant  = false
	_narr_lbl.text = ""

	var lines: Array = _narr_pages[page]
	# segments: {bold, text}
	var segs: Array[Dictionary] = []
	for i in lines.size():
		segs.append({"bold": i == 0, "text": lines[i]})

	var typed_segs: Array[Dictionary] = []   # segments fully typed so far

	for si in segs.size():
		var seg: Dictionary = segs[si]
		var full: String    = seg["text"]
		var is_bold: bool   = seg["bold"]

		if _narr_instant:
			typed_segs.append(seg)
			continue

		for ci in full.length():
			if _narr_instant: break
			var partial := full.substr(0, ci + 1)
			_narr_lbl.text = _compose_bbcode(typed_segs, is_bold, partial, true)
			AudioManager.play("tick", -19.0)
			await get_tree().create_timer(TW_NARR).timeout
			if _narr_instant: break

		typed_segs.append(seg)
		_narr_lbl.text = _compose_bbcode(typed_segs, false, "", false)

	# Show complete page (handles instant-skip)
	_narr_lbl.text = _all_bbcode(segs)
	_narr_typing   = false
	_narr_instant  = false
	_narr_btn.disabled = false
	var is_last := page >= _narr_pages.size() - 1
	_narr_btn.text = "Begin  ›" if (is_last and _guided_step == 0) else ("Continue  ›")

func _compose_bbcode(done: Array[Dictionary], cur_bold: bool, cur_partial: String, cursor: bool) -> String:
	var r := ""
	for d in done:
		r += ("[b]" + d["text"] + "[/b]\n") if d["bold"] else ("[color=#9eadc8]" + d["text"] + "[/color]\n")
	if cur_partial != "" or cursor:
		var txt := cur_partial + ("▌" if cursor else "")
		r += ("[b]" + txt + "[/b]\n") if cur_bold else ("[color=#9eadc8]" + txt + "[/color]\n")
	return r

func _all_bbcode(segs: Array[Dictionary]) -> String:
	var r := ""
	for s in segs:
		r += ("[b]" + s["text"] + "[/b]\n") if s["bold"] else ("[color=#9eadc8]" + s["text"] + "[/color]\n")
	return r

# ── Action instruction bar ─────────────────────────────────────────────────────
func _show_action_bar(step: Dictionary) -> void:
	if is_instance_valid(_action_bar): _action_bar.queue_free()

	_action_bar = PanelContainer.new()
	var sb := _panel_style(Color(0.04, 0.05, 0.12, 0.88), Color(0.28, 0.55, 0.75, 0.55))
	_action_bar.add_theme_stylebox_override("panel", sb)
	_action_bar.custom_minimum_size = Vector2(420, 0)
	var _aa := _planet_area_center_anchor()
	_action_bar.anchor_left   = _aa;  _action_bar.anchor_right  = _aa
	_action_bar.anchor_top    = 1.0;  _action_bar.anchor_bottom = 1.0
	_action_bar.offset_left   = -210; _action_bar.offset_right  = 210
	_action_bar.offset_top    = -110; _action_bar.offset_bottom = -12
	_action_bar.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_action_bar.modulate.a    = 0.0
	add_child(_action_bar)
	create_tween().tween_property(_action_bar, "modulate:a", 1.0, 0.3)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_action_bar.add_child(vbox)

	var tag := Label.new()
	tag.text = "◈  OBJECTIVE"
	if _orbitron: tag.add_theme_font_override("font", _orbitron)
	tag.add_theme_font_size_override("font_size", 8)
	tag.add_theme_color_override("font_color", Color(0.45, 0.65, 0.90))
	vbox.add_child(tag)

	_action_lbl = Label.new()
	_action_lbl.text = ""  # set below by _target_hint
	if _orbitron: _action_lbl.add_theme_font_override("font", _orbitron)
	_action_lbl.add_theme_font_size_override("font_size", 12)
	_action_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.60))
	vbox.add_child(_action_lbl)

	var tgt0: Dictionary = step["targets"][0]
	_action_lbl.text = _target_hint(tgt0)

	# Spawn pulse ring and signal which element to highlight
	_action_block_on = true
	_spawn_pulse_ring()
	highlight_changed.emit(_highlight_id_for(tgt0))

	if step.has("reward_text"):
		var rew := Label.new()
		rew.text = "Reward: " + step["reward_text"]
		if _orbitron: rew.add_theme_font_override("font", _orbitron)
		rew.add_theme_font_size_override("font_size", 8)
		rew.add_theme_color_override("font_color", Color(0.38, 0.85, 0.55))
		vbox.add_child(rew)

func _hide_action_bar() -> void:
	_action_block_on = false
	_allowed_rects   = []
	highlight_cleared.emit()
	_clear_pulse_ring()
	if not is_instance_valid(_action_bar): return
	var bar := _action_bar; _action_bar = null
	var tw := create_tween()
	tw.tween_property(bar, "modulate:a", 0.0, 0.25)
	tw.tween_callback(bar.queue_free)

func _show_construction_wait() -> void:
	if is_instance_valid(_construction_lbl): _construction_lbl.queue_free()

	var bar := PanelContainer.new()
	var sb := _panel_style(Color(0.04, 0.05, 0.12, 0.88), Color(0.55, 0.45, 0.20, 0.55))
	bar.add_theme_stylebox_override("panel", sb)
	bar.custom_minimum_size = Vector2(480, 0)
	var _ba := _planet_area_center_anchor()
	bar.anchor_left   = _ba;  bar.anchor_right  = _ba
	bar.anchor_top    = 1.0;  bar.anchor_bottom = 1.0
	bar.offset_left   = -240; bar.offset_right  = 240
	bar.offset_top    = -110; bar.offset_bottom = -12
	bar.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	bar.modulate.a    = 0.0
	add_child(bar)
	create_tween().tween_property(bar, "modulate:a", 1.0, 0.4)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	bar.add_child(vbox)

	var tag := Label.new()
	tag.text = "⚙  CONSTRUCTION"
	if _orbitron: tag.add_theme_font_override("font", _orbitron)
	tag.add_theme_font_size_override("font_size", 8)
	tag.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45))
	vbox.add_child(tag)

	_construction_lbl = Label.new()
	_construction_lbl.text = "Building underway — explore freely while you wait."
	if _orbitron: _construction_lbl.add_theme_font_override("font", _orbitron)
	_construction_lbl.add_theme_font_size_override("font_size", 12)
	_construction_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.60))
	_construction_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_construction_lbl)

	# Store ref on the bar so we can free it in _hide_construction_wait
	bar.set_meta("is_construction_bar", true)
	_construction_lbl.set_meta("bar_ref", bar)

func _hide_construction_wait() -> void:
	if not is_instance_valid(_construction_lbl): return
	var bar: Node = _construction_lbl.get_meta("bar_ref", null) if _construction_lbl.has_meta("bar_ref") else _construction_lbl
	_construction_lbl = null
	if not is_instance_valid(bar): return
	var tw := create_tween()
	tw.tween_property(bar, "modulate:a", 0.0, 0.3)
	tw.tween_callback(bar.queue_free)

# ── Quest panel ────────────────────────────────────────────────────────────────
func _build_quest_ui() -> void:
	if is_instance_valid(_quest_panel): _quest_panel.queue_free()
	_tracker_items.clear()

	_quest_panel = PanelContainer.new()
	var sb := _panel_style(Color(0.04, 0.05, 0.10, 0.90), Color(0.28, 0.38, 0.72, 0.55))
	_quest_panel.add_theme_stylebox_override("panel", sb)
	_quest_panel.custom_minimum_size = Vector2(260, 0)
	_quest_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_quest_panel.position    = Vector2(16, 72)
	_quest_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quest_panel.modulate.a  = 0.0
	add_child(_quest_panel)
	create_tween().tween_property(_quest_panel, "modulate:a", 1.0, 0.4)

	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	_quest_panel.add_child(rv)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 6)
	rv.add_child(hdr)

	_mk_lbl(hdr, "◈", 10, Color(0.55, 0.75, 1.0))
	_mk_lbl(hdr, "OBJECTIVES", 9, Color(0.50, 0.65, 0.95))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(spacer)

	_skip_btn = _mk_btn("skip", Color(0.38, 0.38, 0.50))
	var skip_btn := _skip_btn
	skip_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	skip_btn.pressed.connect(func() -> void:
		_give_skip_minerals()
		_flash_skip_reward(get_viewport().get_mouse_position())
		_dismiss_quest_panel())
	skip_btn.mouse_entered.connect(func() -> void:
		var _skip_rd := ResourceData.generate(GameState.home_planet_seed, ResourceData.Tag.RAW_MINERAL, 3, 1)
		var ore_icon := MineralIcon.make(_skip_rd.tier, _skip_rd.display_color)
		TooltipManager.show_tip("Scrap the tutorial Bot", ["Skip the optional objectives.", "\n+%.0f " % SKIP_MINERAL_AMOUNT, ore_icon], ""))
	skip_btn.mouse_exited.connect(func() -> void: TooltipManager.hide_tip())
	hdr.add_child(skip_btn)

	var sep_sty := StyleBoxFlat.new()
	sep_sty.bg_color = Color(0.25, 0.32, 0.55, 0.35)
	sep_sty.content_margin_top = 1
	rv.add_child(_hsep(sep_sty))

	_title_lbl = Label.new()
	if _orbitron: _title_lbl.add_theme_font_override("font", _orbitron)
	_title_lbl.add_theme_font_size_override("font_size", 11)
	_title_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.55))
	rv.add_child(_title_lbl)

	_desc_lbl = Label.new()
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _orbitron: _desc_lbl.add_theme_font_override("font", _orbitron)
	_desc_lbl.add_theme_font_size_override("font_size", 9)
	_desc_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.90))
	rv.add_child(_desc_lbl)

	_reward_lbl = Label.new()
	if _orbitron: _reward_lbl.add_theme_font_override("font", _orbitron)
	_reward_lbl.add_theme_font_size_override("font_size", 9)
	_reward_lbl.add_theme_color_override("font_color", Color(0.38, 0.88, 0.55))
	rv.add_child(_reward_lbl)

	rv.add_child(_hsep(sep_sty))

	for i in QUESTS.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		rv.add_child(row)
		var dot := Label.new()
		dot.text = "○"
		if _orbitron: dot.add_theme_font_override("font", _orbitron)
		dot.add_theme_font_size_override("font_size", 9)
		dot.add_theme_color_override("font_color", Color(0.30, 0.36, 0.50))
		row.add_child(dot)
		var ql := Label.new()
		ql.text = QUESTS[i]["title"]
		if _orbitron: ql.add_theme_font_override("font", _orbitron)
		ql.add_theme_font_size_override("font_size", 9)
		ql.add_theme_color_override("font_color", Color(0.36, 0.42, 0.56))
		row.add_child(ql)
		_tracker_items.append({"dot": dot, "lbl": ql})

	# Pre-mark quests that were already completed (e.g. guided tutorial steps)
	for i in _quest_step:
		if i < _tracker_items.size():
			(_tracker_items[i]["dot"] as Label).text = "✓"
			(_tracker_items[i]["dot"] as Label).add_theme_color_override("font_color", Color(0.30, 0.85, 0.50))
			(_tracker_items[i]["lbl"] as Label).add_theme_color_override("font_color", Color(0.40, 0.72, 0.50))

func _show_quest_step(idx: int) -> void:
	if not is_instance_valid(_quest_panel) or idx >= QUESTS.size(): return
	var q: Dictionary = QUESTS[idx]
	for i in _tracker_items.size():
		var dot := _tracker_items[i]["dot"] as Label
		var ql  := _tracker_items[i]["lbl"] as Label
		if i < idx:
			dot.text = "✓"; dot.add_theme_color_override("font_color", Color(0.30, 0.85, 0.50))
			ql.add_theme_color_override("font_color", Color(0.40, 0.72, 0.50))
		elif i == idx:
			dot.text = "▶"; dot.add_theme_color_override("font_color", Color(0.92, 0.88, 0.55))
			ql.add_theme_color_override("font_color", Color(0.92, 0.88, 0.55))
		else:
			dot.text = "○"; dot.add_theme_color_override("font_color", Color(0.30, 0.36, 0.50))
			ql.add_theme_color_override("font_color", Color(0.36, 0.42, 0.56))
	_reward_lbl.text = "Reward: " + q["reward_text"]
	_tw_label(_title_lbl, q["title"].to_upper(), 0.022)
	await get_tree().create_timer(0.022 * q["title"].length() + 0.1).timeout
	_tw_label(_desc_lbl, q["desc"], 0.022)
	# Immediately check if current sub-step is already satisfied
	_check_quest_sub_already_done()

func _check_quest_sub_already_done() -> void:
	if _quest_done or _quest_step >= QUESTS.size() or not is_instance_valid(_quest_panel): return
	var q: Dictionary = QUESTS[_quest_step]
	if _quest_sub >= q["sub_steps"].size(): return
	var ss: Dictionary = q["sub_steps"][_quest_sub]
	var satisfied := false
	match ss["type"]:
		"building":
			for pp: PlanetProgress in GameState._planet_progress.values():
				if pp.has_building(ss["target"]):
					satisfied = true; break
		"district":
			var dtype: int = int(ss["target"])
			# dtype is DistrictDef.Type; map to POIData.POIType via DistrictDef
			var ddef: DistrictDef = DistrictDef.find(dtype as DistrictDef.Type)
			var poi_t: int = int(ddef.to_poi_type()) if ddef != null else -1
			for pp: PlanetProgress in GameState._planet_progress.values():
				if not pp.is_colonized: continue
				var pd: PlanetData = GameState.get_planet_data(pp.planet_seed)
				if pd == null: continue
				for poi: POIData in pd.custom_pois:
					if int(poi.poi_type) == poi_t:
						satisfied = true; break
				if satisfied: break
		"skill":
			satisfied = get_node("/root/SkillTree").unlocked_skills.has(ss["target"])
		"planet_level_up":
			for pp: PlanetProgress in GameState._planet_progress.values():
				if pp.is_colonized and not pp.is_upgrading and pp.level >= 2:
					satisfied = true; break
		"district_upgrade":
			for pp: PlanetProgress in GameState._planet_progress.values():
				if _district_any_upgraded(pp):
					satisfied = true; break
	if satisfied:
		_advance_quest_sub()

func _advance_quest_sub() -> void:
	if is_instance_valid(_skip_btn):
		_skip_btn.queue_free()
		_skip_btn = null
	var q: Dictionary = QUESTS[_quest_step]
	_quest_sub += 1
	if _quest_sub >= q["sub_steps"].size():
		if q.get("reward_credits", 0.0) > 0.0: GameState.credits     += q["reward_credits"]
		if q.get("reward_science", 0.0) > 0.0: GameState.add_science(q["reward_science"])
		_flash_reward(q["reward_text"])
		if _quest_step < _tracker_items.size():
			(_tracker_items[_quest_step]["dot"] as Label).text = "✓"
			(_tracker_items[_quest_step]["dot"] as Label).add_theme_color_override("font_color", Color(0.30, 0.85, 0.50))
			(_tracker_items[_quest_step]["lbl"] as Label).add_theme_color_override("font_color", Color(0.40, 0.72, 0.50))
		_quest_step += 1; _quest_sub = 0
		if _quest_step >= QUESTS.size():
			await get_tree().create_timer(1.5).timeout
			_dismiss_quest_panel()
		else:
			await get_tree().create_timer(0.9).timeout
			_show_quest_step(_quest_step)
	else:
		# More sub-steps remain — check if the next one is already done too
		_check_quest_sub_already_done()

func _dismiss_quest_panel() -> void:
	_quest_done = true
	if is_instance_valid(_quest_panel):
		var tw := create_tween()
		tw.tween_property(_quest_panel, "modulate:a", 0.0, 0.5)
		await tw.finished
		if is_instance_valid(_quest_panel): _quest_panel.queue_free(); _quest_panel = null

func _give_skip_minerals() -> void:
	var rd := ResourceData.generate(GameState.home_planet_seed, ResourceData.Tag.RAW_MINERAL, 3, 1)
	var rid := rd.resource_id()
	if not GameState.known_resources.has(rid): GameState.known_resources[rid] = rd
	GameState.add_resource(rid, SKIP_MINERAL_AMOUNT)

func _flash_skip_reward(pos: Vector2) -> void:
	var rd := ResourceData.generate(GameState.home_planet_seed, ResourceData.Tag.RAW_MINERAL, 3, 1)
	var ore_icon := MineralIcon.make(rd.tier, rd.display_color)
	var flash := RichTextLabel.new()
	flash.bbcode_enabled = true
	flash.fit_content    = true
	flash.scroll_active  = false
	flash.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	if _orbitron: flash.add_theme_font_override("normal_font", _orbitron)
	flash.add_theme_font_size_override("normal_font_size", 15)
	flash.add_theme_color_override("default_color", Color(0.90, 0.82, 0.50))
	flash.append_text("+%.0f " % SKIP_MINERAL_AMOUNT)
	flash.add_image(ore_icon, 16, 16)
	flash.position = pos + Vector2(-30, -20)
	flash.modulate.a = 0.0
	add_child(flash)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "modulate:a", 1.0, 0.15)
	tw.tween_property(flash, "position:y", flash.position.y - 50, 1.0)
	await get_tree().create_timer(0.15).timeout
	create_tween().tween_property(flash, "modulate:a", 0.0, 0.5).set_delay(0.4)
	await get_tree().create_timer(0.9).timeout
	if is_instance_valid(flash): flash.queue_free()

# ── Reward flash ──────────────────────────────────────────────────────────────
func _flash_reward(text: String) -> void:
	var anchor: Control = _quest_panel if is_instance_valid(_quest_panel) else _action_bar
	if not is_instance_valid(anchor): return
	var flash := Label.new()
	flash.text = "+ " + text
	if _orbitron: flash.add_theme_font_override("font", _orbitron)
	flash.add_theme_font_size_override("font_size", 14)
	flash.add_theme_color_override("font_color", Color(0.35, 1.0, 0.58))
	flash.position = anchor.position + Vector2(16, -28)
	add_child(flash)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "position:y", flash.position.y - 44, 1.2)
	tw.tween_property(flash, "modulate:a", 0.0, 1.2)
	await tw.finished
	if is_instance_valid(flash): flash.queue_free()

# ── Inventory hint ─────────────────────────────────────────────────────────────
func _show_inventory_hint() -> void:
	var hint := Label.new()
	hint.text = "◈  Check your Inventory — top right panel"
	if _orbitron: hint.add_theme_font_override("font", _orbitron)
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("outline_size", 3)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(20, -140)
	hint.modulate.a = 0.0
	add_child(hint)
	var tw := create_tween()
	tw.tween_property(hint, "modulate:a", 1.0, 0.4)
	tw.tween_interval(4.5)
	tw.tween_property(hint, "modulate:a", 0.0, 0.6)
	await tw.finished
	if is_instance_valid(hint): hint.queue_free()

# ── Typewriter (plain Label) ──────────────────────────────────────────────────
func _tw_label(lbl: Label, text: String, spd: float) -> void:
	if not is_instance_valid(lbl): return
	lbl.text = ""
	for i in text.length():
		await get_tree().create_timer(spd).timeout
		if not is_instance_valid(lbl): return
		lbl.text = text.substr(0, i + 1) + "▌"
	if is_instance_valid(lbl):
		lbl.text = text

# ── Style helpers ─────────────────────────────────────────────────────────────
func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(1); s.set_corner_radius_all(7)
	s.content_margin_left = 22; s.content_margin_right  = 22
	s.content_margin_top  = 18; s.content_margin_bottom = 16
	return s

func _mk_lbl(parent: Node, txt: String, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	if _orbitron: l.add_theme_font_override("font", _orbitron)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l

func _mk_btn(txt: String, col: Color) -> Button:
	var b := Button.new()
	b.text = txt; b.flat = true
	if _orbitron: b.add_theme_font_override("font", _orbitron)
	b.add_theme_font_size_override("font_size", 9)
	b.add_theme_color_override("font_color", col)
	return b

func _hsep(sty: StyleBoxFlat) -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_stylebox_override("separator", sty)
	return s
