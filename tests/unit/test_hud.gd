extends TestCase
## Step 29 done check: bars track values; the HUD lays out non-empty; a refused press shows
## "Not enough mana!". (Headless has no renderer, so the "screenshot" check is the laid-out
## Control rects here; a real screenshot comes from the desktop playtest.)

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

func test_bars_track_values() -> void:
	var s := _setup()
	var p: Player = s[0]
	var hud: Hud = s[1]
	check(hud.layer == 2, "above the viewmodel overlay")
	p.mana.value = 25.0
	p.breath.value = 50.0
	p.health.value = 40.0
	p.health.shield = 10.0
	hud.refresh(DT)
	check_near(hud.mana_bar.value, 0.25, 1e-6, "mana")
	check_near(hud.breath_bar.value, 0.5, 1e-6, "breath")
	check_near(hud.health_bar.value, 0.4, 1e-6, "health")
	check_near(hud.shield_bar.value, 0.2, 1e-6, "shield")
	check(Hud.bar_color(hud.mana_bar).is_equal_approx(Hud.MANA_COLOR), "Magewar mana colour")
	p.breath.exhausted = true
	hud.refresh(DT)
	check(Hud.bar_color(hud.breath_bar).is_equal_approx(Hud.BREATH_EXHAUSTED), "exhausted tint")
	check(hud.pips.size() == p.dash.max_charges(), "dash pips")
	p.dash.charges = 1
	hud.refresh(DT)
	check(hud.pips[0].value == 1.0 and hud.pips[1].value < 1.0, "spent pip")
	var w := p.loadout.wieldable(0)
	check(w == null or hud.slot_icons[0].color.is_equal_approx(w.rarity_color()), "slot tint")
	p.equip(WieldableInstance.load_base("apprentice_fire_staff"))
	hud.refresh(DT)
	check(hud.slot_icons[0].color.is_equal_approx(p.loadout.wieldable(0).rarity_color()), "staff rarity colour")
	p.focus.focused = true
	hud.refresh(DT)
	check(not hud.crosshair.visible, "crosshair hidden while focused")
	p.focus.focused = false
	hud.refresh(DT)
	check(hud.crosshair.visible and hud.crosshair_gap() >= 0.0, "crosshair back")
	p.progression.add_xp(30)
	hud.refresh(DT)
	check(hud.level_label.text.contains("30 / 100"), "XP line '%s'" % hud.level_label.text)
	p.queue_free(); hud.queue_free()

func test_layout_non_empty() -> void:
	var s := _setup()
	var hud: Hud = s[1]
	await runner_tree.process_frame
	for b in [hud.health_bar, hud.shield_bar, hud.mana_bar, hud.breath_bar]:
		var r: Rect2 = b.get_global_rect()
		check(r.size.x > 100.0 and r.size.y > 5.0, "bar laid out %s" % r)
	check(hud.root.get_global_rect().size.x > 0.0, "root fills the viewport")
	s[0].queue_free(); hud.queue_free()

func test_refused_press_shows_hint() -> void:
	var s := _setup()
	var p: Player = s[0]
	var hud: Hud = s[1]
	p.equip(WieldableInstance.load_base("apprentice_fire_staff"))
	for i in 40:
		p.tick(PlayerInput.hold(), DT)   # draw finishes
	p.mana.value = 0.0
	p.tick(PlayerInput.hold(["action_primary"], ["action_primary"]), DT)
	hud.refresh(DT)
	check(hud.hint_label.visible and hud.hint_label.text == "Not enough mana!", "hint '%s'" % hud.hint_label.text)
	check(hud.mana_flash_left > 0.0, "mana bar flash")
	for i in 120:
		hud.refresh(DT)
	check(not hud.hint_label.visible, "hint fades after 1.5 s")
	p.queue_free(); hud.queue_free()
