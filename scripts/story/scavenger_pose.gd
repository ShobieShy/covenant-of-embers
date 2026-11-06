class_name ScavengerPose
extends RefCounted
## The Landfill scavenger. He used to spawn inside the west crates, rolled 70 degrees,
## which reads as a T-pose stuck in the boxes. He lies on open ground beside the Light
## shrine (the Death clip held on its last frame) and stands when Light reaches him.

## East of the shrine, same depth: clear of the west crates and of the soft walls.
const BESIDE := Vector3(2.2, 0.0, 0.0)


static func lay(n: Npc) -> void:
	if n == null:
		return
	var shrine := n.global_position
	n.global_position = shrine + BESIDE
	n.rotation = Vector3.ZERO
	var look := shrine
	look.y = n.global_position.y
	if look.distance_squared_to(n.global_position) > 0.04:
		n.look_at(look, Vector3.UP)
	var body := n.get_node_or_null("CharacterModel") as CharacterModel
	if body:
		body.hold("Death")
	_label(n, 0.7)


static func stand(n: Npc) -> void:
	if n == null:
		return
	n.rotation.z = 0.0
	var body := n.get_node_or_null("CharacterModel") as CharacterModel
	if body:
		body.release()
	_label(n, 2.2)


static func _label(n: Npc, y: float) -> void:
	for c in n.get_children():
		if c is Label3D:
			(c as Label3D).position.y = y
