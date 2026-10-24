extends TestCase
## Step 38 done check: save -> load round-trip equal; an old version is rejected cleanly;
## a bad item code is dropped with a warning; a save while dead stores full pools.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FILE := "user://test_save.json"
const S := EquipmentItem.Slot
const E := ElementTable.Element


func _player(w: Node3D) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	return p


func _world(z: float) -> Node3D:
	var w := Node3D.new()
	w.position = Vector3(0, 1000, z)
	runner_tree.root.add_child(w)
	return w


func test_round_trip() -> void:
	var w := _world(3900)
	var a := _player(w)
	a.add_xp(300)
	a.inventory.add(PartRoller.from_seed(16, WieldablePart.PartType.HEAD, "rare"))
	a.inventory.add(EquipmentRoller.from_seed(3, S.BELT, "mythic", E.WATER))
	a.inventory.dust = 42
	a.equip_item(EquipmentRoller.from_seed(9, S.HAT, "rare", E.FIRE))
	a.equip_item(EquipmentItem.load_item("traveler_shoes"))
	a.equipment.add_potions(ConsumableItem.load_item("health_potion"), 2)
	a.health.value = a.health.max_value() * 0.5
	a.health.shield = 10.0
	a.mana.value = 7.0
	a.breath.value = 33.0
	var data := SaveGame.capture(a, {"level_id": "breach_slice", "breach_cleared": true})
	check(SaveGame.write(data, FILE) == OK, "written")
	var r := SaveGame.read(FILE)
	check(not r.has("error"), "read back (%s)" % r.get("error", ""))
	var b := _player(_world(4200))
	var warn := SaveGame.apply(b, r["data"])
	check(warn.is_empty(), "no warnings %s" % [warn])
	check(
		b.progression.level == a.progression.level and b.progression.xp == a.progression.xp and b.progression.level > 1,
		"level/xp (%d)" % b.progression.level
	)
	check(is_equal_approx(b.mana.max_value(), a.mana.max_value()), "level bonuses rebuilt")
	check(b.inventory.items.size() == 2 and b.inventory.dust == 42, "backpack")
	for i in 2:
		check(ItemCodes.same_item(a.inventory.items[i], b.inventory.items[i]), "item %d equal" % i)
	for s in EquipmentItem.SLOT_COUNT:
		var x := a.equipment.item(s)
		var y := b.equipment.item(s)
		check((x == null and y == null) or ItemCodes.same_item(x, y), "slot %d equal" % s)
	check(b.equipment.potion != null and b.equipment.potion_count == 2, "potion stack")
	check(
		ItemCodes.same_item(a.loadout.wieldable(Loadout.Slot.STAFF), b.loadout.wieldable(Loadout.Slot.STAFF)), "staff"
	)
	check(is_equal_approx(b.health.value, a.health.value) and is_equal_approx(b.health.shield, 10.0), "health + shield")
	check(is_equal_approx(b.mana.value, 7.0) and is_equal_approx(b.breath.value, 33.0), "mana + breath")
	check(r["data"]["progress"]["breach_cleared"] == true, "progress kept")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	runner_tree.root.remove_child(w)
	w.free()
	for n in runner_tree.root.get_children():
		if n is Node3D and (n as Node3D).position == Vector3(0, 1000, 4200):
			n.free()


func test_old_version_and_bad_codes() -> void:
	var w := _world(4500)
	var p := _player(w)
	var d := SaveGame.capture(p)
	d["version"] = 0
	SaveGame.write(d, FILE)
	var r := SaveGame.read(FILE)
	check(r.has("error") and String(r["error"]).contains("version"), "old version rejected: %s" % r.get("error", ""))
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	f.store_string("not json{")
	f.close()
	check(SaveGame.read(FILE).has("error"), "garbage rejected")
	check(SaveGame.read("user://nope.json").has("error"), "missing rejected")
	d["version"] = SaveGame.VERSION
	d["items"]["inventory"] = ["GARBAGE-CODE"]
	var warn := SaveGame.apply(p, d)
	check(warn.size() == 1 and p.inventory.items.is_empty(), "bad code dropped with a warning")
	p.health.take(10000.0)
	var dd := SaveGame.capture(p)
	check(is_equal_approx(float(dd["player"]["health"]), p.health.max_value()), "dead save = full")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	w.free()
