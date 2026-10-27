class_name InteriorDoor
extends Area3D
## OW5a: a door trigger into an instanced interior (Interiors). A local player walking
## into it enters; only the host's player counts in co-op (the party follows).

const RADIUS := 1.5

var interior := ""
var interiors: Interiors


func _ready() -> void:
	var s := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = RADIUS
	s.shape = sp
	add_child(s)
	collision_mask = 2 | 1
	body_entered.connect(_on_body)


func _on_body(b: Node3D) -> void:
	if b is Player and b.is_in_group(Player.GROUP) and interiors and interiors.current == "":
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			return
		interiors.enter(interior)
