class_name HubToys
extends RefCounted
## Town Square and Old Oak toys. They spend gold, or a breach key the player already holds.

const KEY := "breach_key"
const CHEST_GOLD := 25
const VEND_GOLD := 8
const SLOT_GOLD := 5


static func place(parent: Node) -> void:
	if parent.get_node_or_null("HubToys") != null:
		return
	var root := Node3D.new()
	root.name = "HubToys"
	for id in ["BreachChest", "Vendor", "SlotMachine"]:
		var m := MeshInstance3D.new()
		m.name = id
		m.mesh = BoxMesh.new()
		root.add_child(m)
	parent.add_child(root)


static func open_chest(p: Player) -> bool:
	if p.quest_items.has(KEY):
		p.quest_items.remove_at(p.quest_items.find(KEY))
		return true
	return p.inventory.spend_gold(CHEST_GOLD)


static func vend(p: Player) -> bool:
	return p.inventory.spend_gold(VEND_GOLD)


static func pull_slot(p: Player, rng: RandomNumberGenerator) -> int:
	if not p.inventory.spend_gold(SLOT_GOLD):
		return -1
	if rng.randi() % 4 == 0:
		p.inventory.add_gold(SLOT_GOLD * 3)
	return p.inventory.gold
