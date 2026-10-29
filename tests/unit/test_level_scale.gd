extends TestCase
## 0.3.2 S1–S3: curves, clamps, same-level hits, offsets, normalise round trip,
## loot/XP level, boss phase fraction.


func test_curves_identity_and_caps() -> void:
	for curve in LevelScale.CURVES:
		check_near(LevelScale.mult(curve, 0), 1.0, 1e-6, curve + " dL 0")
		if LevelScale.CURVES[curve].has("growth"):
			var cap := float(LevelScale.CURVES[curve]["cap"])
			var span := LevelScale.mult(curve, LevelScale.MAX_LEVEL - 1)
			check(span <= cap + 1e-6, "%s cap at 1..50 (%f > %f)" % [curve, span, cap])
			check(span > 1.0, curve + " grows")
	check_near(LevelScale.player_dmg_mult(1), 1.0, 1e-6, "level 1 spells")
	check_near(LevelScale.player_dmg_mult(50), LevelScale.mult("hp", 49), 1e-6, "player follows hp")
	check(LevelScale.resist_of(0.0, 0) == 0.0, "resist dL 0")
	check(LevelScale.resist_of(0.5, 100) <= Damage.RESIST_CAP, "resist stays under 60%")
	check_near(LevelScale.resist_of(0.0, 10), 0.05, 1e-6, "+0.5%/level")


func test_effective_level_rules() -> void:
	check(LevelScale.effective(0, 0, 5, true) == 0, "scaling off")
	check(LevelScale.effective(1, 0, 5, true) == 5, "solo zone floor")
	check(LevelScale.effective(30, 0, 5, true) == 30, "solo scales up")
	check(LevelScale.effective(1, 0, 5, false) == 1, "co-op level 1 sees level 1")
	check(LevelScale.effective(50, LevelScale.ELITE_OFFSET, 1, false) == 50, "clamp 50")
	check(LevelScale.effective(49, LevelScale.ELITE_OFFSET, 1, false) == 50, "elite +1")
	check(LevelScale.effective(40, LevelScale.BOSS_OFFSET, 1, false) == 42, "boss +2")
	check(LevelScale.labyrinth_offset(1) == 0, "floor 1 +0")
	check(LevelScale.labyrinth_offset(5) == 2, "king +2")
	check(LevelScale.effective(1, LevelScale.labyrinth_offset(5), 12, true) == 12, "solo king stays on the band")
	check(LevelScale.effective(40, LevelScale.labyrinth_offset(5), 12, true) == 42, "solo king scales up")


func test_same_level_hits_match_across_levels() -> void:
	# L0 authored stats. Player damage uses the hp curve; enemy hp uses hp curve vs L0.
	var base_hp := 100.0
	var spell := 10.0
	var l0 := 8
	var hits := []
	for lv in [8, 14, 20]:
		var d_l := int(lv) - l0
		var hp := base_hp * LevelScale.mult("hp", d_l)
		var dmg := spell * LevelScale.player_dmg_mult(lv)
		hits.append(hp / dmg)
	check_near(hits[0], hits[1], 0.02, "hits 8 vs 14")
	check_near(hits[1], hits[2], 0.02, "hits 14 vs 20")
	check(LevelScale.mult("hp", 49) <= float(LevelScale.CURVES["hp"]["cap"]) + 1e-6, "hp cap binds by 50")
	# At L0 the enemy pool matches today; the spell term is the only change, and at
	# level 1 (L0 1) it is 1 so hits equal the unscaled number.
	var raw := base_hp / spell
	var at_one := (base_hp * LevelScale.mult("hp", 0)) / (spell * LevelScale.player_dmg_mult(1))
	check_near(at_one, raw, 1e-6, "L0 1 hits match today")


func test_normalise_round_trip() -> void:
	var spell := 25.0
	var level := 30
	var l0 := 4
	var local := spell * LevelScale.player_dmg_mult(level)
	var d_l := level - l0
	var norm := LevelScale.normalise(local, d_l)
	var shown := norm * LevelScale.mult("hp", d_l)
	check_near(shown, local, 1e-4, "level 30 hit shown back at level 30")
	var base_hp := 80.0
	var frac := norm / base_hp
	var bar := frac * (base_hp * LevelScale.mult("hp", d_l))
	check_near(bar, local, 1e-3, "shared fraction matches the local hit")


func test_enemy_l0_health_unchanged_and_scales() -> void:
	var d := EnemyTable.load_default().find("gnawer")
	var e := Enemy.create(d)
	check(e != null and d != null, "gnawer spawns")
	check_near(e.max_health(), d.max_health, 0.01, "no viewer: authored hp")
	LevelScale.bind(d.level, true)
	e.apply_level_scale()
	check_near(e.max_health(), d.max_health, 0.01, "at L0 hp is today's")
	LevelScale.bind(d.level + 10, true)
	e.apply_level_scale()
	var want := d.max_health * LevelScale.mult("hp", 10)
	check_near(e.max_health(), want, 0.05, "ten levels up")
	var frac_hp := e.health
	check_near(frac_hp, want, 0.05, "full bar after scale up")
	LevelScale.bind(0, true)


func test_xp_and_gold_follow_local_level() -> void:
	var d := EnemyTable.load_default().find("gnawer")
	var e := Enemy.create(d)
	check(e != null, "gnawer")
	LevelScale.bind(1, true)
	check(e.level() == d.level, "loot level stays authored under the floor")
	LevelScale.bind(20, true)
	check(e.level() == 20, "loot level follows the player")
	var xp := int(round(d.xp_reward * LevelScale.mult("xp", e.combat_level(20) - d.level)))
	check(xp > d.xp_reward, "xp grows")
	check(xp <= int(d.xp_reward * LevelScale.CURVES["xp"]["cap"]) + 1, "xp cap")
	var gold := LevelScale.gold_amount(d, 20)
	check(gold == 3 * 20, "default gold is 3 x level")
	d.gold_drop = 4
	check(LevelScale.gold_amount(d, d.level) == 4, "authored gold at L0")
	LevelScale.bind(0, true)


func test_boss_phase_fraction_is_level_invariant() -> void:
	var d := EnemyTable.load_default().find("the_filth")
	for lv in [1, 25, 50]:
		LevelScale.bind(lv, true)
		var e := Enemy.create(d) as Filth
		e.apply_level_scale()
		e.health = e.max_health() * 0.4
		e.apply_damage(0.0, ElementTable.Element.FIRE)
		check(e.phase == 2, "phase 2 at 40%% regardless of level %d (phase %d)" % [lv, e.phase])
		e.free()
	LevelScale.bind(0, true)
