class_name InventoryUi
extends CanvasLayer
## Inventory + equipment screen (BUILD_PLAN step 30; Magewar InventoryUI, Tab): backpack
## grid (rarity-tinted), worn equipment + staff/wand slots, a compare card for the selected
## item (green/red deltas vs what's worn), Equip, Ember Mark copy, and Ember Mark import.
## Opening sets player.ui_open (no actions, no mouse look) and shows the mouse.
## t74u: Trash (button, Delete/X over a slot, pad Y) with a confirm for Rare+ and a
## quantity for potions; Junk marks (sold together at vendors). Quest items and worn
## gear can't be trashed. Only the bound (local) player's inventory is ever touched.

const ACTION := &"inventory"
const BETTER := Color(0.35, 0.9, 0.35)
const WORSE := Color(0.95, 0.35, 0.3)
const TRASH_ACTION := &"inventory_trash"

var player: Player
var root: PanelContainer
var grid: GridContainer
var slot_buttons: Array[Button] = []
var worn_buttons: Array[Button] = []  ## staff, wand, then EquipmentItem.Slot order
var card: RichTextLabel
var code_field: LineEdit
var status: Label
var dust_label: Label
var selected: Variant = null  ## a Resource, or a quest item id (String)
var hovered: Variant = null
var trash_button: Button
var junk_button: Button
var qty: SpinBox
var confirm_row: VBoxContainer
var confirm_label: Label
var potion_button: Button
var quest_box: VBoxContainer
var pending_trash: Variant = null
var last_code := ""


func _init() -> void:
	layer = 3
	visible = false
	root = PanelContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(1000, 560)
	root.position = Vector2(-500, -280)
	add_child(root)
	var h := HBoxContainer.new()
	root.add_child(h)
	var left := VBoxContainer.new()
	h.add_child(left)
	left.add_child(_label("Backpack"))
	grid = GridContainer.new()
	grid.columns = 6
	left.add_child(grid)
	for i in Inventory.CAPACITY:
		var b := _button("")
		b.custom_minimum_size = Vector2(64, 64)  # icon-only slot; the name is the tooltip + card title
		b.theme_type_variation = UiTheme.SLOT
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(func(): select(player.inventory.at(i) if player else null))
		b.mouse_entered.connect(func(): hovered = player.inventory.at(i) if player else null)
		b.mouse_exited.connect(func(): hovered = null)
		grid.add_child(b)
		slot_buttons.append(b)
	dust_label = _label("")
	left.add_child(dust_label)
	var mid := VBoxContainer.new()
	h.add_child(mid)
	mid.add_child(_label("Worn"))
	for i in 2 + EquipmentItem.SLOT_COUNT:
		var b := _button("")
		b.custom_minimum_size = Vector2(250, 44)
		b.theme_type_variation = UiTheme.SLOT
		b.pressed.connect(func(): select(_worn(i)))
		b.mouse_entered.connect(func(): hovered = _worn(i))
		b.mouse_exited.connect(func(): hovered = null)
		mid.add_child(b)
		worn_buttons.append(b)
	potion_button = _button("")
	potion_button.custom_minimum_size = Vector2(250, 44)
	potion_button.theme_type_variation = UiTheme.SLOT
	potion_button.pressed.connect(func(): select(player.equipment.potion if player else null))
	mid.add_child(potion_button)
	mid.add_child(_label("Quest items"))
	quest_box = VBoxContainer.new()
	mid.add_child(quest_box)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	card = RichTextLabel.new()
	card.bbcode_enabled = true
	card.fit_content = true
	card.custom_minimum_size = Vector2(300, 300)
	right.add_child(card)
	var eq := _button("Equip")
	eq.pressed.connect(equip_selected)
	right.add_child(eq)
	var uq := _button("Unequip")  # t60u: every worn slot, staff and wand included
	uq.pressed.connect(unequip_selected)
	right.add_child(uq)
	var th := HBoxContainer.new()
	right.add_child(th)
	trash_button = _button("Trash")
	trash_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trash_button.pressed.connect(func(): request_trash(selected))
	th.add_child(trash_button)
	qty = SpinBox.new()
	qty.min_value = 1
	qty.max_value = 1
	qty.tooltip_text = "How many to trash"
	qty.custom_minimum_size = Vector2(80, 0)
	th.add_child(qty)
	junk_button = _button("Mark junk")
	junk_button.custom_minimum_size = Vector2(120, 0)
	junk_button.pressed.connect(toggle_junk)
	th.add_child(junk_button)
	confirm_row = VBoxContainer.new()
	confirm_row.visible = false
	right.add_child(confirm_row)
	confirm_label = _label("")
	confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_label.modulate = WORSE
	confirm_row.add_child(confirm_label)
	var yn := HBoxContainer.new()
	confirm_row.add_child(yn)
	var yes := _button("Trash it")
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.pressed.connect(confirm_trash)
	yn.add_child(yes)
	var no := _button("Keep")
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(cancel_trash)
	yn.add_child(no)
	var cp := _button("Copy Ember Mark")
	cp.pressed.connect(copy_selected)
	right.add_child(cp)
	code_field = LineEdit.new()
	code_field.placeholder_text = "Paste an Ember Mark"
	right.add_child(code_field)
	var im := _button("Import")
	im.pressed.connect(func(): import_code(code_field.text))
	right.add_child(im)
	status = _label("")
	right.add_child(status)


