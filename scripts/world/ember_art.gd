class_name EmberArt
extends RefCounted
## Step 163 (W12) Ember Art pass: the slots for the original landmark / chest / waystone /
## decal / skyline / world-map art (TERRAIN_MAPS_PLAN section 11, docs/EMBER_ART_REQUESTS.md).
## Each slot loads res://assets/original/ember_art/<id>.glb (models) or .png (textures) when
## that file exists and otherwise builds a procedural placeholder, so the art drops in later
## with no code change. `dress()` adds a level's decals, skyline and landmark art.

## Landmark and prop collision (batch 07: the spire and junk mountain use landmark_bodies).
const COLLIDE := true
const DIR := "res://assets/original/ember_art/"
const GROUP := &"ember_art"
## id -> kind ("model" / "texture"), the level it belongs to ("" = any) and where it stands.
const SLOTS := {
	"junk_mountain": {"kind": "model", "level": "midden", "at": Vector3(0, 0, 300)},
	"association_spire": {"kind": "model", "level": "mage_association", "at": Vector3(0, 0, -15)},
	"oak_lod": {"kind": "model", "level": "old_oak", "at": Vector3(0, 0, -13)},
	"breach_crater_rim": {"kind": "model", "level": "breach", "at": Vector3(0, 0, 125)},
	"waystone_town": {"kind": "model", "level": ""},
	"waystone_landfill": {"kind": "model", "level": ""},
	"waystone_oak": {"kind": "model", "level": ""},
	"waystone_breach": {"kind": "model", "level": ""},
	"chest_normal": {"kind": "model", "level": ""},
	"chest_hidden": {"kind": "model", "level": ""},
	"chest_vault": {"kind": "model", "level": ""},
	"filth_decal": {"kind": "texture", "level": ""},
	"skyline": {"kind": "texture", "level": ""},
	"map_eldoria": {"kind": "texture", "level": ""},
	"map_luminar": {"kind": "texture", "level": ""},
	"map_willowbrook": {"kind": "texture", "level": ""},
	"map_stonehaven": {"kind": "texture", "level": ""},
	"map_landfill": {"kind": "texture", "level": ""},
	"map_whispering_woods": {"kind": "texture", "level": ""},
	"map_shattered_peaks": {"kind": "texture", "level": ""},
	"map_crimson_sea": {"kind": "texture", "level": ""},
}
## Batch 06: LOD switch distances (m) per model with <id>_LOD0/1/2 (+ _Impostor) siblings,
## and the landmark scale (junk_mountain arrives ~190 m wide x 63 m tall).
const LOD_RANGES := {
	"junk_mountain": [180.0, 450.0],
	"association_spire": [90.0, 260.0],
	"oak_lod": [45.0, 120.0, 300.0],
}
const SCALE := {"junk_mountain": 0.6}
## The waystone GLBs' emission read nearly white; scale it down.
const WAYSTONE_GLOW := 0.3
## Placeholder tints (body, trim) per chest tier.
const CHEST := {
	"normal": [Color(0.45, 0.3, 0.15), Color(0.85, 0.65, 0.2)],
	"hidden": [Color(0.16, 0.22, 0.24), Color(0.3, 0.9, 0.8)],
	"vault": [Color(0.3, 0.3, 0.34), Color(1.0, 0.8, 0.3)],
}
const WAYSTONE := {
	"town": Color(0.95, 0.8, 0.45),
	"landfill": Color(0.55, 0.85, 0.3),
	"oak": Color(0.4, 0.95, 0.55),
	"breach": Color(0.75, 0.4, 1.0),
}
const SKYLINE_N := 12


static func path(id: String) -> String:
	return DIR + id + (".png" if String(SLOTS.get(id, {}).get("kind", "model")) == "texture" else ".glb")


static func has_art(id: String) -> bool:
	return ResourceLoader.exists(path(id))


## The slot's model, or null while only the placeholder exists.
static func model(id: String) -> Node3D:
	if not has_art(id):
		return null
	var ps := load(path(id)) as PackedScene
	var m := ps.instantiate() as Node3D if ps else null
	if m:
		_prep(m, id)
	return m


