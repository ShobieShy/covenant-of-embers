extends SceneTree
## Art review (t60u/t61u): in-game screens with the pixel theme and item icons.
## XDG_DATA_HOME=/tmp/x godot --display-driver wayland --path . -s tools/ui_shots.gd -- <out_dir>
## (a scratch XDG_DATA_HOME keeps the real saves and keybinds untouched)

var out := "user://ui_shots"
var main: Node


func _initialize() -> void:
	_run.call_deferred()


func _shot(file: String) -> void:
	for _f in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(file))
	print("[ui_shots] ", file)


func _run() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	GameFlow.level_id = "midden"
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for _f in 30:
		await process_frame
	var p := main.get_node("Player") as Player
	var inv := p.inventory
	for id in ["basic_fire_head", "basic_handle", "basic_exterior", "basic_interior", "rare_light_charm"]:
		inv.add(WieldablePart.load_part(id))
	inv.add(ElementGem.make(ElementTable.Element.WATER))
	for s in EquipmentItem.Slot.values():
		var rng := RandomNumberGenerator.new()
		rng.seed = 7 + s
		inv.add(EquipmentRoller.roll(rng, s, "rare"))
	inv.add(WieldableInstance.load_base("novice_arcane_wand"))
	var st := main.get_node("StationUi") as StationUi
	var station := AssemblyStation.new()
	main.add_child(station)
	st.open(station)
	await _shot("station_autoloaded_staff.png")
	st.close()
	var iv := main.get_node("InventoryUi") as InventoryUi
	iv.open()
	iv.select(inv.at(0))
	await _shot("inventory_icons.png")
	iv.close()
	var d := main.get("dialogue_ui") as DialogueUI
	if d == null:  # the midden has no dialogue layer; stand one up like main does elsewhere
		var layer := CanvasLayer.new()
		main.add_child(layer)
		d = DialogueUI.new()
		layer.add_child(d)
	d._on_line("Bob", "Joe's trash, eh? Bring it here and we'll see what the Landfill coughed up.")
	d._on_choices(PackedStringArray(["Here it is.", "Not yet."]))
	await _shot("dialogue.png")
	d.visible = false
	var pm := main.get_node("PauseMenu")
	pm.call("open")
	await _shot("menu_pause.png")
	pm.set("visible", false)
	var su := main.get_node("SettingsUi")
	su.call("open")
	await _shot("menu_settings.png")
	quit()