static func ensure_trash_action() -> void:
	if InputMap.has_action(TRASH_ACTION):
		return
	InputMap.add_action(TRASH_ACTION)
	for k in [KEY_DELETE, KEY_X]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(TRASH_ACTION, e)
	var j := InputEventJoypadButton.new()
	j.button_index = JOY_BUTTON_Y
	InputMap.action_add_event(TRASH_ACTION, j)


func bind(p: Player) -> void:
	ensure_trash_action()
	player = p
	p.inventory.changed.connect(refresh)
	p.equipment.changed.connect(func(_s): refresh())


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _button(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.clip_text = true
	return b


func _worn(i: int) -> Resource:
	if player == null:
		return null
	return player.loadout.wieldable(i) if i < 2 else player.equipment.item(i - 2)


static func name_of(item: Variant) -> String:
	if item == null:
		return ""
	if item is String:
		return String(item).capitalize()
	if item.has_method("display_name"):
		return item.call("display_name")
	return String(item.get("display_name"))


static func color_of(item: Variant) -> Color:
	if item is Resource and item.has_method("rarity_color"):
		return item.call("rarity_color")
	return Color.WHITE


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	if player:
		player.ui_open = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	Gamepad.focus_first(self)  # step 77


func close() -> void:
	visible = false
	if player:
		player.ui_open = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle() -> void:
	if visible:
		close()
	elif not IntroDirector.refuse(self, "inventory"):  # step 112: locked early in the intro
		open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"ui_cancel"):
		if pending_trash != null:
			cancel_trash()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif visible and InputMap.has_action(TRASH_ACTION) and event.is_action_pressed(TRASH_ACTION):
		if code_field.has_focus():
			return  # typing an X into the Ember Mark field
		var target: Variant = hovered if hovered != null else selected
		if target == null:
			var f := get_viewport().gui_get_focus_owner()
			var i := slot_buttons.find(f)
			target = player.inventory.at(i) if player and i >= 0 else null
		if target != null:
			select(target)
			request_trash(target)
		get_viewport().set_input_as_handled()


func refresh() -> void:
	if player == null:
		return
	for i in slot_buttons.size():
		var it := player.inventory.at(i)
		slot_buttons[i].tooltip_text = name_of(it)
		ItemIcons.dress(slot_buttons[i], it)
		slot_buttons[i].modulate = color_of(it) if it else Color(1, 1, 1, 0.4)
	for i in worn_buttons.size():
		var it := _worn(i)
		var label: String = ["Staff", "Wand"][i] if i < 2 else EquipmentItem.SLOT_NAMES[i - 2]
		worn_buttons[i].text = "%s: %s" % [label, name_of(it) if it else "-"]
		worn_buttons[i].modulate = color_of(it) if it else Color(1, 1, 1, 0.6)
		ItemIcons.dress(worn_buttons[i], it)
	dust_label.text = "Arcane Dust: %d" % player.inventory.dust
	for i in slot_buttons.size():
		var it := player.inventory.at(i)
		if it and player.inventory.is_junk(it):
			slot_buttons[i].modulate = slot_buttons[i].modulate.darkened(0.55)
			slot_buttons[i].tooltip_text += " (junk)"
	var pot := player.equipment.potion
	potion_button.text = ("Potions: %s x%d" % [name_of(pot), player.equipment.potion_count] if pot else "Potions: -")
	for c in quest_box.get_children():
		c.queue_free()
	for q in player.quest_items:
		var qb := _button(name_of(q))
		qb.custom_minimum_size = Vector2(250, 32)
		qb.pressed.connect(func(): select(q))
		quest_box.add_child(qb)
	var is_pot: bool = selected is ConsumableItem
	qty.visible = is_pot
	qty.max_value = maxi(1, player.equipment.potion_count) if is_pot else 1
	junk_button.disabled = not (selected is Resource and player.inventory.has(selected))
	junk_button.text = ("Unmark junk" if selected is Resource and player.inventory.is_junk(selected) else "Mark junk")
	trash_button.disabled = selected == null
	card.text = card_text(selected)


