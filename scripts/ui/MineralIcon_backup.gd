## Generates 18×18 procedural pixel-art mineral icons.
## Shape encodes tier (T1=ore blob, T2=crystal, T3=gem, T4=cross, T5=hollow diamond).
## Color is tinted from ResourceData.display_color (hue = rarity, brightness = tier).
class_name MineralIcon
extends RefCounted

const SIZE := 18

# ── Base shapes ───────────────────────────────────────────────────────────────

# T1: rounded ore blob
static var _T1: Array[int] = [
	0, 8160, 32760, 65532, 131070, 131070,
	262143, 262143, 262143, 262143,
	131070, 131070, 65532, 32760, 8160, 0, 0, 0,
]

# T2: crystal prism — flat top, wide middle, pointed bottom
static var _T2: Array[int] = [
	0, 0,
	4032,   # row 2  flat top 6px  (cols 6-11)
	8160,   # row 3  8px  (cols 5-12)
	16368,  # row 4  10px (cols 4-13)
	16368,  # row 5
	16368,  # row 6
	16368,  # row 7
	16368,  # row 8
	16368,  # row 9
	8160,   # row 10 tapering
	4032,   # row 11
	1920,   # row 12 4px
	768,    # row 13 bottom point 2px
	0, 0, 0, 0,
]

# T3: solid diamond gem (rhombus)
static var _T3: Array[int] = [
	0, 768, 1920, 4032, 8160, 16368,
	32760,
	16368, 8160, 4032, 1920, 768, 0, 0, 0, 0, 0, 0,
]

# T4: engineering cross / plus
# Vertical bar: cols 8-9 (rows 1-16), Horizontal bar: cols 2-15 (rows 7-9)
static var _T4: Array[int] = [
	0,
	768, 768, 768, 768, 768, 768,          # rows 1-6: vertical bar only (cols 8-9)
	65532, 65532, 65532,                    # rows 7-9: full horizontal (cols 2-15) ∪ vertical
	768, 768, 768, 768, 768, 768, 768, 0,  # rows 10-16: vertical bar only
]

# T5: hollow diamond (outline only — advanced/core material)
static var _T5: Array[int] = [
	0,
	768,    # row 1:  cols 8-9   (tip)
	1920,   # row 2:  cols 7-10
	2112,   # row 3:  cols 6,11  (edge only)
	4128,   # row 4:  cols 5,12
	8208,   # row 5:  cols 4,13
	16392,  # row 6:  cols 3,14  (widest)
	8208,   # row 7:  cols 4,13
	4128,   # row 8:  cols 5,12
	2112,   # row 9:  cols 6,11
	1152,   # row 10: cols 7,10
	768,    # row 11: cols 8-9   (tip)
	0, 0, 0, 0, 0, 0,
]

# ── Detail overlays ───────────────────────────────────────────────────────────

# T1: diagonal dark vein
static var _T1_detail: Array[int] = [
	0, 0, 4096, 6144, 3072, 1536,
	512, 768, 256, 128, 192, 0, 0, 0, 0, 0, 0, 0,
]

# T2: bright right-edge facet (light hits the right crystal face)
static var _T2_detail: Array[int] = [
	0, 0,
	2048,  # row 2  col 11 (right of flat top)
	4096,  # row 3  col 12
	8192,  # row 4  col 13
	8192,  # row 5
	4096,  # row 6
	2048,  # row 7
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]

# T3: upper triangular facet
static var _T3_detail: Array[int] = [
	0, 0, 512, 768, 1920, 4032, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]

# T4: bright center junction highlight
static var _T4_detail: Array[int] = [
	0, 0, 0, 0, 0, 0, 0,
	768, 768, 768,  # rows 7-9: center cross junction
	0, 0, 0, 0, 0, 0, 0, 0,
]

# T5: no detail (the hollow outline is distinctive enough)
static var _T5_detail: Array[int] = [
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]

static func make(tier: int, base_color: Color) -> ImageTexture:
	var mask:        Array[int]
	var detail:      Array[int]
	var dark_detail: bool

	match tier:
		1:
			mask = _T1; detail = _T1_detail; dark_detail = true
		2:
			mask = _T2; detail = _T2_detail; dark_detail = false
		3:
			mask = _T3; detail = _T3_detail; dark_detail = false
		4:
			mask = _T4; detail = _T4_detail; dark_detail = false
		_:  # T5+
			mask = _T5; detail = _T5_detail; dark_detail = false

	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var highlight := base_color.lightened(0.50)
	var shadow    := base_color.darkened(0.45)
	var vein      := base_color.darkened(0.60)
	var facet     := base_color.lightened(0.70)

	for y in SIZE:
		var row:        int = mask[y]
		var detail_row: int = detail[y]
		for x in SIZE:
			if not (row & (1 << x)):
				continue
			if detail_row & (1 << x):
				var dc := vein if dark_detail else facet
				dc.a = 1.0
				img.set_pixel(x, y, dc)
				continue
			var t: float = (float(x) + float(SIZE - 1 - y)) / float((SIZE - 1) * 2)
			var px_col := shadow.lerp(highlight, t)
			px_col.a = 1.0
			img.set_pixel(x, y, px_col)

	return ImageTexture.create_from_image(img)
