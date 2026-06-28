import os

BUILDINGS = [
    # id, dname, desc, poi_type, cost, min_lv, slots, tick, energy, out_type, out_amt, in_type, in_amt, logic_class
    ("solar_panel", "Solar Array", "Free energy from sunlight; no fuel needed.", 1, 80.0, 1, 1, 20.0, 0.0, 1, 2.0, 0, 0.0, "EnergyLogic"),
    ("generator", "Generator", "Burns minerals for reliable mid-tier energy.", 1, 350.0, 1, 1, 14.0, 0.0, 1, 8.0, 3, 3.0, "GeneratorLogic"),
    ("power_plant", "Power Plant", "High-output plant; consumes more fuel per cycle.", 1, 1200.0, 2, 2, 12.0, 0.0, 1, 25.0, 3, 8.0, "GeneratorLogic"),
    ("mine", "Mine", "Extracts raw minerals from local deposits.", 2, 150.0, 1, 1, 18.0, -2.0, 3, 10.0, 0, 0.0, "MineLogic"),
    ("deep_drill", "Deep Drill", "High-yield extraction at higher energy cost.", 2, 600.0, 2, 2, 15.0, -5.0, 3, 28.0, 0, 0.0, "MineLogic"),
    ("refinery", "Refinery", "Converts raw ore to refined minerals.", 2, 800.0, 2, 2, 24.0, -8.0, 4, 5.0, 3, 10.0, "RefineryLogic"),
    ("residential", "Residential Block", "Basic housing; fast cycles, light income.", 0, 100.0, 1, 1, 22.0, -2.0, 2, 15.0, 0, 0.0, "CreditLogic"),
    ("apartments", "Apartments", "Denser housing; higher income per slot.", 0, 250.0, 1, 1, 20.0, -4.0, 2, 30.0, 0, 0.0, "CreditLogic"),
    ("commercial", "Commercial Center", "Trade hub with good mid-tier returns.", 0, 500.0, 1, 1, 40.0, -6.0, 2, 65.0, 0, 0.0, "CreditLogic"),
    ("luxury_complex", "Luxury Complex", "Premium residency; slow cycle, large payout.", 0, 1200.0, 2, 2, 80.0, -12.0, 2, 160.0, 0, 0.0, "CreditLogic"),
    ("spaceport", "SpacePort", "Enables ship construction and trade routes.", 4, 2000.0, 2, 2, 0.0, -12.0, 0, 0.0, 0, 0.0, "BuildingLogic"),
    ("lab", "Research Lab", "Generates research and bonus credits.", 3, 700.0, 2, 1, 35.0, -6.0, 2, 25.0, 0, 0.0, "CreditLogic"),
    ("scanner", "Deep Scanner", "Reveals hidden deposits across the system.", 3, 400.0, 1, 1, 55.0, -3.0, 2, 10.0, 0, 0.0, "CreditLogic"),
]

TPL = """[gd_resource type="Resource" script_class="BuildingDef" load_steps=3 format=3 uid="uid://{uid}"]

[ext_resource type="Script" path="res://scripts/game/logic/{logic_class}.gd" id="1_logic"]
[ext_resource type="Script" path="res://scripts/game/BuildingDef.gd" id="2_def"]

[sub_resource type="Resource" id="Resource_logic"]
script = ExtResource("1_logic")

[resource]
script = ExtResource("2_def")
building_id = "{bid}"
display_name = "{dname}"
description = "{desc}"
allowed_poi_types = Array[int]([{poi}])
base_cost = {cost}
slot_cost = {slots}
min_planet_lv = {min_lv}
tick_duration = {tick}
energy_per_tick = {energy}
output_type = {out_type}
output_amount = {out_amt}
input_type = {in_type}
input_amount = {in_amt}
logic = SubResource("Resource_logic")
unlocked_by_default = {unlocked}
"""

import uuid
os.makedirs("resources/buildings", exist_ok=True)

# Default unlocked: solar, mine, residential, scanner
unlocked_list = ["solar_panel", "mine", "residential", "scanner"]

for b in BUILDINGS:
    bid, dname, desc, poi, cost, min_lv, slots, tick, energy, out_type, out_amt, in_type, in_amt, logic_class = b
    content = TPL.format(
        uid="b_" + bid + "_" + str(uuid.uuid4()).replace("-", "")[:8],
        bid=bid, dname=dname, desc=desc, poi=poi, cost=cost, min_lv=min_lv, slots=slots,
        tick=tick, energy=energy, out_type=out_type, out_amt=out_amt, in_type=in_type, in_amt=in_amt,
        logic_class=logic_class, unlocked="true" if bid in unlocked_list else "false"
    )
    with open(f"resources/buildings/{bid}.tres", "w") as f:
        f.write(content)

print("Generated buildings!")
