import os
import shutil

ACHIEVEMENTS_DIR = "resources/achievements"

# Ensure the directory exists
os.makedirs(ACHIEVEMENTS_DIR, exist_ok=True)

# Helper to write a .tres file
def write_achievement(a_id, title, desc, icon, trigger, int_val=0, float_val=0.0, str_val=""):
    content = f"""[gd_resource type="Resource" script_class="AchievementDef" format=3]

[ext_resource type="Script" path="res://resources/achievements/AchievementDef.gd" id="1_def"]

[resource]
script = ExtResource("1_def")
achievement_id = "{a_id}"
title = "{title}"
description = "{desc}"
icon = "{icon}"
trigger = {trigger}
int_value = {int_val}
float_value = {float_val}
string_value = "{str_val}"
steam_id = ""
secret = false
"""
    file_path = os.path.join(ACHIEVEMENTS_DIR, f"{a_id}.tres")
    with open(file_path, "w") as f:
        f.write(content)

achievements = []

# 1. Firsts (10)
achievements.extend([
    ("first_tutorial", "First Steps", "Complete the basics of Voidle.", "🎓", 15), # TUTORIAL_COMPLETE=15
    ("first_district", "Pioneer", "Place your first district on a planet.", "🏕️", 0), # FIRST_DISTRICT=0
    ("first_building", "Architect", "Construct your first building.", "🏗️", 1), # FIRST_BUILDING=1
    ("first_orbital", "Defying Gravity", "Launch your first orbital station.", "🛰️", 2), # FIRST_ORBITAL=2
    ("first_asteroid", "Rockhound", "Scan your first asteroid belt.", "☄️", 3), # FIRST_ASTEROID_SCAN=3
    ("first_moon", "One Small Step", "Colonize your first moon.", "🌕", 4), # FIRST_MOON_COLONY=4
    ("first_interplanetary", "Interplanetary", "Travel to another solar system.", "🚀", 5), # FIRST_SOLAR_TRAVEL=5
    ("first_galaxy", "Galactic Vision", "Unlock the Galaxy view.", "🌌", 6), # FIRST_GALAXY_VIEW=6
    ("first_survey", "Deep Space Surveyor", "Survey your first star system.", "🔭", 7), # FIRST_SURVEY=7
])

# 2. Economy / Credits (12)
# trigger CREDITS_TOTAL = 9
cr_tiers = [
    (10_000, "Spare Change", "Earn your first 10,000 credits."),
    (100_000, "Start-up", "Earn 100,000 credits."),
    (1_000_000, "Millionaire", "Earn 1,000,000 credits."),
    (10_000_000, "Corporate Entity", "Earn 10,000,000 credits."),
    (100_000_000, "Mega-Corp", "Earn 100,000,000 credits."),
    (1_000_000_000, "Billionaire", "Earn 1,000,000,000 credits."),
    (10_000_000_000, "Market Dominator", "Earn 10 Billion credits."),
    (100_000_000_000, "Interstellar Monopoly", "Earn 100 Billion credits."),
    (1_000_000_000_000, "Trillionaire", "Earn 1 Trillion credits."),
    (1_000_000_000_000_000, "Quadrillionaire", "Earn 1 Quadrillion credits."),
    (1_000_000_000_000_000_000, "Quintillionaire", "Earn 1 Quintillion credits."),
    (1e21, "Post-Scarcity Economy", "Earn 1 Sextillion credits. Money has lost all meaning."),
]
for i, (amt, title, desc) in enumerate(cr_tiers):
    achievements.append((f"credits_tier_{i}", title, desc, "💰", 9, 0, amt, ""))

# 3. Science (12)
# trigger SCIENCE_TOTAL = 10
sci_tiers = [
    (5_000, "Hypothesis", "Generate 5,000 Science."),
    (50_000, "Theory", "Generate 50,000 Science."),
    (500_000, "Discovery", "Generate 500,000 Science."),
    (5_000_000, "Breakthrough", "Generate 5 Million Science."),
    (50_000_000, "Paradigm Shift", "Generate 50 Million Science."),
    (500_000_000, "Scientific Revolution", "Generate 500 Million Science."),
    (5_000_000_000, "Universal Laws", "Generate 5 Billion Science."),
    (50_000_000_000, "Grand Unified Theory", "Generate 50 Billion Science."),
    (500_000_000_000, "Omniscience", "Generate 500 Billion Science."),
    (5_000_000_000_000, "Transcendent Knowledge", "Generate 5 Trillion Science."),
    (5_000_000_000_000_000, "God-Brain", "Generate 5 Quadrillion Science."),
    (5e18, "Singularity", "Generate 5 Quintillion Science."),
]
for i, (amt, title, desc) in enumerate(sci_tiers):
    achievements.append((f"science_tier_{i}", title, desc, "🔬", 10, 0, amt, ""))

