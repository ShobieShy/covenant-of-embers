extends SceneTree
## Renders every staff/wand part and tier, plus assembled weapons, for the 0.15.0 sheets.
## godot --rendering-driver opengl3 --path . -s tools/weapon_contact.gd -- <out_dir>

const TIERS: PackedStringArray = ["basic", "uncommon", "rare", "mythic", "primordial", "unique"]
const PARTS: PackedStringArray = ["head", "exterior", "interior", "handle", "charm"]
const TYPES: Array[WieldablePart.PartType] = [
	WieldablePart.PartType.HEAD,
	WieldablePart.PartType.EXTERIOR,
	WieldablePart.PartType.INTERIOR,
	WieldablePart.PartType.HANDLE,
	WieldablePart.PartType.CHARM,
]
const ELEMS: Array[ElementTable.Element] = [
	ElementTable.Element.ARCANE,
	ElementTable.Element.FIRE,
	ElementTable.Element.WATER,
	ElementTable.Element.EARTH,
	ElementTable.Element.AIR,
	ElementTable.Element.LIGHT,
	ElementTable.Element.DARK,
]


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://weapon_contact"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(1.0, 0.0, 1.0)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.54, 0.44)
	env.environment.glow_enabled = false
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -28, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.94, 0.84)
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 140, 0)
	fill.light_energy = 0.45
	stage.add_child(fill)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.current = true
	stage.add_child(cam)
	var holder := Node3D.new()
	holder.name = "Holder"
	stage.add_child(holder)

	for pi in PARTS.size():
		for tier in TIERS:
			_clear(holder)
			var width := 0.0
			var height := 0.0
			var nodes: Array[Node3D] = []
			for _e in ELEMS:
				var inst := StaffKit.instantiate(StaffKit.mesh_id(PARTS[pi], tier))
				var part := WieldablePart.make(TYPES[pi], 0.0, 1.0, 0.0, ELEMS[nodes.size()])
				part.rarity = tier
				StaffKit._paint(inst, part)
				StaffKit._dress(inst, 1)
				holder.add_child(inst)
				var mi := inst as MeshInstance3D
				if mi == null:
					var found := inst.find_children("*", "MeshInstance3D", true, false)
					mi = found[0] as MeshInstance3D if not found.is_empty() else null
				var abb := mi.get_aabb()
				height = maxf(height, abb.size.y)
				nodes.append(inst)
			var gap := height * 0.42
			var x := 0.0
			for inst in nodes:
				var mi2 := inst as MeshInstance3D
				if mi2 == null:
					var found2 := inst.find_children("*", "MeshInstance3D", true, false)
					mi2 = found2[0] as MeshInstance3D if not found2.is_empty() else null
				var abb2 := mi2.get_aabb()
				inst.position = Vector3(x - abb2.position.x + abb2.size.x * 0.0, -abb2.position.y - abb2.size.y * 0.5, 0.0)
				x += abb2.size.x + gap
				width = x
			width -= gap
			var aspect := 1280.0 / 720.0
			cam.size = maxf(height / 0.58, width / (aspect * 0.92))
			cam.position = Vector3((width - gap) * 0.5, 0.0, 4.0)
			cam.rotation = Vector3.ZERO
			await _shot("%s/%s_%s.png" % [out, PARTS[pi], tier])
			print("[weapon_contact] ", PARTS[pi], " ", tier)

	for tier in TIERS:
		for form in ["staff", "wand"]:
			_clear(holder)
			var w := _weapon(form, tier, ElementTable.Element.ARCANE)
			var sc := 1.0 if form == "staff" else float(StaffKit.layout()["wand_length"]) / float(StaffKit.layout()["staff_length"])
			var kit := StaffKit.build(w, 1.0, 0.04, 0.06, StaffKit.sheet_color(0), 1, sc, false)
			holder.add_child(kit)
			var fig := StaffKit.instantiate("scale_figure")
			fig.position = Vector3(-0.85, 0.0, 0.0)
			holder.add_child(fig)
			cam.size = 2.3
			cam.position = Vector3(0.15, 0.9, 5.0)
			cam.rotation = Vector3.ZERO
			await _shot("%s/assembled_%s_%s.png" % [out, form, tier])
			print("[weapon_contact] assembled ", form, " ", tier)
	quit()


func _weapon(form: String, tier: String, element: ElementTable.Element) -> WieldableInstance:
	var base := "apprentice_fire_staff" if form == "staff" else "novice_arcane_wand"
	var w := WieldableInstance.load_base(base)
	for ty in TYPES:
		var p := WieldablePart.make(ty, 0.0, 1.0, 0.0, element)
		p.rarity = tier
		w.parts.append(p)
	w.assembled = true
	return w


func _clear(holder: Node) -> void:
	for c in holder.get_children():
		c.free()


func _shot(path: String) -> void:
	for _f in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
