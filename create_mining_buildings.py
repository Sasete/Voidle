import os
import uuid

resources_dir = "resources/buildings"
os.makedirs(resources_dir, exist_ok=True)

TPL_LOGIC = """[gd_resource type="Resource" script_class="BuildingDef" load_steps=3 format=3 uid="uid://{uid}"]

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
allowed_planet_types = Array[int]([{planet}])
base_cost = {cost}
slot_cost = {slots}
min_planet_lv = {min_lv}
construct_duration = 0.0
tick_duration = {tick}
energy_per_tick = {energy}
output_type = {out_type}
output_amount = {out_amt}
input_type = {in_type}
input_amount = {in_amt}
input_tier = 1
logic = SubResource("Resource_logic")
unlocked_by_default = {unlocked}
"""

TPL_NO_LOGIC = """[gd_resource type="Resource" script_class="BuildingDef" load_steps=2 format=3 uid="uid://{uid}"]

[ext_resource type="Script" path="res://scripts/game/BuildingDef.gd" id="1_def"]

[resource]
script = ExtResource("1_def")
building_id = "{bid}"
display_name = "{dname}"
description = "{desc}"
allowed_poi_types = Array[int]([{poi}])
allowed_planet_types = Array[int]([{planet}])
base_cost = {cost}
slot_cost = {slots}
min_planet_lv = {min_lv}
construct_duration = 0.0
tick_duration = {tick}
energy_per_tick = {energy}
output_type = 0
output_amount = 0.0
input_type = 0
input_amount = 0.0
input_tier = 1
unlocked_by_default = {unlocked}
"""

def create_building(bid, dname, desc, planet, cost, min_lv, tick, energy, out_type, out_amt, in_type, in_amt, logic_class, unlocked="false"):
    uid = "b_" + bid + "_" + str(uuid.uuid4()).replace("-", "")[:8]
    if logic_class:
        content = TPL_LOGIC.format(
            uid=uid, bid=bid, dname=dname, desc=desc, poi="2", planet=planet, cost=cost, slots=1,
            min_lv=min_lv, tick=tick, energy=energy, out_type=out_type, out_amt=out_amt,
            in_type=in_type, in_amt=in_amt, logic_class=logic_class, unlocked=unlocked
        )
    else:
        content = TPL_NO_LOGIC.format(
            uid=uid, bid=bid, dname=dname, desc=desc, poi="2", planet=planet, cost=cost, slots=1,
            min_lv=min_lv, tick=tick, energy=energy, unlocked=unlocked
        )
    with open(f"{resources_dir}/{bid}.tres", "w") as f:
        f.write(content)

# Extractors (output_type=3 RAW_MINERAL, logic_class="MineLogic")
create_building("mine", "Mine", "Extracts all raw minerals proportionately.", "", "150.0", "1", "18.0", "-2.0", "3", "10.0", "0", "0.0", "MineLogic", "true")
create_building("deep_drill", "Deep Drill", "Drills deeper for all raw minerals.", "", "600.0", "2", "15.0", "-5.0", "3", "28.0", "0", "0.0", "MineLogic", "false")
create_building("precision_extractor", "Precision Extractor", "Extracts only the TARGETED raw mineral.", "", "1500.0", "3", "20.0", "-15.0", "3", "80.0", "0", "0.0", "MineLogic", "false")
create_building("mantle_cracker", "Mantle Cracker", "Cracks the mantle for massive mixed raw minerals.", "", "4000.0", "4", "12.0", "-40.0", "3", "250.0", "0", "0.0", "MineLogic", "false")
create_building("quantum_harvester", "Quantum Harvester", "Godlike TARGETED extraction via quantum teleportation.", "", "12000.0", "5", "8.0", "-120.0", "3", "800.0", "0", "0.0", "MineLogic", "false")

