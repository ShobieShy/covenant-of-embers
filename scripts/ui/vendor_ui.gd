class_name VendorUi
extends CanvasLayer
## Shop screen (BUILD_PLAN step 60): the vendor's stock on the left (Buy), the backpack on the
## right (Sell, and Re-roll at the Runesmith), a gold/Dust line, a compare line for the
## selected stock item against what's equipped in its slot, and a status line. Esc closes.

var player: Player
var vendor: Vendor
var root: PanelContainer
var stock_list: ItemList
var pack_list: ItemList
var wallet: Label
var compare: Label
var status: Label
var reroll_button: Button
var seed_rng := RandomNumberGenerator.new()


func _init() -> void:
	layer = 3
	visible = false
	root = PanelContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(900, 520)
	root.position = Vector2(-450, -260)
	add_child(root)
	var v := VBoxContainer.new()
	root.add_child(v)
	wallet = Label.new()
	v.add_child(wallet)
	var h := HBoxContainer.new()
	v.add_child(h)
	stock_list = ItemList.new()
	stock_list.custom_minimum_size = Vector2(440, 360)
	stock_list.item_selected.connect(_on_stock_selected)
	h.add_child(stock_list)
	pack_list = ItemList.new()
	pack_list.custom_minimum_size = Vector2(440, 360)
	h.add_child(pack_list)
	compare = Label.new()
	v.add_child(compare)
	var b := HBoxContainer.new()
	v.add_child(b)
	for pair in [
		["Buy", buy_selected],
		["Sell", sell_selected],
		["Sell all junk", sell_junk],
		["Re-roll", reroll_selected],
		["Close", close]
	]:
		var btn := Button.new()
		btn.text = pair[0]
		btn.pressed.connect(pair[1])
		b.add_child(btn)
		if pair[0] == "Re-roll":
			reroll_button = btn
	status = Label.new()
	v.add_child(status)


func bind(p: Player) -> void:
	player = p
	seed_rng.randomize()


static func today() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)


func open(v: Vendor) -> void:
	vendor = v
	vendor.restock(today())
	UiAnim.open(self)  # 0.3.1 P1
	status.text = ""
	player.ui_open = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	Gamepad.focus_first(self)


func close() -> void:
	UiAnim.close(self)  # 0.3.1 P1
	if player:
		player.ui_open = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


static func name_of(item: Resource) -> String:
	var n: Variant = item.get("display_name")
	return String(n) if n != null and String(n) != "" else "Item"


func refresh() -> void:
	if player == null or vendor == null:
		return
	wallet.text = (
		"%s   -   %d Gold   %d Arcane Dust"
		% [vendor.id.capitalize(), player.inventory.gold, player.inventory.dust]
	)
	stock_list.clear()
	for s in vendor.stock:
		var si := stock_list.add_item(
			(
				"%s   %d Gold"
				% [name_of(s["item"]), Archetype.discounted(int(s["price"]), player.archetype)]
			),
			ItemIcons.for_item(s["item"])
		)
		stock_list.set_item_icon_modulate(si, ItemIcons.tint_for(s["item"]))
	pack_list.clear()
	for it in player.inventory.items:
		var extra := ""
		if vendor.role == Vendor.Role.REROLL and it is WieldablePart:
			var c := Vendor.reroll_cost(it)
			extra = "   re-roll %d Gold + %d Dust" % [c["gold"], c["dust"]]
		var pi := pack_list.add_item(
			"%s   sells %d%s" % [name_of(it), Vendor.sell_price(it), extra], ItemIcons.for_item(it)
		)
		pack_list.set_item_icon_modulate(pi, ItemIcons.tint_for(it))
	reroll_button.visible = vendor.role == Vendor.Role.REROLL


func _on_stock_selected(i: int) -> void:
	compare.text = ""
	var it: Resource = vendor.stock[i]["item"]
	if it is EquipmentItem:
		var cur: EquipmentItem = player.equipment.item((it as EquipmentItem).slot)
		compare.text = "vs equipped: %s" % (name_of(cur) if cur else "nothing")
	var b: Brand = null  # step 140: the maker line (plain text; the Label has no BBCode)
	if it is WieldableInstance:
		b = (it as WieldableInstance).brand()
	elif it is WieldablePart:
		b = (it as WieldablePart).brand()
	if b != null:
		compare.text = ("%s - %s\n%s" % [b.display_name, b.mode_line, compare.text]).strip_edges()


func _selected(list: ItemList) -> int:
	var s := list.get_selected_items()
	return s[0] if s.size() > 0 else -1


func _done(err: String, ok: String) -> bool:
	status.text = ok if err == "" else err
	refresh()
	return err == ""


func buy_selected() -> bool:
	return _done(vendor.buy(player, _selected(stock_list)), "Bought.")


func sell_selected() -> bool:
	return _done(vendor.sell(player.inventory, player.inventory.at(_selected(pack_list))), "Sold.")


## t74u: sells every item marked as junk in the inventory screen.
func sell_junk() -> bool:
	var n := player.inventory.junk_items().size()
	if n == 0:
		status.text = "Nothing marked as junk."
		return false
	var g := vendor.sell_junk(player.inventory)
	status.text = "Sold %d junk item(s) for %d gold." % [n, g]
	refresh()
	return true


func reroll_selected() -> bool:
	var it := player.inventory.at(_selected(pack_list))
	return _done(vendor.reroll(player.inventory, it as WieldablePart, seed_rng), "Re-rolled.")


func _unhandled_input(event: InputEvent) -> void:
	if UiAnim.is_shown(self) and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
