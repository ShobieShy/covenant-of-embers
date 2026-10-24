extends TestCase
## Step 71 done check: skill trees from data.
##  - parse + validation (unknown branch/effect, bad capstone);
##  - points: 1 per level from level 2; tier gating at 5 x tier in that branch;
##  - rank caps; capstone on the last tier; respec refunds everything;
##  - totals feed Player.apply_bonuses; ranks survive a save round trip.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

const TREE := """
[tree]
id = "t"
name = "Test"
tiers = 3

[[branch]]
id = "a"
name = "A"

[[branch]]
id = "b"
name = "B"

[[skill]]
id = "hp"
branch = "a"
tier = 0
max_rank = 5
effects = { max_health = 10 }

[[skill]]
id = "mana"
branch = "a"
tier = 1
max_rank = 5
effects = { max_mana = 4, spell_damage = 1 }

[[skill]]
id = "cap"
branch = "a"
tier = 2
max_rank = 1
capstone = true
effects = { speed_pct = 10 }

[[skill]]
id = "res"
branch = "b"
tier = 0
max_rank = 5
effects = { resist_all = 20 }
"""


func _tree() -> SkillTree:
	var r := SkillTree.from_dict(LevelToml.parse(TREE))
	check(not r.has("error"), "tree parses: %s" % r.get("error", ""))
	return r.get("tree")


func _skills() -> Skills:
	var s := Skills.new()
	s.tree = _tree()
	return s


func test_parse() -> void:
	var t := _tree()
	check(t.id == "t" and t.tiers == 3 and t.branches.size() == 2, "header + branches")
	check(t.skill("cap")["capstone"] and t.in_branch("a").size() == 3, "skills by branch")
	var bad := TREE.replace('branch = "b"', 'branch = "zz"')
	check(SkillTree.from_dict(LevelToml.parse(bad)).has("error"), "unknown branch rejected")
	bad = TREE.replace("resist_all", "wings")
	check(SkillTree.from_dict(LevelToml.parse(bad)).has("error"), "unknown effect rejected")
	bad = TREE.replace("tier = 2\nmax_rank = 1", "tier = 1\nmax_rank = 1")
	check(SkillTree.from_dict(LevelToml.parse(bad)).has("error"), "capstone off the last tier rejected")


func test_points_and_tiers() -> void:
	var s := _skills()
	check(Skills.points_for_level(1) == 0 and Skills.points_for_level(2) == 1, "first point at level 2")
	check(Skills.points_for_level(50) == 49, "one per level")
	check(not s.spend("hp", 1), "no points at level 1")
	check(s.why_not("mana", 20) != "", "tier 1 closed with 0 spent")
	for i in 5:
		check(s.spend("hp", 20), "rank %d" % (i + 1))
	check(s.why_not("hp", 20) == "max rank", "rank cap")
	check(s.tier_open("a", 1) and not s.tier_open("a", 2), "5 points open tier 1 only")
	check(not s.tier_open("b", 1), "tiers count per branch")
	for i in 4:
		s.spend("mana", 20)
	check(s.why_not("cap", 20) != "", "capstone needs 10 in branch")
	s.spend("mana", 20)
	check(s.spend("cap", 20) and s.why_not("cap", 20) == "max rank", "capstone: one rank")
	check(s.spent() == 11 and s.available(20) == 8, "points tally")
	check(s.main_branch() == "a", "main branch")
	var t := s.totals()
	check_near(t["max_health"], 50.0, 0.001, "hp 5x10")
	check_near(t["spell_damage"], 5.0, 0.001, "dmg 5x1")
	check(s.respec() == 11 and s.spent() == 0 and s.respecs == 1, "respec refunds all")
	check(s.totals().is_empty(), "no bonuses after respec")


func test_points_cap_on_level() -> void:
	var s := _skills()
	check(s.spend("hp", 3) and s.spend("hp", 3), "level 3 -> 2 points")
	check(s.why_not("hp", 3) == "no skill points", "out of points")


func test_load_sanitises() -> void:
	var s := _skills()
	var w := s.from_dict({"ranks": {"hp": 99, "ghost": 2}}, 30)
	check(s.rank("hp") == 5 and not s.ranks.has("ghost") and w.size() == 1, "clamped + dropped")
	w = s.from_dict({"ranks": {"hp": 5}}, 3)
	check(s.spent() == 0 and w.size() == 1, "over-spent refunded")


