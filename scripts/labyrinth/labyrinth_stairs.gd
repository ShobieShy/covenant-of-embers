class_name LabyrinthStairs
extends Area3D
## Labyrinth L2: a stair trigger. DOWN (exit room) takes the party to the next floor, UP
## (start room) back out to the Breach crater. Only a local player counts, and only the
## host's in co-op (the party follows, like InteriorDoor).
## 0.3.1 P2: walking on no longer takes them. A local player on the stairs sees "E: go down"
## and holds Interact for HOLD_S, with a fill bar in the prompt. A finished hold fires once
## and needs a release before it can fire again. The co-op vote stays in LabyrinthSync.gate().
## The pad glows with a slow pulse (not headless or under reduced motion).

signal used(dir: int)

enum { DOWN, UP }

const RADIUS := 1.5
const HOLD_S := 0.5

var dir := DOWN
var hold := 0.0  ## s Interact held by a player on the stairs
var fires := 0
var prompt: Label3D
var _mat: StandardMaterial3D
var _on: Array[Player] = []
var _fired := false
var _t := 0.0


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
	_mat = m
	add_child(c)
	prompt = Label3D.new()
	prompt.name = "Prompt"
	prompt.position.y = 2.0
	prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(prompt)
	_refresh()
	body_entered.connect(_on_body)
	body_exited.connect(_off_body)


func title() -> String:
	return "Stairs down" if dir == DOWN else "Stairs up: the Breach"


func action_text() -> String:
	return "E: go down" if dir == DOWN else "E: go up to the Breach"


func _refresh() -> void:
	if prompt == null:
		return
	if _on.is_empty():
		prompt.text = title()
		return
	var n := 10
	var f := clampi(int(hold / HOLD_S * n), 0, n)
	prompt.text = action_text() + ("\n" + "|".repeat(f) + ".".repeat(n - f) if hold > 0.0 else "")


func _on_body(b: Node3D) -> void:
	if b is Player and b.is_in_group(Player.GROUP) and not _on.has(b):
		_on.append(b)
		_refresh()


func _off_body(b: Node3D) -> void:
	if not b is Player:
		return
	_on.erase(b)
	if _on.is_empty():
		hold = 0.0
		_fired = false
	_refresh()


func _physics_process(dt: float) -> void:
	tick(dt)


## One step of the hold: any local player on the stairs holding Interact fills it.
func tick(dt: float) -> void:
	_glow(dt)
	var held := false
	for p in _on:
		if is_instance_valid(p) and p.interact_held:
			held = true
	if not held:
		if hold > 0.0 or _fired:
			hold = 0.0
			_fired = false
			_refresh()
		return
	if _fired:
		return
	hold += dt
	if hold + 1e-6 >= HOLD_S:
		_fired = true
		hold = 0.0
		_refresh()
		GameEvents.bus().sfx.emit("stairs", global_position if is_inside_tree() else Vector3.INF)  # P7
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			return  # a joiner's stairs are the host's call
		fires += 1
		used.emit(dir)
	else:
		_refresh()


func _glow(dt: float) -> void:
	if _mat == null or UiAnim.instant():
		return
	_t += dt
	_mat.emission_energy_multiplier = 1.0 + 0.6 * (0.5 + 0.5 * sin(_t * 3.0))
