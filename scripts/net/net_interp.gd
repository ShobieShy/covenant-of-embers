class_name NetInterp
extends RefCounted
## 0.3.2 C3: render a pose about 100 ms behind the newest sample, extrapolate a
## little when a packet is late, and snap only when the correction is large.

const DELAY_MS := 100.0
const EXTRAP_MS := 80.0
const SNAP_M := 4.0
const KEEP := 32

var samples: Array[Dictionary] = []
var _offset := 0.0
var _have_offset := false


## `receiver_ms` is the local session clock when this sample arrived.
func push_remote(sender_ms: float, receiver_ms: float, pos: Vector3, yaw: float) -> void:
	if not _have_offset:
		_offset = receiver_ms - sender_ms
		_have_offset = true
	push(sender_ms, pos, yaw)


func sample_sender(receiver_ms: float, current: Vector3) -> Dictionary:
	return sample(receiver_ms - _offset, current)


func push(t_ms: float, pos: Vector3, yaw: float) -> void:
	var row := {"t": t_ms, "p": pos, "y": yaw}
	if not samples.is_empty() and t_ms < float(samples.back()["t"]):
		samples.clear()
	samples.append(row)
	if samples.size() > KEEP:
		samples.pop_front()


## {pos, yaw, snap}. `now_ms` is the receiver clock. `current` is where we are drawn.
func sample(now_ms: float, current: Vector3) -> Dictionary:
	if samples.is_empty():
		return {"pos": current, "yaw": 0.0, "snap": false}
	var want := now_ms - DELAY_MS
	var newest: Dictionary = samples.back()
	var pos := newest["p"] as Vector3
	var yaw := float(newest["y"])
	if samples.size() == 1:
		pos = newest["p"]
	elif want <= float(samples[0]["t"]):
		pos = samples[0]["p"]
		yaw = float(samples[0]["y"])
	elif want >= float(newest["t"]):
		var prev: Dictionary = samples[samples.size() - 2]
		var span := maxf(1.0, float(newest["t"]) - float(prev["t"]))
		var extra := clampf(want - float(newest["t"]), 0.0, EXTRAP_MS)
		var step := (newest["p"] as Vector3) - (prev["p"] as Vector3)
		pos = (newest["p"] as Vector3) + step * (extra / span)
		yaw = lerp_angle(float(prev["y"]), float(newest["y"]), 1.0 + extra / span)
	else:
		var b := 1
		while b < samples.size() and float(samples[b]["t"]) < want:
			b += 1
		var a0: Dictionary = samples[b - 1]
		var b0: Dictionary = samples[b]
		var span := maxf(0.001, float(b0["t"]) - float(a0["t"]))
		var k := clampf((want - float(a0["t"])) / span, 0.0, 1.0)
		pos = (a0["p"] as Vector3).lerp(b0["p"] as Vector3, k)
		yaw = lerp_angle(float(a0["y"]), float(b0["y"]), k)
	var snap := current.distance_to(pos) > SNAP_M
	return {"pos": pos, "yaw": yaw, "snap": snap}


## The first call places; later calls count a step. `big` is a jump over 1 m that was
## not a snap (the buffer should not do that on a steady walk).
static func watch(stats: Dictionary, before: Vector3, after: Vector3, snap: bool) -> void:
	if not bool(stats.get("seen", false)):
		stats["seen"] = true
		return
	stats["steps"] = int(stats.get("steps", 0)) + 1
	if snap:
		stats["snaps"] = int(stats.get("snaps", 0)) + 1
	elif before.distance_to(after) > 1.0:
		stats["big"] = int(stats.get("big", 0)) + 1
