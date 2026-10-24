class_name QuestPickup
extends Node3D
## A quest item on the ground (BUILD_PLAN step 57: Joe's Trash from The Filth). A glowing
## box that any player walking within RADIUS collects: it goes into Player.quest_items,
## EventBus.quest_item_collected fires (the quest log counts it as "collect") and the
## pickup frees itself. Never refused (quest items take no backpack slot).

const GROUP := &"quest_pickups"
const RADIUS := 1.5

var item_id := ""
var display_name := ""
var collected_by: Node
var auto_tick := true


static func make(id: String, nm: String) -> QuestPickup:
	var q := QuestPickup.new()
	q.item_id = id
	q.display_name = nm
	q.name = "Quest_%s" % id
	return q


func _ready() -> void:
	add_to_group(GROUP)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.4, 0.4)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.55, 0.9)
	m.emission_enabled = true
	m.emission = Color(0.7, 0.4, 1.0)
	mi.material_override = m
	mi.position.y = 0.3
	add_child(mi)


func _physics_process(_dt: float) -> void:
	if auto_tick:
		tick()


func tick() -> void:
	if collected_by != null or not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group(Player.GROUP):
		var p := n as Player
		if p == null or not p.alive():
			continue
		var d := p.global_position - global_position
		if Vector2(d.x, d.z).length() <= RADIUS and absf(d.y) < 2.0:
			collect(p)
			return


func collect(p: Player) -> void:
	collected_by = p
	if not p.quest_items.has(item_id):
		p.quest_items.append(item_id)
	GameEvents.bus().quest_item_collected.emit(p, item_id)
	queue_free()
