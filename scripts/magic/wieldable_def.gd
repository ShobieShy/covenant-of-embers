class_name WieldableDef
extends Resource
## A base staff or wand (BUILD_PLAN step 7, port of the archived C++ game/magic/wieldable.*,
## old step 17; PLAN §30.1). Follows Magewar's StaffWieldableItem directly (weapon system =
## Magewar design): a base *is* the spell: type (Magewar staff_type STAFF/WAND), base
## rarity, primary element, base damage (wieldable_damage), mana per cast, fire cooldown,
## projectile speed and range (wieldable_range). Data: resources/wieldables/*.tres
## (Magewar's four bases; cross-checked against data/magic/wieldables.toml and the Magewar
## .tres copies in assets/magewar by test_casting.gd). Parts and final stats live in
## WieldableInstance.

enum Type { STAFF, WAND }  ## Magewar StaffWieldableItem.StaffType order

const TYPE_IDS: PackedStringArray = ["staff", "wand"]
## Magewar ItemRarity.Rarity order (= Rarity.IDS; tiers in resources/loot/rarities.tres).
const RARITY_IDS: PackedStringArray = Rarity.IDS
const MIN_COOLDOWN := 0.1  ## Magewar get_final_fire_rate: max(0.1, rate)

@export var id := ""  ## lower_snake_case key
@export var display_name := ""  ## Magewar `name`
@export var type: Type = Type.STAFF
@export var base_rarity := "basic"  ## RARITY_IDS
@export var element: ElementTable.Element = ElementTable.Element.ARCANE  ## Magewar primary_element
@export var damage := 10.0  ## Magewar wieldable_damage (before rarity / parts)
@export var mana_cost := 5.0  ## per cast (step 8 spends it)
@export var cooldown := 0.4  ## Magewar fire_cooldown, seconds
@export var projectile_speed := 30.0  ## m/s
@export var range_m := 50.0  ## Magewar wieldable_range: the bolt fizzles here


static func type_of(id_str: String) -> int:
	return TYPE_IDS.find(id_str)


## From a data/magic/wieldables.toml [[wieldable]] table (LevelToml); validate() afterwards.
static func from_toml(t: Dictionary) -> WieldableDef:
	var d := WieldableDef.new()
	d.id = str(t.get("id", ""))
	d.display_name = str(t.get("name", ""))
	d.type = maxi(0, type_of(str(t.get("type", "")))) as Type
	d.base_rarity = str(t.get("base_rarity", ""))
	d.element = maxi(0, ElementTable.parse(str(t.get("element", "")))) as ElementTable.Element
	d.damage = float(t.get("damage", 0.0))
	d.mana_cost = float(t.get("mana_cost", 0.0))
	d.cooldown = float(t.get("cooldown", 0.0))
	d.projectile_speed = float(t.get("projectile_speed", 0.0))
	d.range_m = float(t.get("range", 0.0))
	return d


## Empty when usable; else one message per problem (the C++ loader's checks: generous
## sanity bounds around Magewar's bases, cooldown >= Magewar's 0.1 s floor).
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	var w := "wieldable '%s'" % id
	var re := RegEx.create_from_string("^[a-z0-9_]+$")
	if re.search(id) == null:
		errs.append("%s: id must be lower_snake_case [a-z0-9_]" % w)
	if display_name.is_empty():
		errs.append("%s: name is empty" % w)
	if type < 0 or type >= TYPE_IDS.size():
		errs.append("%s: unknown type %d" % [w, type])
	if not RARITY_IDS.has(base_rarity):
		errs.append("%s: unknown base_rarity '%s' (expected %s)" % [w, base_rarity, ", ".join(RARITY_IDS)])
	if element < 0 or element >= ElementTable.COUNT:
		errs.append("%s: unknown element %d" % [w, element])
	for r in [
		["damage", damage, 0.1, 1000.0],
		["mana_cost", mana_cost, 0.0, 100.0],
		["cooldown", cooldown, MIN_COOLDOWN, 10.0],
		["projectile_speed", projectile_speed, 1.0, 500.0],
		["range", range_m, 1.0, 1000.0]
	]:
		var v: float = r[1]
		if not (v >= r[2] and v <= r[3]):
			errs.append("%s %s must be in [%s, %s] (got %s)" % [w, r[0], r[2], r[3], v])
	return errs
