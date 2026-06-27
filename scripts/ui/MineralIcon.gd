## Generates 14×14 procedural pixel-art mineral icons.
## Shape depends on tier (1=blob, 2=crystal, 3=gem), color is tinted from ResourceData.display_color.
class_name MineralIcon
extends RefCounted

# Pixel masks — each row is 14 bits wide (low bit = left column).
# T1: rounded ore blob
static var _T1: Array[int] = [
	0b00000000000000,
	0b00000110000000,
	0b00011111100000,
	0b00111111110000,
	0b01111111111000,
	0b01111111111000,
	0b11111111111100,
	0b11111111111100,
	0b01111111111000,
	0b01111111111000,
	0b00111111110000,
	0b00011111100000,
	0b00000110000000,
	0b00000000000000,
]

# T2: angular crystal shard
static var _T2: Array[int] = [
	0b00000100000000,
	0b00001110000000,
	0b00011111000000,
	0b00111111100000,
	0b01111111110000,
	0b11111111111000,
	0b11111111111000,
	0b01111111110000,
	0b00111111100000,
	0b00011111000000,
	0b00001110000000,
	0b00000100000000,
	0b00000000000000,
	0b00000000000000,
]

# T3: pointed gem (diamond)
static var _T3: Array[int] = [
	0b00000000000000,
	0b00000100000000,
	0b00001110000000,
	0b00111111100000,
	0b01111111110000,
	0b11111111111100,
	0b01111111110000,
	0b00111111100000,
	0b00001110000000,
	0b00000100000000,
	0b00000000000000,
	0b00000000000000,
	0b00000000000000,
	0b00000000000000,
]

const SIZE := 14

static func make(tier: int, base_color: Color) -> ImageTexture:
	var mask: Array[int] = _T1 if tier <= 1 else (_T2 if tier == 2 else _T3)
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var highlight := base_color.lightened(0.35)
	var shadow    := base_color.darkened(0.30)

	for y in SIZE:
		var row: int = mask[y]
		for x in SIZE:
			if row & (1 << x):
				# Simple lighting: top-left corner lighter
				var t: float = (float(x) + float(SIZE - 1 - y)) / float(SIZE * 2 - 2)
				var px_col := base_color.lerp(highlight, t * 0.5).lerp(shadow, (1.0 - t) * 0.25)
				px_col.a = 1.0
				img.set_pixel(x, y, px_col)

	return ImageTexture.create_from_image(img)
