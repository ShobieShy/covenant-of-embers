class_name MapAnchors
extends RefCounted
## Step 155 (W4, TERRAIN_MAPS_PLAN section 10): where a loaded or joining player stands.
## Levels carry named spawn anchors (TOML [[anchor]] -> Anchors/<name>, meta yaw_deg and
## an optional intro `beat`) and waystone markers ([[waystone]] -> Waystones/<point>).
## Saves keep progress.anchor (the anchor or waystone the player was last near) and
## progress.map_version (the level's Terrain map_version when saved; absent = 1).
##  - same map version + a known anchor: spawn there;
##  - the map is newer than the save (a redesign moved things): the anchor for the saved
##    story state (the intro beat anchor), else the zone's waystone, else PlayerStart;
##  - otherwise PlayerStart, exactly like builds before step 155.

const NEAR := 30.0  ## m: progress.anchor = the closest anchor/waystone within this


static func version_of(level: Node) -> int:
	var t := level.get_node_or_null(^"Terrain") if level else null
	return int(t.get(&"map_version")) if t != null and &"map_version" in t else 1


static func markers(level: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if level == null:
		return out
	for holder in [^"Anchors", ^"Waystones"]:
		var h := level.get_node_or_null(holder)
		if h:
			for c in h.get_children():
				if c is Node3D:
					out.append(c)
	return out


static func find(level: Node, id: String) -> Node3D:
	if level == null or id.is_empty():
		return null
	for holder in ["Anchors", "Waystones"]:
		var n := level.get_node_or_null(NodePath("%s/%s" % [holder, id])) as Node3D
		if n:
			return n
	return null


static func waystone(level: Node) -> Node3D:
	var h := level.get_node_or_null(^"Waystones") if level else null
	if h == null or h.get_child_count() == 0:
		return null
	# Step 160: a zone with extra waystones (landfill_camp) spawns at its primary point only.
	var p := h.get_node_or_null(NodePath(String(FastTravel.LEVEL_POINT.get(GameFlow.id_of(level), ""))))
	return p as Node3D


static func beat_anchor(level: Node, beat: String) -> Node3D:
	var h := level.get_node_or_null(^"Anchors") if level and not beat.is_empty() else null
	if h:
		for c in h.get_children():
			if String(c.get_meta(&"beat", "")) == beat:
				return c as Node3D
	return null


## The node to spawn at, or null for PlayerStart. `forced` = an anchor the host named
## (co-op join) or a fast-travel point; it wins when the level has it.
static func spawn_node(level: Node, progress: Dictionary, beat := "", forced := "") -> Node3D:
	var f := find(level, forced)
	if f:
		return f
	if not forced.is_empty() and waystone(level):
		return waystone(level)
	var id := String(progress.get("anchor", ""))
	# A travel save names the anchor but no map_version (it is the target's current map).
	var travelled := progress.has("anchor") and not progress.has("map_version")
	if travelled or int(progress.get("map_version", 1)) >= version_of(level):
		return find(level, id)
	var b := beat_anchor(level, beat)
	if b:
		return b
	return waystone(level)


## The closest anchor/waystone id within NEAR m of `at`, else "".
static func nearest(level: Node, at: Vector3, within := NEAR) -> String:
	var best := ""
	var bd := within
	for m in markers(level):
		var d := m.global_position.distance_to(at)
		if d <= bd:
			bd = d
			best = String(m.name)
	return best


## Co-op: the host's waystone nearest `at` (or the level's first), for joining clients.
static func nearest_waystone(level: Node, at: Vector3) -> String:
	var h := level.get_node_or_null(^"Waystones") if level else null
	if h == null:
		return ""
	var best := ""
	var bd := INF
	for c in h.get_children():
		var d := (c as Node3D).global_position.distance_to(at)
		if d < bd:
			bd = d
			best = String(c.name)
	return best
