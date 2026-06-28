import os

files = {
    "generator.tres": "2",
    "solar_panel.tres": "2",
    "power_plant.tres": "2",
    "mine.tres": "1",
    "deep_drill.tres": "1",
    "refinery.tres": "1",
    "spaceport.tres": "5",
    "lab.tres": "4",
    "scanner.tres": "4",
    "residential.tres": "0",
    "apartments.tres": "0",
    "commercial.tres": "0",
    "luxury_complex.tres": "0",
}

for fname, poi in files.items():
    path = os.path.join("resources/buildings", fname)
    with open(path, "r") as f:
        content = f.read()
    
    import re
    content = re.sub(r'allowed_poi_types = Array\[int\]\(\[\d+\]\)', f'allowed_poi_types = Array[int]([{poi}])', content)
    
    with open(path, "w") as f:
        f.write(content)

print("Fixed!")
