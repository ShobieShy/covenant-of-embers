extends TestCase
## 0.3.1 P4: chip bar math, heartbeat vignette, pickup magnet arc, rarity pickup sounds,
## pickup toasts, level-up banner / skill badge, damage-number merge and crit pop.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"


func _setup() -> Array:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(Vector3(0, 200, 1500), 0.0)
	var hud := Hud.new()
	runner_tree.root.add_child(hud)
	hud.bind(p)
	return [p, hud]


func test_chip_trails_then_drains() -> void:
	var c := HudFx.Chip.new()
	c.step(1.0, 0.0)
	c.step(0.6, DT)
	check_near(c.shown, 0.6, 1e-6, "a drop snaps the fill")
	check_near(c.chip, 1.0, 1e-6, "the chip stays behind")
	var t := 0.0
	while t < HudFx.CHIP_HOLD - 0.05:
		c.step(0.6, DT)
		t += DT
	check_near(c.chip, 1.0, 1e-6, "held for CHIP_HOLD")
	for i in 120:
		c.step(0.6, DT)
	check_near(c.chip, 0.6, 1e-6, "drained down to the fill")
	c.step(0.9, DT)
	check(c.shown > 0.6 and c.shown < 0.9, "a rise eases up: %.3f" % c.shown)
	check_near(c.chip, c.shown, 1e-6, "the chip rides a rise")
	for i in 60:
		c.step(0.9, DT)
	check_near(c.shown, 0.9, 1e-6, "the rise lands")
	c.step(0.2, 0.0)
	check_near(c.shown, 0.2, 1e-6, "dt 0 still snaps")


func test_heartbeat() -> void:
	check(HudFx.heartbeat(0.5, 0.3) == 0.0, "healthy: none")
	check(HudFx.heartbeat(0.0, 0.3) == 0.0, "dead: none")
	var lo := 0.0
	var hi := 0.0
	for i in 120:
		var a := HudFx.heartbeat(0.1, i / 60.0)
		lo = minf(lo if i > 0 else a, a)
		hi = maxf(hi, a)
	check(hi > lo + 0.1, "it beats: %.2f..%.2f" % [lo, hi])
	check(hi <= HudFx.VIGNETTE_MAX + 1e-6, "capped")
	check(
		HudFx.heartbeat(0.05, 0.0, true) == HudFx.heartbeat(0.05, 0.4, true),
		"steady under reduced motion"
	)
	check(HudFx.heartbeat(0.05, 0.0, true) > HudFx.heartbeat(0.25, 0.0, true), "stronger lower")


func test_hud_chip_and_vignette() -> void:
	var s := _setup()
	var p: Player = s[0]
	var hud: Hud = s[1]
	p.health.value = p.health.max_value() * 0.2
	hud.refresh(DT)
	var r: ColorRect = hud.chip_rects[hud.health_bar]
	check(r.visible and r.size.x > 50.0, "chip segment drawn: %.0f px" % r.size.x)
	check_near(r.position.x, 0.2 * Hud.BAR_SIZE.x, 1.0, "chip starts at the fill")
	check(hud.vignette.visible, "low health: vignette on")
	p.health.value = p.health.max_value()
	for i in 90:
		hud.refresh(DT)
	check(not r.visible and not hud.vignette.visible, "healed: chip and vignette gone")
	hud.free()
	p.free()


func test_magnet_arc() -> void:
	var a := Vector3.ZERO
	var b := Vector3(3, 0, 0)
	check(LootPickup.magnet_point(a, b, 0.0).is_equal_approx(a), "starts at the drop")
	check(LootPickup.magnet_point(a, b, 1.0).is_equal_approx(b), "ends at the feet")
	check_near(
		LootPickup.magnet_point(a, b, 0.5).y, LootPickup.MAGNET_ARC, 1e-6, "hop peaks halfway"
	)
	var s := _setup()
	var p: Player = s[0]
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	var g := LootPickup.create_gold(5, p.global_position + Vector3(2.5, 0, 0))
	w.add_child(g)
	var gold := p.inventory.gold
	for i in 60:
		p.pickups.tick(p, false, DT)
	check(p.inventory.gold == gold + 5, "gold flew in and was taken")
	p.mana.refill()
	var orb := LootPickup.create_mana(5, p.global_position + Vector3(2.5, 0, 0))
	w.add_child(orb)
	var at := orb.global_position
	for i in 30:
		p.pickups.tick(p, false, DT)
	check(orb.global_position.is_equal_approx(at), "full mana: the orb stays put")
	w.free()
	s[1].free()
	p.free()


