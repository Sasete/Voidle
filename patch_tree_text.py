import re

with open("scripts/game/SkillTree.gd", "r") as f:
    content = f.read()

# Replace the text descriptions for all buildings.
replaces = [
    ('Unlocks Thermal Generator (+5 E)', 'Unlocks Thermal Generator.\\nProduces +5 ⚡. Consumes -5 ore (T1).'),
    ('Unlocks Fusion Reactor (+100 E)', 'Unlocks Fusion Reactor.\\nProduces +100 ⚡. Consumes -1 sci.'),
    ('Unlocks Thermic Burner (+15 E)', 'Unlocks Thermic Burner.\\nProduces +15 ⚡. Consumes -2 ref (T2).'),
    ('Unlocks Plasma Reactor (+45 E)', 'Unlocks Plasma Reactor.\\nProduces +45 ⚡. Consumes -1 ref (T3).'),
    ('Unlocks Antimatter Chamber (+120 E)', 'Unlocks Antimatter Chamber.\\nProduces +120 ⚡. Consumes -1 ref (T4).'),
    ('Unlocks Singularity Core (+350 E)', 'Unlocks Singularity Core.\\nProduces +350 ⚡. Consumes -1 ref (T5).'),
    ('Unlocks Circuit Overloader (+3% Solar)', 'Unlocks Circuit Overloader.\\nBoosts district Solar output by +3%.'),
    ('Unlocks Magma Resonator (+2% Geo)', 'Unlocks Magma Resonator.\\nBoosts district Geothermal output by +2%.'),
    ('Unlocks Grid Optimizer (+1% Clean)', 'Unlocks Grid Optimizer.\\nBoosts all district clean energy by +1%.'),
    ('Unlocks Combustion Stabilizer (+5% Duration)', 'Unlocks Combustion Stabilizer.\\nExtends district burner fuel duration by +5%.')
]

for old, new in replaces:
    content = content.replace(old, new)

with open("scripts/game/SkillTree.gd", "w") as f:
    f.write(content)

print("Skill tree node descriptions patched.")
