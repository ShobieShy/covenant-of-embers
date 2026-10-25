extends SceneTree
## FX review (step 128+): six element bolt heads + impact bursts, Light heal motes and a Dark
## conversion aura in the Breach, rendered to PNGs.
## godot --display-driver wayland --path . -s tools/fx_shots.gd -- <out_dir>

const ELS := [
	ElementTable.Element.FIRE,
	ElementTable.Element.WATER,
	ElementTable.Element.EARTH,
	ElementTable.Element.AIR,
	ElementTable.Element.LIGHT,
	ElementTable.Element.DARK,
]


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var lvl: Node3D = (load("res://scenes/levels/breach.tscn") as PackedScene).instantiate()
	root.add_child(lvl)
	var fx := SpellFX.new()
	lvl.add_child(fx)
	await process_frame
	var cam := Camera3D.new()
	lvl.add_child(cam)
	cam.current = true
	# 1: bolt heads in a row
	var heads := []
	for i in ELS.size():
		heads.append([Vector3(-2.5 + i, 1.4, -3.0), ELS[i]])
	fx.update_heads(heads)
	cam.look_at_from_position(Vector3(0, 1.6, 0.5), Vector3(0, 1.3, -3.0))
	await _shot(out + "/fx_bolts.png", 6)
	# 2: impacts mid-burst
	fx.update_heads([])
	for i in ELS.size():
		fx.impact(Vector3(-2.5 + i, 1.0, -3.0), Vector3(0, 0, 1), ELS[i])
	await _shot(out + "/fx_impacts.png", 6)
	# 3: heal motes + dark aura on an enemy
	var d := EnemyTable.load_default().find("gnawer")
	var e := Enemy.create(d) if d else null
	var host := Node3D.new()
	lvl.add_child(host)
	host.position = Vector3(1.0, 0.0, -3.0)
	if e:
		host.add_child(e)
	SpellFX.sync_aura(host, 30.0, 1.0)
	fx.heal_motes(Vector3(-1.0, 0.0, -3.0))
	cam.look_at_from_position(Vector3(0, 2.0, 0.0), Vector3(0, 0.3, -3.0))
	await _shot(out + "/fx_heal_aura.png", 30)
	host.queue_free()
	# 4 (step 129): burn / slow / stagger, a chain arc and a death dissolve
	var sz := Vector3(0.7, 1.4, 0.7)
	for i in 3:
		var n := Node3D.new()
		lvl.add_child(n)
		n.position = Vector3(-2.0 + i * 1.6, 0.0, -3.0)
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sz
		box.mesh = bm
		box.position.y = sz.y * 0.5
		n.add_child(box)
		StatusFX.sync(n, sz, i == 0, i == 1, i == 2)
	cam.look_at_from_position(Vector3(0, 2.0, 1.0), Vector3(0, 0.8, -3.0))
	await _shot(out + "/fx_status.png", 40)
	StatusFX.chain_arc(lvl, Vector3(-2, 1, -3), Vector3(1.2, 1, -3))
	StatusFX.death(lvl, Vector3(2.6, 0, -3), sz, Color(0.4, 0.5, 0.3), Color(1.0, 0.35, 0.08))
	await _shot(out + "/fx_chain_death.png", 22)
	quit()


func _shot(path: String, frames: int) -> void:
	for _f in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
