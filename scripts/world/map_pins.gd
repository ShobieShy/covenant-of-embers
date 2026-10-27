class_name MapPins
extends RefCounted
## OW7: the player's custom map pins (up to MAX), saved under progress.pins as [x, z, label].

const MAX := 32
const NEAR := 12.0  ## clicking within this many metres of a pin removes it

var pins: Array = []


func add(x: float, z: float, label := "") -> bool:
	if pins.size() >= MAX:
		return false
	pins.append([x, z, label])
	return true


## Removes the pin nearest (x, z) within NEAR; true when one went.
func remove_near(x: float, z: float) -> bool:
	var best := -1
	var bd := NEAR
	for i in pins.size():
		var d := Vector2(pins[i][0], pins[i][1]).distance_to(Vector2(x, z))
		if d <= bd:
			best = i
			bd = d
	if best < 0:
		return false
	pins.remove_at(best)
	return true


func to_save() -> Array:
	return pins.duplicate(true)


func from_save(a: Variant) -> void:
	pins = []
	if a is Array:
		for p in a:
			if p is Array and p.size() >= 2 and pins.size() < MAX:
				pins.append([float(p[0]), float(p[1]), String(p[2]) if p.size() > 2 else ""])
