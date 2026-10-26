extends SceneTree
## t74u: the inventory Trash flow (Rare+ confirm, junk marks, quest item, potions).
## XDG_DATA_HOME=/tmp/x godot --display-driver wayland --path . -s tools/trash_shots.gd -- <out_dir>

var out := "user://trash_shots"


func _initialize() -> void:
	_run.call_deferred()


func _shot(file: String) -> void:
	for _f in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(file))
	print("[trash_shots] ", file)


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
	var inv := p.inventory
	for id in ["basic_fire_head", "basic_handle", "basic_exterior", "rare_light_charm"]:
		inv.add(WieldablePart.load_part(id))
	for s in [EquipmentItem.Slot.HAT, EquipmentItem.Slot.BELT]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7 + s
		inv.add(EquipmentRoller.roll(rng, s, "rare"))
	p.quest_items.append("joes_trash")
	p.equipment.add_potions(ConsumableItem.load_item("health_potion"), 4)
	inv.set_junk(inv.at(1), true)
	inv.set_junk(inv.at(2), true)
	var iv := main.get_node("InventoryUi") as InventoryUi
	iv.open()
	iv.select(inv.at(3))
	iv.request_trash(inv.at(3))
	await _shot("trash_confirm_rare.png")
	iv.cancel_trash()
	iv.select(p.equipment.potion)
	iv.qty.value = 2
	await _shot("trash_potion_qty.png")
	iv.select("joes_trash")
	iv.request_trash("joes_trash")
	await _shot("trash_quest_blocked.png")
	quit()
