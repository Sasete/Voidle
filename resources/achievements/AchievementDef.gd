## AchievementDef — defines a single achievement.
## Create .tres files from this resource for each achievement.
## Future: map steam_id to the matching Steam Achievement API key.
class_name AchievementDef
extends Resource

enum Trigger {
	FIRST_DISTRICT,        # First district placed on any planet
	FIRST_BUILDING,        # First building constructed
	FIRST_ORBITAL,         # First orbital station launched
	FIRST_ASTEROID_SCAN,   # First asteroid belt scanned
	FIRST_MOON_COLONY,     # First moon colonized
	FIRST_SOLAR_TRAVEL,    # Traveled to a non-home solar system
	FIRST_GALAXY_VIEW,     # Galaxy view unlocked and visited
	FIRST_SURVEY,          # First system surveyed
	PLANET_LEVEL,          # Planet reaches a specific level (use int_value)
	CREDITS_TOTAL,         # Cumulative credits ever earned (use float_value)
	SCIENCE_TOTAL,         # Cumulative science ever earned (use float_value)
	MINERAL_COLLECTED,     # Total of any mineral collected (use float_value)
	SKILL_PURCHASED,       # Specific skill unlocked (use string_value = skill id)
	BUILDING_COUNT,        # Total buildings constructed (use int_value)
	DISTRICT_COUNT,        # Total districts placed (use int_value)
	COLONIZED_PLANETS_COUNT, # Total planets colonized (use int_value)
	TUTORIAL_COMPLETE,     # Guided tutorial fully completed
}

@export var achievement_id: String = ""
@export var title: String = ""
@export var description: String = ""
@export var icon: String = "★"          # emoji or short text icon
@export var trigger: Trigger = Trigger.FIRST_DISTRICT
@export var int_value: int = 0          # threshold for INT triggers
@export var float_value: float = 0.0   # threshold for FLOAT triggers
@export var string_value: String = ""  # id for STRING triggers
@export var steam_id: String = ""      # future Steam Achievement API key
@export var secret: bool = false       # hidden until unlocked
