@tool
extends EditorScenePostImport
## Kenney Nature Kit GLBs ship metallicFactor = 1 (they render near-black in Godot without
## reflections); make every imported material fully rough dielectric.


func _post_import(scene: Node) -> Object:
	_fix(scene)
	return scene


func _fix(n: Node) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m != null:
				m.metallic = 0.0
				m.roughness = 1.0
	for c in n.get_children():
		_fix(c)
