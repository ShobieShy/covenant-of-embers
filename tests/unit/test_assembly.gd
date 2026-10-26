extends TestCase
## Step 17 done check: assembly rules + final stats (Assembly = Magewar MagicAssemblyStation
## can_build_* / _calculate_assembled_rarity / _build_*; getters = StaffWieldableItem).
##  - invalid builds rejected with a message: missing Head/Exterior/Interior/Handle (staff)
##    or Head/Exterior (wand), Interior/Charm on a wand, two parts of one type, too few/many
##    parts, empty or invalid parts, no base; assemble() returns null for them;
##  - staff 4-5 parts, wand 2-3; rarity = floor(mean part tier) replaces the base's;
##  - cooldown = base x Exterior x Charm >= 0.1 s; the Head's element overrides the base's
##    (an Arcane Head keeps the base's);
##  - the PLAN §30.3 worked examples (Fire staff, + charm, Earthward, Swift Wind wand);
##  - name "<Rarity> [Brand] <Element> Staff|Wand", same part objects kept (disassemble returns
##    them), wand Head sockets capped at 1, handling shortens the Loadout draw.

const EPS := 1e-6
const P := WieldablePart.PartType
const E := ElementTable.Element

const FIRE_STAFF := ["basic_fire_head", "basic_exterior", "basic_interior", "basic_handle"]
const TOP_PARTS := [
	"primordial_fire_head", "mythic_water_exterior", "basic_earth_interior", "rare_air_handle", "unique_void_charm"
]
const WAND_PARTS := ["rare_water_head", "uncommon_air_exterior", "uncommon_dark_handle"]


func _def(id: String) -> WieldableDef:
	return WieldableInstance.load_base(id).def


func _parts(ids: Array) -> Array[WieldablePart]:
	var out: Array[WieldablePart] = []
	for id in ids:
		out.append(WieldablePart.load_part(id))
	return out


func _has(errs: PackedStringArray, text: String) -> bool:
	for e in errs:
		if e.contains(text):
			return true
	return false


# --- Rules ------------------------------------------------------------------------------


func test_part_counts_and_slots() -> void:
	check(Assembly.count_range(WieldableDef.Type.STAFF) == Vector2i(4, 5), "staff 4-5 parts")
	check(Assembly.count_range(WieldableDef.Type.WAND) == Vector2i(2, 3), "wand 2-3 parts")
	for t in [P.HEAD, P.EXTERIOR, P.INTERIOR, P.HANDLE, P.CHARM]:
		check(Assembly.allows(WieldableDef.Type.STAFF, t), "a staff takes every part type")
	check(
		Assembly.allows(WieldableDef.Type.WAND, P.HEAD) and Assembly.allows(WieldableDef.Type.WAND, P.HANDLE),
		"wand Head + Handle"
	)
	check(
		(
			not Assembly.allows(WieldableDef.Type.WAND, P.INTERIOR)
			and not Assembly.allows(WieldableDef.Type.WAND, P.CHARM)
		),
		"no Interior/Charm on a wand"
	)
	var staff := _def("apprentice_fire_staff")
	var wand := _def("novice_arcane_wand")
	check(
		Assembly.can_build(staff, _parts(FIRE_STAFF)),
		"4-part staff ok: %s" % [Assembly.check(staff, _parts(FIRE_STAFF))]
	)
	check(Assembly.can_build(staff, _parts(FIRE_STAFF + ["rare_light_charm"])), "5-part staff ok")
	check(Assembly.can_build(wand, _parts(["rare_water_head", "uncommon_air_exterior"])), "2-part wand ok")
	check(Assembly.can_build(wand, _parts(WAND_PARTS)), "3-part wand ok")


