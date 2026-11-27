extends TestCase
## 0.15.1: parchment theme, painted map plates, and the detail-row layout.


func test_theme_is_readable_serif() -> void:
	var theme := UiTheme.get_theme()
	check(theme.default_font_size >= 20, "body size reads at 1080p")
	check(theme.default_font != null, "serif loaded")
	var ink: Color = theme.get_color(&"font_color", &"Label")
	check(ink.get_luminance() < 0.35, "ink on parchment, not pale type")
	var panel := theme.get_stylebox(&"panel", &"PanelContainer") as StyleBoxTexture
	check(panel != null and panel.texture != null, "parchment panel")
	check(panel.texture.resource_path.contains("ui_scribe"), "panel is the scribe sheet")


func test_painted_plates_follow_the_level() -> void:
	check(ResourceLoader.exists(WorldMapScreen.painted_path("town_square")), "town plate")
	check(WorldMapScreen.painted_path("midden").ends_with("landfill.jpg"), "landfill plate")
	check(WorldMapScreen.painted_path("breach", 0).ends_with("breach.jpg"), "breach mouth")
	check(WorldMapScreen.painted_path("breach", 1).ends_with("warrens.jpg"), "act I plate")
	check(WorldMapScreen.painted_path("breach", 6).ends_with("blightcoil.jpg"), "act II plate")
	check(WorldMapScreen.painted_path("breach", 19).ends_with("spire.jpg"), "act V plate")
	check(WorldMapScreen.painted_path("no_such_level").ends_with("elyria.jpg"), "unknown place uses Elyria")
	check(SkillIcons.texture("fire") != null and SkillIcons.texture("ember") != null, "skill medallions")


func test_detail_row_fits() -> void:
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(Vector3(0, 200, 1600), 0.0)
	var ui := InventoryUi.new()
	runner_tree.root.add_child(ui)
	ui.bind(p)
	check(ui.trash_button.get_parent() is HBoxContainer, "trash shares the count row")
	check(ui.junk_button.get_parent() == ui.favorite_button.get_parent(), "junk and favorite share a column")
	check(ui.junk_button.get_parent() != ui.trash_button.get_parent(), "long labels are not on the trash row")
	check(not ui.junk_button.clip_text and not ui.favorite_button.clip_text, "labels are not clipped")
	var shop := VendorUi.new()
	runner_tree.root.add_child(shop)
	check(shop.sell_junk_button.get_parent() is GridContainer, "vendor actions wrap")
	check((shop.sell_junk_button.get_parent() as GridContainer).columns == 3, "three vendor actions per row")
	p.queue_free()
	ui.queue_free()
	shop.queue_free()
