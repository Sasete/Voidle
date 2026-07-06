import re

with open("scripts/planetary/PlanetaryView.gd", "r") as f:
    content = f.read()

# 1002
t1 = """				var in_min: String = entry.get("burning_mineral", "")
				if in_min != "":
					var rd: ResourceData = GameState.known_resources.get(in_min)
					if rd: mult *= float(rd.rarity)"""
r1 = """				var in_min: String = entry.get("burning_mineral", "")
				if in_min == "":
					mult = 0.0"""
content = content.replace(t1, r1)

# 1046
t2 = """				var in_min: String = b.get("burning_mineral", "")
				if in_min != "":
					var rd: ResourceData = GameState.known_resources.get(in_min)
					if rd: mult *= float(rd.rarity)"""
r2 = """				var in_min: String = b.get("burning_mineral", "")
				if in_min == "":
					mult = 0.0"""
content = content.replace(t2, r2)

# 3173
t3 = """					var in_min: String = entry.get("burning_mineral", "")
					if in_min != "":
						var rd: ResourceData = GameState.known_resources.get(in_min)
						if rd: out_val *= float(rd.rarity)"""
r3 = """					var in_min: String = entry.get("burning_mineral", "")
					if in_min == "":
						out_val = 0.0"""
content = content.replace(t3, r3)

with open("scripts/planetary/PlanetaryView.gd", "w") as f:
    f.write(content)

print("Removed rarity mults from PlanetaryView.gd")
