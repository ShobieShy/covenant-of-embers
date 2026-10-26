extends TestCase
## Step 151: BalancePatch "skills" section and the skill-aware DPS harness.


func _pick() -> Array:
	var t := SkillTree.element_tree("fire")
	for sid in t.skills:
		var fx: Dictionary = t.skills[sid].get("effects", {})
		for k in fx:
			if fx[k] is float or fx[k] is int:
				return [sid, k, float(fx[k])]
	return []


func test_skills_patch_applies_and_resets() -> void:
	BalancePatch.reset()
	var p := _pick()
	check(not p.is_empty(), "fire tree has a numeric effect")
	if p.is_empty():
		return
	var errs := BalancePatch.apply({"version": BalancePatch.VERSION, "skills": {"fire": {p[0]: {p[1]: p[2] + 1.0}}}})
	check(errs.is_empty(), "valid skills patch: %s" % [errs])
	check_near(float(SkillTree.element_tree("fire").skills[p[0]]["effects"][p[1]]), p[2] + 1.0, 0.001, "patched")
	BalancePatch.reset()
	check_near(float(SkillTree.element_tree("fire").skills[p[0]]["effects"][p[1]]), p[2], 0.001, "reset restores")


func test_skills_patch_rejects_unknown() -> void:
	BalancePatch.reset()
	var p := _pick()
	var v := BalancePatch.VERSION
	check(not BalancePatch.apply({"version": v, "skills": {"fire": {"no_such_skill": {"x": 1.0}}}}).is_empty(), "skill")
	check(not BalancePatch.apply({"version": v, "skills": {"fire": {p[0]: {"no_such_fx": 1.0}}}}).is_empty(), "effect")
	check(not BalancePatch.apply({"version": v, "skills": {"fire": {p[0]: {p[1]: "big"}}}}).is_empty(), "non-number")
	check_near(float(SkillTree.element_tree("fire").skills[p[0]]["effects"][p[1]]), p[2], 0.001, "untouched")
	BalancePatch.reset()


func test_skill_dps_gain_sane() -> void:
	for r in BrandDps.skills_table(20):
		check(r.gain >= 0.99 and r.gain <= 1.5, "%s gain %.2f in [1.0, 1.5]" % [r.element, r.gain])
	for r in BrandDps.skills_table(0):
		check(absf(r.gain - 1.0) < 0.03, "%s no points = parity" % r.element)
