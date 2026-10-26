class_name EmberArt
extends RefCounted
## Step 163 (W12) Ember Art pass: the slots for the original landmark / chest / waystone /
## decal / skyline / world-map art (TERRAIN_MAPS_PLAN section 11, docs/EMBER_ART_REQUESTS.md).
## Each slot loads res://assets/original/ember_art/<id>.glb (models) or .png (textures) when
## that file exists and otherwise builds a procedural placeholder, so the art drops in later
## with no code change. `dress()` adds a level's decals, skyline and landmark art.

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
