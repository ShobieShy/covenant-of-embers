extends TestCase
## Step 124 (Art A6): outdoor levels use the procedural sky (night preset drops it), the
## Landfill is dressed with trash props, the Association has reading benches, town ground is darker.


func _lvl(id: String) -> Node3D:
	return (load("res://scenes/levels/%s.tscn" % id) as PackedScene).instantiate()


func test_outdoor_sky_and_night() -> void:
	for id: String in ["town_square", "midden", "breach"]:
		var l := _lvl(id)
		var env := (l.get_node("WorldEnvironment") as WorldEnvironment).environment
		check(env.background_mode == Environment.BG_SKY and env.sky != null, "%s has a sky" % id)
		NightPreset.apply(l, Vector3.ZERO)
		var night := (l.get_node("WorldEnvironment") as WorldEnvironment).environment
		check(night.background_mode == Environment.BG_COLOR, "%s night drops the sky" % id)
		l.free()


func test_dressing() -> void:
	var m := _lvl("midden")
	var trash := 0
	for c in m.get_node("Props").get_children():
		trash += 1 if c.name.begins_with("trash_") else 0
	check(trash >= 15, "landfill has %d trash props" % trash)
	m.free()
	var h := _lvl("mage_association")
	check(
		h.get_node_or_null("Props/bench_w1") != null and h.get_node_or_null("Props/dais_book") != null, "hall benches"
	)
	h.free()
	var t := _lvl("town_square")
	t.free()
	var d := LevelToml.load_file("res://data/levels/town_square.toml")
	var gc := LevelToml.color((d["box"] as Array)[0]["color"])
	check(gc.v < 0.4, "town cobble darker (v %.2f)" % gc.v)
