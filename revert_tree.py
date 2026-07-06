import re

with open("scripts/game/SkillTree.gd", "r") as f:
    content = f.read()

replaces = [
    ('Unlocks Thermal Generator.\\nProduces +5 ⚡. Consumes -5 ore (T1).', 'Unlocks Thermal Generator.'),
    ('Unlocks Fusion Reactor.\\nProduces +100 ⚡. Consumes -1 sci.', 'Unlocks Fusion Reactor.'),
    ('Unlocks Thermic Burner.\\nProduces +15 ⚡. Consumes -2 ref (T2).', 'Unlocks Thermic Burner.'),
    ('Unlocks Plasma Reactor.\\nProduces +45 ⚡. Consumes -1 ref (T3).', 'Unlocks Plasma Reactor.'),
    ('Unlocks Antimatter Chamber.\\nProduces +120 ⚡. Consumes -1 ref (T4).', 'Unlocks Antimatter Chamber.'),
    ('Unlocks Singularity Core.\\nProduces +350 ⚡. Consumes -1 ref (T5).', 'Unlocks Singularity Core.'),
]

for old, new in replaces:
    content = content.replace(old, new)

with open("scripts/game/SkillTree.gd", "w") as f:
    f.write(content)
print("Reverted effect_desc in SkillTree.gd")