func select(item: Variant) -> void:
	selected = item
	status.text = ""
	cancel_trash()
	refresh()


## Trash flow: Rare+ asks first (confirm_row), everything else goes straight away.
## Returns true when the item was destroyed now.
func request_trash(item: Variant) -> bool:
	if player == null or item == null:
		status.text = "Nothing selected."
		return false
	if item is Resource and ItemTrash.needs_confirm(item) and player.inventory.has(item):
		pending_trash = item
		confirm_label.text = "Trash %s for good?" % name_of(item)
		confirm_row.visible = true
		return false
	return _do_trash(item)


func confirm_trash() -> bool:
	var it: Variant = pending_trash
	cancel_trash()
	return _do_trash(it) if it != null else false


func cancel_trash() -> void:
	pending_trash = null
	if confirm_row:
		confirm_row.visible = false


func _do_trash(item: Variant) -> bool:
	var n := int(qty.value) if item is ConsumableItem else 1
	var label := name_of(item)
	var err := player.trash_item(item, n)
	status.text = err if not err.is_empty() else "Trashed %s." % label
	if err.is_empty():
		if not (item is ConsumableItem and player.equipment.potion == item):
			selected = null
		hovered = null
	refresh()
	return err.is_empty()


func toggle_junk() -> bool:
	if player == null or not (selected is Resource):
		return false
	var on := not player.inventory.is_junk(selected)
	var ok := player.inventory.set_junk(selected, on)
	status.text = (("Marked as junk." if on else "Unmarked.") if ok else "Only backpack items can be junk.")
	refresh()
	return ok


## The compare card as BBCode: title in rarity colour, rows with green/red deltas.
func card_text(item: Variant) -> String:
	if item == null:
		return "[i]Select an item[/i]"
	if item is String:
		return "[b]%s[/b]\nQuest item (can't be trashed)" % name_of(item)
	if not (item is WieldableInstance or item is WieldablePart or item is EquipmentItem):
		return "[b]%s[/b]" % name_of(item)
	var c := CompareCard.for_item(item, player)
	var s := "[color=#%s][b]%s[/b][/color]\n%s %s\n" % [c.color.to_html(false), c.title, c.rarity_name, c.kind]
	if not c.compared_to.is_empty():
		s += "[i]vs %s[/i]\n" % c.compared_to
	for r in c.rows:
		s += "%s: %s" % [r.label, snapped(r.value, 0.01)]
		if r.compared and not is_zero_approx(r.delta):
			s += (" [color=#%s](%+.2f)[/color]" % [(BETTER if r.better else WORSE).to_html(false), r.delta])
		s += "\n"
	return s + c.extra_lines()


func equip_selected() -> bool:
	if not (selected is Resource) or player == null:
		return false
	var ok := player.equip_from_inventory(selected)
	status.text = "Equipped." if ok else "Can't equip that."
	refresh()
	return ok


## t60u: moves the selected worn staff/wand/gear piece into the backpack (refused when full).
func unequip_selected() -> bool:
	if not (selected is Resource) or player == null:
		return false
	var ok := false
	var worn := false
	for slot in [Loadout.Slot.STAFF, Loadout.Slot.WAND]:
		if player.loadout.wieldable(slot) == selected:
			worn = true
			ok = player.unequip_wieldable_to_inventory(slot)
	for slot in EquipmentItem.SLOT_COUNT:
		if not worn and player.equipment.item(slot) == selected:
			worn = true
			ok = player.unequip_item_to_inventory(slot)
	status.text = "Unequipped." if ok else ("Backpack full." if worn else "That isn't worn.")
	refresh()
	return ok


## Puts the selected item's Ember Mark in the code field (and the clipboard when there is one).
func copy_selected() -> String:
	last_code = ItemCodes.encode(selected) if selected is Resource else ""
	if last_code.is_empty():
		status.text = (ItemCodes.encode_error(selected) if selected is Resource else "Nothing selected.")
		return ""
	code_field.text = last_code
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(last_code)
	status.text = "Ember Mark copied."
	return last_code


## Decodes `code` into the backpack; false (with the reason in `status`) on a bad code or full pack.
func import_code(code: String) -> bool:
	var m := ItemCodes.decode(code.strip_edges())
	if not m.ok():
		status.text = "Bad Ember Mark: %s" % m.error
		return false
	if m.item is ConsumableItem:
		var n := player.equipment.add_potions(m.item, m.count)
		status.text = "Imported %d potion(s)." % n
		return n > 0
	if not player.inventory.add(m.item):
		status.text = "Backpack full."
		return false
	status.text = "Imported %s." % name_of(m.item)
	selected = m.item
	refresh()
	return true
