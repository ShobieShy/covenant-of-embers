extends TestCase
## 0.3.1 P7 (L6): the missing UI / world cues exist, are distinct, and fire from their hooks.

const NEW_KEYS := ["ui_hover", "ui_open", "ui_close", "chest_open", "shrine_use", "stairs"]


func test_keys_present_and_distinct() -> void:
	for k in NEW_KEYS:
		check(GameAudio.SOUNDS.has(k), "%s key" % k)
		check(GameAudio.load_stream(k) != null, "%s loads" % k)
	check(
		GameAudio.SOUNDS["cast"] != GameAudio.SOUNDS["brand_crystal_set"],
		"cast / crystal set differ"
	)
	check(
		not String(GameAudio.SOUNDS["enemy_death"]).contains("Metal"),
		"enemy death is no longer a metal clang"
	)
	for k in ["ui_hover", "ui_open", "ui_close"]:
		check(GameAudio.UI_KEYS.has(k), "%s on the UI bus" % k)


func _audio() -> GameAudio:
	var a := GameAudio.new()
	runner_tree.root.add_child(a)
	a.muted_output = true
	return a


func test_ui_open_close() -> void:
	var a := _audio()
	var c := Control.new()
	c.visible = false
	runner_tree.root.add_child(c)
	UiAnim.open(c)
	check(int(a.played.get("ui_open", 0)) == 1, "open plays (%s)" % [a.played])
	UiAnim.open(c)
	check(int(a.played.get("ui_open", 0)) == 1, "a refresh of an open panel is silent")
	UiAnim.close(c)
	check(int(a.played.get("ui_close", 0)) == 1, "close plays")
	UiAnim.close(c)
	check(int(a.played.get("ui_close", 0)) == 1, "closing a hidden panel is silent")
	UiAnim.open(c, false)
	check(int(a.played.get("ui_open", 0)) == 1, "sound := false stays quiet")
	c.free()
	a.free()


func test_world_cues() -> void:
	var a := _audio()
	var s := RestShrine.new()
	runner_tree.root.add_child(s)
	s.rest(null)
	check(int(a.played.get("shrine_use", 0)) == 1, "shrine")
	s.free()
	var ch := VaultChest.new()
	runner_tree.root.add_child(ch)
	ch.locked = false
	ch.open_chest()
	check(int(a.played.get("chest_open", 0)) == 1, "chest (%s)" % [a.played])
	ch.open_chest()
	check(int(a.played.get("chest_open", 0)) == 1, "only once")
	ch.free()
	GameEvents.bus().sfx.emit("nope", Vector3.INF)
	check(not a.played.has("nope"), "unknown keys are ignored")
	a.free()
