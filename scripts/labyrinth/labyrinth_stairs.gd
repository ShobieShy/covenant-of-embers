class_name LabyrinthStairs
extends Area3D
## Labyrinth L2: a stair trigger. DOWN (exit room) takes the party to the next floor, UP
## (start room) back out to the Breach crater. Only a local player counts, and only the
## host's in co-op (the party follows, like InteriorDoor).

signal used(dir: int)

enum { DOWN, UP }

const RADIUS := 1.5

var dir := DOWN


func _ready() -> void:
	var s := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = RADIUS
	s.shape = sp
	s.position.y = 1.0
	add_child(s)
	collision_mask = 2 | 1
	var c := CSGBox3D.new()
	c.size = Vector3(2.5, 0.3, 2.5)
	c.position.y = 0.15
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.6, 0.2) if dir == DOWN else Color(0.6, 0.8, 1.0)
	m.emission_enabled = true
	m.emission = m.albedo_color * 0.5
	c.material = m
	add_child(c)
	var l := Label3D.new()
	l.text = "Stairs down" if dir == DOWN else "Stairs up: the Breach"
	l.position.y = 2.0
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)
	body_entered.connect(_on_body)


func _on_body(b: Node3D) -> void:
	if not (b is Player and b.is_in_group(Player.GROUP)):
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	used.emit(dir)
