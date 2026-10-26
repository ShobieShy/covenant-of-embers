extends SceneTree
## Step 149: skills screen with a Fire capstone owned and the others padlocked.
## XDG_DATA_HOME=/tmp/coe_x godot --display-driver wayland --path . -s tools/skills_shots.gd -- <out_dir>

var out := "user://skills_shots"


func _shot(file: String) -> void:
	for _f in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(file))
	print("[skills_shots] ", file)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	GameFlow.level_id = "midden"
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _f in 30:
		await process_frame
	var p := main.get_node("Player") as Player
	while p.progression.level < 40:
		p.add_xp(p.progression.xp_to_next)
	var d := {}
	var n := 0
	var cap := ""
	for s in SkillTree.element_tree("fire").skills.values():
		if bool(s.get("capstone", false)):
			cap = s["id"]
		elif n < Skills.CAPSTONE_POINTS or int(s["tier"]) == 4:
			d[s["id"]] = int(s["max_rank"]) if int(s["tier"]) < 4 else 1
			n += int(d[s["id"]])
	d[cap] = 1
	p.skills.el_ranks["fire"] = d
	var ui: SkillsUi = null
	for c in main.get_children():
		if c is SkillsUi:
			ui = c
	ui.open()
	ui.show_tab("fire")
	await _shot("skills_fire_capstone_owned.png")
	ui.show_tab("water")
	await _shot("skills_water_capstone_locked.png")
	quit()
