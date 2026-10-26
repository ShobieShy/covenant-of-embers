class_name ItemIcons
extends RefCounted
## t61u: one pixel icon per item type, wherever items show (backpack, worn slots, station, vendor).
## Kenney Tiny Dungeon (CC0, icons/items) and the Ember Art spell/element icons first; the gaps
## (hat, robe, belt, shoes, grimoire, gem) are project-made CC0 pixel art in icons/gear.

const ITEMS := "res://assets/kenney/pixel-ui/icons/items/"
const SPELLS := "res://assets/kenney/pixel-ui/icons/spells_elements/"
const GEAR := "res://assets/kenney/pixel-ui/icons/gear/"
## Ember Art batch 06 (CC0, original): 16 px element / gear / junk icons, preferred when present.
const EMBER := "res://assets/original/ember_art/icons/"
const EMBER_ELEMENTS: PackedStringArray = ["arcane", "fire", "water", "earth", "air", "", ""]
const EMBER_GEAR: PackedStringArray = ["hood", "robe", "", "boots", ""]
const EMBER_JUNK: PackedStringArray = ["bottle", "can", "bag", "bone", "scrap"]
const PART_ICONS: PackedStringArray = [
	"",  # HEAD: by element (HEAD_BY_ELEMENT)
	ITEMS + "buckler_square.png",  # EXTERIOR: the casing
	ITEMS + "vial_blue.png",  # INTERIOR: the core
	ITEMS + "spear.png",  # HANDLE: the shaft
	SPELLS + "element_light.png",  # CHARM
]
const GEAR_ICONS: PackedStringArray = ["hat.png", "robe.png", "belt.png", "shoes.png", "grimoire.png"]
## ElementTable.Element order: ARCANE, FIRE, WATER, EARTH, AIR, LIGHT, DARK
const HEAD_BY_ELEMENT: PackedStringArray = [
	"spell_light_orb.png",
	"spell_fire.png",
	"spell_ice.png",
	"spell_heal.png",
	"spell_lightning.png",
	"spell_light_orb.png",
	"spell_dark_orb.png",
]
const GEM_TINT: Array[Color] = [
	Color(0.75, 0.55, 1.0),
	Color(1.0, 0.45, 0.3),
	Color(0.4, 0.7, 1.0),
	Color(0.55, 0.85, 0.4),
	Color(0.85, 0.95, 1.0),
	Color(1.0, 0.95, 0.55),
	Color(0.6, 0.4, 0.75),
]


## Path of the icon for `item` ("" for null / an unknown type).
static func path_for(item: Resource) -> String:
	var e := _ember_path(item)
	if not e.is_empty() and ResourceLoader.exists(e):
		return e
	if item is WieldableInstance:
		var w := item as WieldableInstance
		return ITEMS + ("staff_purple.png" if w.type() == WieldableDef.Type.STAFF else "staff_blue.png")
	if item is WieldablePart:
		var p := item as WieldablePart
		if p.part_type == WieldablePart.PartType.HEAD:
			return SPELLS + HEAD_BY_ELEMENT[clampi(p.element, 0, HEAD_BY_ELEMENT.size() - 1)]
		return PART_ICONS[clampi(p.part_type, 0, PART_ICONS.size() - 1)]
	if item is EquipmentItem:
		return GEAR + GEAR_ICONS[clampi((item as EquipmentItem).slot, 0, GEAR_ICONS.size() - 1)]
	if item is ElementGem:
		return GEAR + "gem.png"
	if item is ConsumableItem:
		return ITEMS + ("potion_blue.png" if (item as ConsumableItem).attribute == "mana" else "potion_red.png")
	return ""


## The batch 06 icon for `item`, or "" when it has none.
static func _ember_path(item: Resource) -> String:
	if item is WieldableInstance:
		return (
			EMBER
			+ "gear/"
			+ ("staff" if (item as WieldableInstance).type() == WieldableDef.Type.STAFF else "wand")
			+ ".png"
		)
	if item is WieldablePart and (item as WieldablePart).part_type == WieldablePart.PartType.HEAD:
		var n := EMBER_ELEMENTS[clampi((item as WieldablePart).element, 0, EMBER_ELEMENTS.size() - 1)]
		return "" if n.is_empty() else EMBER + "elements/" + n + ".png"
	if item is EquipmentItem:
		var g := EMBER_GEAR[clampi((item as EquipmentItem).slot, 0, EMBER_GEAR.size() - 1)]
		return "" if g.is_empty() else EMBER + "gear/" + g + ".png"
	if item is ElementGem:
		return EMBER + "gear/gem.png"
	if item is WieldablePart and (item as WieldablePart).part_type == WieldablePart.PartType.CHARM:
		return EMBER + "gear/amulet.png"
	return ""


## A junk mark icon (one of 5, stable per item) for backpack slots marked as junk.
static func junk_icon(item: Resource) -> Texture2D:
	var p := (
		EMBER + "junk/" + EMBER_JUNK[absi(hash(item.resource_name + item.resource_path)) % EMBER_JUNK.size()] + ".png"
	)
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


static func for_item(item: Resource) -> Texture2D:
	var p := path_for(item)
	return load(p) as Texture2D if not p.is_empty() and ResourceLoader.exists(p) else null


## Gems share one sprite, tinted by element; everything else draws untinted.
static func tint_for(item: Resource) -> Color:
	if item is ElementGem:
		return GEM_TINT[clampi((item as ElementGem).element, 0, GEM_TINT.size() - 1)]
	return Color.WHITE


## Puts `item`'s icon on a Button, nearest-filtered at a whole-number scale.
static func dress(b: Button, item: Resource) -> void:
	b.icon = for_item(item)
	b.expand_icon = true
	b.add_theme_constant_override(&"icon_max_width", 32)
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.add_theme_color_override(&"icon_normal_color", tint_for(item))
	b.add_theme_color_override(&"icon_hover_color", tint_for(item))
	b.add_theme_color_override(&"icon_pressed_color", tint_for(item))
	b.add_theme_color_override(&"icon_focus_color", tint_for(item))
