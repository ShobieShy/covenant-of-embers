extends TestCase
## Step 140 (Brands B6, docs/BRANDS_PLAN.md): the brand on item cards and the HUD meter.
##  - every brand has a loadable original logo (assets/original/brands, CC0, in ASSETS.toml);
##  - a branded staff's card leads with "[img] Brand - mode line", Rare+ adds the tagline,
##    parts show the maker too, unbranded cards add nothing;
##  - the HUD meter shows the held brand's meter/text and hides for unbranded staffs.

const P := WieldablePart.PartType
const E := ElementTable.Element
const DT := 1.0 / 60.0


func _staff(head_element: E) -> WieldableInstance:
	var head := PartRoller.from_seed(1234, P.HEAD, "basic", head_element)
	var parts: Array[WieldablePart] = [head]
	for id in ["basic_exterior", "basic_interior", "basic_handle"]:
		parts.append(WieldablePart.load_part(id))
	return Assembly.assemble(WieldableInstance.load_base("apprentice_fire_staff").def, parts)


func test_logos_load() -> void:
	for b in BrandTable.load_default().brands:
		var br := b as Brand
		check(br.logo_path.begins_with("res://assets/original/brands/"), "%s logo path" % br.id)
		var t := br.logo()
		check(t != null and t.get_width() == 32, "%s logo loads at 32 px" % br.id)


func test_card_brand_line() -> void:
	var c := CompareCard.for_item(_staff(E.FIRE))
	var s := c.extra_lines()
	check(c.brand != null and c.brand.id == "pyrowning_arms", "card brand")
	check(s.begins_with("[img=16x16]res://assets/original/brands/pyrowning_arms.png[/img]"), s)
	check(s.contains("Pyrowning Arms") and s.contains(c.brand.mode_line), s)
	check(not s.contains(c.brand.tagline), "no tagline on Basic")
	var rare := CompareCard.for_item(_staff(E.DARK))
	rare.rarity_id = "rare"  # assembled rarity comes from all four parts
	check(rare.extra_lines().contains(rare.brand.tagline), "Rare+ shows the tagline")
	check(CompareCard.for_item(_staff(E.ARCANE)).brand_line() == "", "unbranded: no line")
	var part := CompareCard.for_item(WieldablePart.load_part("rare_light_charm"))
	check(part.brand_line().contains("Coltara Halo"), "part card shows its maker")


func test_hud_meter() -> void:
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(Vector3(0, 200, 1500), 0.0)
	var hud := Hud.new()
	runner_tree.root.add_child(hud)
	hud.bind(p)
	p.loadout.equip(_staff(E.ARCANE))
	hud.refresh(DT)
	check(not hud.brand_meter.visible, "unbranded: meter hidden")
	p.loadout.equip(_staff(E.FIRE))
	p.loadout.swap_left = 0.0
	var m := p.caster.fire_mode()
	hud.refresh(DT)
	check(hud.brand_meter.visible, "branded: meter shown")
	check(hud.brand_meter.kind == m.meter_kind() and hud.brand_meter.text == m.meter_text(), "mirrors the mode")
	check(hud.brand_meter.logo != null, "logo on the meter")
	p.queue_free()
	hud.queue_free()
