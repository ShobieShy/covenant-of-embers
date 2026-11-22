extends TestCase
## Step 122 (Art A4): the modular staff kit shows the attached parts, stays under the
## 4k-tri budget, rebuilds when parts change, and keeps every mesh on the viewmodel layer.


func _w(base: String, ids: Array) -> WieldableInstance:
	var w := WieldableInstance.load_base(base)
	for id: String in ids:
		w.parts.append(load("res://resources/parts/%s.tres" % id) as WieldablePart)
	w.assembled = not ids.is_empty()
	return w


func test_parts_and_budget() -> void:
	var vm := Viewmodel.new()
	var full := [
		"uncommon_dark_handle",
		"mythic_water_exterior",
		"basic_fire_interior",
		"primordial_fire_head",
		"unique_void_charm"
	]
	vm.show_wieldable(_w("apprentice_fire_staff", full))
	check(vm.kit != null, "kit built")
	for n in ["Pommel", "Band0", "Core", "Prong0", "Charm"]:
		check(vm.kit.find_child(n, true, false) != null, "has " + n)
	check(StaffKit.tris(vm) <= 4000, "under 4k tris (%d)" % StaffKit.tris(vm))
	for mi in vm.find_children("*", "MeshInstance3D", true, false):
		check((mi as MeshInstance3D).layers == Viewmodel.LAYER_MASK, "viewmodel layer " + mi.name)
	vm.show_wieldable(_w("apprentice_fire_staff", []))
	check(
		vm.kit.find_child("Core", true, false) == null and vm.kit.find_child("Charm", true, false) == null,
		"rebuilt bare"
	)
	vm.free()


func _world_box(mi: MeshInstance3D) -> AABB:
	return mi.transform * mi.get_aabb()


func _gap(a: AABB, b: AABB) -> float:
	var d := 0.0
	for i in 3:
		var an := a.position[i]
		var ax := an + a.size[i]
		var bn := b.position[i]
		var bx := bn + b.size[i]
		if ax < bn:
			d = maxf(d, bn - ax)
		elif bx < an:
			d = maxf(d, an - bx)
	return d


func _meet(vm: Viewmodel, label: String) -> void:
	var grip := vm.kit.find_child("Grip", true, false) as MeshInstance3D
	var pommel := vm.kit.find_child("Pommel", true, false) as MeshInstance3D
	var shell := vm.kit.find_child("Shell", true, false) as MeshInstance3D
	var collar := vm.kit.find_child("Collar", true, false) as MeshInstance3D
	var prong := vm.kit.find_child("Prong0", true, false) as MeshInstance3D
	check(_gap(_world_box(grip), _world_box(pommel)) < 0.02, "%s grip meets pommel" % label)
	check(_gap(_world_box(grip), _world_box(shell)) < 0.02, "%s grip meets shell" % label)
	check(_gap(_world_box(shell), _world_box(collar)) < 0.02, "%s shell meets collar" % label)
	check(_gap(_world_box(collar), _world_box(prong)) < 0.03, "%s collar meets prong" % label)
	check(_gap(_world_box(collar), _world_box(vm.gem)) < 0.03, "%s collar meets gem" % label)
	var cord := vm.kit.find_child("Cord", true, false) as MeshInstance3D
	var charm := vm.kit.find_child("Charm", true, false) as MeshInstance3D
	if cord and charm:
		check(_gap(_world_box(cord), _world_box(charm)) < 0.02, "%s cord meets charm" % label)
		check(_gap(_world_box(cord), _world_box(collar)) < 0.02, "%s cord meets collar" % label)


func test_parts_meet() -> void:
	var vm := Viewmodel.new()
	runner_tree.root.add_child(vm)
	vm.show_wieldable(
		_w(
			"apprentice_fire_staff",
			[
				"uncommon_dark_handle",
				"mythic_water_exterior",
				"basic_fire_interior",
				"primordial_fire_head",
				"unique_void_charm"
			]
		)
	)
	_meet(vm, "staff")
	vm.show_wieldable(_w("novice_arcane_wand", ["basic_handle", "basic_exterior", "basic_fire_head"]))
	_meet(vm, "wand")
	vm.free()


func test_variant_stable() -> void:
	var p := load("res://resources/parts/basic_handle.tres") as WieldablePart
	check(StaffKit.variant(p, 3) == StaffKit.variant(p, 3), "stable variant")
	check(StaffKit.variant(null, 3) == 0, "null part")
