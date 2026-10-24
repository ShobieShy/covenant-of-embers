extends TestCase
## Step 35 done check: the vault chest's guaranteed boss loot.
##  - 1000 seeds: every chest holds 2 parts + 1 equipment piece, each >= the Rare floor
##    (and a higher floor holds too); the floor only raises (some rolls land above it);
##  - the Breach places a locked chest at the vault spawn; it won't open before the boss
##    dies, opens once after, and spills its drops as pickups through a LootDropper.

const SCENE := "res://scenes/levels/breach.tscn"
const E := ElementTable.Element

func test_floor_across_1000_seeds() -> void:
	var floor_t := Rarity.parse("rare")
	var bad := 0
	var above := 0
	var count_bad := 0
	for s in 1000:
		var r := RandomNumberGenerator.new()
		r.seed = s
		var drops := VaultChest.roll_contents(r)
		if drops.size() != 3 or drops[2].kind != LootDrop.Kind.EQUIPMENT or drops[2].item == null:
			count_bad += 1
		for d in drops:
			if Rarity.parse(d.rarity_id) < floor_t:
				bad += 1
			elif Rarity.parse(d.rarity_id) > floor_t:
				above += 1
	check(count_bad == 0, "2 parts + 1 equipment every time (%d bad)" % count_bad)
	check(bad == 0, "nothing below Rare (%d)" % bad)
	check(above > 0, "some rolls above the floor (%d)" % above)
	var r2 := RandomNumberGenerator.new()
	var low := 0
	for s in 200:
		r2.seed = 5000 + s
		for d in VaultChest.roll_contents(r2, "mythic"):
			if Rarity.parse(d.rarity_id) < Rarity.parse("mythic"):
				low += 1
	check(low == 0, "a Mythic floor holds")

func test_chest_opens_after_boss() -> void:
	var w := Node3D.new()
	w.position = Vector3(0, 700, 3000)
	runner_tree.root.add_child(w)
	var level: Node3D = (load(SCENE) as PackedScene).instantiate()
	w.add_child(level)
	var br := Breach.new()
	w.add_child(br)
	br.setup(level)
	var ch := br.chest
	check(ch != null and ch.locked, "a locked chest")
	check(ch.global_position.distance_to((level.get_node("WaveSpawns/vault_chest") as Node3D).global_position) < 0.01, "at the vault spawn")
	var dr := LootDropper.new()
	dr.parent = w
	w.add_child(dr)
	dr.parent = w
	ch.dropper = dr
	ch.rng.seed = 7
	check(ch.open_chest().is_empty() and not ch.is_open, "won't open before the boss")
	var b := Enemy.create(EnemyTable.load_default().find("breach_warden"), Transform3D(Basis.IDENTITY, Vector3(0, 0, -7)))
	b.auto_tick = false
	w.add_child(b)
	var before := dr.spawned
	b.apply_damage(1000.0, E.FIRE)
	check(not ch.locked, "the boss death unlocks it")
	var drops := ch.open_chest()
	check(drops.size() == 3 and ch.is_open, "opens with 3 drops")
	check(dr.spawned - before >= 3, "pickups spawned (%d)" % (dr.spawned - before))
	check(ch.open_chest().is_empty(), "opens once")
	for d in drops:
		check(d.element == E.DARK, "boss affinity element (%s)" % d.element)
	w.free()
