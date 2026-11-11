class_name ElitePresence
extends RefCounted
## Name tag, glow, and a world health bar for affix elites and named rares.
## Presentation only: the 0.8.3 attack scripts are not involved.


static func attach(e: Enemy) -> void:
	if e == null or e.def == null or e.get_node_or_null("NameTag") != null:
		return
	var rare := String(e.def.get_meta(&"rare_id", ""))
	var affix := Elites.affix_of(e.def)
	if rare == "" and affix == "":
		return
	var tint: Color = NamedUniques.COLOR if rare != "" else Elites.COLORS.get(affix, Color.WHITE)
	if e._body_mat:
		e._body_mat.emission_enabled = true
		e._body_mat.emission = tint
		e._body_mat.emission_energy_multiplier = 0.55
	var tag := Label3D.new()
	tag.name = "NameTag"
	tag.text = e.display_name()
	tag.font_size = 42
	tag.pixel_size = 0.004
	tag.position = Vector3(0.0, e.def.size.y + 0.55, 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = tint
	tag.outline_size = 8
	tag.no_depth_test = true
	e.add_child(tag)
	e.add_child(_bar("EliteBarBack", Color(0.05, 0.05, 0.05), e.def.size.y + 0.28))
	e.add_child(_bar("EliteBar", tint, e.def.size.y + 0.3))


static func sync(e: Enemy) -> void:
	var bar := e.get_node_or_null("EliteBar") as MeshInstance3D
	if bar == null:
		return
	var alive := e.alive()
	var frac := clampf(e.health / e.max_health(), 0.0, 1.0) if e.max_health() > 0.0 else 0.0
	bar.scale = Vector3(maxf(frac, 0.02), 1.0, 1.0)
	bar.visible = alive
	var back := e.get_node_or_null("EliteBarBack") as Node3D
	if back:
		back.visible = alive
	var tag := e.get_node_or_null("NameTag") as Node3D
	if tag:
		tag.visible = alive


static func _bar(node_name: String, color: Color, y: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.06, 0.02)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mi.material_override = mat
	mi.position = Vector3(0.0, y, 0.0)
	return mi
