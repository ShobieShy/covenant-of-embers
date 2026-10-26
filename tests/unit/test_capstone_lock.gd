extends TestCase
## Phase V step 144: one element capstone across all trees; others refuse with
## capstone_locked; respec unlocks them.


static func fill(s: Skills, el: String) -> void:
	var t := SkillTree.element_tree(el)
	for tier in 5:
		for sid in t.order:
			if int(t.skill(sid)["tier"]) == tier:
				while s.el_spend(el, sid, 200):
					pass


func test_lock() -> void:
	var s := Skills.new()
	s.tree = SkillTree.default_tree()
	fill(s, "fire")
	check(s.el_why_not("fire", "backdraft", 200).is_empty(), "fire capstone open after 25 + T4")
	check(s.el_spend("fire", "backdraft", 200), "take Backdraft")
	check(s.capstone_owner() == "fire", "owner fire")
	fill(s, "water")
	check(s.el_why_not("water", "tidal_hold", 200) == Skills.CAPSTONE_LOCKED, "water capstone locked")
	check(not s.el_spend("water", "tidal_hold", 200), "refused")
	s.respec()
	check(s.capstone_owner().is_empty() and s.spent() == 0, "respec clears")
	fill(s, "water")
	check(s.el_spend("water", "tidal_hold", 200), "unlocked after respec")


func test_capstone_needs_points() -> void:
	var s := Skills.new()
	s.tree = SkillTree.default_tree()
	check(
		s.el_why_not("dark", "eclipse", 200) != "" and s.el_why_not("dark", "eclipse", 200) != Skills.CAPSTONE_LOCKED,
		"needs 25"
	)
