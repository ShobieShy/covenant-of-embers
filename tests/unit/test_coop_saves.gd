extends TestCase
## Step 91 done check: a client's portable character persists (level, gear, skills) and
## loads into any host's game; the character file carries no world progress; character
## writes never touch a host save slot; the host's world flags are unchanged by clients.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const S := EquipmentItem.Slot
const E := ElementTable.Element

var _worlds: Array[Node3D] = []


func _free() -> void:
	for w in _worlds:
		w.queue_free()
	_worlds.clear()


func _player(z: float) -> Player:
	var w := Node3D.new()
	w.position = Vector3(9000, 5000, z)
	_worlds.append(w)
	runner_tree.root.add_child(w)
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	return p


func test_slug_and_paths() -> void:
	check(
		CharacterSave.path_for("Shobie Shy!") == "user://character_shobie_shy.json",
		CharacterSave.path_for("Shobie Shy!")
	)
	check(CharacterSave.path_for("") == "user://character_player.json", "empty name")
	check(not CharacterSave.path_for("x").begins_with(SaveGame.PATH.get_basename()), "not a save slot")


func test_character_round_trip_into_another_host() -> void:
	var path := CharacterSave.path_for("test client 91")
	var a := _player(5100)
	a.add_xp(300)
	a.equip_item(EquipmentRoller.from_seed(9, S.HAT, "rare", E.FIRE))
	a.inventory.dust = 17
	check(CharacterSave.write(a, path) == OK, "written")
	var raw := SaveGame.read(path)
	check(not raw.has("error"), "readable")
	check((raw["data"] as Dictionary)["progress"].is_empty(), "no world progress in a character")
	check(String((raw["data"] as Dictionary).get("kind", "")) == "character", "kind")
	var b := _player(5400)  # "another host's game"
	var r := CharacterSave.load_into(b, path)
	check(r.has("warnings") and (r["warnings"] as PackedStringArray).is_empty(), "loaded %s" % [r])
	check(b.progression.level == a.progression.level and b.progression.level > 1, "level kept")
	check(b.inventory.dust == 17, "dust kept")
	check(b.equipment.item(S.HAT) != null, "gear kept")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_free()


func test_never_writes_host_slot_and_host_world_unchanged() -> void:
	var host_slot := "user://test_host_world_91.json"
	var host := _player(5700)
	SaveGame.write(SaveGame.capture(host, {"level_id": "breach", "flags": {"met_bob": true}}), host_slot)
	var before := FileAccess.get_file_as_string(host_slot)
	var c := _player(6000)
	c.add_xp(500)
	check(CharacterSave.write(c, host_slot) != OK, "refuses a non-character path")
	check(CharacterSave.write(c, SaveGame.PATH) != OK, "refuses the real slot 1")
	check(FileAccess.get_file_as_string(host_slot) == before, "host world bytes unchanged")
	var hw := SaveGame.read(host_slot)
	check(bool((hw["data"] as Dictionary)["progress"]["flags"]["met_bob"]), "host flags intact")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(host_slot))
	_free()


func test_missing_character_is_fresh() -> void:
	var p := _player(6300)
	var r := CharacterSave.load_into(p, CharacterSave.path_for("nobody here 91"))
	check(r.has("error") and p.progression.level == 1, "fresh character")
	_free()
