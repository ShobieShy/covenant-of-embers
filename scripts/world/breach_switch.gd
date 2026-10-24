class_name BreachSwitch
extends Node3D
## A lever (BUILD_PLAN step 47): `interact` within REACH (or press()) pulls it once, when
## `armed` (the Breach arms the levers once every room encounter is cleared).

signal pressed(sw: BreachSwitch)

const REACH := 2.0
const GROUP := &"breach_switches"

var opens := ""
var armed := false
var is_pressed := false
var player: Player
var _handle: MeshInstance3D
var _gem: StandardMaterial3D


func _ready() -> void:
	add_to_group(GROUP)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.5, 1.0, 0.5)
	post.mesh = pm
	post.position.y = 0.5
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.35, 0.33, 0.36)
	post.material_override = stone
	add_child(post)
	_handle = MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.12, 0.7, 0.12)
	_handle.mesh = hm
	_handle.position = Vector3(0, 1.3, 0)
	_handle.rotation_degrees.x = -35.0
	_gem = StandardMaterial3D.new()
	_gem.emission_enabled = true
	_handle.material_override = _gem
	add_child(_handle)
	_refresh()


func arm() -> void:
	armed = true
	_refresh()


func in_reach(p: Player) -> bool:
	return p != null and is_inside_tree() and p.global_position.distance_to(global_position) <= REACH


func press() -> bool:
	if not armed or is_pressed:
		return false
	is_pressed = true
	_refresh()
	pressed.emit(self)
	return true


func _refresh() -> void:
	if _gem == null:
		return
	var c := Color(0.4, 0.4, 0.45)
	if is_pressed:
		c = Color(0.3, 1.0, 0.4)
	elif armed:
		c = Color(1.0, 0.6, 0.15)
	_gem.albedo_color = c
	_gem.emission = c
	_handle.rotation_degrees.x = 35.0 if is_pressed else -35.0


func _unhandled_input(event: InputEvent) -> void:
	if player == null or player.ui_open or is_pressed:
		return
	if event.is_action_pressed(&"interact") and in_reach(player) and press():
		get_viewport().set_input_as_handled()
