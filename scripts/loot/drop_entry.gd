class_name DropEntry
extends Resource
## One weighted row of a DropPool (BUILD_PLAN step 18; PLAN §31.4): a base staff/wand by id
## (resources/wieldables/<id>.tres, WieldableInstance.load_base) and a relative weight.
## Its rarity is the base's `base_rarity` unless `rarity` overrides it (e.g. a Rare
## Apprentice Fire Staff: the same spell at a higher tier; Bible "base staff/wand have
## rarities"). The pool picks a rarity first (RarityTable.roll) and then an entry of it.

@export var wieldable_id := ""  ## resources/wieldables id
@export var weight := 1.0  ## relative within entries of the same rarity (> 0)
@export var rarity := ""  ## Rarity.IDS; "" = the base's base_rarity

var _def: WieldableDef


## The referenced base (cached; null when the id doesn't load).
func def() -> WieldableDef:
	if _def == null and not wieldable_id.is_empty():
		var w := (
			WieldableInstance.load_base(wieldable_id)
			if ResourceLoader.exists("res://resources/wieldables/%s.tres" % wieldable_id)
			else null
		)
		_def = w.def if w != null else null
	return _def


## Effective rarity id ("" when the base doesn't load).
func rarity_id() -> String:
	if not rarity.is_empty():
		return rarity
	var d := def()
	return d.base_rarity if d != null else ""


func tier() -> int:
	return Rarity.parse(rarity_id())


## A fresh bare instance of the base at this entry's rarity (its own def copy when the
## rarity is overridden, so the shared base resource is never edited).
func make() -> WieldableInstance:
	var d := def()
	if d == null:
		return null
	if rarity_id() != d.base_rarity:
		d = d.duplicate() as WieldableDef
		d.base_rarity = rarity_id()
	return WieldableInstance.of(d)


## Empty when usable; else one message per problem.
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	var tag := "entry '%s'" % wieldable_id
	if def() == null:
		errs.append("%s: unknown wieldable id" % tag)
	elif not def().validate().is_empty():
		errs.append("%s: base invalid (%s)" % [tag, "; ".join(def().validate())])
	if not rarity.is_empty() and Rarity.parse(rarity) < 0:
		errs.append("%s: unknown rarity '%s'" % [tag, rarity])
	if not (weight > 0.0 and weight < INF):
		errs.append("%s: weight must be > 0 (got %s)" % [tag, weight])
	return errs