# 4. Building Count (12)
# trigger BUILDING_COUNT = 13
build_tiers = [
    (10, "Settlement", "Construct 10 buildings."),
    (50, "Town", "Construct 50 buildings."),
    (250, "City", "Construct 250 buildings."),
    (1000, "Metropolis", "Construct 1,000 buildings."),
    (5000, "Ecumene", "Construct 5,000 buildings."),
    (10_000, "Dysonian Scale", "Construct 10,000 buildings."),
    (25_000, "Megastructure", "Construct 25,000 buildings."),
    (50_000, "Stellar Engine", "Construct 50,000 buildings."),
    (100_000, "Galactic Core", "Construct 100,000 buildings."),
    (250_000, "Kardashev Type II", "Construct 250,000 buildings."),
    (500_000, "Kardashev Type III", "Construct 500,000 buildings."),
    (1_000_000, "Universal Architects", "Construct 1,000,000 buildings."),
]
for i, (amt, title, desc) in enumerate(build_tiers):
    achievements.append((f"building_tier_{i}", title, desc, "🏙️", 13, amt, 0.0, ""))

# 5. District Count (10)
# trigger DISTRICT_COUNT = 14
dist_tiers = [
    (5, "Expanding Borders", "Place 5 districts."),
    (25, "Urban Sprawl", "Place 25 districts."),
    (100, "Planetary Network", "Place 100 districts."),
    (250, "Global Grid", "Place 250 districts."),
    (500, "System-Wide Grid", "Place 500 districts."),
    (1000, "Interstellar Logistics", "Place 1,000 districts."),
    (2500, "Sector Governance", "Place 2,500 districts."),
    (5000, "Galactic Empire", "Place 5,000 districts."),
    (10_000, "Infinite Reach", "Place 10,000 districts."),
    (25_000, "Manifest Destiny", "Place 25,000 districts."),
]
for i, (amt, title, desc) in enumerate(dist_tiers):
    achievements.append((f"district_tier_{i}", title, desc, "🗺️", 14, amt, 0.0, ""))

# 6. Planet Levels (9)
# trigger PLANET_LEVEL = 8
for lvl in range(2, 11):
    achievements.append((f"planet_level_{lvl}", f"World Class Lv{lvl}", f"Upgrade a planet to Level {lvl}.", "🌍", 8, lvl, 0.0, ""))

# 7. Colonized Planets Count (10)
# trigger COLONIZED_PLANETS_COUNT = 15
colonize_tiers = [
    (2, "Multi-Planetary", "Colonize 2 planets."),
    (5, "Local Hegemony", "Colonize 5 planets."),
    (10, "Sector Authority", "Colonize 10 planets."),
    (25, "Stellar Federation", "Colonize 25 planets."),
    (50, "Grand Alliance", "Colonize 50 planets."),
    (100, "Galactic Republic", "Colonize 100 planets."),
    (250, "The First Empire", "Colonize 250 planets."),
    (500, "Dominion", "Colonize 500 planets."),
    (1000, "Thousand Worlds", "Colonize 1,000 planets."),
    (5000, "Master of the Cosmos", "Colonize 5,000 planets."),
]
for i, (amt, title, desc) in enumerate(colonize_tiers):
    achievements.append((f"colonized_tier_{i}", title, desc, "🪐", 15, amt, 0.0, ""))

