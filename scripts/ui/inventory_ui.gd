class_name InventoryUi
extends CanvasLayer
## Inventory + equipment screen (BUILD_PLAN step 30; Magewar InventoryUI, Tab): backpack
## grid (rarity-tinted), worn equipment + staff/wand slots, a compare card for the selected
## item (green/red deltas vs what's worn), Equip, Ember Mark copy, and Ember Mark import.
## Opening sets player.ui_open (no actions, no mouse look) and shows the mouse.

const ACTION := &"inventory"
const BETTER := Color(0.35, 0.9, 0.35)
const WORSE := Color(0.95, 0.35, 0.3)

var player: Player
var root: PanelContainer
var grid: GridContainer
var slot_buttons: Array[Button] = []
var worn_buttons: Array[Button] = []     ## staff, wand, then EquipmentItem.Slot order
var card: RichTextLabel
var code_field: LineEdit
var status: Label
var dust_label: Label
var selected: Resource = null
var last_code := ""

func _init() -> void:
	layer = 3
	visible = false
	root = PanelContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(900, 560)
	root.position = Vector2(-450, -280)
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
		b.custom_minimum_size = Vector2(72, 44)
		b.pressed.connect(func(): select(player.inventory.at(i) if player else null))
		grid.add_child(b)
		slot_buttons.append(b)
	dust_label = _label("")
	left.add_child(dust_label)
	var mid := VBoxContainer.new()
	h.add_child(mid)
	mid.add_child(_label("Worn"))
	for i in 2 + EquipmentItem.SLOT_COUNT:
		var b := _button("")
		b.custom_minimum_size = Vector2(170, 36)
		b.pressed.connect(func(): select(_worn(i)))
		mid.add_child(b)
		worn_buttons.append(b)
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

func bind(p: Player) -> void:
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

static func name_of(item: Resource) -> String:
	if item == null:
		return ""
	if item.has_method("display_name"):
		return item.call("display_name")
	return String(item.get("display_name"))

static func color_of(item: Resource) -> Color:
	if item != null and item.has_method("rarity_color"):
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

func close() -> void:
	visible = false
	if player:
		player.ui_open = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func refresh() -> void:
	if player == null:
		return
	for i in slot_buttons.size():
		var it := player.inventory.at(i)
		slot_buttons[i].text = name_of(it)
		slot_buttons[i].modulate = color_of(it) if it else Color(1, 1, 1, 0.4)
	for i in worn_buttons.size():
		var it := _worn(i)
		var label: String = ["Staff", "Wand"][i] if i < 2 else EquipmentItem.SLOT_NAMES[i - 2]
		worn_buttons[i].text = "%s: %s" % [label, name_of(it) if it else "-"]
		worn_buttons[i].modulate = color_of(it) if it else Color(1, 1, 1, 0.6)
	dust_label.text = "Arcane Dust: %d" % player.inventory.dust
	card.text = card_text(selected)

func select(item: Resource) -> void:
	selected = item
	status.text = ""
	refresh()

## The compare card as BBCode: title in rarity colour, rows with green/red deltas.
func card_text(item: Resource) -> String:
	if item == null:
		return "[i]Select an item[/i]"
	if not (item is WieldableInstance or item is WieldablePart or item is EquipmentItem):
		return "[b]%s[/b]" % name_of(item)
	var c := CompareCard.for_item(item, player)
	var s := "[color=#%s][b]%s[/b][/color]\n%s %s\n" % [c.color.to_html(false), c.title, c.rarity_name, c.kind]
	if not c.compared_to.is_empty():
		s += "[i]vs %s[/i]\n" % c.compared_to
	for r in c.rows:
		s += "%s: %s" % [r.label, snapped(r.value, 0.01)]
		if r.compared and not is_zero_approx(r.delta):
			s += " [color=#%s](%+.2f)[/color]" % [(BETTER if r.better else WORSE).to_html(false), r.delta]
		s += "\n"
	return s

func equip_selected() -> bool:
	if selected == null or player == null:
		return false
	var ok := player.equip_from_inventory(selected)
	status.text = "Equipped." if ok else "Can't equip that."
	refresh()
	return ok

## Puts the selected item's Ember Mark in the code field (and the clipboard when there is one).
func copy_selected() -> String:
	last_code = ItemCodes.encode(selected) if selected else ""
	if last_code.is_empty():
		status.text = ItemCodes.encode_error(selected) if selected else "Nothing selected."
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
