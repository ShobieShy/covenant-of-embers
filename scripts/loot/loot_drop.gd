class_name LootDrop
extends RefCounted
## One rolled drop (BUILD_PLAN step 18): what DropPool.roll / DropRoller hand to step 22's
## pickups. A drop is either
##  - WIELDABLE: a bare base staff/wand (WieldableInstance) from a weighted DropPool,
##  - PART: a procedural WieldablePart (PartRoller, regenerable from its roll_seed),
##  - EQUIPMENT: a Hat/Clothes/Belt/Shoes spec (slot, rarity, element, roll_seed). Step 19
##    turns it into the item with its seeded equipment roller (Magewar
##    generate_equipment_with_rng); until then `item` is null.
## `rarity_id` is the item's tier (pickup beam colour); `rolled_rarity_id` is what
## RarityTable.roll gave before a pool fell back to a tier it has.

enum Kind { WIELDABLE, PART, EQUIPMENT }

## Magewar EquipmentItem.EquipSlot order; drops use the first four (Magewar
## _random_equip_slot never drops a Grimoire).
const EQUIP_SLOTS: PackedStringArray = ["hat", "clothes", "belt", "shoes", "grimoire"]
const DROP_EQUIP_SLOTS := 4

var kind: Kind = Kind.PART
var item: Resource                 ## WieldableInstance / WieldablePart / null (equipment until step 19)
var rarity_id := "basic"
var rolled_rarity_id := "basic"
var element: ElementTable.Element = ElementTable.Element.ARCANE
var equip_slot := -1               ## EQUIP_SLOTS index for EQUIPMENT
var roll_seed := -1                ## PART: = the part's roll_seed; EQUIPMENT: seed for step 19
var pool_id := ""                  ## WIELDABLE: the pool it came from
var entry: DropEntry               ## WIELDABLE: the chosen row

func rarity_color() -> Color:
	return RarityTable.load_default().color(rarity_id)

func equip_slot_id() -> String:
	return EQUIP_SLOTS[equip_slot] if equip_slot >= 0 and equip_slot < EQUIP_SLOTS.size() else ""

func describe() -> String:
	var r := RarityTable.load_default().display_name(rarity_id)
	match kind:
		Kind.WIELDABLE:
			return "%s %s" % [r, (item as WieldableInstance).display_name() if item else "?"]
		Kind.PART:
			return "%s %s" % [r, (item as WieldablePart).display_name if item else "?"]
		_:
			return "%s %s %s" % [r, ElementTable.load_default().display_name(element), equip_slot_id().capitalize()]
