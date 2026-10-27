class_name CoopLeash
extends Node
## OW9: keeps co-op partners within reach of the host in the open world. A joiner gets a
## soft warning past WARN metres from the host and is pulled back beside the host past PULL.
## The host streams cells around every partner (WorldStreamer.viewers), capped at MAX_PLAYERS.

enum State { OK, WARN, PULL }

const WARN := 300.0
const PULL := 400.0
const MAX_PLAYERS := 4
const LAND := 5.0  ## metres from the host, on the partner's side

var player: Node3D
var host_pos := Callable()  ## -> Variant: the host's world position, or null if unknown
var height_fn := Callable()  ## (x, z) -> ground y
var hint := Callable()  ## (text)
var pulls := 0
var _warned := false


static func state_for(d: float) -> State:
	if d > PULL:
		return State.PULL
	if d > WARN:
		return State.WARN
	return State.OK


## One check; returns the state. Distances are flat (x/z).
func check() -> State:
	if player == null or not host_pos.is_valid():
		return State.OK
	var h: Variant = host_pos.call()
	if not (h is Vector3):
		return State.OK
	var hp: Vector3 = h
	var off := Vector2(player.global_position.x - hp.x, player.global_position.z - hp.z)
	var s := state_for(off.length())
	if s == State.WARN and not _warned:
		_warned = true
		_say("You're straying far from the host. Turn back or be pulled to them.")
	elif s == State.OK:
		_warned = false
	elif s == State.PULL:
		var dir := off.normalized() if off.length() > 0.01 else Vector2(0, 1)
		var at := Vector3(hp.x + dir.x * LAND, hp.y, hp.z + dir.y * LAND)
		if height_fn.is_valid():
			at.y = float(height_fn.call(at.x, at.z))
		player.global_position = at
		if player is CharacterBody3D:
			(player as CharacterBody3D).velocity = Vector3.ZERO
		pulls += 1
		_warned = false
		_say("Pulled back to the host.")
	return s


func _say(t: String) -> void:
	if hint.is_valid():
		hint.call(t)
	print("[leash] " + t)
