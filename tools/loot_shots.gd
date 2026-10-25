extends SceneTree
## Art review (step 123): every LootMeshes ground prop on a pickup pad, rendered to a PNG.
## godot --display-driver wayland --path . -s tools/loot_shots.gd -- <out_dir>

const KINDS := [
	"hat", "clothes", "belt", "shoes", "grimoire", "staff", "wand", "part", "gold", "mana", "dust", "potion", "trash"
]
const COLORS := [
	Color(0.9, 0.9, 0.9), Color(0.3, 0.9, 0.3), Color(0.3, 0.5, 1.0), Color(0.7, 0.3, 1.0), Color(1.0, 0.5, 0.1)
]


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var lvl: Node3D = (load("res://scenes/levels/town_square.tscn") as PackedScene).instantiate()
	root.add_child(lvl)
	for i in KINDS.size():
		var c: Color = COLORS[i % COLORS.size()]
		var p := LootPickup.new()
		p._build("Shot_" + KINDS[i], c, String(KINDS[i]).capitalize(), KINDS[i])
		p.beam.visible = false
		lvl.add_child(p)
		p.position = Vector3(-3.0 + (i % 7) * 1.0, 0.02, 4.0 + (i / 7) * 1.1)
	var cam := Camera3D.new()
	lvl.add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.2, 8.2), Vector3(0, 0.0, 4.4))
	cam.current = true
	for _f in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/loot_props.png" % out)
	quit()
