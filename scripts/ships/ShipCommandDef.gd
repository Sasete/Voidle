## Defines a single radial-menu command — visual data + filter rules.
## The actual implementation (Callable) is registered separately in ShipCommandRegistry.
class_name ShipCommandDef
extends Resource

enum Context {
	SHIP,    ## appears when right-clicking a ship
	PLANET,  ## appears when right-clicking empty planet space
}

@export var command_id:  String  = ""
@export var icon:        String  = ""
@export var label:       String  = ""
@export var color:       Color   = Color.WHITE
@export var context:     Context = Context.SHIP
## Empty = appears for ALL ship types. ["shuttle"] = only shuttle, etc.
@export var ship_types:  Array[String] = []
