class_name BrandTable
extends Resource
## The six brands (step 135): resources/brands/brands.tres. Every element except Arcane has
## exactly one brand; for_element(ARCANE) is null (unbranded, today's behaviour).

const PATH := "res://resources/brands/brands.tres"

@export var brands: Array[Brand] = []

static var _default: BrandTable


static func load_default() -> BrandTable:
	if _default == null:
		_default = load(PATH) as BrandTable
		var errs := _default.validate()
		if not errs.is_empty():
			push_error("%s: %s" % [PATH, "; ".join(errs)])
	return _default


## The brand for `element`, or null (Arcane / unknown).
static func for_element(element: ElementTable.Element) -> Brand:
	if element == ElementTable.Element.ARCANE:
		return null
	for b in load_default().brands:
		if b != null and b.element == element:
			return b
	return null


static func by_id(brand_id: String) -> Brand:
	for b in load_default().brands:
		if b != null and b.id == brand_id:
			return b
	return null


## Empty when usable; else one message per problem.
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	var per_element := {}
	var ids := {}
	for b in brands:
		if b == null:
			errs.append("null brand entry")
			continue
		var tag := "brand '%s'" % b.id
		if b.id.is_empty() or b.display_name.is_empty() or b.short_name.is_empty():
			errs.append("%s: id/display_name empty" % tag)
		if ids.has(b.id):
			errs.append("%s: duplicate id" % tag)
		ids[b.id] = true
		if b.element == ElementTable.Element.ARCANE:
			errs.append("%s: Arcane is unbranded" % tag)
		per_element[b.element] = int(per_element.get(b.element, 0)) + 1
		if not (b.wand_scale > 0.0 and b.wand_scale <= 1.0):
			errs.append("%s: wand_scale must be in (0, 1]" % tag)
		if not b.logo_path.is_empty() and not ResourceLoader.exists(b.logo_path):
			errs.append("%s: logo %s missing" % [tag, b.logo_path])
	for e in range(1, ElementTable.COUNT):
		if int(per_element.get(e, 0)) != 1:
			errs.append("element %s: %d brands (expected 1)" % [ElementTable.IDS[e], per_element.get(e, 0)])
	return errs
