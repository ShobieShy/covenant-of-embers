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
	p.queue_free()
	hud.queue_free()


func test_world_compare_card() -> void:
	var s := _setup()
	var p: Player = s[0]
	var hud: Hud = s[1]
	var held := WieldableInstance.load_base("apprentice_fire_staff")
	var other := WieldableInstance.load_base("earthward_battlestaff")
	p.equip(held)
	var d := LootDrop.new()
	d.kind = LootDrop.Kind.WIELDABLE
	d.item = other
	d.rarity_id = other.rarity_id()
	var lp := LootPickup.create(d, p.global_position + p.forward_for(p.yaw) * 2.0)
	p.get_parent().add_child(lp)
	Interaction.face(p, lp)
	p.tick(PlayerInput.hold(), 1.0 / 60.0)
	check(p.pickups.focused == lp, "the drop under the crosshair")
	hud.refresh(1.0 / 60.0)
	check(hud.world_card_bg.visible, "card is up")
	var card := CompareCard.for_item(other, p, true)
	check(card.compared_to == held.display_name(), "compared to the weapon in hand")
	var row := card.row("damage")
	check(bool(row.compared) and not is_zero_approx(float(row.delta)), "a damage delta")
	var hex := (CompareCard.BETTER if row.better else CompareCard.WORSE).to_html(false)
	check(hud.world_card.text.contains(hex), "green or red delta in the card")
	check(hud.world_card.text.contains("vs "), "names what you have equipped")
	p.set_look(p.yaw + 2.0, 0.0)
	p.tick(PlayerInput.hold(), 1.0 / 60.0)
	hud.refresh(1.0 / 60.0)
	check(p.pickups.focused == null and not hud.world_card_bg.visible, "hidden when you look away")
	var hat := EquipmentRoller.from_seed(4, EquipmentItem.Slot.HAT, "rare", ElementTable.Element.FIRE)
	var better := EquipmentRoller.from_seed(8, EquipmentItem.Slot.HAT, "mythic", ElementTable.Element.FIRE)
	better.health_bonus = hat.health_bonus + 12.0
	p.equip_item(hat)
	var ed := LootDrop.new()
	ed.kind = LootDrop.Kind.EQUIPMENT
	ed.item = better
	ed.rarity_id = "mythic"
	var ep := LootPickup.create(ed, p.global_position + p.forward_for(p.yaw) * 2.0)
	p.get_parent().add_child(ep)
	Interaction.face(p, ep)
	p.tick(PlayerInput.hold(), 1.0 / 60.0)
	hud.refresh(1.0 / 60.0)
	var er := CompareCard.for_item(better, p).row("health_bonus")
	check(bool(er.better) and float(er.delta) > 0.0, "hat compares against the worn piece")
	check(hud.world_card.text.contains(CompareCard.BETTER.to_html(false)), "better health is green")
	lp.free()
	ep.free()
	p.free()
	hud.free()


func test_layout_non_empty() -> void:
	var s := _setup()
	var hud: Hud = s[1]
	await runner_tree.process_frame
	for b in [hud.health_bar, hud.shield_bar, hud.mana_bar, hud.breath_bar]:
		var r: Rect2 = b.get_global_rect()
		check(r.size.x > 100.0 and r.size.y > 5.0, "bar laid out %s" % r)
	check(hud.root.get_global_rect().size.x > 0.0, "root fills the viewport")
	s[0].queue_free()
	hud.queue_free()


func test_refused_press_shows_hint() -> void:
	var s := _setup()
	var p: Player = s[0]
	var hud: Hud = s[1]
	p.equip(WieldableInstance.load_base("apprentice_fire_staff"))
	for i in 40:
		p.tick(PlayerInput.hold(), DT)  # draw finishes
	p.mana.value = 0.0
	p.tick(PlayerInput.hold(["action_primary"], ["action_primary"]), DT)
	hud.refresh(DT)
	check(hud.hint_label.visible and hud.hint_label.text == "Not enough mana!", "hint '%s'" % hud.hint_label.text)
	check(hud.mana_flash_left > 0.0, "mana bar flash")
	for i in 120:
		hud.refresh(DT)
	check(not hud.hint_label.visible, "hint fades after 1.5 s")
	p.queue_free()
	hud.queue_free()
