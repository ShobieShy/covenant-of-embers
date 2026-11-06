class_name MossBed
extends RefCounted
## The Old Oak rest point. "Moss bed" has no character model, so an Npc would stand in
## as a blue cylinder. This puts the interact point on the front lip of a moss bed and
## leaves the body off; the moss itself is the flat bed_moss dressing on those platforms.


static func place(main: Node, player: Player, on_rest: Callable) -> Npc:
	var bed := Npc.new("Moss bed")
	bed.name = "MossBed"
	bed.plain = true
	bed.player = player
	main.add_child(bed)
	bed.global_position = _spot(main)
	for c in bed.get_children():
		if c is Label3D:
			(c as Label3D).position.y = 0.55
	bed.talked.connect(func(_s: String) -> void: on_rest.call())
	return bed


## On the floor, just in front of the middle bed. The top is 0.4 m and the nav climb is
## 0.25 m, so the rest point stays on the ground where the player (and the bot) can stand.
static func _spot(main: Node) -> Vector3:
	var level := main.get_node_or_null("Level")
	var host := level.get_node_or_null("Boxes/moss_bed_2") if level else null
	if host == null and level:
		host = level.find_child("moss_bed_1", true, false)
	var body := host as StaticBody3D
	var shape := body.get_node_or_null("Shape") as CollisionShape3D if body else null
	var box := shape.shape as BoxShape3D if shape else null
	if box == null:
		return Vector3(-2.5, 0.0, -3.15)
	return body.to_global(Vector3(0.0, -box.size.y * 0.5, box.size.z * 0.5 + 0.45))
