class_name TechIcon
extends RefCounted

const BASE_SIZE := 16
const EXPORT_SIZE := 32 # Sharp pixel-art scale

static var _noise_tex: FastNoiseLite = null

# ASCII tabanlı kalıplar (Tech ve Hologram stili):
# ' ' : Saydam
# 'X' : Dış Çerçeve (Koyu Hologram Rengi)
# '.' : Ana Renk (Kısmen saydam / tarama çizgili)
# 'O' : Parlak / Yüksek Enerjili Çekirdek

const TEMPLATES: Dictionary = {
	1: [ # T1: Data / Node (Sade Üçgen)
		"                ",
		"       XX       ",
		"      X..X      ",
		"     X....X     ",
		"    X..OO..X    ",
		"   X.OOOOOO.X   ",
		"  X..OOOOOO..X  ",
		" X....OOOO....X ",
		" X............X ",
		"  XX........XX  ",
		"    XXXXXXXX    ",
		"                ",
		"                ",
		"                ",
		"                ",
		"                "
	],
	2: [ # T2: Drill / Mining (Matkap / Kazı)
		"                ",
		"  XXXXXXXXXXXX  ",
		"  X..........X  ",
		"  X.OOOOOOOO.X  ",
		"   X.OOOOOO.X   ",
		"   X.OOOOOO.X   ",
		"    X.OOOO.X    ",
		"    X.OOOO.X    ",
		"     X.OO.X     ",
		"     X....X     ",
		"      X..X      ",
		"      X..X      ",
		"       XX       ",
		"                ",
		"                ",
		"                "
	],
	3: [ # T3: Energy / Lightning (Şimşek / Enerji)
		"                ",
		"      XXXX      ",
		"     X...X      ",
		"    X.OOX       ",
		"   X.OOX        ",
		"  X.OOXXXXXX    ",
		"  X.OOOO...X    ",
		"  XXXXXX.OOX    ",
		"       X.OOX    ",
		"      X.OOX     ",
		"     X...X      ",
		"     XXXX       ",
		"                ",
		"                ",
		"                ",
		"                "
	],
	4: [ # T4: Grid / Solar (Güneş Paneli / Çapraz Ağ)
		"                ",
		"   XX      XX   ",
		"   X.X    X.X   ",
		"  X..XXXXXX..X  ",
		"  X.OOOOOOOO.X  ",
		"  X.O..XX..O.X  ",
		"  X.OX.OO.XO.X  ",
		"  X.OX.OO.XO.X  ",
		"  X.O..XX..O.X  ",
		"  X.OOOOOOOO.X  ",
		"  X..XXXXXX..X  ",
		"   X.X    X.X   ",
		"   XX      XX   ",
		"                ",
		"                ",
		"                "
	],
	5: [ # T5: Core (Ana Çekirdek)
		"                ",
		"       XX       ",
		"      X..X      ",
		"   XXXXOOXXXX   ",
		"  X...XOOX...X  ",
		"  X.OOXOOXOO.X  ",
		"  XXOOOOOOOOXX  ",
		"   XXOOOOOOXX   ",
		"  XXOOOOOOOOXX  ",
		"  X.OOXOOXOO.X  ",
		"  X...XOOX...X  ",
		"   XXXXOOXXXX   ",
		"      X..X      ",
		"       XX       ",
		"                ",
		"                "
	]
}

## Generates a Monochromatic Holographic Tech Icon
static func make(tier: int, base_color: Color) -> ImageTexture:
	if _noise_tex == null:
		_noise_tex = FastNoiseLite.new()
		_noise_tex.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise_tex.frequency = 0.5

	var img := Image.create_empty(BASE_SIZE, BASE_SIZE, false, Image.FORMAT_RGBA8)
	var template: Array = TEMPLATES.get(tier, TEMPLATES[1])

	for y in range(BASE_SIZE):
		var row: String = template[y]
		for x in range(BASE_SIZE):
			var char_val = row[x]
			if char_val == ' ': continue
				
			var c := base_color
			
			match char_val:
				'X': # Dış Çerçeve (Karanlık ve Saydam)
					c = c.darkened(0.5)
					c.a = 0.85
				'O': # Çekirdek (Çok Parlak, Işık Saçan)
					c = c.lightened(0.4)
					c.s = clampf(c.s - 0.2, 0.0, 1.0)
				'.': # Ana Gövde (Hologram Scanline Efekti)
					if y % 2 == 0:
						c = c.darkened(0.2)
						c.a = 0.6
					else:
						c = c.lightened(0.1)
						c.a = 0.8

			img.set_pixel(x, y, c)

	img.resize(EXPORT_SIZE, EXPORT_SIZE, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)
