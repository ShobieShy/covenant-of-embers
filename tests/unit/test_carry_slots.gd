extends TestCase
## 0.8.4: keys 3 and 4 draw two extra wieldable slots. Save version stays 1, and a save
## from before those slots still loads.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"


func _player() -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(Vector3(0, 60, 2600), 0.0)
	return p


func test_four_slots_and_keys() -> void:
	var p := _player()
	check(p.loadout.casters.size() == 4, "four slots")
	check(InputMap.has_action(&"slot_3") and InputMap.has_action(&"slot_4"), "keys bound")
	var staff := WieldableInstance.load_base("apprentice_fire_staff")
	var wand := WieldableInstance.load_base("swift_wind_wand")
	var extra := WieldableInstance.load_base("earthward_battlestaff")
	var fourth := WieldableInstance.load_base("novice_arcane_wand")
	p.equip(staff)
	p.equip(wand)
	p.inventory.add(extra)
	p.inventory.add(fourth)
	check(p.equip_from_inventory(extra) and p.loadout.wieldable(Loadout.Slot.CARRY_3) == extra, "third weapon is carry")
	check(p.loadout.wieldable(Loadout.Slot.STAFF) == staff, "the staff slot was not replaced")
	check(p.equip_from_inventory(fourth) and p.loadout.wieldable(Loadout.Slot.CARRY_4) == fourth, "fourth weapon")
	p.tick(PlayerInput.hold([], [&"slot_3"]), DT)
	check(p.loadout.active == Loadout.Slot.CARRY_3 and p.loadout.swapping(), "key 3 draws it")
	for i in 30:
		p.tick(PlayerInput.hold(), DT)
	p.tick(PlayerInput.hold([], [&"slot_4"]), DT)
	check(p.loadout.active == Loadout.Slot.CARRY_4, "key 4 draws the last slot")
	for i in 30:
		p.tick(PlayerInput.hold(), DT)
	check(p.loadout.cycle(1) and p.loadout.active == Loadout.Slot.STAFF, "wheel wraps to the staff")
	var hud := Hud.new()
	runner_tree.root.add_child(hud)
	hud.bind(p)
	hud.refresh(DT)
	check(hud.slot_icons.size() == 4, "HUD shows four slots")
	check(hud.slot_icons[2].color.is_equal_approx(extra.rarity_color()), "carry slot tint")
	hud.free()
	p.free()


func test_save_version_stays_1() -> void:
	var p := _player()
	var staff := WieldableInstance.load_base("apprentice_fire_staff")
	var extra := WieldableInstance.load_base("earthward_battlestaff")
	p.equip(staff)
	p.inventory.add(extra)
	p.equip_from_inventory(extra)
	var data := SaveGame.capture(p)
	check(int(data["version"]) == SaveGame.VERSION and SaveGame.VERSION == 1, "save version 1")
	var carry: Array = data["items"]["carry"]
	check(carry.size() == 2 and not String(carry[0]).is_empty() and String(carry[1]).is_empty(), "carry codes")
	var q := _player()
	SaveGame.apply(q, data)
	check(ItemCodes.same_item(q.loadout.wieldable(Loadout.Slot.STAFF), staff), "staff restored")
	check(ItemCodes.same_item(q.loadout.wieldable(Loadout.Slot.CARRY_3), extra), "carry restored")
	# A save from before the extra slots has no key. A fresh player stays empty there.
	data["items"].erase("carry")
	var old := _player()
	SaveGame.apply(old, data)
	check(old.loadout.wieldable(Loadout.Slot.CARRY_3) == null, "old save leaves carry empty")
	check(ItemCodes.same_item(old.loadout.wieldable(Loadout.Slot.STAFF), staff), "old save still has the staff")
	p.free()
	q.free()
	old.free()
