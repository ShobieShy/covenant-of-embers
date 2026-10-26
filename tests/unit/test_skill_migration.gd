extends TestCase
## Phase V step 144: version-1 skill saves load unchanged; v2 round-trips element ranks;
## two capstones in a save keep the first in tree order.


func test_v1_save() -> void:
	var s := Skills.new()
	s.tree = SkillTree.default_tree()
	var sid: String = s.tree.order[0]
	var w := s.from_dict({"tree": s.tree.id, "ranks": {sid: 1}, "respecs": 2}, 10)
	check(w.is_empty(), "no warnings: %s" % [w])
	check(s.rank(sid) == 1 and s.respecs == 2 and s.el_ranks.is_empty(), "v1 loads")
	check(int(s.to_dict()["skills_version"]) == 2, "saves as v2")


func test_v2_round_trip() -> void:
	var s := Skills.new()
	s.tree = SkillTree.default_tree()
	s.el_spend("air", "tailwind", 10)
	s.el_spend("air", "tailwind", 10)
	var d := JSON.parse_string(JSON.stringify(s.to_dict())) as Dictionary
	var t := Skills.new()
	t.tree = SkillTree.default_tree()
	t.from_dict(d, 10)
	check(t.el_rank("air", "tailwind") == 2, "element ranks round trip")


func test_two_capstones() -> void:
	var s := Skills.new()
	s.tree = SkillTree.default_tree()
	var w := s.from_dict({"elements": {"water": {"tidal_hold": 1}, "fire": {"backdraft": 1}}}, 200)
	check(s.el_rank("fire", "backdraft") == 1 and s.el_rank("water", "tidal_hold") == 0, "first in order kept")
	check(w.size() == 1, "one warning")
