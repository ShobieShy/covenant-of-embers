extends TestCase
## Step 141 (Brands B7): brand VFX/SFX hooks.
##  - BrandFX shows heat glow + steam puff (rising edge only), charge glow, spin ring, all from
##    (bits, meter, colour) so co-op can drive it from the snapshot;
##  - quality presets cap the steam particles;
##  - GameAudio maps brand events to the Kenney CC0 sounds (each key loads);
##  - orbs and boulders draw bigger bolt heads.


func test_fx_from_bits() -> void:
	var fx := BrandFX.new()
	runner_tree.root.add_child(fx)
	check(not fx.glow.visible and not fx.ring.visible and not fx.steam.emitting, "idle: nothing")
	fx.apply(BrandFX.BIT_HOT, 0.8, Color.RED)
	check(fx.glow.visible and fx.light.light_energy > 1.5, "hot: glow + light")
	fx.apply(BrandFX.BIT_HOT | BrandFX.BIT_VENT, 1.0, Color.RED)
	fx.apply(BrandFX.BIT_VENT, 0.5, Color.RED)
	check(fx.puffs == 1 and fx.steam.emitting, "one steam puff per vent")
	fx.apply(0, 0.0, Color.RED)
	check(not fx.steam.emitting, "steam stops")
	fx.apply(BrandFX.BIT_CHARGE, 0.5, Color.BLUE)
	check(fx.glow.visible and fx.light.light_color == Color.BLUE, "charge glow in the brand colour")
	fx.apply(BrandFX.BIT_SPIN, 1.0, Color.WHITE)
	check(fx.ring.visible and not fx.glow.visible, "spin ring")
	var keep := QualityPresets.level
	QualityPresets.level = QualityPresets.Level.LOW
	fx.apply(BrandFX.BIT_VENT, 1.0, Color.RED)
	check(fx.steam.amount == 8, "Low preset halves steam")
	QualityPresets.level = keep
	fx.queue_free()


func test_fx_follows_mode() -> void:
	var fx := BrandFX.new()
	var heat := FireMode.for_wieldable(_staff(ElementTable.Element.FIRE))
	fx.show_mode(heat)
	check(fx.bits == heat.fx_bits(), "bits from the mode")
	fx.show_mode(null)
	check(fx.bits == 0 and not fx.glow.visible, "empty hands clear")
	fx.free()


func test_audio_keys() -> void:
	for k in GameAudio.SOUNDS:
		if String(k).begins_with("brand_"):
			check(GameAudio.load_stream(k) != null, "%s loads" % k)
	var a := GameAudio.new()
	a.muted_output = true
	a._on_brand_event(&"overheated", 1.0)
	a._on_brand_event(&"vent", 1.0)
	a._on_brand_event(&"charge", 0.5)
	a._on_brand_event(&"charge", 1.0)
	a._on_brand_event(&"charge", 1.0)
	a._on_brand_event(&"charge_released", 1.0)
	a._on_brand_event(&"mode_toggled", 1.0)
	a._on_brand_event(&"orb_thrown", 6.0)
	for k in ["brand_overheat", "brand_vent", "brand_charge_release", "brand_toggle", "brand_orb"]:
		check(int(a.played.get(k, 0)) == 1, "%s played once" % k)
	check(int(a.played.get("brand_charge_full", 0)) == 1, "full-charge cue once per charge")
	a.free()


func test_big_heads() -> void:
	var b := SpellBolts.new()
	var sizes := []
	for kind in ["plain", "boulder", "orb"]:
		var s := SpellBolts.Spawn.new()
		s.has_visual_origin = true
		s.blast_radius = 2.0 if kind != "plain" else 0.0
		s.is_orb = kind == "orb"
		b.spawn(s)
	for bolt in b.live:
		bolt.ticks = 1
		bolt.travelled = 5.0
	for h in b.bolt_heads(1.0):
		sizes.append(h[2])
	check(sizes == [1.0, 1.8, 2.6], "head scale plain/boulder/orb: %s" % [sizes])
	b.free()


func _staff(e: ElementTable.Element) -> WieldableInstance:
	var head := PartRoller.from_seed(1234, WieldablePart.PartType.HEAD, "basic", e)
	var parts: Array[WieldablePart] = [head]
	for id in ["basic_exterior", "basic_interior", "basic_handle"]:
		parts.append(WieldablePart.load_part(id))
	return Assembly.assemble(WieldableInstance.load_base("apprentice_fire_staff").def, parts)
