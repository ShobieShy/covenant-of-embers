class_name EnemySleep
extends Node
## OW4 (OPEN_WORLD_PLAN section 3): enemies farther than SLEEP_M from every viewer (local
## players, co-op avatars, stream_viewers) stop processing (no AI, physics or status
## ticks) and wake again inside WAKE_M; the 16 m gap stops thrash at the line. Only the
## open world adds this, so the per-level game is unchanged. Dead enemies are left alone.

const SLEEP_M := 96.0
const WAKE_M := 80.0
const TICK_S := 0.5

var asleep := {}  ## Enemy -> true
var _t := 0.0


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= TICK_S:
		_t = 0.0
		update_now()


func update_now(at: Array[Vector3] = []) -> void:
	var pts := at
	if pts.is_empty():
		for g in [Player.GROUP, RemotePlayer.GROUP, &"stream_viewers"]:
			for n in get_tree().get_nodes_in_group(g):
				if n is Node3D and (n as Node3D).is_inside_tree():
					pts.append((n as Node3D).global_position)
	if pts.is_empty():
		return
	for k in asleep.keys():
		if not is_instance_valid(k):
			asleep.erase(k)
	for n in get_tree().get_nodes_in_group(Enemy.GROUP):
		var e := n as Enemy
		if e == null or e.dead:
			continue
		var d := INF
		for v in pts:
			d = minf(d, Vector2(v.x - e.global_position.x, v.z - e.global_position.z).length())
		if not asleep.has(e) and d > SLEEP_M:
			e.process_mode = Node.PROCESS_MODE_DISABLED
			asleep[e] = true
		elif asleep.has(e) and d < WAKE_M:
			e.process_mode = Node.PROCESS_MODE_INHERIT
			asleep.erase(e)
