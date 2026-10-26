class_name FlagGate
extends StaticBody3D
## Step 156 (W5, TERRAIN_MAPS_PLAN section 7): an intro soft-block. TOML [[gate]] -> a
## Gates/<name> wall (center, size) that stays up until story flag `requires_flag` is set
## (usually "tutorial_done"), with a short reason shown on it. Not navmesh source (Boxes
## only), so enemies path through; it only keeps the player on the intro corridor.

const GROUP := &"flag_gates"

@export var requires_flag := "tutorial_done"
@export var reason := "Bob said to stick to the path."
@export var size := Vector3(4, 3, 0.5)

var flags: StoryFlags
var label: Label3D


func _ready() -> void:
	add_to_group(GROUP)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.55, 0.2, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = mat
	mi.mesh = bm
	add_child(mi)
	label = Label3D.new()
	label.text = reason
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = size.y / 2.0 + 0.4
	add_child(label)


func bind(f: StoryFlags) -> void:
	flags = f
	if not f.changed.is_connected(_on_flag):
		f.changed.connect(_on_flag)
	refresh()


func is_open() -> bool:
	return flags != null and (requires_flag.is_empty() or flags.has(requires_flag))


func refresh() -> void:
	var open := is_open()
	visible = not open
	collision_layer = 0 if open else 1
	collision_mask = 0


func _on_flag(_flag: String, _v: int) -> void:
	refresh()
