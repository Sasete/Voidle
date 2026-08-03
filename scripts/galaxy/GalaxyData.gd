class_name GalaxyData
extends Resource

var names:     Array[String]   = []
var types:     Array[int]      = []
var seeds:     Array[int]      = []
var positions: Array[Vector2]  = []
var heights:   Array[float]    = []   # slight Z offset per star
var links:     Array[Vector2i] = []
var unlocked:  Array[bool]     = []
var home_idx:  int             = 0

# persisted view state so returning from SolarView restores the same camera
var view_offset:   Vector2 = Vector2.ZERO
var view_zoom:     float   = 0.0   # 0 = unset, use default
var view_tilt:     float   = 0.52
var view_rotation: float   = 0.0

func star_count() -> int:
	return names.size()

func unlock(idx: int) -> void:
	if idx >= 0 and idx < unlocked.size():
		unlocked[idx] = true

func is_unlocked(idx: int) -> bool:
	return unlocked[idx]

# visible = unlocked, OR directly connected to an unlocked star
func is_visible(idx: int) -> bool:
	if unlocked[idx]:
		return true
	for link: Vector2i in links:
		if link.x == idx and unlocked[link.y]:
			return true
		if link.y == idx and unlocked[link.x]:
			return true
	return false

## BFS hop distances from home_idx. Index i = how many jumps from home to star i.
## Unreachable stars (shouldn't happen with MST) return -1.
func compute_hop_distances() -> Array[int]:
	var n: int = names.size()
	var dist: Array[int] = []
	dist.resize(n)
	dist.fill(-1)
	dist[home_idx] = 0
	var queue: Array[int] = [home_idx]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		for link: Vector2i in links:
			var nb: int = -1
			if   link.x == cur: nb = link.y
			elif link.y == cur: nb = link.x
			if nb >= 0 and dist[nb] < 0:
				dist[nb] = dist[cur] + 1
				queue.append(nb)
	return dist

static func from_seed(s: int, custom_n: int = 34) -> GalaxyData:
	var rng := RandomNumberGenerator.new()
	rng.seed = s ^ 0xCA1A
	var g   := GalaxyData.new()
	var n   := custom_n

	# home star at center
	g.names.append(_gen_name(rng))
	g.types.append(SolarData.StarType.YELLOW_DWARF)
	g.seeds.append(s % 99999)
	g.positions.append(Vector2.ZERO)
	g.heights.append(0.0)
	g.home_idx = 0

	# random scatter — local neighbourhood, no galaxy shape
	for _i in n - 1:
		var angle := rng.randf_range(0.0, TAU)
		var dist  := rng.randf_range(55.0, 580.0)
		if rng.randf() < 0.25:
			dist *= 0.35
		g.positions.append(Vector2(cos(angle) * dist, sin(angle) * dist))
		g.heights.append(rng.randf_range(-18.0, 18.0))   # slight height variance
		g.names.append(_gen_name(rng))
		g.types.append(_roll_type(rng))
		g.seeds.append(rng.randi() % 99999)

	# --- Build fully connected graph via Prim's MST ---
	var added: Dictionary = {}
	var in_tree: Array[bool] = []
	in_tree.resize(n)
	in_tree.fill(false)
	in_tree[0] = true
	var tree_size := 1

	while tree_size < n:
		var best_d := INF
		var best_i := -1
		var best_j := -1
		for i in n:
			if not in_tree[i]:
				continue
			for j in n:
				if in_tree[j]:
					continue
				var d: float = g.positions[i].distance_to(g.positions[j])
				if d < best_d:
					best_d = d
					best_i = i
					best_j = j
		if best_i < 0:
			break
		var key := "%d_%d" % [mini(best_i, best_j), maxi(best_i, best_j)]
		added[key] = true
		g.links.append(Vector2i(best_i, best_j))
		in_tree[best_j] = true
		tree_size += 1

	# Extra short-range edges for variety (~30% of stars get one more lane)
	for i in n:
		if rng.randf() > 0.30:
			continue
		var by_dist: Array = []
		for j in n:
			if i != j:
				by_dist.append([g.positions[i].distance_to(g.positions[j]), j])
		by_dist.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for entry: Array in by_dist.slice(1, 5):
			var j: int = int(entry[1])
			var key := "%d_%d" % [mini(i, j), maxi(i, j)]
			if not added.has(key):
				added[key] = true
				g.links.append(Vector2i(i, j))
				break

	# unlock state — home starts visited
	g.unlocked.resize(n)
	g.unlocked.fill(false)
	g.unlocked[0] = true
	return g

static func _roll_type(rng: RandomNumberGenerator) -> int:
	var roll := rng.randi() % 10
	if   roll < 3: return SolarData.StarType.RED_DWARF
	elif roll < 6: return SolarData.StarType.YELLOW_DWARF
	elif roll < 8: return SolarData.StarType.ORANGE_SUBGIANT
	elif roll < 9: return SolarData.StarType.BLUE_GIANT
	else:          return SolarData.StarType.WHITE_DWARF

static func _gen_name(rng: RandomNumberGenerator) -> String:
	var pre := ["Aethon","Voryn","Calix","Theron","Solun","Myrk","Delvai","Orun","Zethis","Ilvar",
				"Corvus","Lyren","Narek","Solvex","Tauri","Pheron","Kalos","Veldris","Ulnor","Azmar",
				"Oryn","Hexis","Caldun","Sethar","Verix","Druun","Althar","Synor","Kelvar","Praxis"]
	var suf := ["Prime","Nova","VII","Minor","Reach","Cross","Rift","Deep","Verge","Shoal",
				"Veil","Cradle","Spur","Drift","Mark","Gate","Expanse","Void","Nexus","Anchor",
				"Fold","Breach","Haven","Margin","Limit","Pulse","Sector","Fringe","Hollow","Basin"]
	return pre[rng.randi() % pre.size()] + " " + suf[rng.randi() % suf.size()]
