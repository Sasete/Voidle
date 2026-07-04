extends SceneTree

func _init():
    var tex = preload("res://scripts/ui/MineralIcon.gd").make(1, Color.RED)
    if tex == null:
        print("TEXTURE IS NULL")
    else:
        print("TEXTURE IS VALID: ", tex.get_width(), "x", tex.get_height())
    quit()