## Batch 06 fix-ups: LOD visibility ranges, landmark scale, dimmer waystone glow.
static func _prep(m: Node3D, id: String) -> void:
	if SCALE.has(id):
		m.scale = Vector3.ONE * float(SCALE[id])
	var r: Array = LOD_RANGES.get(id, [])
	if not r.is_empty():
		var bands := {
			"_LOD0": [0.0, r[0]],
			"_LOD1": [r[0], r[1]],
			"_LOD2": [r[1], r[2] if r.size() > 2 else 0.0],
			"_Impostor": [r[2] if r.size() > 2 else 0.0, 0.0],
		}
		for n in m.find_children("*", "Node3D", true, false):
			for suf in bands:
				if String(n.name).ends_with(suf):
					var b: Array = bands[suf]
					if suf == "_Impostor" and r.size() < 3:
						n.visible = false
					for g in [n] + n.find_children("*", "GeometryInstance3D", true, false):
						if g is GeometryInstance3D:
							(g as GeometryInstance3D).visibility_range_begin = float(b[0])
							(g as GeometryInstance3D).visibility_range_end = float(b[1])
	if COLLIDE:
		_collide(m, id)
	if id.begins_with("waystone_"):
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			if mesh == null:
				continue
			for i in mesh.get_surface_count():
				var mat := mesh.surface_get_material(i) as StandardMaterial3D
				if mat and mat.emission_enabled:
					var d := mat.duplicate() as StandardMaterial3D
					d.emission_energy_multiplier *= WAYSTONE_GLOW
					d.emission = d.emission * 0.6
					(mi as MeshInstance3D).set_surface_override_material(i, d)


## The slot's texture, or a procedural placeholder (a two-colour gradient).
static func texture(id: String) -> Texture2D:
	if has_art(id):
		var t := load(path(id)) as Texture2D
		if t:
			return t
	var g := Gradient.new()
	var tex := GradientTexture2D.new()
	tex.width = 128
	tex.height = 128
	match id:
		"filth_decal":
			g.set_color(0, Color(0.25, 0.3, 0.12, 0.9))
			g.set_color(1, Color(0.2, 0.18, 0.1, 0.0))
			tex.fill = GradientTexture2D.FILL_RADIAL
			tex.fill_from = Vector2(0.5, 0.5)
			tex.fill_to = Vector2(1.0, 0.5)
		"skyline":
			g.set_color(0, Color(0.12, 0.1, 0.12, 0.0))
			g.set_color(1, Color(0.12, 0.1, 0.12, 0.85))
			tex.fill_from = Vector2(0.5, 0.0)
			tex.fill_to = Vector2(0.5, 1.0)
		_:
			var h := float(hash(id) % 1000) / 1000.0
			g.set_color(0, Color.from_hsv(h, 0.45, 0.7))
			g.set_color(1, Color.from_hsv(fmod(h + 0.1, 1.0), 0.6, 0.35))
	tex.gradient = g
	return tex


static func chest_colors(tier: String) -> Array:
	return CHEST.get(tier, CHEST["normal"])


## A waystone point id -> one of the 4 variants (town / landfill / oak / breach).
static func waystone_variant(point: String) -> String:
	for v in ["town", "landfill", "oak", "breach"]:
		if point.begins_with(v) or (v == "oak" and point == "old_oak"):
			return v
	return "town"


## Adds Level/EmberArt: Filth residue decals at Anchors/filth_residue_*, a skyline ring at a
## terrain zone's edge, and the level's landmark art when it exists. Returns the holder.
static func dress(level: Node3D, level_id: String) -> Node3D:
	if level == null:
		return null
	var old := level.get_node_or_null(^"EmberArt")
	if old:
		old.free()
	var holder := Node3D.new()
	holder.name = "EmberArt"
	level.add_child(holder)
	var an := level.get_node_or_null(^"Anchors")
	if an:
		for a in an.get_children():
			if String(a.name).begins_with("filth_residue"):
				var d := Decal.new()
				d.name = "Decal_" + String(a.name)
				d.size = Vector3(6, 2, 6)
				d.texture_albedo = texture("filth_decal")
				d.add_to_group(GROUP)
				holder.add_child(d)
				d.position = (a as Node3D).position
	var tz := level.get_node_or_null(^"Terrain") as TerrainZone
	if tz:
		_skyline(holder, tz)
	for id in SLOTS:
		var s: Dictionary = SLOTS[id]
		if String(s["level"]) == level_id and s.has("at"):
			var m := model(id)
			if m:
				m.name = "Landmark_" + id
				holder.add_child(m)
				m.position = s["at"]
	return holder


static func _skyline(holder: Node3D, tz: TerrainZone) -> void:
	var r := maxf(tz.size.x, tz.size.y) * 0.5 + 60.0
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture("skyline")
	mat.texture_repeat = true
	mat.uv1_scale = Vector3(2, 1, 1)  # the batch 06 strip tiles horizontally
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in SKYLINE_N:
		var a := TAU * i / SKYLINE_N
		var q := MeshInstance3D.new()
		q.name = "Skyline_%d" % (i + 1)
		var qm := QuadMesh.new()
		qm.size = Vector2(2.0 * PI * r / SKYLINE_N + 4.0, 40.0 + 15.0 * (i % 3))
		q.mesh = qm
		q.material_override = mat
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.add_to_group(GROUP)
		holder.add_child(q)
		q.position = Vector3(tz.center.x + r * sin(a), qm.size.y * 0.5, tz.center.y + r * cos(a))
		q.rotation.y = a + PI