# 8. Minerals Collected (15)
# trigger MINERAL_COLLECTED = 11
min_tiers = [
    (10_000, "Miner", "Collect 10,000 minerals."),
    (50_000, "Excavator", "Collect 50,000 minerals."),
    (250_000, "Strip Miner", "Collect 250,000 minerals."),
    (1_000_000, "Planetary Crack", "Collect 1,000,000 minerals."),
    (5_000_000, "Mantle Breaker", "Collect 5 Million minerals."),
    (25_000_000, "Core Tap", "Collect 25 Million minerals."),
    (100_000_000, "Asteroid Wrangler", "Collect 100 Million minerals."),
    (500_000_000, "Stellar Forge", "Collect 500 Million minerals."),
    (2_500_000_000, "Matter Converter", "Collect 2.5 Billion minerals."),
    (10_000_000_000, "Planetary Dismantler", "Collect 10 Billion minerals."),
    (50_000_000_000, "System Sweeper", "Collect 50 Billion minerals."),
    (250_000_000_000, "Nebula Harvester", "Collect 250 Billion minerals."),
    (1_000_000_000_000, "Trillion-Ton Haul", "Collect 1 Trillion minerals."),
    (1_000_000_000_000_000, "Galactic Devourer", "Collect 1 Quadrillion minerals."),
    (1_000_000_000_000_000_000, "Entropy Engine", "Collect 1 Quintillion minerals."),
]
for i, (amt, title, desc) in enumerate(min_tiers):
    achievements.append((f"mineral_tier_{i}", title, desc, "🪨", 11, 0, amt, ""))

# 9. Technology Unlocks (26)
# trigger SKILL_PURCHASED = 12
skills = [
    ("unlock_space_station", "Zero-G Lab", "Unlock Orbital Facilities.", "🛰️"),
    ("unlock_orbital_shipyard", "Shipwright", "Unlock Orbital Shipyard.", "🛠️"),
    ("unlock_orbital_mirrors", "Let There Be Light", "Unlock Orbital Mirrors.", "☀️"),
    ("unlock_moon", "To The Moon", "Unlock Moon Outpost.", "🌕"),
    ("unlock_lunar_observatory", "Eye on the Cosmos", "Unlock Lunar Observatory.", "🔭"),
    ("unlock_interstellar", "Warp Drive", "Unlock Interstellar Travel.", "🌠"),
    ("unlock_market_square", "First Market", "Unlock Market Square.", "⚖️"),
    ("unlock_trading_post", "Trade Routes", "Unlock Trading Post.", "🐪"),
    ("unlock_commercial_hub", "Commercialization", "Unlock Commercial Hub.", "🛍️"),
    ("unlock_commodities_exchange", "High Finance", "Unlock Commodities Exchange.", "📈"),
    ("unlock_financial_district", "Wall Street", "Unlock Financial District.", "🏦"),
    ("unlock_interstellar_syndicate", "The Syndicate", "Unlock Interstellar Syndicate.", "🕴️"),
    ("unlock_orbital_offworld_market", "Market Maker", "Unlock Offworld Trading Hub.", "🪐"),
    ("unlock_apartments", "High Density", "Unlock Apartments.", "🏢"),
    ("unlock_luxury_complex", "Luxury Living", "Unlock Luxury Complex.", "🏨"),
    ("unlock_arcologies", "Master of Housing", "Unlock Arcologies.", "🌆"),
    ("unlock_lab", "Basic Research", "Unlock Research Lab.", "🧫"),
    ("unlock_research_academy", "Higher Education", "Unlock Research Academy.", "🏫"),
    ("unlock_research_nexus", "Hive Mind", "Unlock Research Nexus.", "🧠"),
    ("unlock_deep_core_mining", "Deep Core Miner", "Unlock Deep Core Mining.", "⛏️"),
    ("unlock_asteroid_mining", "Belt Belt", "Unlock Asteroid Mining.", "☄️"),
    ("unlock_mohole_mine", "Journey to the Center", "Unlock Mohole Mine.", "🕳️"),
    ("unlock_fusion_reactor", "Power of the Sun", "Unlock Fusion Reactor.", "⚛️"),
    ("unlock_antimatter_reactor", "Annihilation", "Unlock Antimatter Reactor.", "💥"),
    ("unlock_dyson_sphere", "Stellar Engineering", "Unlock Dyson Sphere.", "🌞"),
    ("unlock_black_hole_extractor", "Event Horizon", "Unlock Black Hole Extractor.", "🕳️"),
]
for skill_id, title, desc, icon in skills:
    achievements.append((f"skill_{skill_id}", title, desc, icon, 12, 0, 0.0, skill_id))


# Write all
for a in achievements:
    write_achievement(
        a_id=a[0], 
        title=a[1], 
        desc=a[2], 
        icon=a[3], 
        trigger=a[4],
        int_val=a[5] if len(a) > 5 else 0, 
        float_val=a[6] if len(a) > 6 else 0.0, 
        str_val=a[7] if len(a) > 7 else ""
    )

print(f"Generated {len(achievements)} achievements.")
