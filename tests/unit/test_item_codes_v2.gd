extends TestCase
## Step 44 done check: Ember Mark v2 extras. Socketed gems (loose Heads and inside assembled
## wieldables), consecrations on rolled + template equipment and loose gems round-trip as
## "EM2-" codes; items without extras keep their exact EM1 code; save round-trip keeps them.

const P := WieldablePart.PartType
const E := ElementTable.Element
const S := EquipmentItem.Slot


func _rt(item: Variant) -> EmberMark:
	var c := ItemCodes.encode(item)
	check(not c.is_empty(), "encodes: %s" % ItemCodes.encode_error(item))
	var m := ItemCodes.decode(c)
	check(m.ok(), "decodes %s: %s" % [c, m.error])
	check(ItemCodes.encode(m.item) == c, "re-encodes the same")
	return m


func test_loose_head_with_gems() -> void:
	var head := PartRoller.from_seed(99, P.HEAD, "rare", E.WATER)
	var plain := ItemCodes.encode(head)
	check(plain.begins_with("EM1-"), "no gems -> EM1")
	head.gems = [ElementGem.make(E.FIRE), ElementGem.make(E.DARK)] as Array[ElementGem]
	check(ItemCodes.encode(head).begins_with("EM2-"), "gems -> EM2")
	var m := _rt(head)
	var h := m.item as WieldablePart
	check(
		h.gems.size() == 2 and h.gems[0].element == E.FIRE and h.gems[1].element == E.DARK,
		"gems back in order"
	)
	check(ItemCodes.same_item(h, head), "same item")


func test_assembled_staff_keeps_gems_and_stats() -> void:
	var head := PartRoller.from_seed(99, P.HEAD, "rare", E.WATER)
	head.gems = [ElementGem.make(E.FIRE)] as Array[ElementGem]
	var w := Assembly.assemble(
		WieldableInstance.load_base("apprentice_fire_staff").def,
		[
			head,
			PartRoller.from_seed(1, P.EXTERIOR, "rare", E.FIRE),
			PartRoller.from_seed(2, P.INTERIOR, "rare", E.FIRE),
			WieldablePart.load_part("basic_handle").duplicate()
		]
	)
	check(w != null, "built")
	var m := _rt(w)
	var w2 := m.item as WieldableInstance
	check(w2.element() == E.FIRE, "gem element wins after decode")
	check_near(w2.damage(), w.damage(), 1e-6, "damage incl. gem bonus")


func test_consecrated_equipment() -> void:
	var e := EquipmentRoller.from_seed(9, S.HAT, "rare", E.FIRE)
	var code1 := ItemCodes.encode(e)
	e.consecration = "kindling"
	var m := _rt(e)
	check((m.item as EquipmentItem).consecration == "kindling", "rolled keeps consecration")
	var t := EquipmentItem.load_item("traveler_shoes").duplicate() as EquipmentItem
	t.consecration = "fleetfoot"
	check((_rt(t).item as EquipmentItem).consecration == "fleetfoot", "template keeps consecration")
	e.consecration = ""
	check(ItemCodes.encode(e) == code1, "removing it gives the old EM1 code back")
	e.consecration = "nonsense"
	check(ItemCodes.encode(e).is_empty(), "unknown consecration refused")


func test_loose_gem_and_old_codes() -> void:
	var m := _rt(ElementGem.make(E.LIGHT))
	check(m.item is ElementGem and (m.item as ElementGem).element == E.LIGHT, "gem item")
	for c in [
		"EM1-0M08G-1G7ZX-R7FX8",
		"EM1-0R18G-00002-CFKSR",
		"EM1-0J042-1MB00-000AH-075AG",
		"EM1-0W431-XQP"
	]:
		check(ItemCodes.decode(c).ok(), "golden v1 still decodes: %s" % c)
	var good := ItemCodes.encode(EquipmentRoller.from_seed(1, S.BELT, "rare", E.FIRE))
	check(
		not ItemCodes.decode("EM2-" + good.substr(4)).ok(), "EM2 prefix on a flagless code rejected"
	)


func test_save_keeps_gems_and_consecrations() -> void:
	var w := Node3D.new()
	w.position = Vector3(0, 1000, 4300)
	runner_tree.root.add_child(w)
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	var head := PartRoller.from_seed(5, P.HEAD, "primordial", E.AIR)
	head.gems = [ElementGem.make(E.EARTH)] as Array[ElementGem]
	p.inventory.add(head)
	p.inventory.add(ElementGem.make(E.WATER))
	var hat := EquipmentRoller.from_seed(4, S.HAT, "mythic", E.FIRE)
	hat.consecration = "reaping"
	p.equip_item(hat)
	var data := SaveGame.capture(p)
	var q: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	q.input_enabled = false
	w.add_child(q)
	q.spawn(w.global_position + Vector3(5, 0, 0), 0.0)
	var warn := SaveGame.apply(q, JSON.parse_string(JSON.stringify(data)))
	check(warn.is_empty(), "no warnings: %s" % [warn])
	var heads := q.inventory.items.filter(func(i): return i is WieldablePart)
	var gems := q.inventory.items.filter(func(i): return i is ElementGem)
	check(heads.size() == 1 and (heads[0] as WieldablePart).gems.size() == 1, "head gem saved")
	check(gems.size() == 1 and (gems[0] as ElementGem).element == E.WATER, "loose gem saved")
	check(q.equipment.item(S.HAT).consecration == "reaping", "consecration saved")
	check(q.consecrations.has("reaping"), "consecration active after load")
	w.queue_free()
