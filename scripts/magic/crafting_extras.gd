class_name CraftingExtras
extends RefCounted
## Crafting extras (BUILD_PLAN step 26; our additions on Magewar's base, PLAN §30.3):
##  * Gems: socket an ElementGem from the backpack into a Head (loose or inside an
##    assembled wieldable) with a free gem slot (wand Heads use 1, Assembly.WAND_GEM_SLOTS);
##    unsocket puts it back in the backpack.
##  * Salvage: a loose part from the backpack -> Arcane Dust (SALVAGE_DUST by tier); its
##    socketed gems return to the backpack (refused when they don't fit).
##  * Upgrade: a rolled part (roll_seed >= 0) one tier up for UPGRADE_COST[tier] Dust:
##    PartRoller.from_seed(same seed, type, next tier, same element), so the relative roll
##    is kept and stats/name/gem slots follow the tier. Never to Unique (PLAN §30.3: Unique
##    stays drop-only), so Primordial is the top; hand-made template parts can't upgrade.
## Every call returns "" on success or the refusal text.

const SALVAGE_DUST: PackedInt32Array = [1, 3, 6, 12, 25, 50]  ## by Rarity.Tier
const UPGRADE_COST: PackedInt32Array = [5, 12, 30, 75]  ## Basic->Unc .. Mythic->Primordial
const MAX_UPGRADE_TIER := Rarity.Tier.PRIMORDIAL


static func head_slots(head: WieldablePart, owner: WieldableInstance = null) -> int:
	if head == null or head.part_type != WieldablePart.PartType.HEAD:
		return 0
	if owner != null and owner.def != null and owner.def.type == WieldableDef.Type.WAND:
		return mini(head.gem_slots, Assembly.WAND_GEM_SLOTS)
	return head.gem_slots


static func socket(inv: Inventory, head: WieldablePart, gem: ElementGem, owner: WieldableInstance = null) -> String:
	if gem == null or not inv.has(gem):
		return "The gem must be in your backpack."
	if head == null or head.part_type != WieldablePart.PartType.HEAD:
		return "Gems only fit a Head."
	if head.gems.size() >= head_slots(head, owner):
		return "No free gem slot."
	inv.remove(gem)
	var a: Array[ElementGem] = head.gems.duplicate()  # fresh array: never share a template's
	a.append(gem)
	head.gems = a
	return ""


static func unsocket(inv: Inventory, head: WieldablePart, index: int) -> String:
	if head == null or index < 0 or index >= head.gems.size():
		return "No gem there."
	if inv.is_full():
		return PickupCollector.HINT_FULL
	var a: Array[ElementGem] = head.gems.duplicate()
	var g: ElementGem = a[index]
	a.remove_at(index)
	head.gems = a
	inv.add(g)
	return ""


static func salvage_value(part: WieldablePart) -> int:
	return SALVAGE_DUST[clampi(Rarity.parse(part.rarity), 0, Rarity.COUNT - 1)]


static func salvage(inv: Inventory, part: WieldablePart) -> String:
	if part == null or not inv.has(part):
		return "Choose a loose part in your backpack."
	if inv.free_slots() + 1 < part.gems.size():
		return PickupCollector.HINT_FULL
	inv.remove(part)
	for g in part.gems:
		inv.add(g)
	part.gems = [] as Array[ElementGem]
	inv.add_dust(salvage_value(part))
	return ""


## Dust for the next tier; -1 when the part can't go higher.
static func upgrade_cost(part: WieldablePart) -> int:
	var t := Rarity.parse(part.rarity)
	return UPGRADE_COST[t] if t >= 0 and t < MAX_UPGRADE_TIER else -1


## Upgrades `part` in place (same object, so a backpack slot or assembled wieldable keeps it).
static func upgrade(inv: Inventory, part: WieldablePart) -> String:
	if part == null:
		return "Choose a part."
	if part.roll_seed < 0:
		return "Only rolled parts can be upgraded."
	var cost := upgrade_cost(part)
	if cost < 0:
		return "Already at the highest upgradable rarity."
	if inv.dust < cost:
		return "Not enough Arcane Dust (%d needed)." % cost
	var next := PartRoller.from_seed(
		part.roll_seed, part.part_type, Rarity.IDS[Rarity.parse(part.rarity) + 1], part.element
	)
	if next == null:
		return "Upgrade failed."
	inv.spend_dust(cost)
	var gems: Array[ElementGem] = part.gems.duplicate()
	for prop in next.get_property_list():
		if (
			prop["usage"] & PROPERTY_USAGE_STORAGE
			and prop["name"] not in ["script", "resource_path", "resource_name", "resource_local_to_scene", "gems"]
		):
			part.set(prop["name"], next.get(prop["name"]))
	part.gems = gems
	return ""
