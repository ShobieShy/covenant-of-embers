class_name RouteGraph
extends RefCounted
## Step 154 (W3): the playtest bot's long-route graph for open zones. Nodes are the level's
## landmarks (PlayerStart, POI centres, camps, waystones, exits, anchors); each joins its
## NEIGHBOURS nearest within MAX_LINK m, and A* (AStar3D) gives a chain of landmarks to
## walk between, each leg short enough for a navmesh path inside the loaded tiles.

const NEIGHBOURS := 3
const MAX_LINK := 160.0
const LONG := 64.0  ## the bot uses the graph for targets farther than this

var astar := AStar3D.new()
var points: Array[Vector3] = []


static func from_level(lvl: Node) -> RouteGraph:
	var g := RouteGraph.new()
	var start := lvl.get_node_or_null(^"PlayerStart") as Node3D
	if start:
		g.points.append(start.position)
	for holder in [^"Pois", ^"Camps"]:
		var h := lvl.get_node_or_null(holder)
		if h:
			for p in h.get_children():
				g.points.append(p.get_meta(&"center", Vector3.ZERO))
	for holder in [^"Waystones", ^"Exits", ^"Anchors"]:
		var h := lvl.get_node_or_null(holder)
		if h:
			for p in h.get_children():
				if p is Node3D:
					g.points.append((p as Node3D).position)
	g.build()
	return g


func build() -> void:
	astar.clear()
	for i in points.size():
		astar.add_point(i, points[i])
	for i in points.size():
		var near := range(points.size())
		near.erase(i)
		near.sort_custom(
			func(a: int, b: int) -> bool: return points[a].distance_to(points[i]) < points[b].distance_to(points[i])
		)
		for j in near.slice(0, NEIGHBOURS):
			if points[j].distance_to(points[i]) <= MAX_LINK and not astar.are_points_connected(i, j):
				astar.connect_points(i, j)


## The next landmark to walk to from `from` towards `to` (`to` itself when it is close,
## or when the graph can't help).
func next_waypoint(from: Vector3, to: Vector3) -> Vector3:
	if points.size() < 2 or from.distance_to(to) <= LONG:
		return to
	var a := astar.get_closest_point(from)
	var b := astar.get_closest_point(to)
	var chain := astar.get_id_path(a, b)
	for id in chain:
		var p := astar.get_point_position(id)
		if Vector2(p.x - from.x, p.z - from.z).length() > 4.0:
			return p if p.distance_to(to) < from.distance_to(to) else to
	return to