func test_pickup_sound_and_toast() -> void:
	var d := LootDrop.new()
	d.rarity_id = "mythic"
	var lp := LootPickup.create(d, Vector3.ZERO)
	check(GameAudio.pickup_key(lp, "item") == "pickup_mythic", "rarity sound")
	check(GameAudio.pickup_key(lp, "gold") == "pickup", "walk-over blip")
	for t in Rarity.IDS:
		check(ResourceLoader.exists(GameAudio.SOUNDS["pickup_" + t]), "%s sound exists" % t)
	check(ResourceLoader.exists(GameAudio.SOUNDS["level_up"]), "level_up exists")
	lp.free()
	var s := _setup()
	var hud: Hud = s[1]
	for i in 3:
		hud.add_toast("+5 Gold", Color.YELLOW)
	check(hud.toasts.size() == 1 and hud.toasts[0]["count"] == 3, "repeats count up")
	for i in Hud.TOAST_MAX + 2:
		hud.add_toast("Item %d" % i)
	check(hud.toasts.size() == Hud.TOAST_MAX, "stack capped")
	for i in int(Hud.TOAST_S / DT) + 2:
		hud.refresh(DT)
	check(hud.toasts.is_empty(), "toasts expire")
	hud.free()
	s[0].free()


func test_level_up_and_badge() -> void:
	var s := _setup()
	var p: Player = s[0]
	var hud: Hud = s[1]
	p.progression.add_xp(p.progression.xp_to_next)
	hud.refresh(DT)
	check(hud.level_ups == 1 and hud.level_banner.visible, "banner up")
	check(
		hud.level_banner.text == "Level %d!" % p.progression.level, "'%s'" % hud.level_banner.text
	)
	var n := p.skills.available(p.progression.level)
	check(hud.skill_badge.visible == (n > 0), "badge follows unspent points (%d)" % n)
	for i in int(Hud.LEVEL_BANNER_S / DT) + 2:
		hud.refresh(DT)
	check(not hud.level_banner.visible, "banner goes")
	check(Hud.skill_badge_text(1).contains("1 skill point "), "singular")
	check(
		PauseMenu.skills_label(0) == "Skills" and PauseMenu.skills_label(2).contains("2"),
		"pause entry"
	)
	check(PauseMenu.skills_label(15) == "Skills\u00a0◆ 15", "QA r12: a gap before the ◆")
	hud.free()
	p.free()


func test_damage_numbers_merge_and_pop() -> void:
	var dn := DamageNumbers.new()
	dn.auto_tick = false
	dn.draw_labels = false
	var foe := Node.new()
	var r := Damage.Result.new()
	r.amount = 10.0
	var a := dn.add(Vector3.ZERO, r, ElementTable.Element.FIRE, foe)
	dn.tick(0.1)
	var b := dn.add(Vector3.ZERO, r, ElementTable.Element.FIRE, foe)
	check(a == b and dn.numbers.size() == 1, "merged inside MERGE_S")
	check_near(a.amount, 20.0, 1e-6, "amounts add")
	check(a.hits == 2 and a.pop_age == 0.0, "re-popped")
	check_near(a.age, 0.1, 1e-6, "QA r12: a merge keeps the age (it keeps rising)")
	dn.tick(DamageNumbers.MERGE_S + 0.05)
	var c := dn.add(Vector3.ZERO, r, ElementTable.Element.FIRE, foe)
	check(c != a and c.stack == 1, "later hit stacks above")
	check(DamageNumbers.position_of(c).y > DamageNumbers.position_of(a).y - 0.5, "stacked up")
	var other := dn.add(Vector3.ZERO, r, ElementTable.Element.FIRE, Node.new())
	check(other.stack == 0, "other targets do not stack")
	var cr := Damage.Result.new()
	cr.amount = 5.0
	cr.crit = 2.0
	var k := dn.add(Vector3.ZERO, cr, ElementTable.Element.FIRE)
	check_near(DamageNumbers.pop_scale(k), 1.0 + DamageNumbers.CRIT_POP, 1e-6, "crit pops")
	dn.tick(DamageNumbers.POP_S)
	check_near(DamageNumbers.pop_scale(k), 1.0, 1e-6, "pop settles")
	var x := dn.add(Vector3.ZERO, r, ElementTable.Element.FIRE)
	var y := dn.add(Vector3.ZERO, r, ElementTable.Element.FIRE)
	check(x != y, "no target: never merges")
	other.target.free()
	foe.free()
	dn.free()


## QA r12: under constant fire (a hit every 0.05 s) a number still rises and expires on
## its LIFETIME; the later hits start new numbers instead of holding one in place.
func test_damage_number_under_constant_fire_rises() -> void:
	var dn := DamageNumbers.new()
	dn.auto_tick = false
	dn.draw_labels = false
	var foe := Node.new()
	var r := Damage.Result.new()
	r.amount = 1.0
	var first := dn.add(Vector3.ZERO, r, ElementTable.Element.FIRE, foe)
	var y0 := DamageNumbers.position_of(first).y
	for i in 12:
		dn.tick(0.05)
		dn.add(Vector3.ZERO, r, ElementTable.Element.FIRE, foe)
	check(DamageNumbers.position_of(first).y > y0 + 0.2, "the first number rose")
	check(first.hits < 13, "merging stopped after MERGE_S (%d hits)" % first.hits)
	for i in 30:
		dn.tick(0.05)
	check(not dn.numbers.has(first), "gone after its LIFETIME")
	foe.free()
	dn.free()