# Refineries (output_type=4 REFINED_MINERAL, input_type=3 RAW_MINERAL, logic_class="RefineryLogic")
create_building("refinery", "Refinery", "Converts raw ore to refined minerals.", "", "800.0", "2", "24.0", "-8.0", "4", "5.0", "3", "10.0", "RefineryLogic", "false")
create_building("plasma_smelter", "Plasma Smelter", "Uses plasma to rapidly smelt minerals.", "", "2500.0", "3", "16.0", "-25.0", "4", "18.0", "3", "36.0", "RefineryLogic", "false")
create_building("molecular_forge", "Molecular Forge", "Reconstructs minerals at the molecular level.", "", "7000.0", "4", "10.0", "-60.0", "4", "60.0", "3", "120.0", "RefineryLogic", "false")
create_building("singularity_forge", "Singularity Forge", "Extreme gravity compression refining.", "", "20000.0", "5", "5.0", "-150.0", "4", "200.0", "3", "400.0", "RefineryLogic", "false")

# Volcanic Specialized (planet=3)
create_building("magma_dredge", "Magma Dredge", "Filters lava streams for extreme raw yield. (Volcanic)", "3", "3000.0", "3", "10.0", "-10.0", "3", "150.0", "0", "0.0", "MineLogic", "false")
create_building("pyroclastic_forge", "Pyroclastic Forge", "Uses geothermal heat to refine at near-zero energy cost. (Volcanic)", "3", "3500.0", "3", "12.0", "-2.0", "4", "30.0", "3", "60.0", "RefineryLogic", "false")
create_building("tectonic_stabilizer", "Tectonic Stabilizer", "Boosts Output of Magma Dredges. (Volcanic)", "3", "2000.0", "3", "30.0", "-5.0", "0", "0.0", "0", "0.0", "", "false")

# Gas Giant Specialized (planet=5)
create_building("atmospheric_siphon", "Atmospheric Siphon", "Filters rare particles from the atmosphere. (Gas Giant)", "5", "3000.0", "3", "25.0", "-8.0", "3", "200.0", "0", "0.0", "MineLogic", "false")
create_building("aerosol_refinery", "Aerosol Refinery", "Uses extreme atmospheric pressure to refine efficiently. (Gas Giant)", "5", "3500.0", "3", "20.0", "-5.0", "4", "40.0", "3", "80.0", "RefineryLogic", "false")
create_building("pressure_funnel", "Pressure Funnel", "Boosts Speed of Siphons and Aerosol Refineries. (Gas Giant)", "5", "2000.0", "3", "30.0", "-5.0", "0", "0.0", "0", "0.0", "", "false")

# Asteroid Specialized (planet=7)
create_building("micro_g_drill", "Micro-G Drill", "Fires tethers deep into the core. (Asteroid)", "7", "1200.0", "2", "12.0", "-15.0", "3", "40.0", "0", "0.0", "MineLogic", "false")
create_building("zero_g_sorter", "Zero-G Sorter", "Improves extraction speed on Asteroids.", "7", "1800.0", "2", "30.0", "-8.0", "0", "0.0", "0", "0.0", "", "false")

# District Buffs
create_building("extraction_optimizer", "Extraction Optimizer", "Increases raw output for all extractors.", "", "1200.0", "2", "30.0", "-10.0", "0", "0.0", "0", "0.0", "", "false")
create_building("sonic_resonator", "Sonic Resonator", "Increases tick speed for all extractors.", "", "1500.0", "2", "30.0", "-15.0", "0", "0.0", "0", "0.0", "", "false")
create_building("thermal_crusher", "Thermal Crusher", "Increases tick speed for all refineries.", "", "1500.0", "2", "30.0", "-12.0", "0", "0.0", "0", "0.0", "", "false")
create_building("logistics_hub", "Logistics Hub", "Reduces energy cost for all mining buildings.", "", "2000.0", "3", "30.0", "-5.0", "0", "0.0", "0", "0.0", "", "false")

print("Mining buildings created.")
