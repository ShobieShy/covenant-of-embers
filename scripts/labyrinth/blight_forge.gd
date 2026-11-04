class_name BlightForge
extends Node3D
## The Drowned Forge door. It is not a LevelGate and it does not travel. After the
## Matriarch dies it says the way down has opened and cannot be taken yet.

signal spoke(line: String)

var opened := false
var calls_travel := false
var player: Player
var last_line := ""


func _ready() -> void:
	Interaction.register(self, 1.6, 0.6)
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.2, 3.2, 0.4)
	body.mesh = mesh
	body.position.y = 1.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.28, 0.32)
	body.material_override = mat
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 3.2, 0.4)
	shape.shape = box
	shape.position.y = 1.6
	var solid := StaticBody3D.new()
	solid.add_child(shape)
	add_child(solid)


func line() -> String:
	if opened:
		return "The way down has opened and cannot be taken yet."
	return "The way down is still shut."


func interact_prompt() -> String:
	return "[F] " + line()


func interact() -> void:
	last_line = line()
	spoke.emit(last_line)
	# No GameFlow.travel and no level id. calls_travel stays false.


func _unhandled_input(event: InputEvent) -> void:
	if (
		player
		and not player.ui_open
		and event.is_action_pressed(&"interact")
		and Interaction.is_target(player, self)
	):
		interact()
		get_viewport().set_input_as_handled()
