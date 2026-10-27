class_name WorldZones
extends Node3D
## OW10d: the outdoor levels' gameplay markers in the seamless world. Each zone is its level
## scene at the level's world_offset with the art stripped (terrain, boxes, props and POIs
## stream in as world cells; sky, sun and navigation come from the world), so EnemySpawns,
## waves, camps, chests, gates, exits, NPCs, waystones and anchors keep their level-authored
## layout. Each zone gets its own EnemySpawner (named "<zone>Enemies"), set up exactly as a
## level's. The Breach's rooms stay an interior (Interiors "breach_rooms").

const ZONES: PackedStringArray = ["town_square", "old_oak", "midden"]
const STRIP: PackedStringArray = [
	"WorldEnvironment", "Sun", "Boxes", "Terrain", "Props", "Pois", "Navigation"
]

var zones := {}  ## level id -> Node3D (the stripped level root)
var spawners := {}  ## level id -> EnemySpawner


## Builds every zone (call once, in the tree). `player` null: markers only, no spawners.
func build(player: Player = null) -> void:
	for id in ZONES:
		var z := zone_of(id)
		if z == null:
			continue
		add_child(z)
		zones[id] = z
		if player:
			var sp := EnemySpawner.new()
			sp.name = id.capitalize().replace(" ", "") + "Enemies"
			add_child(sp)
			sp.setup(z, player)
			spawners[id] = sp


## One stripped zone root at its world offset (not in the tree yet), or null.
static func zone_of(id: String) -> Node3D:
	if not GameFlow.LEVELS.has(id):
		return null
	var z := (load(GameFlow.level_scene(id)) as PackedScene).instantiate() as Node3D
	for s in STRIP:
		var e := z.get_node_or_null(NodePath(s))
		if e:
			z.remove_child(e)
			e.free()
	var wo: Vector2 = z.get_meta(&"world_offset", Vector2.ZERO)
	z.position = Vector3(wo.x, 0.0, wo.y)
	z.name = "Zone_" + id
	return z


## The zone whose world_offset is nearest `p`.
func zone_at(p: Vector3) -> String:
	var best := ""
	var bd := INF
	for id in zones:
		var d := Vector2(p.x, p.z).distance_to(
			Vector2((zones[id] as Node3D).position.x, (zones[id] as Node3D).position.z)
		)
		if d < bd:
			bd = d
			best = id
	return best


## OW11a: the groups main.gd's level systems read, merged from every zone.
const MERGE: PackedStringArray = [
	"Anchors", "Waystones", "Camps", "Chests", "Gates", "EnemySpawns", "WaveSpawns", "Waves", "NPCs"
]

## Group metas that are level-local points.
const POINT_METAS: Array[StringName] = [&"trigger_center"]


## One "Level" for main.gd in the open world: every zone's MERGE groups with their markers
## moved to world positions, `here`'s PlayerStart, and `here`'s level_id, so the spawner,
## NPCs, quests, gates, chests, waystones and arena walls run once over the whole world.
## No art, terrain or navigation (world cells), no Exits (zones join seamlessly; doors are
## Interiors). Name clashes between zones get Godot's readable suffixes.
static func merged(here: String) -> Node3D:
	var lv := Node3D.new()
	lv.name = "Level"
	var boxes := Node3D.new()
	boxes.name = "Boxes"
	lv.add_child(boxes)
	var ids := Array(ZONES)
	if not ids.has(here):
		here = ids[0]
	for id in ids:
		var z := zone_of(id)
		if id == here:
			lv.set_meta(&"level_id", z.get_meta(&"level_id", id))
			var st := z.get_node_or_null("PlayerStart") as Node3D
			if st:
				var xf := z.transform * st.transform
				z.remove_child(st)
				st.owner = null
				lv.add_child(st)
				st.owner = lv
				st.transform = xf
		for g in MERGE:
			var src := z.get_node_or_null(NodePath(g))
			if src == null:
				continue
			var dst := lv.get_node_or_null(NodePath(g))
			if dst == null:
				dst = Node3D.new() if src is Node3D else Node.new()
				dst.name = g
				lv.add_child(dst)
			for k in src.get_meta_list():  # e.g. Waves' trigger (level-local -> world)
				var v: Variant = src.get_meta(k)
				dst.set_meta(k, z.transform * (v as Vector3) if k in POINT_METAS else v)
			var base := (
				z.transform * ((src as Node3D).transform if src is Node3D else Transform3D())
			)
			for c in src.get_children():
				var xf := base * (c as Node3D).transform if c is Node3D else Transform3D()
				src.remove_child(c)
				var owned := _owned_by(c, z)
				for o in owned:
					o.owner = null  # OW11c-2: no owner-inconsistency warning on reparent
				dst.add_child(c, true)
				for o in owned:
					o.owner = lv
				if c is Node3D:
					(c as Node3D).transform = xf
		z.free()
	lv.set_meta(&"world_offset", Vector2.ZERO)
	lv.set_meta(&"open_world", true)
	return lv


## OW11c-2: `n` and its descendants owned by `z`, to re-own to the merged level.
static func _owned_by(n: Node, z: Node) -> Array[Node]:
	var out: Array[Node] = []
	if n.owner == z:
		out.append(n)
	for c in n.get_children():
		out.append_array(_owned_by(c, z))
	return out
