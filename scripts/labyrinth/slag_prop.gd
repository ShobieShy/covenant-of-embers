class_name SlagProp
extends Area3D
## A crucible interact: the main lift or the Sunken Ruins door. Neither calls travel.

signal spoke(line: String)

var role := "lift"
var host: Node
var calls_travel := false


func _ready() -> void:
	monitoring = true
	collision_layer = 0
	collision_mask = 1 << (Player.CHARACTER_LAYER - 1)


func line() -> String:
	if host == null:
		return ""
	return String(host.call(&"prop_line", role))


func interact() -> void:
	var text := line()
	spoke.emit(text)
	if role == "lift" and host != null:
		host.call(&"use_lift")
