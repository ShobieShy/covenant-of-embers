extends Node
## The Landfill's ground and cliffs are authored meshes. Terrain3D still
## collides and feeds the nav bake; its own draw would fight those meshes.


func _ready() -> void:
	var zone := get_parent().get_node_or_null("Terrain")
	if zone == null:
		return
	var drawn := zone.get_node_or_null("Terrain3D")
	if drawn:
		drawn.visible = false
	var grass := zone.get_node_or_null("Foliage")
	if grass:
		grass.visible = false
