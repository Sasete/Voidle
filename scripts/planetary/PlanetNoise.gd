class_name PlanetNoise
extends RefCounted

# 3D gradient noise — mirrors planet_rocky.gdshader exactly, no seam.

static func hash3(p: Vector3, seed: int) -> Vector3:
	var s := seed * 0.001
	return Vector3(
		-1.0 + 2.0 * fposmod(sin(p.dot(Vector3(127.1+s, 311.7,  74.7))) * 43758.5453123, 1.0),
		-1.0 + 2.0 * fposmod(sin(p.dot(Vector3(269.5+s, 183.3, 246.1))) * 43758.5453123, 1.0),
		-1.0 + 2.0 * fposmod(sin(p.dot(Vector3(113.5,   271.9, 124.6))) * 43758.5453123, 1.0)
	)

static func noise3(p: Vector3, seed: int) -> float:
	var i := Vector3(floor(p.x), floor(p.y), floor(p.z))
	var f := Vector3(fposmod(p.x,1.0), fposmod(p.y,1.0), fposmod(p.z,1.0))
	var u := f * f * (Vector3(3,3,3) - 2.0*f)

	var v000 := hash3(i,               seed).dot(f)
	var v100 := hash3(i+Vector3(1,0,0),seed).dot(f-Vector3(1,0,0))
	var v010 := hash3(i+Vector3(0,1,0),seed).dot(f-Vector3(0,1,0))
	var v110 := hash3(i+Vector3(1,1,0),seed).dot(f-Vector3(1,1,0))
	var v001 := hash3(i+Vector3(0,0,1),seed).dot(f-Vector3(0,0,1))
	var v101 := hash3(i+Vector3(1,0,1),seed).dot(f-Vector3(1,0,1))
	var v011 := hash3(i+Vector3(0,1,1),seed).dot(f-Vector3(0,1,1))
	var v111 := hash3(i+Vector3(1,1,1),seed).dot(f-Vector3(1,1,1))

	return lerp(lerp(lerp(v000,v100,u.x), lerp(v010,v110,u.x), u.y),
	            lerp(lerp(v001,v101,u.x), lerp(v011,v111,u.x), u.y), u.z)

static func fbm3(p: Vector3, octaves: int, seed: int) -> float:
	var v := 0.0; var amp := 0.5; var freq := 1.0
	for _i in octaves:
		v    += amp * noise3(p * freq, seed)
		freq *= 2.0; amp *= 0.5
	return v

static func rot_y(p: Vector3, angle: float) -> Vector3:
	var c := cos(angle); var s := sin(angle)
	return Vector3(p.x*c + p.z*s, p.y, -p.x*s + p.z*c)

static func terrain_height(lon_rad: float, lat_rad: float, seed: int, roughness: float = 1.0) -> float:
	var nx := sin(lon_rad) * cos(lat_rad)
	var ny := -sin(lat_rad)
	var nz := cos(lon_rad) * cos(lat_rad)
	return fbm3(Vector3(nx, ny, nz) * 3.2 * roughness, 7, seed)

static func is_land(lon_rad: float, lat_rad: float, seed: int, sea_level: float = 0.0, roughness: float = 1.0) -> bool:
	return terrain_height(lon_rad, lat_rad, seed, roughness) - sea_level > 0.12

static func find_land_lon(base_lon: float, lat_rad: float, seed: int, sea_level: float = 0.0, roughness: float = 1.0, tries: int = 36) -> float:
	for i in tries:
		var lon := fposmod(base_lon + (i / float(tries)) * TAU, TAU)
		if is_land(lon, lat_rad, seed, sea_level, roughness):
			return lon
	return base_lon
