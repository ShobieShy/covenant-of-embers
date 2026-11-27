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
	for n in ["Handle", "Exterior", "Interior", "Head", "Charm"]:
		var part := vm.kit.find_child(n, true, false) as MeshInstance3D
		check(part != null and part.mesh != null, "has " + n)
		check(not (part.mesh is PrimitiveMesh), n + " is a real mesh")
	check(StaffKit.tris(vm) <= 4000, "under 4k tris (%d)" % StaffKit.tris(vm))
	for mi in vm.find_children("*", "MeshInstance3D", true, false):
		if _under_brand(mi):
			continue
		var mesh := (mi as MeshInstance3D).mesh
		if mesh != null:
			check(not (mesh is PrimitiveMesh), "no primitive " + mi.name)
		check((mi as MeshInstance3D).layers == Viewmodel.LAYER_MASK, "viewmodel layer " + mi.name)
	vm.show_wieldable(_w("apprentice_fire_staff", []))
	check(
		vm.kit.find_child("Interior", true, false) == null and vm.kit.find_child("Charm", true, false) == null,
		"rebuilt bare"
	)
	check(vm.shaft.mesh != null and not (vm.shaft.mesh is PrimitiveMesh), "bare shaft is a real mesh")
	check(vm.gem.mesh != null and not (vm.gem.mesh is PrimitiveMesh), "focus gem is a real mesh")
	vm.free()


func _under_brand(n: Node) -> bool:
	while n != null:
		if n.name == "BrandFX":
			return true
		n = n.get_parent()
	return false


func _world_box(mi: MeshInstance3D) -> AABB:
	return mi.global_transform * mi.get_aabb()


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
	var handle := vm.kit.find_child("Handle", true, false) as MeshInstance3D
	var shell := vm.kit.find_child("Exterior", true, false) as MeshInstance3D
	var interior := vm.kit.find_child("Interior", true, false) as MeshInstance3D
	var head := vm.kit.find_child("Head", true, false) as MeshInstance3D
	var charm := vm.kit.find_child("Charm", true, false) as MeshInstance3D
	check(_gap(_world_box(handle), _world_box(shell)) < 0.02, "%s handle meets exterior" % label)
	check(_gap(_world_box(shell), _world_box(head)) < 0.02, "%s exterior meets head" % label)
	check(_gap(_world_box(head), _world_box(vm.gem)) < 0.03, "%s head meets gem" % label)
	if interior:
		check(_gap(_world_box(shell), _world_box(interior)) < 0.02, "%s exterior meets interior" % label)
	if charm:
		check(_gap(_world_box(head), _world_box(charm)) < 0.02, "%s head meets charm" % label)


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


func test_every_tier_on_both_forms() -> void:
	var tiers := ["basic", "uncommon", "rare", "mythic", "primordial", "unique"]
	var types: Array[WieldablePart.PartType] = [
		WieldablePart.PartType.HEAD,
		WieldablePart.PartType.EXTERIOR,
		WieldablePart.PartType.INTERIOR,
		WieldablePart.PartType.HANDLE,
		WieldablePart.PartType.CHARM,
	]
	for form in ["apprentice_fire_staff", "novice_arcane_wand"]:
		for tier in tiers:
			var w := WieldableInstance.load_base(form)
			for ty in types:
				var p := WieldablePart.make(ty)
				p.rarity = tier
				w.parts.append(p)
			var vm := Viewmodel.new()
			runner_tree.root.add_child(vm)
			vm.show_wieldable(w)
			for n in ["Handle", "Exterior", "Interior", "Head", "Charm"]:
				var mi := vm.kit.find_child(n, true, false) as MeshInstance3D
				check(
					mi != null and mi.mesh != null and not (mi.mesh is PrimitiveMesh),
					"%s %s %s mesh" % [form, tier, n]
				)
			_meet(vm, "%s %s" % [form, tier])
			check(StaffKit.tris(vm) <= 4000, "%s %s under 4k (%d)" % [form, tier, StaffKit.tris(vm)])
			vm.free()


func test_variant_stable() -> void:
	var p := load("res://resources/parts/basic_handle.tres") as WieldablePart
	check(StaffKit.variant(p, 3) == StaffKit.variant(p, 3), "stable variant")
	check(StaffKit.variant(null, 3) == 0, "null part")
