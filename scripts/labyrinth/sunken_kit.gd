class_name SunkenKit
extends RefCounted
## Act IV tileset. Kenney's CC0 fantasy-town modules, retinted by SunkenTheme.
## Pieces are 1 m modules. Callers pass the scale that fits the painted bay.

const DIR := "res://assets/kenney/fantasy-town-kit/"
const TILES := {
	"arch": DIR + "wall-doorway-round.glb",
	"window": DIR + "wall-window-round.glb",
	"wall": DIR + "wall.glb",
	"broken": DIR + "wall-broken.glb",
	"pillar": DIR + "pillar-stone.glb",
	"rock": DIR + "rock-large.glb",
	"rock_wide": DIR + "rock-wide.glb",
	"stair": DIR + "stairs-stone.glb",
	"bench": DIR + "stall-bench.glb",
	"lantern": DIR + "lantern.glb",
	"cap": DIR + "roof-high-point.glb",
	"block": DIR + "wall-block.glb",
}

static var _mesh := {}
static var _aabb := {}


static func mesh(id: String) -> Mesh:
	if _mesh.has(id):
		return _mesh[id]
	var path := String(TILES.get(id, ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate()
	var found: Mesh = null
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		found = (node as MeshInstance3D).mesh
	else:
		var kids := node.find_children("*", "MeshInstance3D", true, false)
		if not kids.is_empty():
			found = (kids[0] as MeshInstance3D).mesh
	node.free()
	_mesh[id] = found
	_aabb[id] = found.get_aabb() if found else AABB()
	return found


static func place(id: String, at: Vector3, yaw: float, scale: Vector3) -> Transform3D:
	mesh(id)
	var ab: AABB = _aabb.get(id, AABB())
	var shift := Vector3(ab.get_center().x, ab.position.y, ab.get_center().z)
	var basis := Basis(Vector3.UP, yaw).scaled(scale)
	return Transform3D(basis, at - basis * shift)


static func scatter(parent: Node3D, id: String, xforms: Array, mat: Material, nm: String) -> void:
	if xforms.is_empty():
		return
	var m := mesh(id)
	if m == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = nm
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(inst)
