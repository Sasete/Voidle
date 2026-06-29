## Defines a ship type — display name and the commands available on right-click.
class_name ShipTypeDef
extends Resource

@export var type_id:      String               = ""
@export var display_name: String               = ""
@export var commands:     Array[ShipCommandDef] = []
