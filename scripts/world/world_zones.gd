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
