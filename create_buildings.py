import os

resources_dir = "resources/buildings"
os.makedirs(resources_dir, exist_ok=True)

def create_building(filename, bid, name, desc, allowed_poi, allowed_planet, base_cost, slot, min_lv, c_dur, t_dur, e_tick, o_type, o_amt, i_type, i_amt, i_tier, unlocked="true"):
    content = f"""[gd_resource type="Resource" script_class="BuildingDef" load_steps=2 format=3 uid="uid://bid_{bid}"]

[ext_resource type="Script" path="res://scripts/game/BuildingDef.gd" id="1_1"]

[resource]
script = ExtResource("1_1")
building_id = "{bid}"
display_name = "{name}"
description = "{desc}"
allowed_poi_types = Array[int]([{allowed_poi}])
allowed_planet_types = Array[int]([{allowed_planet}])
base_cost = {base_cost}
slot_cost = {slot}
min_planet_lv = {min_lv}
construct_duration = {c_dur}
tick_duration = {t_dur}
energy_per_tick = {e_tick}
output_type = {o_type}
output_amount = {o_amt}
input_type = {i_type}
input_amount = {i_amt}
input_tier = {i_tier}
unlocked_by_default = {unlocked}
"""
    with open(f"{resources_dir}/{filename}.tres", "w") as f:
        f.write(content)

# Update existing
create_building("solar_panel", "solar_panel", "Solar Array", "Generates minor clean energy from sunlight.", "0", "", "150.0", "1", "1", "0.0", "30.0", "0.0", "1", "1.0", "0", "0.0", "1")
create_building("solar_matrix", "solar_matrix", "Solar Matrix", "Massive concentrated solar array. Only works on Arid planets.", "0", "2", "600.0", "1", "2", "0.0", "30.0", "0.0", "1", "4.0", "0", "0.0", "1", "false")
create_building("geothermal_plant", "geothermal_plant", "Geothermal Plant", "Extracts massive energy from the core. Only works on Volcanic planets.", "0", "6", "1000.0", "1", "3", "0.0", "30.0", "0.0", "1", "10.0", "0", "0.0", "1", "false")

create_building("generator", "generator", "Thermic Generator", "Burns raw minerals for basic energy.", "0", "", "100.0", "1", "1", "0.0", "30.0", "0.0", "1", "5.0", "3", "5.0", "1")

# Create new burners
create_building("thermic_burner", "thermic_burner", "Thermic Burner", "Burns T2 (Ingot) refined minerals for higher energy.", "0", "", "300.0", "1", "2", "0.0", "30.0", "0.0", "1", "15.0", "4", "2.0", "2", "false")
create_building("plasma_reactor", "plasma_reactor", "Plasma Reactor", "Burns T3 (Alloy) refined minerals for massive energy.", "0", "", "800.0", "1", "3", "0.0", "30.0", "0.0", "1", "45.0", "4", "1.0", "3", "false")
create_building("antimatter_chamber", "antimatter_chamber", "Antimatter Chamber", "Burns T4 (Component) refined minerals for extreme energy.", "0", "", "2000.0", "1", "4", "0.0", "30.0", "0.0", "1", "120.0", "4", "1.0", "4", "false")
create_building("singularity_core", "singularity_core", "Singularity Core", "Burns T5 (Core) refined minerals for godlike energy.", "0", "", "5000.0", "1", "5", "0.0", "30.0", "0.0", "1", "350.0", "4", "1.0", "5", "false")

# Create Buff Buildings
create_building("circuit_overloader", "circuit_overloader", "Circuit Overloader", "Increases Solar Array output in the district.", "0", "", "400.0", "1", "2", "0.0", "30.0", "0.0", "0", "0.0", "0", "0.0", "1", "false")
create_building("magma_resonator", "magma_resonator", "Magma Resonator", "Increases Geothermal Plant output in the district.", "0", "6", "800.0", "1", "3", "0.0", "30.0", "0.0", "0", "0.0", "0", "0.0", "1", "false")
create_building("grid_optimizer", "grid_optimizer", "Grid Optimizer", "Slightly increases all clean energy output in the district.", "0", "", "500.0", "1", "2", "0.0", "30.0", "0.0", "0", "0.0", "0", "0.0", "1", "false")
create_building("combustion_stabilizer", "combustion_stabilizer", "Combustion Stabilizer", "Increases tick duration of all district burners, reducing fuel consumption.", "0", "", "600.0", "1", "2", "0.0", "30.0", "0.0", "0", "0.0", "0", "0.0", "1", "false")

print("Buildings updated and created.")
