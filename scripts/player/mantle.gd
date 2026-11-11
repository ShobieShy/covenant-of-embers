class_name Mantle
extends RefCounted
## A cosmetic cloak. No stats.


static func wear(p: Player) -> void:
	if p == null or p.get_node_or_null("Mantle") != null:
		return
	var m := MeshInstance3D.new()
	m.name = "Mantle"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.7, 0.9)
	m.mesh = mesh
	m.position = Vector3(0, 1.1, 0.15)
	p.add_child(m)
