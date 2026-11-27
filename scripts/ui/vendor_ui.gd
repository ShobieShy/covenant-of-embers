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
var sell_junk_button: Button
var sell_all_button: Button
var confirm_row: VBoxContainer
var confirm_label: Label
var keep_button: Button
var pending_kind := ""  ## "junk", "all", or ""
var confirm_from: Button
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
	var b := GridContainer.new()
	b.columns = 3
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(b)
	for pair in [
		["Buy", buy_selected],
		["Sell", sell_selected],
		["Sell all junk", sell_junk],
		["Sell all", sell_all],
		["Re-roll", reroll_selected],
		["Close", close],
	]:
		var btn := Button.new()
		btn.text = pair[0]
		btn.clip_text = false
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(pair[1])
		b.add_child(btn)
		match pair[0]:
			"Sell all junk":
				sell_junk_button = btn
			"Sell all":
				sell_all_button = btn
			"Re-roll":
				reroll_button = btn
	confirm_row = VBoxContainer.new()
	confirm_row.visible = false
	v.add_child(confirm_row)
	confirm_label = Label.new()
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_row.add_child(confirm_label)
	var yn := HBoxContainer.new()
	confirm_row.add_child(yn)
	var yes := Button.new()
	yes.text = "Sell"
	yes.pressed.connect(confirm_sale)
	yn.add_child(yes)
	keep_button = Button.new()
	keep_button.text = "Keep"
	keep_button.pressed.connect(func(): cancel_sale(true))
	yn.add_child(keep_button)
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
	if pending_kind != "":
		cancel_sale(false)
	UiAnim.close(self)  # 0.3.1 P1
	if player:
		player.ui_open = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


static func name_of(item: Resource) -> String:
	var n: Variant = item.get("display_name")
	if n == null:
		return "Item"
	var s := str(n)
	return "Item" if s.is_empty() else s


func refresh() -> void:
	if player == null or vendor == null:
		return
	wallet.text = (
		"%s   -   %d Gold   %d Arcane Dust" % [vendor.id.capitalize(), player.inventory.gold, player.inventory.dust]
	)
	stock_list.clear()
	for s in vendor.stock:
		var si := stock_list.add_item(
			"%s   %d Gold" % [name_of(s["item"]), Archetype.discounted(int(s["price"]), player.archetype)],
			ItemIcons.for_item(s["item"])
		)
		stock_list.set_item_icon_modulate(si, ItemIcons.tint_for(s["item"]))
	pack_list.clear()
	for it in player.inventory.items:
		var extra := ""
		if vendor.role == Vendor.Role.REROLL and it is WieldablePart:
			var c := Vendor.reroll_cost(it)
			extra = "   re-roll %d Gold + %d Dust" % [c["gold"], c["dust"]]
		var mark := ""
		if player.inventory.is_junk(it):
			mark = " (junk)"
		elif player.inventory.is_favorite(it):
			mark = " (favorite)"
		var pi := pack_list.add_item(
			"%s%s   sells %d%s" % [name_of(it), mark, Vendor.sell_price(it), extra], ItemIcons.for_item(it)
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
	_drop_confirm_for_other()
	return _done(vendor.buy(player, _selected(stock_list)), "Bought.")


func sell_selected() -> bool:
	_drop_confirm_for_other()
	return _done(vendor.sell(player.inventory, player.inventory.at(_selected(pack_list))), "Sold.")


## Asks before selling junk. An empty set sets the status line and does not pay.
func sell_junk() -> bool:
	return _ask_bulk(true, sell_junk_button)


## Asks before selling every backpack item that is not favorite.
func sell_all() -> bool:
	return _ask_bulk(false, sell_all_button)


func _empty_line(junk_only: bool) -> String:
	if junk_only:
		return "Nothing marked as junk."
	if player.inventory.items.is_empty():
		return "Nothing to sell."
	return "Everything left is locked."


func _ask_bulk(junk_only: bool, from: Button) -> bool:
	if pending_kind != "":
		cancel_sale(false)
	var items := Vendor.bulk_targets(player.inventory, junk_only)
	if items.is_empty():
		status.text = _empty_line(junk_only)
		return false
	pending_kind = "junk" if junk_only else "all"
	confirm_from = from
	confirm_label.text = Vendor.confirm_text(items)
	confirm_row.visible = true
	if keep_button.is_inside_tree():
		keep_button.grab_focus()
	return false


## Recomputes the eligible set. An empty set pays nothing.
func confirm_sale() -> bool:
	var kind := pending_kind
	var from := confirm_from
	pending_kind = ""
	confirm_from = null
	confirm_row.visible = false
	if kind == "" or player == null:
		return false
	var junk_only := kind == "junk"
	var items := Vendor.bulk_targets(player.inventory, junk_only)
	if items.is_empty():
		status.text = _empty_line(junk_only)
		_focus(from)
		refresh()
		return false
	var g := vendor.sell_items(player.inventory, items)
	status.text = "Sold %d items for %d gold." % [items.size(), g]
	refresh()
	_focus(from)
	return g > 0


## `restore` puts focus back on the bulk button that opened the confirm.
func cancel_sale(restore := true) -> void:
	var from := confirm_from
	pending_kind = ""
	confirm_from = null
	if confirm_row:
		confirm_row.visible = false
	if restore:
		_focus(from)


func _drop_confirm_for_other() -> void:
	if pending_kind != "":
		cancel_sale(false)


func _focus(b: Button) -> void:
	if b and b.is_inside_tree():
		b.grab_focus()


func reroll_selected() -> bool:
	_drop_confirm_for_other()
	var it := player.inventory.at(_selected(pack_list))
	return _done(vendor.reroll(player.inventory, it as WieldablePart, seed_rng), "Re-rolled.")


func _unhandled_input(event: InputEvent) -> void:
	if UiAnim.is_shown(self) and event.is_action_pressed(&"ui_cancel"):
		if pending_kind != "":
			cancel_sale(true)
		else:
			close()
		get_viewport().set_input_as_handled()
