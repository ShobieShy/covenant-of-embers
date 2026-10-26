extends TestCase
## Phase V step 144: the 7 element trees load (21 skills: 20 ranked + 1 exclusive capstone),
## share the Core point pool, and gate tiers on points spent in that tree.


func _skills() -> Skills:
	var s := Skills.new()
	s.tree = SkillTree.default_tree()
	return s


func test_trees_load() -> void:
	for el in ElementTable.IDS:
		var t := SkillTree.element_tree(el)
		check(t != null, "%s tree loads" % el)
		if t == null:
			continue
		check(t.order.size() == 21, "%s has 21 skills" % el)
		check(t.element == el and t.gate == "tree" and t.tiers == 6, "%s header" % el)
		var caps := 0
		for sid in t.order:
			var s := t.skill(sid)
			if s["capstone"]:
				caps += 1
				check(s["exclusive_group"] == "element_capstone", "%s capstone group" % sid)
		check(caps == 1, "%s one capstone" % el)


func test_core_unchanged() -> void:
	check(SkillTree.default_tree().element.is_empty(), "Core is not an element tree")
	check(SkillTree.default_tree().gate == "branch", "Core gates per branch")


func test_shared_pool_and_tree_gate() -> void:
	var s := _skills()
	var lvl := 4  # 3 points
	check(s.el_spend("fire", "hot_coals", lvl), "tier 0 spend")
	check(s.available(lvl) == 2, "shared pool")
	check(not s.el_why_not("fire", "searing", 50).is_empty(), "tier 1 needs 5 in fire")
	for i in 4:
		s.el_spend("fire", "hot_coals", 50)
	check(s.el_why_not("fire", "searing", 50).is_empty(), "tier 1 opens at 5")
	check(not s.el_why_not("water", "heavy_water", 50).is_empty(), "points in fire don't open water")
	check_near(float(s.el_totals("fire").get("damage_pct", 0.0)), 15.0, 0.01, "5 ranks x 3%")
	check(s.totals().is_empty(), "element ranks never touch Core totals")
