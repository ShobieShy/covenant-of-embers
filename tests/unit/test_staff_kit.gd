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


func test_variant_stable() -> void:
	var p := load("res://resources/parts/basic_handle.tres") as WieldablePart
	check(StaffKit.variant(p, 3) == StaffKit.variant(p, 3), "stable variant")
	check(StaffKit.variant(null, 3) == 0, "null part")
