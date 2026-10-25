extends TestCase
## Step 130 (FX F4): every rarity gets a shader beam in its colour with a ground ring;
## Primordial+ swirls, Unique has rune ticks; the close fade lives in the shader.


func test_beams_per_rarity() -> void:
	var rt := RarityTable.load_default()
	for i in Rarity.IDS.size():
		var d := LootDrop.new()
		d.rarity_id = Rarity.IDS[i]
		var p := LootPickup.create(d, Vector3.ZERO)
		var bm := p.beam.material_override as ShaderMaterial
		check(bm != null and bm.shader == LootPickup.BEAM_SHADER, "%s beam shader" % d.rarity_id)
		var c: Color = bm.get_shader_parameter(&"beam_color")
		check(c.is_equal_approx(rt.color(d.rarity_id)), "%s beam colour" % d.rarity_id)
		check_near(bm.get_shader_parameter(&"fade_near"), LootPickup.BEAM_FADE_NEAR, 1e-6, "close fade")
		check((bm.get_shader_parameter(&"swirl") > 0.5) == (i >= LootPickup.SWIRL_TIER), "swirl tier")
		var rm := p.ring.material_override as ShaderMaterial
		check((rm.get_shader_parameter(&"runes") > 0.5) == (i >= LootPickup.RUNE_TIER), "rune ring tier")
		p.free()
