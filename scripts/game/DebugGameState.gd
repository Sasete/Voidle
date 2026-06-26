## DebugGameState — attach to any node in the scene tree.
## Use Inspector checkboxes to toggle unlocks at runtime.
## Remove this node (or set enabled=false) before shipping.
@tool
extends Node

@export var enabled: bool = true

@export_group("Unlocks")
@export var solar_unlocked:  bool = false : set = _set_solar
@export var galaxy_unlocked: bool = false : set = _set_galaxy

@export_group("Economy")
@export var add_credits: float = 0.0
@export var apply_credits: bool = false : set = _apply_credits_btn

@export_group("Planet")
@export var home_planet_level: int = 1 : set = _set_home_level

@export_group("Asteroids")
@export var discover_asteroid_slot: int = -1
@export var do_discover: bool = false : set = _do_discover_btn

func _set_solar(v: bool) -> void:
	solar_unlocked = v
	if Engine.is_editor_hint() or not enabled: return
	GameState.solar_unlocked = v
	print("[Debug] solar_unlocked = ", v)

func _set_galaxy(v: bool) -> void:
	galaxy_unlocked = v
	if Engine.is_editor_hint() or not enabled: return
	GameState.galaxy_unlocked = v
	print("[Debug] galaxy_unlocked = ", v)

func _apply_credits_btn(v: bool) -> void:
	apply_credits = false   # reset toggle immediately
	if Engine.is_editor_hint() or not enabled or not v: return
	GameState.earn_credits(add_credits)
	print("[Debug] Added %.0f credits → total %.0f" % [add_credits, GameState.credits])

func _set_home_level(v: int) -> void:
	home_planet_level = v
	if Engine.is_editor_hint() or not enabled: return
	var pp := GameState.get_planet(GameState.home_planet_seed)
	pp.level = v
	pp.recalculate_limits()
	print("[Debug] Home planet level = ", v, " | max_districts=", pp.max_districts)

func _do_discover_btn(v: bool) -> void:
	do_discover = false
	if Engine.is_editor_hint() or not enabled or not v: return
	if discover_asteroid_slot >= 0:
		GameState.discover_asteroid(discover_asteroid_slot)
		print("[Debug] Discovered asteroid slot ", discover_asteroid_slot)
