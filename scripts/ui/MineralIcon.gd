## Generates 18×18 procedural pixel-art mineral icons.
## Shape + inner detail depend on tier. Color is tinted from ResourceData.display_color.
class_name MineralIcon
extends RefCounted

const SIZE := 18

# ── Base shapes ──────────────────────────────────────────────────────────────

# T1: rounded ore blob (full oval)
static var _T1: Array[int] = [
	0, 8160, 32760, 65532, 131070, 131070,
	262143, 262143, 262143, 262143,
	131070, 131070, 65532, 32760, 8160, 0, 0, 0,
]

# T2: tall hexagonal crystal shard
static var _T2: Array[int] = [
	768, 1920, 4032, 8160, 16368, 32760,
	65532, 65532, 65532,
	32760, 16368, 8160, 4032, 1920, 768, 0, 0, 0,
]

# T3: diamond gem (rhombus)
static var _T3: Array[int] = [
	0, 768, 1920, 4032, 8160, 16368,
	32760,
	16368, 8160, 4032, 1920, 768, 0, 0, 0, 0, 0, 0,
]

# ── Detail overlays ───────────────────────────────────────────────────────────
# Detail pixels are rendered darker (T1 vein) or brighter (T2/T3 facet).

# T1: diagonal dark vein through the ore
static var _T1_detail: Array[int] = [
	0, 0, 4096, 6144, 3072, 1536,
	512, 768, 256, 128,
	192, 0, 0, 0, 0, 0, 0, 0,
]

# T2: bright vertical spine (center facet line at col 9)
static var _T2_detail: Array[int] = [
	0, 512, 512, 512, 512, 512,
	512, 512, 512,
	512, 512, 512, 512, 512, 0, 0, 0, 0,
]

# T3: upper triangular facet highlight
static var _T3_detail: Array[int] = [
	0, 0, 512, 768, 1920, 4032,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]

static func make(tier: int, base_color: Color) -> ImageTexture:
	var mask:   Array[int] = _T1 if tier <= 1 else (_T2 if tier == 2 else _T3)
	var detail: Array[int] = _T1_detail if tier <= 1 else (_T2_detail if tier == 2 else _T3_detail)
	var dark_detail: bool  = tier <= 1   # T1: dark vein; T2/T3: bright facet

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
			# Directional lighting: top-left = highlight, bottom-right = shadow
			var t: float = (float(x) + float(SIZE - 1 - y)) / float((SIZE - 1) * 2)
			var px_col := shadow.lerp(highlight, t)
			px_col.a = 1.0
			img.set_pixel(x, y, px_col)

	return ImageTexture.create_from_image(img)