func test_invalid_builds_rejected() -> void:
	var staff := _def("apprentice_fire_staff")
	var wand := _def("novice_arcane_wand")
	var cases := [
		[staff, ["basic_exterior", "basic_interior", "basic_handle"], "needs a Head"],
		[staff, ["basic_fire_head", "basic_interior", "basic_handle"], "needs a Exterior"],
		[staff, ["basic_fire_head", "basic_exterior", "basic_handle", "rare_light_charm"], "needs a Interior"],
		[staff, ["basic_fire_head", "basic_exterior", "basic_interior", "rare_light_charm"], "needs a Handle"],
		[
			staff,
			["basic_fire_head", "basic_exterior", "basic_interior", "basic_handle", "rare_air_handle"],
			"two Handle"
		],
		[staff, FIRE_STAFF + ["rare_light_charm", "unique_void_charm"], "takes 4-5 parts (got 6)"],
		[staff, [], "takes 4-5 parts (got 0)"],
		[wand, ["uncommon_air_exterior"], "needs a Head"],
		[wand, ["rare_water_head"], "needs a Exterior"],
		[wand, ["rare_water_head", "uncommon_air_exterior", "basic_interior"], "can't take a Interior"],
		[wand, ["rare_water_head", "uncommon_air_exterior", "rare_light_charm"], "can't take a Charm"],
		[
			wand,
			["rare_water_head", "uncommon_air_exterior", "basic_interior", "basic_handle"],
			"takes 2-3 parts (got 4)"
		],
		[wand, ["rare_water_head", "uncommon_fire_head", "uncommon_air_exterior"], "two Head"],
	]
	for c in cases:
		var def: WieldableDef = c[0]
		var errs := Assembly.check(def, _parts(c[1]))
		check(_has(errs, c[2]), "%s %s -> '%s' (got %s)" % [def.id, c[1], c[2], errs])
		check(Assembly.assemble(def, _parts(c[1])) == null, "%s %s: assemble() refuses" % [def.id, c[1]])
	# Empty slot, broken part, no base.
	var with_null: Array = _parts(["basic_fire_head", "basic_exterior", "basic_interior"])
	with_null.append(null)
	check(_has(Assembly.check(staff, with_null), "part 3 is empty"), "null part rejected")
	var bad := WieldablePart.load_part("basic_handle").duplicate() as WieldablePart
	bad.rarity = "legendary"
	var with_bad: Array = _parts(["basic_fire_head", "basic_exterior", "basic_interior"])
	with_bad.append(bad)
	check(_has(Assembly.check(staff, with_bad), "unknown rarity"), "invalid part rejected")
	check(_has(Assembly.check(null, _parts(FIRE_STAFF)), "no base"), "no base rejected")
	# Magewar drops Interior/Charm (and the Handle when an Interior is picked) on a wand
	# silently; ours rejects, so nothing a player selected vanishes.


func test_rarity_is_floor_of_mean() -> void:
	check(Assembly.rarity_for([]) == "basic", "no parts -> Basic (Magewar)")
	check(Assembly.rarity_for(_parts(FIRE_STAFF)) == "basic", "0,0,0,0 -> Basic")
	check(Assembly.rarity_for(_parts(FIRE_STAFF + ["rare_light_charm"])) == "basic", "0,0,0,0,2 = 0.4 -> Basic")
	check(Assembly.rarity_for(_parts(TOP_PARTS)) == "rare", "4,3,0,2,5 = 2.8 -> Rare (floor, not round)")
	check(Assembly.rarity_for(_parts(WAND_PARTS)) == "uncommon", "2,1,1 = 1.33 -> Uncommon")
	check(
		Assembly.rarity_for(_parts(["primordial_fire_head", "mythic_water_exterior"])) == "mythic",
		"4,3 = 3.5 -> Mythic"
	)
	check(Assembly.rarity_for(_parts(["unique_void_charm"])) == "unique", "5 -> Unique")
	# It replaces the base rarity: the Uncommon Earthward base becomes Rare; a Basic base
	# with Uncommon parts becomes Uncommon.
	var big := Assembly.assemble(_def("earthward_battlestaff"), _parts(TOP_PARTS))
	check(big.rarity_id() == "rare" and big.def.base_rarity == "uncommon", "assembled rarity replaces the base's")
	var wand := Assembly.assemble(_def("novice_arcane_wand"), _parts(WAND_PARTS))
	check(wand.rarity_id() == "uncommon" and wand.def.base_rarity == "basic", "Basic wand -> Uncommon")
	check(wand.rarity_color() == RarityTable.load_default().color("uncommon"), "colour follows")
	# A bare base (and free-form part lists) keep the base rarity (steps 7/15 behaviour).
	check(WieldableInstance.load_base("earthward_battlestaff").rarity_id() == "uncommon", "bare base keeps its rarity")


# --- Worked examples (PLAN §30.3) -------------------------------------------------------


