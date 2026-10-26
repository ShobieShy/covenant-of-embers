class_name CampLeash
extends RefCounted
## Step 154 (W3, TERRAIN_MAPS_PLAN section 9): camp enemies are leashed to their camp.
## One pulled more than LEASH m (flat) from its home spot (Enemy meta "camp_home") snaps
## back there at full health with statuses cleared, so a kite across the zone can't drag
## a pack into a town or onto a tile with no navmesh. Bosses are never leashed.

const LEASH := 40.0
const ACTIVATE := 80.0  ## step 155: a camp wakes while any player is this close (flat m)
const HOME := &"camp_home"


static func home(e: Enemy, at: Vector3) -> void:
	e.set_meta(HOME, at)


## Step 155: per-player proximity; `players` = Node3Ds (local Player, RemotePlayers).
static func camp_active(center: Vector3, players: Array, radius := ACTIVATE) -> bool:
	for p in players:
		var n := p as Node3D
		if (
			n
			and is_instance_valid(n)
			and Vector2(n.global_position.x - center.x, n.global_position.z - center.z).length() <= radius
		):
			return true
	return false


## Returns how many enemies were sent home.
static func enforce(enemies: Array, leash := LEASH) -> int:
	var n := 0
	for x in enemies:
		var e := x as Enemy
		if e == null or not is_instance_valid(e) or e.dead or e.is_boss() or not e.has_meta(HOME):
			continue
		var h: Vector3 = e.get_meta(HOME)
		if Vector2(e.global_position.x - h.x, e.global_position.z - h.z).length() > leash:
			e.reset(Transform3D(e.transform.basis, h))
			n += 1
	return n
