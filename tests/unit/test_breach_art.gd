extends TestCase
## Step 125 (Art A7): Scorchling gets a procedural imp body under budget, the Warden gets rune
## eyes, gnawers draw from the rat variants, and the Breach is dressed.


func test_scorchling_body() -> void:
	var m := EnemyModels.make("scorchling", 0.8)
	check(m != null, "scorchling has a body")
	var b := m.find_child("Scorchling", true, false) as ScorchlingBody
	check(b != null and b.flame != null and b.light != null, "flame + light")
	var t := ScorchlingBody.tris(b)
	check(t > 50 and t < 1500, "scorchling tris %d under budget" % t)
	m.free()


func test_warden_eyes_and_rats() -> void:
	var w := EnemyModels.make("breach_warden", 2.8)
	check(w != null and w.find_child("WardenEye*", true, false) != null, "warden glow")
	w.free()
	for _i in 6:
		var g := EnemyModels.make("gnawer", 0.6)
		check(g != null, "gnawer variant loads")
		g.free()


func test_breach_dressed() -> void:
	var l: Node3D = (load("res://scenes/levels/breach.tscn") as PackedScene).instantiate()
	var n := 0
	for c in l.find_children("*", "", true, false):
		if String(c.name).begins_with("rubble_") or String(c.name).begins_with("breach_"):
			n += 1
	check(n >= 16, "breach has %d props" % n)
	l.free()
