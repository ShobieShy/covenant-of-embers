extends TestCase
## 0.8.9: a story boss opens the Abyss, beating it opens Endless Descent, and a
## forced deep drop does not change the kill rng.


func test_abyss_then_endless() -> void:
	var s := LabyrinthState.fresh(9)
	check(not Descent.abyss_open(s, "warrens"), "the King is still up")
	check(not Descent.finish_abyss(s, "warrens"), "no Abyss before the story boss")
	s.defeat_boss("goblin_king")
	check(Descent.abyss_open(s, "warrens") and not Descent.endless_open(s, "warrens"), "the Abyss is open")
	check(Descent.finish_abyss(s, "warrens"), "the finite replay can be beaten")
	check(Descent.endless_open(s, "warrens"), "Endless Descent opens after the Abyss")
	check(not Descent.finish_abyss(s, "warrens"), "the Abyss is not beaten twice")
	var a := Descent.endless_floor(s, "warrens", 2)
	var b := Descent.endless_floor(s, "warrens", 3)
	check(a.get("rooms", []).size() > 0 and a["seed"] != b["seed"], "deeper floors change the seed")
	check(int(a["tier_cap"]) == 2 and Descent.set_tier(2, 9) == 2, "the dial stops at the depth cap")
	check(Descent.set_tier(2, 0) == 0, "tier 0 is still allowed")
	var before := s.floor_seed(1)
	s.clear_floor(1)
	check(s.remix(1) and s.floor_seed(1) != before, "remix still changes a cleared floor")


func test_deep_drop_keeps_the_kill_rng() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	DeepGear.chance = 0.0
	DropRoller.roll_kill(rng, "gnawer", 4, 0)
	var quiet := rng.state
	rng.seed = 99
	DeepGear.chance = 1.0
	var loud := DropRoller.roll_kill(rng, "gnawer", 4, 0)
	check(rng.state == quiet, "the deep drop does not draw on the kill rng")
	var found := false
	for d in loud:
		if d.item is WieldablePart and (d.item as WieldablePart).id == DeepGear.PART:
			found = true
			check(int(d.item.get_meta(&"story_level")) == 4, "scaled to the story floor")
			check(String(NamedUniques.DEFS[DeepGear.PART]["effect"]) == "leech", "the effect stays")
	check(found, "a forced chance drops the deep part")
	var other := RandomNumberGenerator.new()
	other.seed = 100
	var alt := DeepGear.roll(other.state, 4, 1.0)
	var same := DeepGear.roll(rng.state, 4, 1.0)
	check(alt != null and same != null, "each stream can roll")
	check(
		int(alt.item.get_meta(&"source_tier")) != int(same.item.get_meta(&"source_tier")) or alt.item != same.item,
		"two states are not one shared roll"
	)
	DeepGear.chance = 0.0
	PostClear.tier = 0
	check(is_equal_approx(PostClear.scale_damage(10.0), 10.0), "tier 0 damage is unchanged")
