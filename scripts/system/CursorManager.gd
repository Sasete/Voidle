## CursorManager — autoload singleton.
## Hides the OS cursor and draws a custom pixel-art cursor via a CanvasLayer.
## Usage: CursorManager.set_state(CursorManager.State.HOVER)
extends Node

enum State { NORMAL, HOVER, SPACE, GRAB, EXIT, POINTER, IBEAM }

const SCALE := 2
const SZ    := 16

const T := 0
const W := 1
const K := 2
const C := 3
const G := 4

var _state:    State        = State.NORMAL
var _layer:    CanvasLayer  = null
var _sprite:   TextureRect  = null
var _textures: Array[ImageTexture] = []
var _hotspots: Array[Vector2]      = []

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_VISIBLE)
			if _sprite: _sprite.visible = false
		NOTIFICATION_APPLICATION_FOCUS_IN:
			DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_HIDDEN)
			if _sprite: _sprite.visible = true

func _ready() -> void:
	_register(_arrow(),   Vector2(1, 1) * SCALE)   # NORMAL
	_register(_hover(),   Vector2(7, 7) * SCALE)   # HOVER
	_register(_space(),   Vector2(7, 7) * SCALE)   # SPACE
	_register(_grab(),    Vector2(5, 3) * SCALE)   # GRAB
	_register(_exit(),    Vector2(7, 7) * SCALE)   # EXIT
	_register(_pointer(), Vector2(4, 1) * SCALE)   # POINTER
	_register(_ibeam(),   Vector2(7, 8) * SCALE)   # IBEAM

	# Hide OS cursor
	DisplayServer.mouse_set_mode(DisplayServer.MOUSE_MODE_HIDDEN)

	# CanvasLayer on top of everything
	_layer          = CanvasLayer.new()
	_layer.layer    = 500
	_layer.name     = "CursorLayer"
	add_child(_layer)

	_sprite               = TextureRect.new()
	_sprite.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_sprite.expand_mode   = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode  = TextureRect.STRETCH_KEEP
	_layer.add_child(_sprite)

	set_state(State.NORMAL)

func _process(_delta: float) -> void:
	if _sprite == null:
		return
	var mouse := _sprite.get_viewport().get_mouse_position()
	var hot   := _hotspots[_state]
	_sprite.position = mouse - hot
	_sprite.size     = Vector2(SZ, SZ) * SCALE

func set_state(s: State) -> void:
	if _state == s and _sprite != null and _sprite.texture != null:
		return
	_state          = s
	if _sprite != null:
		_sprite.texture = _textures[s]

# ── Internal ──────────────────────────────────────────────────────────────────

func _register(grid: Array, hotspot: Vector2) -> void:
	_textures.append(_bake(grid))
	_hotspots.append(hotspot)

