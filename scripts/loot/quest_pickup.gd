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
	# Step 123: a real prop (Joe's Trash = Quaternius trash bag) plus a soft quest glow.
	add_child(
		LootMeshes.prop_for(
			"trash" if item_id.contains("trash") or item_id.contains("discard") else "", Color(0.7, 0.4, 1.0)
		)
	)
	var l := OmniLight3D.new()
	l.light_color = Color(0.7, 0.4, 1.0)
	l.omni_range = 2.0
	l.light_energy = 1.2
	l.position.y = 0.6
	add_child(l)


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
