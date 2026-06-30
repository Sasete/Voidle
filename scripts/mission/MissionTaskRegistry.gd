## Static registry for MissionTaskDef instances.
## Access anywhere via MissionTaskRegistry.register() / get_available() etc.
## No autoload needed — static variables persist for the lifetime of the process.
class_name MissionTaskRegistry

static var _defs: Dictionary = {}

# ── Registration ──────────────────────────────────────────────────────────────

static func register(def: MissionTaskDef) -> void:
	_defs[def.task_type] = def

static func get_def(task_type: String) -> MissionTaskDef:
	return _defs.get(task_type, null)

# ── Filtering ─────────────────────────────────────────────────────────────────

## ship_type: pass current ship type to filter type-restricted tasks.
static func get_available(current_status: String, ship_type: String = "") -> Array:
	var result: Array = []
	for def in _defs.values():
		var d := def as MissionTaskDef
		if not _matches(current_status, d.required_status):
			continue
		if not d.required_ship_types.is_empty() and ship_type not in d.required_ship_types:
			continue
		result.append(d)
	return result

static func resolve_status(def: MissionTaskDef, entry: Dictionary) -> String:
	var s: String = def.produced_status
	for key: String in entry:
		s = s.replace("{%s}" % key, str(entry[key]))
	return s

## Walk a task chain and return the tail status after all tasks.
## An empty produced_status means "keep current status" (task doesn't change location).
static func chain_tail_status(tasks: Array, start_status: String) -> String:
	var status: String = start_status
	for t in tasks:
		var def: MissionTaskDef = get_def((t as Dictionary).get("type", ""))
		if def == null or def.produced_status == "":
			continue
		status = resolve_status(def, t as Dictionary)
	return status

# ── Internal ──────────────────────────────────────────────────────────────────

static func _matches(status: String, required: Array) -> bool:
	for req in required:
		var r: String = req as String
		if r == "*":
			return true
		if r.ends_with(":*"):
			if status.begins_with(r.substr(0, r.length() - 1)):
				return true
		elif r == status:
			return true
	return false
