import os
import uuid

os.makedirs("resources/districts", exist_ok=True)

TPL = """[gd_resource type="Resource" script_class="DistrictDef" load_steps=2 format=3 uid="uid://{uid}"]

[ext_resource type="Script" path="res://scripts/game/DistrictDef.gd" id="1_def"]

[resource]
script = ExtResource("1_def")
id = {did}
display_name = "{dname}"
description = "{desc}"
icon = "{icon}"
placement = {placement}
base_cost = {cost}
allowed_planet_types = Array[int]([{allowed}])
building_ids = Array[String]([{buildings}])
name_pool = Array[String]([{names}])
"""

DISTRICTS = [
    (0, "City", "Residential and commercial hub. Generates credits and houses population.", "⬡", 1, 500.0, "0, 1, 3, 5", '"residential", "apartments", "commercial", "luxury_complex", "spaceport"', '"New Carthage", "Iron Shore", "Veylan", "Kelast", "Dusk Harbor", "Aelstrom", "Fort Virion", "Mirelith", "Sunfall", "Coldmere", "Outpost Hera", "New Delos", "Vanta Port", "Ashfield", "Creston"'),
    (1, "Generator Facility", "Power plant complex. Produces energy for the colony grid.", "⚡", 1, 300.0, "", '"solar_panel", "generator", "power_plant"', '"Prometheus Array", "Grid Station Alpha", "Helios Platform", "Solara Base", "Arc Station", "Photon Plant", "Voltex Hub", "Enerion Core", "Tesla Relay", "Surge Complex", "Dawn Array"'),
    (2, "Mining Facility", "Extracts raw minerals from local deposits.", "⛏", 1, 250.0, "0, 1, 3, 2, 4, 5, 6", '"mine", "deep_drill", "refinery"', '"Deepvein Complex", "Stratum Site Alpha", "Iron Reach", "Core Station", "Bedrock Post", "Shaft Prime", "Mineral Yard", "Excavation Base", "Ironfall", "Quarry One", "Veindepth"')
]

filenames = ["city_district.tres", "generator_district.tres", "mining_district.tres"]

for i, d in enumerate(DISTRICTS):
    did, dname, desc, icon, placement, cost, allowed, buildings, names = d
    content = TPL.format(
        uid="d_" + str(did) + "_" + str(uuid.uuid4()).replace("-", "")[:8],
        did=did, dname=dname, desc=desc, icon=icon, placement=placement, cost=cost,
        allowed=allowed, buildings=buildings, names=names
    )
    with open(f"resources/districts/{filenames[i]}", "w") as f:
        f.write(content)

print("Districts generated!")