func test_player_bonuses_and_save() -> void:
	var w := Node3D.new()
	w.position = Vector3(0, 800, 3600)
	runner_tree.root.add_child(w)
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	p.skills.tree = _tree()
	while p.progression.level < 12:
		p.add_xp(p.progression.xp_to_next)
	check(p.progression.level >= 12, "levelled")
	var hp0 := p.health.max_value()
	var sp0 := p.speed_multiplier if "speed_multiplier" in p else 1.0
	for i in 5:
		check(p.spend_skill("hp"), "spend hp")
	check_near(p.health.max_value() - hp0, 50.0, 0.001, "max health +50")
	for i in 5:
		check(p.spend_skill("res"), "spend res")
	check_near(p.damage_target.resist[0], 1.0, 0.001, "resist stored raw")
	check(Damage.RESIST_CAP <= 0.6, "cap applied at hit time")
	var data := SaveGame.capture(p, {})
	check(data["player"]["skills"]["ranks"]["hp"] == 5, "ranks captured")
	var q: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	q.input_enabled = false
	w.add_child(q)
	q.skills.tree = p.skills.tree
	var warn := SaveGame.apply(q, JSON.parse_string(JSON.stringify(data)))
	check(warn.is_empty(), "no warnings: %s" % [warn])
	check(q.skills.rank("hp") == 5 and q.skills.rank("res") == 5, "ranks restored")
	check_near(q.health.max_value(), p.health.max_value(), 0.001, "same max health")
	check(p.respec_skills() == 10, "respec")
	check_near(p.health.max_value(), hp0, 0.001, "bonus gone")
	check(sp0 > 0.0, "speed ok")
	w.queue_free()


## --- Step 72 done check: the placeholder tree, kill procs, capstone, UI, loot bias ---


func test_placeholder_tree() -> void:
	var t := SkillTree.default_tree()
	check(t != null and t.id == "ember_path", "default tree loads")
	check(t.branches.size() == 3, "3 branches")
	check(t.skills.size() >= 12, "about 12 skills (%d)" % t.skills.size())
	var caps := 0
	for sid in t.skills:
		caps += 1 if t.skills[sid]["capstone"] else 0
	check(caps == 1, "one capstone")
	for b in t.branches:
		check(not (b["consecrations"] as Array).is_empty(), "branch %s biases loot" % b["id"])


func _player() -> Array:
	var w := Node3D.new()
	w.position = Vector3(0, 800, 3900)
	runner_tree.root.add_child(w)
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	while p.progression.level < 20:
		p.add_xp(p.progression.xp_to_next)
	return [w, p]


func test_kill_procs_and_capstone() -> void:
	var s := _player()
	var p: Player = s[1]
	check(p.skills.tree.id == "ember_path", "player uses the default tree")
	for sid in ["still_mind", "still_mind", "still_mind", "steady_flow", "steady_flow", "harvest", "harvest"]:
		check(p.spend_skill(sid), "spend " + sid)
	p.mana.value = 0.0
	p.skill_procs.on_kill(p)
	check_near(p.mana.value, 10.0, 0.001, "harvest 2 ranks: +10 mana per kill")
	p.respec_skills()
	for sid in [
		"kindled_focus",
		"kindled_focus",
		"kindled_focus",
		"kindled_focus",
		"kindled_focus",
		"flare",
		"flare",
		"flare",
		"flare",
		"flare",
		"quick_step",
		"quick_step",
		"quick_step",
		"quick_step",
		"quick_step"
	]:
		check(p.spend_skill(sid), "spend " + sid)
	check(p.spend_skill("wildfire"), "capstone at 15 in pyre")
	check_near(p.loadout.casters[0].damage_bonus, 15.0 + p.equipment.spell_damage_bonus(), 0.001, "flat +15")
	p.skill_procs.on_kill(p)
	p.tick(PlayerInput.new(), 1.0 / 60.0)
	check_near(p.loadout.casters[0].conditional_bonus, 8.0, 0.001, "frenzy +8")
	for i in 400:
		p.tick(PlayerInput.new(), 1.0 / 60.0)
	check_near(p.loadout.casters[0].conditional_bonus, 0.0, 0.001, "frenzy over")
	check(Consecrations.bias_for(p) == PackedStringArray(["kindling"]), "pyre biases kindling")
	s[0].queue_free()


func test_biased_consecrations() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var n := 0
	for i in 400:
		n += 1 if Consecrations.roll(r, PackedStringArray(["reaping"])) == "reaping" else 0
	check(n > 220 and n < 330, "about 62 pct reaping with bias (%d/400)" % n)
	n = 0
	for i in 400:
		n += 1 if Consecrations.roll(r) == "reaping" else 0
	check(n > 60 and n < 140, "about 25 pct without (%d/400)" % n)


func test_skills_ui() -> void:
	var s := _player()
	var p: Player = s[1]
	var ui := SkillsUi.new()
	var at_hub := [false]
	ui.can_respec = func(): return at_hub[0]
	s[0].add_child(ui)
	ui.bind(p)
	check(ui.buttons.size() == p.skills.tree.skills.size(), "a button per skill")
	check(not ui.buttons["thick_bark"].disabled and ui.buttons["second_wind"].disabled, "tier gating shown")
	check(ui.take("thick_bark") and p.skills.rank("thick_bark") == 1, "button spends")
	check(ui.respec() == -1 and p.skills.spent() == 1, "no respec away from the Old Oak")
	at_hub[0] = true
	check(ui.respec() == 1 and p.skills.spent() == 0, "respec at the Old Oak")
	ui.open()
	check(p.ui_open, "opening blocks input")
	ui.close()
	s[0].queue_free()
