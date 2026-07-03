class_name MineralIcon
extends RefCounted

const BASE_SIZE := 16
const EXPORT_SIZE := 48 # Standart envanter boyutlarına tam oturması için 48x48

static var _noise_tex: FastNoiseLite = null

# ASCII tabanlı kalıplar:
# ' ' : Boşluk (Saydam)
# 'X' : Dış Çizgi (Çok koyu outline)
# '.' : Ana Maden Rengi (Noise ile doku alır)
# 'O' : Aydınlık İç Çizgi / Yüzey
# '#' : Karanlık İç Çizgi / Yüzey
# 'M' : Metalik Gri Kısım (Pinler ve Kapaklar)

const TEMPLATES: Dictionary = {
	1: [ # T1: Kaya / Ore
		"                ",
		"     XXXX       ",
		"   XXOOOOXX     ",
		"  XOOOOOOOOX    ",
		" XOO.......#X   ",
		" XOO........X   ",
		"XO..........#X  ",
		"X.....##.....X  ",
		"X.....#......X  ",
		" X..........X   ",
		" X..#X..#..#X   ",
		"  XXX XX XXX    ",
		"                ",
		"                ",
		"                ",
		"                "
	],
	2: [ # T2: Ingot (Külçe)
		"                ",
		"                ",
		"                ",
		"   XXXXXXXXXX   ",
		"  XOOOOOOOOOOX  ",
		" XOOOOOOOOOOOOX ",
		" X............X ",
		" X............X ",
		" X............X ",
		" X############X ",
		" X############X ",
		"  XXXXXXXXXXXX  ",
		"                ",
		"                ",
		"                ",
		"                "
	],
	3: [ # T3: Alloy Box (Kalın Alaşım)
		"                ",
		"      XXXX      ",
		"    XXOOOOXX    ",
		"   XOOOOOOOOX   ",
		"  XOOXXXXXXOOX  ",
		"  XOXX....XXOX  ",
		"  XOX......XOX  ",
		"  XOX......XOX  ",
		"  XOXX....XXOX  ",
		"  X##XXXXXX##X  ",
		"   X########X   ",
		"    XX####XX    ",
		"      XXXX      ",
		"                ",
		"                ",
		"                "
	],
	4: [ # T4: Microchip
		"                ",
		"    XXXXXXXX    ",
		"  XXMXXXXXXMXX  ",
		"  XM.OOOOOO.MX  ",
		"  XXO######OXX  ",
		"  XM.O....O.MX  ",
		"  XXO#XXXX#OXX  ",
		"  XM.OXXXXO.MX  ",
		"  XXO#XXXX#OXX  ",
		"  XM.O....O.MX  ",
		"  XXO######OXX  ",
		"  XM.OOOOOO.MX  ",
		"  XXMXXXXXXMXX  ",
		"    XXXXXXXX    ",
		"                ",
		"                "
	],
	5: [ # T5: Canister (Kapsül)
		"                ",
		"     XXXXXX     ",
		"    XMMMMMMX    ",
		"    XMMMMMMX    ",
		"    XXXXXXXX    ",
		"    XOO..##X    ",
		"    XO....#X    ",
		"    XO....#X    ",
		"    XO....#X    ",
		"    XO....#X    ",
		"    XO....#X    ",
		"    XXXXXXXX    ",
		"    XMMMMMMX    ",
		"    XMMMMMMX    ",
		"     XXXXXX     ",
		"                "
	]
}

## Generates a HYBRID PIXEL-ART icon (ASCII Shape + Procedural Texture).
static func make(tier: int, base_color: Color) -> ImageTexture:
	if _noise_tex == null:
		_noise_tex = FastNoiseLite.new()
		_noise_tex.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise_tex.frequency = 0.2

	var img := Image.create_empty(BASE_SIZE, BASE_SIZE, false, Image.FORMAT_RGBA8)
	_noise_tex.seed = int(base_color.to_html().hash() + tier * 100)

	var template: Array = TEMPLATES.get(tier, TEMPLATES[1])

	for y in range(BASE_SIZE):
		var row: String = template[y]
		for x in range(BASE_SIZE):
			var char_val = row[x]
			if char_val == ' ':
				continue # Transparent
				
			var c := base_color
			
			match char_val:
				'X': # Dış Çizgi
					c = c.darkened(0.75)
					c.a = 1.0
					
				'O': # Aydınlık Yüzey / Edge
					c = c.lightened(0.3)
					
				'#': # Karanlık Yüzey / Edge
					c = c.darkened(0.4)
					
				'M': # Metalik Gri (Pin/Kapak)
					# Biraz mavi/mor tonlu şık bir uzay metali
					c = Color(0.45, 0.48, 0.55)
					# Ufak ışık oyunları
					if y % 2 == 0: c = c.lightened(0.1)
					
				'.': # Ana Doku (Procedural Noise & Dithering)
					var n_tex = _noise_tex.get_noise_2d(x * 1.5, y * 1.5)
					
					# Renk Paleti Kademeleri (Dithering etkisi)
					if n_tex < -0.2:
						c = c.darkened(0.2)
					elif n_tex < 0.3:
						pass # Base color
					elif n_tex < 0.6:
						c = c.lightened(0.2)
					else:
						# Specular/Damar (Çok nadir aydınlık nokta)
						c.h = wrapf(c.h + 0.05, 0.0, 1.0)
						c.s = clampf(c.s - 0.3, 0.2, 1.0)
						c = c.lightened(0.5)
			
			img.set_pixel(x, y, c)

	# Nearest Neighbor ile büyüt (Tam keskin pikseller)
	img.resize(EXPORT_SIZE, EXPORT_SIZE, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)