func test_worked_examples() -> void:
	# 1. Apprentice Fire Staff + the four Basic parts: Basic x1.0 -> 10 + 2 + 0 + 3 + 0.
	var a := Assembly.assemble(_def("apprentice_fire_staff"), _parts(FIRE_STAFF))
	check(a != null and a.assembled, "example 1 builds")
	check(a.rarity_id() == "basic", "1: Basic")
	check_near(a.damage(), 15.0, EPS, "1: damage 15")
	check_near(a.cooldown(), 0.4, EPS, "1: 0.4 s")
	check_near(a.accuracy(), 65.0, EPS, "1: 50 + 5 + 10")
	check(a.element() == E.FIRE and a.display_name() == "Basic Pyrowning Fire Staff", "1: %s" % a.display_name())
	# 2. + Rare Light Charm: still Basic (0.4 floors to 0): 17.5 / 0.36 s / 75 %.
	var b := Assembly.assemble(_def("apprentice_fire_staff"), _parts(FIRE_STAFF + ["rare_light_charm"]))
	check(b.rarity_id() == "basic", "2: Basic")
	check_near(b.damage(), 17.5, EPS, "2: 15 + 2.5")
	check_near(b.cooldown(), 0.36, EPS, "2: 0.4 x 1.0 x 0.9")
	check_near(b.accuracy(), 75.0, EPS, "2: + 10")
	# 3. Earthward Battlestaff + the top parts: Rare x1.5 -> 14 x 1.5 + 12 + 1.5 + 3.5 + 0 + 8 = 46;
	#    0.55 x 0.55 x 0.85; 50 + 15 + 22 + 12 = 99 (capped 100); Head Fire beats base Earth.
	var c := Assembly.assemble(_def("earthward_battlestaff"), _parts(TOP_PARTS))
	check_near(c.damage(), 46.0, EPS, "3: damage 46")
	check_near(c.cooldown(), 0.55 * 0.55 * 0.85, EPS, "3: 0.2571 s")
	check_near(c.accuracy(), 99.0, EPS, "3: 99 %")
	check(c.element() == E.FIRE and c.display_name() == "Rare Pyrowning Fire Staff", "3: %s" % c.display_name())
	# 4. Swift Wind Wand + Rare Water Head + Uncommon Air Exterior + Uncommon Dark Handle:
	#    Uncommon x1.25 -> 6 x 1.25 + 6 + 0 + 1 = 14.5; 0.18 x 0.65 = 0.117 s; 50 + 12 + 15 = 77.
	var d := Assembly.assemble(_def("swift_wind_wand"), _parts(WAND_PARTS))
	check_near(d.damage(), 14.5, EPS, "4: damage 14.5")
	check_near(d.cooldown(), 0.117, EPS, "4: 0.117 s")
	check_near(d.accuracy(), 77.0, EPS, "4: 77 %")
	check(d.element() == E.WATER and d.display_name() == "Uncommon Sigil Sauer Water Wand", "4: %s" % d.display_name())
	# 4b. Without the optional Handle: 7.5 + 6 = 13.5, 62 %.
	var d2 := Assembly.assemble(_def("swift_wind_wand"), _parts(["rare_water_head", "uncommon_air_exterior"]))
	check_near(d2.damage(), 13.5, EPS, "4b: 13.5")
	check_near(d2.accuracy(), 62.0, EPS, "4b: 62 %")
	print(
		(
			"    worked: %s %.1f/%.2fs/%.0f%%, +charm %.1f/%.2fs, %s %.1f/%.4fs/%.0f%%, %s %.1f/%.3fs/%.0f%%"
			% [
				a.display_name(),
				a.damage(),
				a.cooldown(),
				a.accuracy(),
				b.damage(),
				b.cooldown(),
				c.display_name(),
				c.damage(),
				c.cooldown(),
				c.accuracy(),
				d.display_name(),
				d.damage(),
				d.cooldown(),
				d.accuracy()
			]
		)
	)