## Batch 07: landmarks whose collision is part of the level's navmesh bake (LevelNavigation).
const NAV_LANDMARKS: PackedStringArray = ["association_spire", "junk_mountain"]
const JUNK_COL := DIR + "junk_mountain_col.glb"
## The spire's 12 x 12 m footprint (model space) and the back-door gap in its south (+z) wall,
## lined up with the Association's back door (level x 0, z -10) and the to_landfill exit.
const SPIRE_HALF := 6.0
const SPIRE_TALL := 45.0
const SPIRE_WALL := 0.8
const SPIRE_DOOR := Vector2(4.4, 5.0)  ## gap width, height


## Collision bodies for a NAV_LANDMARKS model, in the model's own (unscaled) space.
static func landmark_bodies(id: String) -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	if id == "junk_mountain" and ResourceLoader.exists(JUNK_COL):
		var c := (load(JUNK_COL) as PackedScene).instantiate() as Node3D
		for mi in c.find_children("col_*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			if mesh == null:
				continue
			var sh := ConvexPolygonShape3D.new()
			sh.points = mesh.get_faces()
			out.append(_body("Col_" + String(mi.name), sh, (mi as Node3D).transform))
		c.free()
	elif id == "association_spire":
		var h := SPIRE_HALF
		var w := SPIRE_WALL
		var t := SPIRE_TALL
		var side := (2.0 * h - SPIRE_DOOR.x) * 0.5
		var walls := {
			"North": [Vector3(2 * h, t, w), Vector3(0, t / 2, -h + w / 2)],
			"West": [Vector3(w, t, 2 * h), Vector3(-h + w / 2, t / 2, 0)],
			"East": [Vector3(w, t, 2 * h), Vector3(h - w / 2, t / 2, 0)],
			"SouthW": [Vector3(side, t, w), Vector3(-h + side / 2, t / 2, h - w / 2)],
			"SouthE": [Vector3(side, t, w), Vector3(h - side / 2, t / 2, h - w / 2)],
			"Lintel":
			[Vector3(SPIRE_DOOR.x, t - SPIRE_DOOR.y, w), Vector3(0, SPIRE_DOOR.y + (t - SPIRE_DOOR.y) / 2, h - w / 2)],
		}
		for k in walls:
			var bs := BoxShape3D.new()
			bs.size = walls[k][0]
			out.append(_body("Col_" + String(k), bs, Transform3D(Basis(), walls[k][1])))
	return out


static func _body(n: String, sh: Shape3D, xf: Transform3D) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = n
	b.transform = xf
	var cs := CollisionShape3D.new()
	cs.shape = sh
	b.add_child(cs)
	return b


## A collision-only stand-in for the level's NAV_LANDMARKS (placed and scaled like dress()
## places the art), for LevelNavigation to parse. The caller frees it.
static func nav_source(level_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "EmberArtNav"
	for id in NAV_LANDMARKS:
		var s: Dictionary = SLOTS[id]
		if String(s["level"]) != level_id or not has_art(id):
			continue
		var n := Node3D.new()
		n.name = id
		n.position = s["at"]
		n.scale = Vector3.ONE * float(SCALE.get(id, 1.0))
		for b in landmark_bodies(id):
			n.add_child(b)
		root.add_child(n)
	return root


## Simple collision: a trimesh from each landmark's LOD0 (or its only mesh); a convex hull for
## the small props (waystones, chests) so the interaction reach still works round them.
static func _collide(m: Node3D, id: String) -> void:
	if id in NAV_LANDMARKS:  ## batch 07: hand-made shapes, also baked into the navmesh
		for b in landmark_bodies(id):
			m.add_child(b)
		return
	var small := id.begins_with("waystone_") or id.begins_with("chest_")
	var meshes := m.find_children("*", "MeshInstance3D", true, false)
	var lod0 := meshes.filter(
		func(n: Node) -> bool: return String(n.name).contains("_LOD0") or String(n.get_parent().name).ends_with("_LOD0")
	)
	for mi in lod0 if not lod0.is_empty() else meshes:
		if String(mi.name).contains("Impostor") or (small and String(mi.get_parent().name) == "Lid"):
			continue
		if small:
			(mi as MeshInstance3D).create_convex_collision(true, true)
		else:
			(mi as MeshInstance3D).create_trimesh_collision()
