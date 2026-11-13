class_name KillPlane
extends RefCounted
## 0.9.3: under every level, a floor that skips the downed window.
## You come back at the last waystone (or the level spawn), and you keep your gold.

const DROP := 8.0


static func line_for(lowest_top: float) -> float:
	return lowest_top - DROP


static func below(feet_y: float, line_y: float) -> bool:
	return feet_y < line_y


## Lowest wide floor in `root` (ground slabs, not walls). NAN if none yet.
static func lowest_top(root: Node) -> float:
	var best := INF
	if root == null:
		return NAN
	for n in root.find_children("*", "CollisionShape3D", true, false):
		var shape := (n as CollisionShape3D).shape
		if shape is BoxShape3D:
			var box := shape as BoxShape3D
			if box.size.x < 4.0 or box.size.z < 4.0:
				continue
			var top := (n as Node3D).global_position.y + box.size.y * 0.5
			if top < best:
				best = top
	return best if best < 1.0e8 else NAN


## True when this tick should stop because the player was sent back.
static func tick(p: Player) -> bool:
	if p == null or not p.alive() or p.downed or Cinematic.playing != null:
		return false
	_refresh(p)
	if not p.kill_ready or not below(p.global_position.y, p.kill_line_y):
		p.void_wait = 0
		return false
	if Coop.is_client():
		if p.void_wait == 0:
			var world := p.get_parent().get_node_or_null("CoopWorld") if p.get_parent() else null
			if world and world.has_method(&"send_void"):
				world.call(&"send_void", p.global_position.y, p.spawn_feet, p.spawn_yaw)
		p.void_wait += 1
		if p.void_wait < 90:
			return false
	_recover(p)
	return true


static func recover_at(p: Player, at: Vector3, yaw: float) -> void:
	p.void_wait = 0
	p.spawn_feet = at
	p.spawn_yaw = yaw
	_recover(p)


static func _recover(p: Player) -> void:
	p.void_falls += 1
	p.respawn()


static func _refresh(p: Player) -> void:
	p.kill_scan -= 1
	if p.kill_scan > 0 and p.kill_ready:
		return
	p.kill_scan = 120
	var parent := p.get_parent()
	var level := parent.get_node_or_null("Level") if parent else null
	var top := lowest_top(level)
	if is_nan(top):
		p.kill_ready = false
		return
	p.kill_ready = true
	p.kill_line_y = line_for(top)


## Host: a claimed spawn is kept only if it sits on a real marker. Otherwise the level start.
static func host_dest(level: Node, claimed: Vector3, line_y: float) -> Vector3:
	var start := level.get_node_or_null("PlayerStart") as Node3D if level else null
	var origin := start.global_position if start else Vector3.ZERO
	if claimed.y < line_y:
		return origin
	var best := origin
	var best_d := claimed.distance_to(origin)
	if level:
		for n in level.find_children("*", "Node3D", true, false):
			if n.name != "PlayerStart" and not (n is Waystone) and not (n is RestShrine):
				continue
			var d := claimed.distance_to((n as Node3D).global_position)
			if d < best_d:
				best = (n as Node3D).global_position
				best_d = d
	if best_d <= 6.0:
		return claimed
	return origin
