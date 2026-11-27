extends Node3D
## Storm Warden arena. The shelves that fail live on SpireFloor. This ring is the
## fight's floor: crystals around the low shelf, and a glyph where the Warden stands.


func _ready() -> void:
	var host := get_parent() as SpireFloor
	if host == null:
		return
	SpireKit.dress_arena(self, host)
