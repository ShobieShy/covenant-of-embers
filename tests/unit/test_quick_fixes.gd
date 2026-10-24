extends TestCase
## batch_01 quick fixes: HUD + quest tracker hide under cinematics, loot beam fades up close,
## the prologue kit build beats the Apprentice staff it replaces.


func test_hud_hidden_during_cinematic() -> void:
	var hud := Hud.new()
	runner_tree.root.add_child(hud)
	var c := Cinematic.new()
	Cinematic.playing = c
	hud.refresh(0.016)
	check(not hud.root.visible, "HUD hidden while a cinematic plays")
	Cinematic.playing = null
	hud.refresh(0.016)
	check(hud.root.visible, "HUD back after")
	c.free()
	hud.queue_free()


func test_tracker_hidden_during_cinematic() -> void:
	var q := QuestTrackerUI.new()
	var c := Cinematic.new()
	Cinematic.playing = c
	q._process(0.016)
	check(not q.tracker.visible, "tracker hidden in cinematic")
	Cinematic.playing = null
	q._process(0.016)
	check(q.tracker.visible, "tracker shown after")
	c.free()
	q.free()


func test_beam_fades_close() -> void:
	check(LootPickup.BEAM_FADE_NEAR < LootPickup.BEAM_FADE_FAR, "fade range")
	check(LootPickup.BEAM_FADE_FAR <= 4.0, "beam faded within a few metres")


func test_tutorial_build_beats_apprentice() -> void:
	var base := WieldableInstance.load_base("apprentice_fire_staff")
	var parts: Array = []
	for id in IntroDirector.TUTORIAL_KIT:
		parts.append(WieldablePart.load_part(id))
	var built := Assembly.assemble(base.def, parts)
	check(built.damage() > base.damage(), "damage %.1f > %.1f" % [built.damage(), base.damage()])
	check(built.damage() / built.cooldown() > base.damage() / base.cooldown(), "dps higher")
	check(built.accuracy() >= base.accuracy(), "accuracy not lower")
