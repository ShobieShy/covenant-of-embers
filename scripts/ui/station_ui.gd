class_name StationUi
extends CanvasLayer
## Assembly Station screen (BUILD_PLAN step 31; Magewar assembly_station_ui): pick a bare
## base from the backpack, one part per type slot (Charm/Interior disabled for a wand),
## a live preview (Magewar get_stats_summary + draw time + gem slots), an error line listing
## AssemblyStation.check(), and buttons for Assemble / Disassemble / Salvage / Upgrade /
## Socket gem on the selected backpack item. Opens with `interact` near a station.

const P := WieldablePart.PartType

var player: Player
var station: AssemblyStation
var base: WieldableInstance
var parts := {}                       ## PartType -> WieldablePart
var selected: Resource                ## the backpack item the buttons act on
var root: PanelContainer
var list: ItemList
var slot_buttons := {}                ## PartType -> Button
var base_button: Button
var preview_label: Label
var error_label: Label
var status: Label

func _init() -> void:
	layer = 3
	visible = false
	root = PanelContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	root.custom_minimum_size = Vector2(900, 520)
	root.position = Vector2(-450, -260)
	add_child(root)
	var h := HBoxContainer.new()
	root.add_child(h)
	list = ItemList.new()
	list.custom_minimum_size = Vector2(300, 480)
	list.item_selected.connect(func(i): pick(player.inventory.at(i)))
	h.add_child(list)
	var mid := VBoxContainer.new()
	h.add_child(mid)
	base_button = Button.new()
	base_button.pressed.connect(func(): set_base(null))
	mid.add_child(base_button)
	for t in [P.HEAD, P.EXTERIOR, P.INTERIOR, P.HANDLE, P.CHARM]:
		var b := Button.new()
		b.custom_minimum_size = Vector2(240, 34)
		b.pressed.connect(func(): set_part(t, null))   # click a filled slot to empty it
		mid.add_child(b)
		slot_buttons[t] = b
	for pair in [["Assemble", assemble], ["Disassemble", disassemble_selected],
			["Salvage", salvage_selected], ["Upgrade", upgrade_selected], ["Close", close]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(pair[1])
		mid.add_child(b)
	var right := VBoxContainer.new()
	h.add_child(right)
	preview_label = Label.new()
	preview_label.custom_minimum_size = Vector2(300, 260)
	right.add_child(preview_label)
	error_label = Label.new()
	error_label.modulate = Color(1, 0.5, 0.4)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	error_label.custom_minimum_size = Vector2(300, 0)
	right.add_child(error_label)
	status = Label.new()
	right.add_child(status)

func bind(p: Player) -> void:
	player = p
	p.inventory.changed.connect(refresh)

func open(s: AssemblyStation) -> void:
	station = s
	visible = true
	player.ui_open = true
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()

func close() -> void:
	visible = false
	base = null
	parts.clear()
	if player:
		player.ui_open = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func nearest_station() -> AssemblyStation:
	if player == null or not player.is_inside_tree():
		return null
	for s in player.get_tree().get_nodes_in_group(AssemblyStation.GROUP):
		if (s as AssemblyStation).in_reach(player):
			return s
	return null

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif not visible and player and not player.ui_open and event.is_action_pressed(&"interact"):
		var s := nearest_station()
		if s:
			open(s)
			get_viewport().set_input_as_handled()

## A backpack item was clicked: bare bases fill the base slot, parts their type slot,
## and anything becomes the target of Disassemble/Salvage/Upgrade/Socket.
func pick(item: Resource) -> void:
	selected = item
	status.text = ""
	if item is WieldableInstance and not (item as WieldableInstance).assembled:
		set_base(item)
	elif item is WieldablePart:
		set_part((item as WieldablePart).part_type, item)
	elif item is ElementGem:
		socket_gem(item)
	refresh()

func set_base(b: WieldableInstance) -> void:
	base = b
	if b:
		for t in parts.keys():
			if not Assembly.allows(b.type(), t):
				parts.erase(t)
	refresh()

func set_part(t: int, part: WieldablePart) -> void:
	if part == null:
		parts.erase(t)
	elif base == null or Assembly.allows(base.type(), t):
		parts[t] = part
	refresh()

func chosen_parts() -> Array:
	var a: Array = []
	for t in [P.HEAD, P.EXTERIOR, P.INTERIOR, P.HANDLE, P.CHARM]:
		if parts.has(t):
			a.append(parts[t])
	return a

func errors() -> PackedStringArray:
	if station == null:
		return PackedStringArray(["No station."])
	return station.check(base, chosen_parts())

## Magewar get_stats_summary + draw time + gem slots; "" while the build is invalid.
func preview_text() -> String:
	if station == null:
		return ""
	var w := station.preview(base, chosen_parts())
	if w == null:
		return ""
	return "[%s] %s - %s\nDamage: %.1f\nFire Rate: %.2f s\nAccuracy: %.2f\nMana Cost: %.1f\nDraw: %.2f s\nGem slots: %d" % [
		w.rarity().display_name, Assembly.TYPE_NAMES[w.type()],
		ElementTable.load_default().display_name(w.element()),
		w.damage(), w.cooldown(), w.accuracy(), w.mana_cost(),
		w.draw_seconds(player.loadout.swap_seconds), w.gem_slots()]

func refresh() -> void:
	if player == null:
		return
	list.clear()
	for it in player.inventory.items:
		var i := list.add_item(InventoryUi.name_of(it))
		list.set_item_custom_fg_color(i, InventoryUi.color_of(it))
	base_button.text = "Base: %s" % (base.display_name() if base else "(pick a bare staff/wand)")
	for t in slot_buttons:
		var b: Button = slot_buttons[t]
		var ok := base == null or Assembly.allows(base.type(), t)
		b.disabled = not ok
		b.text = "%s: %s" % [WieldablePart.PART_TYPE_NAMES[t], parts[t].display_name if parts.has(t) else ("-" if ok else "n/a")]
	preview_label.text = preview_text()
	error_label.text = "\n".join(errors())

func assemble() -> WieldableInstance:
	if station == null:
		return null
	var w := station.assemble(player, base, chosen_parts())
	if w == null:
		status.text = station.last_error
	else:
		status.text = "Assembled %s." % w.display_name()
		base = null
		parts.clear()
		selected = w
	refresh()
	return w

func disassemble_selected() -> bool:
	var w := selected as WieldableInstance
	var out := station.disassemble(player, w) if station else []
	status.text = "Disassembled." if not out.is_empty() else (station.last_error if station else "")
	refresh()
	return not out.is_empty()

func _result(err: String, ok_text: String) -> bool:
	status.text = ok_text if err.is_empty() else err
	refresh()
	return err.is_empty()

func salvage_selected() -> bool:
	var part := selected as WieldablePart
	var dust := CraftingExtras.salvage_value(part) if part else 0
	if parts.values().has(part):
		parts.erase(part.part_type)
	return _result(CraftingExtras.salvage(player.inventory, part), "Salvaged for %d Arcane Dust." % dust)

func upgrade_selected() -> bool:
	return _result(CraftingExtras.upgrade(player.inventory, selected as WieldablePart), "Upgraded.")

## Sockets `gem` into the chosen Head slot (owner = the base, so a wand caps at 1 gem).
func socket_gem(gem: ElementGem) -> bool:
	var head: WieldablePart = parts.get(P.HEAD)
	return _result(CraftingExtras.socket(player.inventory, head, gem, base), "Gem socketed.")
