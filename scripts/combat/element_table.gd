class_name ElementTable
extends Resource
## Spell elements + effectiveness chart (BUILD_PLAN step 6, port of the archived C++
## game/combat/element.*, old step 20; PLAN §30.4). Data: resources/magic/elements.tres.
## Reinterprets Magewar's MagicElement (scripts/magic/magic_element.gd, read-only):
##  - same enum order (Magewar NONE = our ARCANE, displayed "Arcane" like Magewar);
##  - effectiveness(attacker, defender): same element or Arcane on either side = x1.0
##    (code rule, as in Magewar); otherwise `strong` if the defender is in the attacker's
##    strong_against, `weak` if in weak_against, else x1.0. The data gives Magewar's
##    cycle Fire > Earth > Air > Water > Fire (x1.5 / x0.5) and Light <-> Dark x1.5 both
##    ways (never weak);
##  - names/colours are Magewar's ELEMENT_NAMES / ELEMENT_COLORS.
## The chart is data (not Magewar's match statement) so step 21's balance patches can
## tune it; validate() refuses tables that would break the code rules (the C++ loader's
## checks). Call rebuild() after changing `elements`, `strong` or `weak` at runtime.

enum Element { ARCANE, FIRE, WATER, EARTH, AIR, LIGHT, DARK }

const COUNT := 7
const IDS: PackedStringArray = ["arcane", "fire", "water", "earth", "air", "light", "dark"]
const PATH := "res://resources/magic/elements.tres"

@export var strong := 1.5  ## multiplier vs strong_against (> 1)
@export var weak := 0.5  ## multiplier vs weak_against ([0, 1))
@export var elements: Array[ElementDef] = []  ## one per Element, any order

var _chart := PackedFloat64Array()  ## COUNT x COUNT, [attacker * COUNT + defender]
var _rows: Array[ElementDef] = []  ## indexed by Element

static var _default: ElementTable


## The shared table from resources/magic/elements.tres (loaded once).
static func load_default() -> ElementTable:
	if _default == null:
		_default = load(PATH) as ElementTable
		var errs := _default.validate()
		if not errs.is_empty():
			push_error("%s: %s" % [PATH, "; ".join(errs)])
	return _default


static func id_of(e: Element) -> String:
	return IDS[e]


## Element for an id, or -1 when unknown ("none"/"wind" are not ids).
static func parse(id: String) -> int:
	return IDS.find(id)


func effectiveness(attacker: Element, defender: Element) -> float:
	if attacker == defender or attacker == Element.ARCANE or defender == Element.ARCANE:
		return 1.0
	_ensure_built()
	return _chart[attacker * COUNT + defender]


func display_name(e: Element) -> String:
	var d := def(e)
	return d.display_name if d != null else IDS[e]


func color(e: Element) -> Color:
	var d := def(e)
	return Accessibility.element_color(e, d.color if d != null else Color.WHITE)  # step 76


func def(e: Element) -> ElementDef:
	_ensure_built()
	return _rows[e]


## Recomputes the chart from `elements`/`strong`/`weak` (after a patch, step 21).
func rebuild() -> void:
	_rows.clear()
	_rows.resize(COUNT)
	_chart = PackedFloat64Array()
	_chart.resize(COUNT * COUNT)
	_chart.fill(1.0)
	for d in elements:
		var a := parse(d.id) if d != null else -1
		if a < 0:
			continue
		_rows[a] = d
		for id in d.strong_against:
			var b := parse(id)
			if b >= 0:
				_chart[a * COUNT + b] = strong
		for id in d.weak_against:
			var b := parse(id)
			if b >= 0:
				_chart[a * COUNT + b] = weak


func _ensure_built() -> void:
	if _chart.size() != COUNT * COUNT:
		rebuild()


## Empty when the table is usable; else one message per problem.
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	if not (strong > 1.0 and strong <= 10.0):
		errs.append("strong must be in (1, 10] (got %s)" % strong)
	if not (weak >= 0.0 and weak < 1.0):
		errs.append("weak must be in [0, 1) (got %s)" % weak)
	var seen: Array[bool] = []
	seen.resize(COUNT)
	seen.fill(false)
	for i in elements.size():
		var d := elements[i]
		if d == null:
			errs.append("element #%d is empty" % (i + 1))
			continue
		var e := parse(d.id)
		if e < 0:
			errs.append("element #%d: unknown element '%s' (expected %s)" % [i + 1, d.id, ", ".join(IDS)])
			continue
		if seen[e]:
			errs.append("duplicate element '%s'" % d.id)
		seen[e] = true
		if d.display_name.is_empty():
			errs.append("element '%s': display_name is empty" % d.id)
		for c in [d.color.r, d.color.g, d.color.b]:
			if c < 0.0 or c > 1.0:
				errs.append("element '%s': color must be in 0..1" % d.id)
				break
		var listed := {}
		for key in ["strong_against", "weak_against"]:
			var ids: PackedStringArray = d.get(key)
			if e == Element.ARCANE and not ids.is_empty():
				errs.append("element 'arcane': arcane is neutral (Magewar NONE), its %s must be empty" % key)
				continue
			for id in ids:
				var t := parse(id)
				if t < 0:
					errs.append("element '%s': unknown element '%s' in %s" % [d.id, id, key])
				elif t == Element.ARCANE:
					errs.append("element '%s': %s can't list arcane (always x1.0)" % [d.id, key])
				elif t == e:
					errs.append("element '%s': %s can't list itself (same element is x1.0)" % [d.id, key])
				elif listed.get(id, "") == key:
					errs.append("element '%s': '%s' listed twice in %s" % [d.id, id, key])
				elif listed.has(id):
					errs.append("element '%s': '%s' is in both strong_against and weak_against" % [d.id, id])
				else:
					listed[id] = key
	for e in COUNT:
		if not seen[e]:
			errs.append("missing element '%s'" % IDS[e])
	return errs
