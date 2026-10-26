class_name ItemTrash
extends RefCounted
## t74u: destroying items from the inventory screen. Only the given (local) player's
## own inventory is touched; nothing goes over the network.


## t74u: true when trashing `item` should ask first (Rare or better).
static func needs_confirm(item: Resource) -> bool:
	return item != null and not (item is ConsumableItem) and Vendor.tier_of(item) >= Rarity.Tier.RARE


## t74u: destroys a backpack item (or `count` quick-slot potions); "" on success, else why
## not. Quest items (ids in p.quest_items) are refused, worn items must be unequipped first.
## Only this player's own inventory is touched (nothing is sent over the network).
static func trash(p: Player, item: Variant, count: int = 1) -> String:
	if item == null:
		return "Nothing selected."
	if item is String or item is StringName:
		return "Quest items can't be trashed." if p.quest_items.has(String(item)) else "Nothing selected."
	if not (item is Resource):
		return "Nothing selected."
	if item is ConsumableItem:
		if p.equipment.potion != item or p.equipment.potion_count <= 0:
			return "Nothing selected."
		var n := clampi(count, 1, p.equipment.potion_count)
		p.equipment.potion_count -= n
		if p.equipment.potion_count == 0:
			p.equipment.potion = null
		p.equipment.changed.emit(-1)
		return ""
	for slot in [Loadout.Slot.STAFF, Loadout.Slot.WAND]:
		if p.loadout.wieldable(slot) == item:
			return "Unequip it first."
	for slot in EquipmentItem.SLOT_COUNT:
		if p.equipment.item(slot) == item:
			return "Unequip it first."
	if not p.inventory.remove(item):
		return "That isn't in your backpack."
	return ""
