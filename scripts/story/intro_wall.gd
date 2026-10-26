class_name IntroWall
extends RefCounted
## The Landfill intro corridor walls (moved out of IntroDirector, step 156).


static func make(main: Node, n: String, z: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = n
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(29.0, 4.0, 0.6)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(29.0, 1.2, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.28, 0.2)
	bm.material = mat
	mesh.mesh = bm
	mesh.position.y = -1.4
	body.add_child(mesh)
	main.add_child(body)
	body.global_position = Vector3(0.0, 2.0, z)
	return body
