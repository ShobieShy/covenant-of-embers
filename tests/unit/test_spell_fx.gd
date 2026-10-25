extends TestCase
## Step 128 (FX F2): shared bolt shader heads per live bolt, element impact bursts (capped),
## Light heal motes and the Dark conversion aura that follows corrupted_left.


func _bolts() -> SpellBolts:
	var sb := SpellBolts.new()
	sb.auto_tick = false
	Engine.get_main_loop().root.add_child(sb)
	return sb


func test_heads_follow_live_bolts() -> void:
	var sb := _bolts()
	check(sb.fx != null, "SpellBolts owns a SpellFX")
	for e in [ElementTable.Element.FIRE, ElementTable.Element.DARK]:
		var s := SpellBolts.Spawn.new()
		s.origin = Vector3(0, 100, 0)
		s.direction = Vector3.FORWARD
		s.element = e
		sb.spawn(s)
	for _i in 4:
		sb.tick(1.0 / 60.0)
	sb._draw_tracers(1.0)
	check(sb.fx.visible_heads() == 2, "two heads, got %d" % sb.fx.visible_heads())
	var mi: MeshInstance3D = sb.fx._heads[0]
	check((mi.material_override as ShaderMaterial).shader == SpellFX.BOLT_SHADER, "bolt shader")
	sb.free()


func test_impact_bursts_capped() -> void:
	var sb := _bolts()
	for i in SpellFX.MAX_BURSTS + 5:
		sb.fx.impact(Vector3.ZERO, Vector3.UP, ElementTable.Element.FIRE)
	check(sb.fx.bursts == SpellFX.MAX_BURSTS, "bursts capped at %d" % sb.fx.bursts)
	check(sb.fx.heal_motes(Vector3.ZERO) == null, "heal motes respect the cap")
	sb.free()


func test_heal_motes() -> void:
	var sb := _bolts()
	var p := sb.fx.heal_motes(Vector3.ZERO)
	check(p != null and p.emitting and p.name == "HealMotes", "heal motes emit")
	sb.free()


func test_dark_aura_follows_corruption() -> void:
	var host := Node3D.new()
	var a := SpellFX.sync_aura(host, 30.0)
	check(a != null and host.get_node_or_null(^"DarkAura") == a, "aura on")
	SpellFX.sync_aura(host, 1.5)
	var f: float = (a.material_override as ShaderMaterial).get_shader_parameter(&"fade")
	check_near(f, 0.5, 0.01, "fades over the last seconds")
	check(SpellFX.sync_aura(host, 0.0) == null, "aura off")
	host.free()
