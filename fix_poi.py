import os

files_to_fix = [
    "aerosol_refinery.tres", "atmospheric_siphon.tres", "deep_drill.tres", "extraction_optimizer.tres",
    "logistics_hub.tres", "magma_dredge.tres", "magma_resonator.tres", "mantle_cracker.tres",
    "micro_g_drill.tres", "mine.tres", "molecular_forge.tres", "plasma_smelter.tres",
    "precision_extractor.tres", "pressure_funnel.tres", "pyroclastic_forge.tres",
    "quantum_harvester.tres", "refinery.tres", "singularity_forge.tres", "sonic_resonator.tres",
    "tectonic_stabilizer.tres", "thermal_crusher.tres", "thermic_burner.tres", "zero_g_sorter.tres"
]

for filename in files_to_fix:
    path = os.path.join("/Users/sasete/Projects/iBright/Voidle/resources/buildings", filename)
    with open(path, "r") as f:
        content = f.read()
    content = content.replace("allowed_poi_types = Array[int]([2])", "allowed_poi_types = Array[int]([1])")
    with open(path, "w") as f:
        f.write(content)
print("Done fixing POIs.")
