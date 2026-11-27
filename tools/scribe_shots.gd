extends SceneTree
## Review shots for the Auto-Scribe (phase 0.15.1).
## godot --display-driver x11 --path . -s res://tools/scribe_shots.gd -- <out_dir>

var out := "/tmp/scribe_shots"


func _initialize() -> void:
	_run.call_deferred()


func _shot(file: String) -> void:
	for _i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(file))
	print("[scribe_shots] ", file, " ", img.get_width(), "x", img.get_height())


func _run() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1920, 1080)
	var menu := (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await _shot("menu.png")
	menu.queue_free()
	for _i in 4:
		await process_frame
	GameFlow.level_id = "town_square"
	GameFlow.intro_mode = GameFlow.INTRO_SKIP
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _i in 45:
		await process_frame
	var flags: StoryFlags = main.get("story_flags")
	if flags:
		flags.set_flag(IntroDirector.SCRIBE, 1)
	var cine := main.get_node_or_null("Cinematic")
	if cine:
		cine.set("visible", false)
	await _shot("hud.png")
	var p := main.get_node("Player") as Player
	var inv := p.inventory
	inv.add(WieldablePart.load_part("basic_fire_head"))
	inv.add(ElementGem.make(ElementTable.Element.WATER))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	inv.add(EquipmentRoller.roll(rng, EquipmentItem.Slot.HAT, "rare"))
	var iv := main.get_node("InventoryUi") as InventoryUi
	iv.open()
	iv.select(inv.at(0))
	if iv.junk_button:
		iv.junk_button.text = "Unmark junk"
	await _shot("inventory.png")
	iv.close()
	main.call("open_shop", "Tailor")
	await _shot("vendor.png")
	var vui := main.get_node_or_null("VendorUi") as VendorUi
	if vui:
		vui.close()
	var echo := main.get_node("EchoMenu")
	echo.call("open", "map")
	await _shot("map.png")
	echo.call("show_tab", 3)
	await _shot("skills.png")
	echo.call("show_tab", 1)
	await _shot("missions.png")
	echo.call("show_tab", 7)
	await _shot("settings.png")
	quit()
