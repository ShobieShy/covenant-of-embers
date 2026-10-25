extends SceneTree
## Art review: line up the character models (CharacterModel) in the town square and render a PNG.
## godot --display-driver wayland --path . -s tools/model_shots.gd -- <out_dir>

const CAST := [
	"Crazy Joe",
	"Elder",
	"Elder Green",
	"Elder Ash",
	"Summoned Gal",
	"Summoned Buff",
	"Summoned Loli",
	"Summoned Nerd",
	"Bob"
]


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var lvl: Node3D = (load("res://scenes/levels/town_square.tscn") as PackedScene).instantiate()
	root.add_child(lvl)
	var x := -4.0
	var walking := []
	for s: String in CAST:
		var m := CharacterModel.make(CharacterModel.for_speaker(s))
		if m == null:
			push_error("no model for " + s)
		else:
			lvl.add_child(m)
			m.position = Vector3(x, 0, 0)
			m.rotation.y = PI
			walking.append(m)
		x += 1.0
	var cam := Camera3D.new()
	lvl.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.4, 5.5), Vector3(0, 0.9, 0))
	cam.current = true
	for _f in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/cast.png" % out)
	for m: CharacterModel in walking:
		print("[model_shots] ", m.get_child(0).name, " anim=", m.anim.current_animation if m.anim else "none")
	var oak := Camera3D.new()
	lvl.add_child(oak)
	oak.look_at_from_position(Vector3(4, 1.7, 14), Vector3(29, 7, 14))
	oak.current = true
	for _f in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/town_oak.png" % out)
	quit()
