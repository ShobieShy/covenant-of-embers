extends TestCase
## Step 25 done check: assemble then disassemble returns the same parts.
##  - preview consumes nothing; assemble takes base + parts from the backpack and puts the
##    assembled wieldable (Magewar stats: worked example 4 = 14.5 dmg) there, emitting
##    crafting_completed on the station and the EventBus;
##  - disassemble gives back the very same part objects + a bare base; refuses when full;
##  - bad builds / items not in the backpack are refused with a message.

const PLAYER_SCENE := "res://scenes/player/player.tscn"


func _player() -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(Vector3(0, 300, -900), 0.0)
	return p


func _station() -> AssemblyStation:
	var s := AssemblyStation.new()
	runner_tree.root.add_child(s)
	s.global_position = Vector3(0, 300, -901)
	return s


func _part(id: String) -> WieldablePart:
	return WieldablePart.load_part(id).duplicate() as WieldablePart


func test_assemble_then_disassemble() -> void:
	var p := _player()
	var st := _station()
	check(st.is_in_group(AssemblyStation.GROUP) and st.in_reach(p), "station in reach")
	var base := WieldableInstance.load_base("swift_wind_wand")
	var parts := [_part("rare_water_head"), _part("uncommon_air_exterior"), _part("uncommon_dark_handle")]
	p.inventory.add(base)
	for x in parts:
		p.inventory.add(x)
	var pv := st.preview(base, parts)
	check(pv != null and p.inventory.size() == 4, "preview consumes nothing")
	var events := [0]
	var cb := func(_pl, _w): events[0] += 1
	GameEvents.bus().crafting_completed.connect(cb)
	var w := st.assemble(p, base, parts)
	GameEvents.bus().crafting_completed.disconnect(cb)
	check(w != null, "assembled: " + st.last_error)
	check_near(w.damage(), 14.5, 1e-4, "Magewar worked example 4 damage")
	check(w.display_name() == "Uncommon Water Wand", w.display_name())
	check(p.inventory.size() == 1 and p.inventory.has(w), "only the wand left in the pack")
	check(events[0] == 1 and st.crafted == 1, "crafting_completed")
	var back := st.disassemble(p, w)
	check(back.size() == 3, "3 parts back")
	for i in 3:
		check(back.has(parts[i]) and p.inventory.has(parts[i]), "same part object %d" % i)
	check(not p.inventory.has(w) and p.inventory.size() == 4, "parts + bare base")
	var bare := 0
	for it in p.inventory.items:
		if it is WieldableInstance and not it.assembled and it.def == base.def:
			bare += 1
	check(bare == 1, "bare base returned")
	p.queue_free()
	st.queue_free()


func test_refusals() -> void:
	var p := _player()
	var st := _station()
	var base := WieldableInstance.load_base("apprentice_fire_staff")
	var head := _part("basic_fire_head")
	var ext := _part("basic_exterior")
	p.inventory.add(base)
	p.inventory.add(head)
	p.inventory.add(ext)
	check(st.assemble(p, base, [head, ext]) == null and st.last_error != "", "staff needs 4 parts")
	var inner := _part("basic_interior")
	var handle := _part("basic_handle")  # not in the pack
	p.inventory.add(inner)
	check(st.assemble(p, base, [head, ext, inner, handle]) == null and "backpack" in st.last_error, "part not in pack")
	p.inventory.add(handle)
	st.can_craft_staffs = false
	check(st.assemble(p, base, [head, ext, inner, handle]) == null, "station without staffs")
	st.can_craft_staffs = true
	var w := st.assemble(p, base, [head, ext, inner, handle])
	check(w != null and p.inventory.size() == 1, "staff built")
	# Full pack: 4 parts + base need 5 slots, the staff frees 1.
	while p.inventory.free_slots() > 3:
		p.inventory.add(WieldablePart.new())
	check(st.disassemble(p, w).is_empty() and p.inventory.has(w), "full: refused")
	check(p.last_hint == PickupCollector.HINT_FULL, "full hint")
	p.queue_free()
	st.queue_free()
