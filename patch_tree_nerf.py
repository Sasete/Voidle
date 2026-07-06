import re

with open("scripts/game/SkillTree.gd", "r") as f:
    content = f.read()

replaces = [
    ('+25% Solar Array output', '+10% Solar Array output'),
    ('base += 0.30', 'base += 0.05'), # generator_efficiency
    ('+30% Generator Energy output', '+5% Generator Energy output'),
    ('base -= 0.15', 'base -= 0.05'), # power_transmission
    ('-15% Energy consumption on all buildings', '-5% Energy consumption on all buildings'),
    ('base += 0.10 * lv', 'base += 0.02 * lv'), # supercharged_generators
    ('+10% Generator Energy output', '+2% Generator Energy output'),
    ('mult -= 0.05 * lv', 'mult -= 0.02 * lv'), # energy_efficiency
    ('-5% global energy consumption', '-2% global energy consumption'),
    ('base += 0.05 * get_skill_level', 'base += 0.02 * get_skill_level'), # masteries
    ('+5% Generator Output', '+2% Generator Output'),
]

for old, new in replaces:
    content = content.replace(old, new)

with open("scripts/game/SkillTree.gd", "w") as f:
    f.write(content)

print("Nerfed SkillTree values")
