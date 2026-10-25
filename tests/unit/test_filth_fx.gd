extends TestCase
## Step 131 (FX F5): The Filth carries FilthFX: acid blob visuals track live blobs, regen
## motes run while phase 2 regenerates, each phase change sends a shockwave, the exposed
## core pulses with a light.


func _filth() -> Filth:
	var d := EnemyTable.load_default().find("the_filth")
	var f := Enemy.create(d) as Filth
	Engine.get_main_loop().root.add_child(f)
	return f


func test_attached() -> void:
	var f := _filth()
	check(f.fx != null and f.get_node_or_null(^"FilthFX") == f.fx, "FilthFX child")
	f.free()


func test_blobs_and_pools() -> void:
	var f := _filth()
	var b := Filth.Blob.new()
	b.pos = f.global_position + Vector3(0, 1, 2)
	f.blobs.append(b)
	f.fx.step(0.016)
	check(f.fx._blob_nodes.size() == 1 and f.fx._blob_nodes[0].visible, "blob drawn")
	f.blobs.clear()
	f.fx.step(0.016)
	check(f.fx.pools == 1, "spent blob leaves a pool")
	f.free()


func test_phase_shockwave_and_core() -> void:
	var f := _filth()
	f.apply_damage(f.max_health() * 0.8, ElementTable.Element.FIRE)
	check(f.phase == 3, "phase 3 (got %d)" % f.phase)
	check(f.fx.shockwaves == 2, "one shockwave per phase change (%d)" % f.fx.shockwaves)
	f.fx.step(0.016)
	check(f.fx.core_light_on(), "core light pulses")
	f.free()


func test_regen_motes() -> void:
	var f := _filth()
	f.apply_damage(f.max_health() * 0.45, ElementTable.Element.FIRE)
	f.fx.step(0.016)
	f.regenerated += 5.0
	f.fx.step(0.016)
	check(f.phase != 2 or f.fx.regen_on, "regen motes while regenerating")
	f.free()
