class_name ElementGem
extends Resource
## An element gem (BUILD_PLAN step 26; our addition on Magewar's Head gem slots — Magewar
## declares gem_slots and "primary element from the head gem" but has no gem item).
## Socketed into a Head part: the first gem sets the wieldable's element (over the Head's
## own), every socketed gem adds GEM_DAMAGE flat damage. A backpack item.

const GEM_DAMAGE := 1.0

@export var element: ElementTable.Element = ElementTable.Element.FIRE


static func make(e: ElementTable.Element) -> ElementGem:
	var g := ElementGem.new()
	g.element = e
	return g


func display_name() -> String:
	return "%s Gem" % ElementTable.load_default().display_name(element)