func test_cooldown_floor_and_element_override() -> void:
	var fast := WieldablePart.load_part("uncommon_air_exterior").duplicate() as WieldablePart
	fast.fire_rate_modifier = 0.5
	var w := Assembly.assemble(_def("swift_wind_wand"), [WieldablePart.load_part("rare_water_head"), fast])
	check_near(w.cooldown(), WieldableDef.MIN_COOLDOWN, EPS, "0.18 x 0.5 = 0.09 -> floored at 0.1")
	# Arcane Head: the base keeps its element (Magewar: only a non-NONE head overrides).
	var arcane := WieldablePart.load_part("basic_fire_head").duplicate() as WieldablePart
	arcane.element = E.ARCANE
	var s := Assembly.assemble(
		_def("earthward_battlestaff"), [arcane] + _parts(["basic_exterior", "basic_interior", "basic_handle"])
	)
	check(
		s.element() == E.EARTH and s.display_name() == "Basic Earth Staff" and s.brand() == null,
		"Arcane Head keeps Earth: %s" % s.display_name()
	)
	var aw := Assembly.assemble(_def("novice_arcane_wand"), [arcane, WieldablePart.load_part("basic_exterior")])
	check(
		aw.element() == E.ARCANE and aw.display_name() == "Basic Arcane Wand",
		"arcane on arcane: %s" % aw.display_name()
	)


# --- Instance details -------------------------------------------------------------------


func test_same_parts_kept_in_slot_order() -> void:
	var parts := _parts(["unique_void_charm", "basic_handle", "basic_interior", "basic_exterior", "basic_fire_head"])
	var w := Assembly.assemble(_def("apprentice_fire_staff"), parts)
	var order := []
	for p in w.parts:
		order.append(p.part_type)
	check(order == [P.HEAD, P.EXTERIOR, P.INTERIOR, P.HANDLE, P.CHARM], "sorted Head..Charm: %s" % [order])
	check(w.part(P.CHARM) == parts[0] and w.part(P.HEAD) == parts[4], "the same objects, not copies")
	check(parts[0].part_type == P.CHARM, "caller's list untouched")
	var back := Assembly.disassemble(w)
	check(back.size() == 5, "disassemble returns all 5")
	for p in parts:
		check(back.has(p), "%s returned" % p.id)
	check(
		Assembly.disassemble(WieldableInstance.load_base("apprentice_fire_staff")).is_empty(),
		"a bare base has nothing to return"
	)
	check(w.def == _def("apprentice_fire_staff"), "the chosen base is kept (not a template)")


func test_gem_slots() -> void:
	var staff := Assembly.assemble(_def("earthward_battlestaff"), _parts(TOP_PARTS))
	check(staff.gem_slots() == 3, "staff: Primordial Head 3 sockets")
	var wand := Assembly.assemble(_def("swift_wind_wand"), _parts(WAND_PARTS))
	check(wand.gem_slots() == 1, "wand: Rare Head's 2 capped at 1 (Bible)")
	check(WieldableInstance.load_base("apprentice_fire_staff").gem_slots() == 0, "no Head, no sockets")


func test_handling_shortens_draw() -> void:
	var a := Assembly.assemble(_def("apprentice_fire_staff"), _parts(FIRE_STAFF))
	check_near(a.handling(), 5.0, EPS, "basic handle 5")
	check_near(a.draw_seconds(0.4), 0.4 * 100.0 / 105.0, EPS, "0.381 s")
	var c := Assembly.assemble(_def("earthward_battlestaff"), _parts(TOP_PARTS))
	check_near(c.handling(), 22.0, EPS, "0 + 5 + 0 + 12 + 5")
	check_near(c.draw_seconds(0.4), 0.4 * 100.0 / 122.0, EPS, "0.328 s")
	check_near(WieldableInstance.load_base("apprentice_fire_staff").draw_seconds(0.4), 0.4, EPS, "bare base 0.4 s")
	check_near(Assembly.draw_seconds(0.4, 1000.0), Assembly.MIN_DRAW_SECONDS, EPS, "floored at 0.2 s")
	check_near(Assembly.draw_seconds(0.4, -50.0), 0.4, EPS, "negative handling never slows past base")
	# Through the Loadout: the drawn slot's handling sets the draw length.
	var lo := Loadout.new()
	lo.swap_seconds = 0.4
	lo.equip(WieldableInstance.load_base("swift_wind_wand"))
	lo.equip(c)
	check(lo.select(Loadout.Slot.STAFF), "draw the Earthward")
	check_near(lo.draw_seconds, 0.4 * 100.0 / 122.0, EPS, "loadout uses the staff's draw time")
	var ticks := 0
	while lo.swapping() and ticks < 100:
		lo.tick(1.0 / 60.0, false)
		lo.tick_swap(false, 1.0 / 60.0)
		ticks += 1
	check(ticks == 20, "~20 ticks instead of 24 (got %d)" % ticks)