func _bake(grid: Array) -> ImageTexture:
	var real := SZ * SCALE
	var img  := Image.create(real, real, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for gy in SZ:
		for gx in SZ:
			var col := _col(grid[gy * SZ + gx])
			if col.a > 0.0:
				for py in SCALE:
					for px in SCALE:
						img.set_pixel(gx * SCALE + px, gy * SCALE + py, col)
	return ImageTexture.create_from_image(img)

func _col(i: int) -> Color:
	match i:
		W: return Color(0.94, 0.96, 1.00)
		K: return Color(0.06, 0.07, 0.12)
		C: return Color(0.35, 0.82, 1.00)
		G: return Color(0.55, 0.60, 0.72)
	return Color(0, 0, 0, 0)

# ── Pixel designs (16×16) ─────────────────────────────────────────────────────

func _arrow() -> Array:
	return [
		K,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		K,W,K,T,T,T,T,T,T,T,T,T,T,T,T,T,
		K,W,W,K,T,T,T,T,T,T,T,T,T,T,T,T,
		K,W,W,W,K,T,T,T,T,T,T,T,T,T,T,T,
		K,W,W,W,W,K,T,T,T,T,T,T,T,T,T,T,
		K,W,W,W,W,W,K,T,T,T,T,T,T,T,T,T,
		K,W,W,W,W,W,W,K,T,T,T,T,T,T,T,T,
		K,W,W,W,W,W,W,W,K,T,T,T,T,T,T,T,
		K,W,W,W,W,W,K,K,T,T,T,T,T,T,T,T,
		K,W,W,K,W,W,K,T,T,T,T,T,T,T,T,T,
		K,W,K,T,K,W,W,K,T,T,T,T,T,T,T,T,
		K,K,T,T,T,K,W,W,K,T,T,T,T,T,T,T,
		T,T,T,T,T,T,K,W,K,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,K,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
	]

func _hover() -> Array:
	return [
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,C,C,C,K,T,T,T,T,T,K,C,C,C,T,T,
		T,C,T,T,T,T,T,T,T,T,T,T,T,C,T,T,
		T,C,T,T,T,T,T,T,T,T,T,T,T,C,T,T,
		T,K,T,T,T,T,T,T,T,T,T,T,T,K,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,K,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,K,W,K,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,K,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,K,T,T,T,T,T,T,T,T,T,T,T,K,T,T,
		T,C,T,T,T,T,T,T,T,T,T,T,T,C,T,T,
		T,C,T,T,T,T,T,T,T,T,T,T,T,C,T,T,
		T,C,C,C,K,T,T,T,T,T,K,C,C,C,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
	]

func _space() -> Array:
	# Simple pixel crosshair — clean and readable on planet surface
	return [
		T,T,T,T,T,T,T,K,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,W,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,W,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,W,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,C,K,C,T,T,T,T,T,T,T,
		K,W,W,W,T,K,W,T,W,K,T,W,W,W,K,T,
		T,T,T,T,T,T,C,K,C,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,W,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,W,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,W,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,K,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
	]

func _grab() -> Array:
	return [
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,K,K,T,K,K,T,K,K,T,T,T,T,T,
		T,T,K,W,W,K,W,W,K,W,W,K,T,T,T,T,
		T,T,K,W,W,W,W,W,W,W,W,K,T,T,T,T,
		T,K,K,W,W,W,W,W,W,W,W,K,T,T,T,T,
		T,K,W,W,W,W,W,W,W,W,W,W,K,T,T,T,
		T,K,W,W,W,W,W,W,W,W,W,W,K,T,T,T,
		T,K,W,W,W,W,W,W,W,W,W,W,K,T,T,T,
		T,T,K,W,W,W,W,W,W,W,W,K,T,T,T,T,
		T,T,T,K,W,W,W,W,W,W,K,T,T,T,T,T,
		T,T,T,K,W,C,W,W,C,W,K,T,T,T,T,T,
		T,T,T,K,W,W,W,W,W,W,K,T,T,T,T,T,
		T,T,T,T,K,K,K,K,K,K,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
	]

func _pointer() -> Array:
	return [
		T,T,T,K,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,K,W,K,T,T,T,T,T,T,T,T,T,T,T,
		T,T,K,W,K,T,T,T,T,T,T,T,T,T,T,T,
		T,T,K,W,K,K,K,T,T,T,T,T,T,T,T,T,
		T,T,K,W,K,W,K,K,K,T,T,T,T,T,T,T,
		T,T,K,W,W,W,K,W,K,K,T,T,T,T,T,T,
		K,K,K,W,W,W,W,W,W,W,K,T,T,T,T,T,
		K,W,W,W,W,W,W,W,W,W,K,T,T,T,T,T,
		K,W,W,W,W,W,W,W,W,W,K,T,T,T,T,T,
		T,K,W,W,W,W,W,W,W,K,T,T,T,T,T,T,
		T,T,K,W,C,W,W,C,W,K,T,T,T,T,T,T,
		T,T,K,W,W,W,W,W,W,K,T,T,T,T,T,T,
		T,T,T,K,K,K,K,K,K,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
	]

func _ibeam() -> Array:
	# Classic I-beam text cursor — serif bar top & bottom, thin stem
	return [
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,K,W,W,W,W,W,K,T,T,T,T,T,
		T,T,T,T,T,K,K,W,K,K,T,T,T,T,T,T,
		T,T,T,T,T,T,K,W,K,T,T,T,T,T,T,T,
		T,T,T,T,T,T,K,W,K,T,T,T,T,T,T,T,
		T,T,T,T,T,T,K,W,K,T,T,T,T,T,T,T,
		T,T,T,T,T,T,K,W,K,T,T,T,T,T,T,T,
		T,T,T,T,T,T,K,W,K,T,T,T,T,T,T,T,
		T,T,T,T,T,T,K,C,K,T,T,T,T,T,T,T,
		T,T,T,T,T,T,K,W,K,T,T,T,T,T,T,T,
		T,T,T,T,T,T,K,W,K,T,T,T,T,T,T,T,
		T,T,T,T,T,T,K,W,K,T,T,T,T,T,T,T,
		T,T,T,T,T,T,K,W,K,T,T,T,T,T,T,T,
		T,T,T,T,T,K,K,W,K,K,T,T,T,T,T,T,
		T,T,T,T,K,W,W,W,W,W,K,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
	]

func _exit() -> Array:
	# Arrow pointing left with a vertical bar — "go back"
	return [
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,C,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,C,C,T,T,T,T,T,T,T,T,T,T,
		T,T,T,C,C,C,T,T,T,T,T,T,T,T,T,T,
		T,T,C,C,C,C,C,C,C,C,C,C,K,T,T,T,
		T,C,C,C,C,C,C,C,C,C,C,C,K,T,T,T,
		K,W,W,W,W,W,W,W,W,W,W,W,K,T,T,T,
		T,C,C,C,C,C,C,C,C,C,C,C,K,T,T,T,
		T,T,C,C,C,C,C,C,C,C,C,C,K,T,T,T,
		T,T,T,C,C,C,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,C,C,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,C,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
		T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,
	]
