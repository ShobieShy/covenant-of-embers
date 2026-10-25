extends TestCase
## Step 133 (FX F7): summoning circle, vortex dressing, crystal, cinematic letterbox/fade, bar shine.


func test_summoning_circle() -> void:
	var c := RitualFX.summoning_circle(Vector3(0, 0.3, -7.5))
	check(c.get_node_or_null("RuneDisc") != null and c.get_node_or_null("Motes") is CPUParticles3D, "disc + motes")
	var m := (c.get_node("RuneDisc") as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	check(m != null and m.shader == RitualFX.CIRCLE_SHADER, "rune shader")
	c.free()


func test_vortex_dressed() -> void:
	var v := MentorArrival.vortex(Vector3.ZERO)
	check(
		v.name == "BobVortex" and v.get_node_or_null("Swirl") != null and v.get_node_or_null("Glow") != null, "vortex"
	)
	v.free()


func test_crystal() -> void:
	var c := RitualFX.crystal(Vector3.ZERO)
	check(c.get_node_or_null("Gem") != null and c.get_node_or_null("Sparkles") != null, "crystal")
	c.free()


func test_cinematic_letterbox_and_fade() -> void:
	var host := Node.new()
	runner_tree.root.add_child(host)
	var shots := [{"from": Vector3(0, 2, 5), "look": Vector3.ZERO, "s": 2.0}]
	var c := Cinematic.make("t", shots, null)
	host.add_child(c)
	check(c.fade.color.a > 0.9 and c.bars[0].anchor_bottom < 0.01, "starts black, bars closed")
	c._process(1.0)
	check(c.fade.color.a < 0.01 and is_equal_approx(c.bars[0].anchor_bottom, Cinematic.BAR), "faded in, bars in")
	c._process(0.9)
	check(c.fade.color.a > 0.5, "fades out at the end")
	host.free()
	Cinematic.playing = null


func test_bar_shine() -> void:
	var b := ProgressBar.new()
	UiTheme.frame_bar(b)
	check(b.get_node_or_null("Shine") != null, "shine on framed bars")
	b.free()
