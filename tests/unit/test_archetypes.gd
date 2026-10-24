extends TestCase
## Step 73 done check: archetypes (Nerd / Gal / Buff / Loli) + name and colour.
##  - each perk lands through apply_bonuses (Buff +20 health, Nerd +15 mana, Loli +8% speed,
##    Gal -10% vendor buy price); switching archetype removes the old perk;
##  - names are cleaned; the pick, name and colour round-trip through SaveGame and the
##    portable character file; old saves default to Nerd / "Ember";
##  - the co-op pose carries the colour and RemotePlayer paints it.

const PLAYER_SCENE := "res://scenes/player/player.tscn"


func _player(at: Vector3) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(at, 0.0)
	return p


func test_perks() -> void:
	var p := _player(Vector3(9000, 0, 0))
	p.set_character("nerd", "A")
	var hp: float = p.health.max_value()
	var mp := p.mana.max_value()
	p.set_character("buff", "A")
	check(is_equal_approx(p.health.max_value(), hp + 20.0), "Buff +20 health (%s -> %s)" % [hp, p.health.max_value()])
	check(is_equal_approx(p.mana.max_value(), mp - 15.0), "leaving Nerd drops its +15 mana")
	p.set_character("nerd", "A")
	check(is_equal_approx(p.health.max_value(), hp), "Buff perk removed")
	check(Archetype.discounted(100, "gal") == 90 and Archetype.discounted(100, "buff") == 100, "Gal discount")
	check(Archetype.discounted(1, "gal") == 1, "price never below 1")
	check(float(Archetype.perks("loli").get("speed_pct", 0)) == 8.0, "Loli speed perk")
	p.queue_free()


func test_gal_buys_cheaper() -> void:
	var p := _player(Vector3(9300, 0, 0))
	p.set_character("gal", "G")
	var v := Vendor.for_speaker("Potion Merchant")
	v.restock(7)
	var price: int = v.stock[2]["price"]
	var cut := Archetype.discounted(price, "gal")
	p.inventory.gold = cut
	check(cut < price, "discount bites (%d -> %d)" % [price, cut])
	check(v.buy(p, 2) == "", "Gal affords it at the discounted price")
	check(p.inventory.gold == 0, "paid %d (%d left)" % [cut, p.inventory.gold])
	p.queue_free()


func test_names() -> void:
	check(Archetype.clean_name("  Zed  ") == "Zed", "trimmed")
	check(Archetype.clean_name("") == "Ember", "empty -> Ember")
	check(Archetype.clean_name("x".repeat(40)).length() == Archetype.NAME_MAX, "capped")
	check(Archetype.valid("bogus") == "" and Archetype.perks("").is_empty(), "unknown -> no archetype")


func test_save_round_trip() -> void:
	var a := _player(Vector3(9600, 0, 0))
	a.set_character("loli", "Pip", Color(0.2, 0.4, 0.6))
	var d := SaveGame.capture(a, {})
	var b := _player(Vector3(9900, 0, 0))
	SaveGame.apply(b, d)
	check(b.archetype == "loli" and b.character_name == "Pip", "pick + name restored")
	check(b.character_color.is_equal_approx(Color(0.2, 0.4, 0.6)), "colour restored")
	var old := d.duplicate(true)
	for k in ["archetype", "name", "color"]:
		(old["player"] as Dictionary).erase(k)
	SaveGame.apply(b, old)
	check(b.archetype == "" and b.character_name == "Ember", "old save defaults (no perk)")
	# Portable co-op character carries the same fields.
	var path := CharacterSave.path_for("arch_test")
	check(CharacterSave.write(a, path) == OK, "character written")
	var c := _player(Vector3(10200, 0, 0))
	CharacterSave.load_into(c, path)
	check(c.archetype == "loli" and c.character_name == "Pip", "character file carries pick + name")
	check(c.character_color.is_equal_approx(a.character_color), "character file carries colour")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for p in [a, b, c]:
		p.queue_free()
	await runner_tree.process_frame


func test_remote_colour() -> void:
	var r := RemotePlayer.new()
	r.position = Vector3(10500, 0, 0)
	runner_tree.root.add_child(r)
	r.apply_pose({"p": Vector3(10500, 0, 0), "y": 0.0, "n": "Pip", "c": "336699"})
	check(r.color.is_equal_approx(Color.from_string("336699", Color.WHITE)), "remote colour applied")
	check(r.display_name == "Pip", "remote name")
	r.queue_free()
	await runner_tree.process_frame


func test_args() -> void:
	var d := GameFlow.identity_from_args(["--archetype", "buff", "--char-name", "Bo", "--color", "#ff0000"])
	check(d["archetype"] == "buff" and d["name"] == "Bo" and (d["color"] as Color).is_equal_approx(Color.RED), "args")
