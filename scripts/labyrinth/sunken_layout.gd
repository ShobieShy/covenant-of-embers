class_name SunkenLayout
extends RefCounted
## Builds the painted Sunken Ruins from data/labyrinth/sunken.toml. Landmarks stay
## on the fractions in the painting. Walk ribbons are the nav graph.

const TOML := "res://data/labyrinth/sunken.toml"

static var _seed := 1


static func dress(floor: SunkenFloor) -> void:
	var data := LevelToml.load_file(TOML)
	if data.has("error"):
		push_error("Sunken ruins: %s" % data["error"])
		return
	var kit: Dictionary = data["kit"]
	var span := Vector2(float(kit["span_x"]), float(kit["span_z"]))
	var walk_y := float(kit["walk_y"])
	var water_y := float(kit["water_y"])
	var wade_y := float(kit["wade_y"])
	var theme := SunkenTheme.new()
	floor.set_meta(&"painted_span", span)
	var dress := Node3D.new()
	dress.name = "Dress"
	floor.add_child(dress)
	var routes: Array[PackedVector3Array] = []
	var gallery: PackedVector3Array = PackedVector3Array()
	var mural_pts: PackedVector3Array = PackedVector3Array()
	var vault_pts: PackedVector3Array = PackedVector3Array()
	for row in data["path"]:
		var pts := _uv_points(row["points"], span, walk_y)
		routes.append(pts)
		var width := float(row["width"])
		_collision(floor, pts, width, walk_y)
		_ribbon(dress, pts, width * 1.5, walk_y + 0.02, theme.stone)
		_ribbon(dress, pts, width * 1.12, walk_y + 0.07, theme.paving)
		var id := String(row["id"])
		if bool(row.get("arches", false)):
			gallery = pts
			_arcade(dress, pts, theme)
		if bool(row.get("murals", false)):
			mural_pts = pts
		if bool(row.get("vaults", false)):
			vault_pts = pts
		if id == "entry":
			_entry(dress, pts, theme)
	floor.routes = routes
	_basins(floor, dress, span, water_y, wade_y, theme)
	_cliffs(dress, span, theme)
	_coral_field(dress, gallery, theme, walk_y)
	var spire_at := _uv(data["spire"]["at"], span, walk_y)
	_spire(dress, spire_at, theme)
	_nave(dress, data["nave"], span, walk_y, theme, floor)
	_bells(floor, dress, data["bells"], span, walk_y, theme)
	_murals(dress, mural_pts, spire_at, theme)
	_vaults(dress, vault_pts, theme, walk_y)
	var shaft_at := _uv(data["shaft"]["at"], span, walk_y)
	_shaft(dress, shaft_at, theme, walk_y)
	_gameplay(floor, data, span, walk_y, theme)
	_lights(floor, dress, spire_at, theme)


static func _reseed(n: int) -> void:
	_seed = n if n != 0 else 1


static func _rand() -> float:
	_seed = (_seed * 1103515245 + 12345) & 0x7FFFFFFF
	return float(_seed % 10000) / 10000.0


## South is +Z (angle PI/2) and north is -Z (angle -PI/2). Those mouths stay open.
static func _cliff_gap(ang: float) -> bool:
	var a := wrapf(ang, -PI, PI)
	return absf(a - PI * 0.5) < 0.42 or absf(a + PI * 0.5) < 0.5


static func _uv(pair: Array, span: Vector2, y: float) -> Vector3:
	return Vector3((float(pair[0]) - 0.5) * span.x, y, (float(pair[1]) - 0.5) * span.y)


static func _uv_points(rows: Array, span: Vector2, y: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for row in rows:
		pts.append(_uv(row, span, y))
	return pts


static func _row(data: Dictionary, n: int) -> Dictionary:
	for row in data["floor"]:
		if int(row["n"]) == n:
			return row
	return {}


static func _collision(floor: Node3D, pts: PackedVector3Array, width: float, y: float) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var flat := Vector3(b.x - a.x, 0, b.z - a.z)
		var length := flat.length()
		if length < 0.2:
			continue
		var body := StaticBody3D.new()
		body.name = "Walk"
		body.position = Vector3((a.x + b.x) * 0.5, y - 0.2, (a.z + b.z) * 0.5)
		body.rotation.y = atan2(flat.x, flat.z)
		body.add_to_group(&"sunken_walk")
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, 0.4, length + 0.8)
		shape.shape = box
		body.add_child(shape)
		floor.add_child(body)


static func _pad(floor: Node3D, at: Vector3, y: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Landing"
	body.position = Vector3(at.x, y - 0.2, at.z)
	body.add_to_group(&"sunken_walk")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 0.4, 5.0)
	shape.shape = box
	body.add_child(shape)
	floor.add_child(body)


static func _ribbon(parent: Node3D, pts: PackedVector3Array, width: float, y: float, mat: Material) -> void:
	var mesh := SunkenMeshes.ribbon(pts, width * 0.92, y, 0.16)
	if mesh.get_surface_count() == 0:
		return
	var inst := MeshInstance3D.new()
	inst.name = "Paving"
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)


static func _samples(pts: PackedVector3Array, spacing: float) -> Array:
	var out: Array = []
	var travelled := 0.0
	var next_at := spacing * 0.5
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var flat := Vector3(b.x - a.x, 0, b.z - a.z)
		var length := flat.length()
		if length < 0.05:
			continue
		var dir := flat / length
		while next_at <= travelled + length:
			var t := (next_at - travelled) / length
			out.append({"at": a.lerp(b, t), "dir": dir})
			next_at += spacing
		travelled += length
	return out


static func _arcade(parent: Node3D, pts: PackedVector3Array, theme: SunkenTheme) -> void:
	var hold := Node3D.new()
	hold.name = "CoralGalleries"
	parent.add_child(hold)
	var xforms: Array = []
	for sample in _samples(pts, 6.2):
		var dir: Vector3 = sample["dir"]
		var yaw := atan2(-dir.z, dir.x)
		xforms.append(SunkenKit.place("arch", sample["at"], yaw, Vector3(4.2, 5.6, 6.4)))
	SunkenKit.scatter(hold, "arch", xforms, theme.masonry, "Arches")


static func _entry(parent: Node3D, pts: PackedVector3Array, theme: SunkenTheme) -> void:
	if pts.size() < 2:
		return
	var dir := pts[1] - pts[0]
	dir.y = 0
	if dir.length() < 0.1:
		return
	dir = dir.normalized()
	var yaw := atan2(-dir.z, dir.x)
	var hold := Node3D.new()
	hold.name = "SlagworksArch"
	parent.add_child(hold)
	var xforms: Array = [SunkenKit.place("arch", pts[0], yaw, Vector3(5.5, 8.0, 9.0))]
	SunkenKit.scatter(hold, "arch", xforms, theme.masonry, "Arch")
	var caps: Array = []
	var side := Vector3(-dir.z, 0, dir.x)
	caps.append(SunkenKit.place("pillar", pts[0] + side * 4.6, 0.0, Vector3(8, 7, 8)))
	caps.append(SunkenKit.place("pillar", pts[0] - side * 4.6, 0.0, Vector3(8, 7, 8)))
	SunkenKit.scatter(hold, "pillar", caps, theme.stone, "Jambs")


static func _basins(
	floor: Node3D, dress: Node3D, span: Vector2, water_y: float, wade_y: float, theme: SunkenTheme
) -> void:
	var silt := MeshInstance3D.new()
	silt.name = "Silt"
	silt.mesh = SunkenMeshes.disc(span.x * 0.40, span.y * 0.40, wade_y + 0.02, 48)
	silt.material_override = theme.silt
	dress.add_child(silt)
	var water := MeshInstance3D.new()
	water.name = "WaterSheet"
	water.mesh = SunkenMeshes.disc(span.x * 0.43, span.y * 0.43, water_y, 56)
	water.material_override = theme.water_mat
	dress.add_child(water)
	var bed := StaticBody3D.new()
	bed.name = "Wade"
	bed.position = Vector3(0, wade_y - 0.2, 0)
	bed.add_to_group(&"sunken_walk")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(span.x * 0.78, 0.4, span.y * 0.76)
	shape.shape = box
	bed.add_child(shape)
	floor.add_child(bed)


static func _cliffs(dress: Node3D, span: Vector2, theme: SunkenTheme) -> void:
	var rocks: Array = []
	var wide: Array = []
	_reseed(41)
	var count := 54
	for i in count:
		var ang := TAU * float(i) / float(count) + _rand() * 0.08
		if _cliff_gap(ang):
			continue
		var rad := 0.46 + _rand() * 0.03
		var at := Vector3(cos(ang) * span.x * rad, -0.4 + _rand() * 1.4, sin(ang) * span.y * rad)
		var scale := 6.5 + _rand() * 6.0
		var yaw := ang + (_rand() * 2.0 - 1.0)
		var xf := SunkenKit.place("rock" if i % 3 else "rock_wide", at, yaw, Vector3.ONE * scale)
		if i % 3 == 0:
			wide.append(xf)
		else:
			rocks.append(xf)
	SunkenKit.scatter(dress, "rock", rocks, theme.stone, "CliffRocks")
	SunkenKit.scatter(dress, "rock_wide", wide, theme.stone, "CliffLedges")
	var broken: Array = []
	for i in 36:
		var ang := TAU * float(i) / 36.0
		if _cliff_gap(ang):
			continue
		var at := Vector3(cos(ang) * span.x * 0.42, 0.0, sin(ang) * span.y * 0.42)
		var yaw := atan2(-cos(ang), sin(ang))
		broken.append(SunkenKit.place("broken", at, yaw, Vector3(3.4, 4.8, 4.2)))
	SunkenKit.scatter(dress, "broken", broken, theme.masonry, "RuinRing")


static func _coral_field(dress: Node3D, gallery: PackedVector3Array, theme: SunkenTheme, walk_y: float) -> void:
	var hold := Node3D.new()
	hold.name = "Coral"
	dress.add_child(hold)
	var samples: Array = _samples(gallery, 4.4)
	var rng := SunkenMeshes._Rng.new(9)
	for i in samples.size():
		var sample: Dictionary = samples[i]
		var dir: Vector3 = sample["dir"]
		var side := Vector3(-dir.z, 0, dir.x)
		if rng.f() > 0.5:
			side = -side
		var at: Vector3 = sample["at"] + side * (3.2 + rng.f() * 2.4)
		at.y = walk_y - 1.15
		var inst := MeshInstance3D.new()
		inst.mesh = SunkenMeshes.coral(30 + i, i)
		inst.material_override = theme.coral(i)
		inst.position = at
		inst.rotation.y = rng.f() * TAU
		inst.scale = Vector3.ONE * (2.4 + rng.f() * 1.6)
		hold.add_child(inst)


static func _spire(dress: Node3D, at: Vector3, theme: SunkenTheme) -> void:
	var hold := Node3D.new()
	hold.name = "DrownedSpire"
	hold.position = at
	dress.add_child(hold)
	var body := MeshInstance3D.new()
	body.name = "SpireMesh"
	body.mesh = SunkenMeshes.spire()
	body.material_override = theme.stone
	hold.add_child(body)
	var glow := MeshInstance3D.new()
	glow.name = "BreachGlow"
	glow.mesh = SunkenMeshes.doorway_glow()
	glow.material_override = theme.violet
	glow.position = Vector3(0, 0.4, 3.3)
	hold.add_child(glow)
	var ring: Array = []
	for i in 6:
		var ang := TAU * float(i) / 6.0
		var p := Vector3(cos(ang) * 6.2, 0, sin(ang) * 6.2)
		ring.append(SunkenKit.place("pillar", p, ang, Vector3(5.5, 6.5, 5.5)))
	SunkenKit.scatter(hold, "pillar", ring, theme.masonry, "SpirePillars")
	var light := OmniLight3D.new()
	light.name = "SpireLight"
	light.position = Vector3(0, 5.5, 2.0)
	light.light_color = Color(0.72, 0.32, 1.0)
	light.light_energy = 10.0
	light.omni_range = 42.0
	hold.add_child(light)
	var isle := MeshInstance3D.new()
	isle.mesh = SunkenMeshes.disc(12.5, 12.5, 0.05, 20)
	isle.material_override = theme.paving
	hold.add_child(isle)
	var body_col := StaticBody3D.new()
	body_col.position = Vector3(0, -0.2, 0)
	body_col.add_to_group(&"sunken_walk")
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 12.0
	cyl.height = 0.4
	shape.shape = cyl
	body_col.add_child(shape)
	hold.add_child(body_col)


static func _nave(
	dress: Node3D, nave: Dictionary, span: Vector2, walk_y: float, theme: SunkenTheme, floor: Node3D
) -> void:
	var mn := _uv([nave["umin"], nave["vmin"]], span, walk_y)
	var mx := _uv([nave["umax"], nave["vmax"]], span, walk_y)
	var centre := (mn + mx) * 0.5
	centre.y = walk_y
	var size := Vector2(absf(mx.x - mn.x), absf(mx.z - mn.z))
	var packed := load("res://scenes/labyrinth/drowned_choir_nave.tscn") as PackedScene
	var hall := packed.instantiate() as DrownedChoirNave
	hall.position = centre
	dress.add_child(hall)
	hall.dress(theme, size)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "NaveFloor"
	floor_mesh.mesh = SunkenMeshes.slab(size, 0.06)
	floor_mesh.material_override = theme.paving
	floor_mesh.position = centre
	dress.add_child(floor_mesh)
	var deck := StaticBody3D.new()
	deck.name = "NaveDeck"
	deck.position = Vector3(centre.x, walk_y - 0.2, centre.z)
	deck.add_to_group(&"sunken_walk")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 0.4, size.y)
	shape.shape = box
	deck.add_child(shape)
	floor.add_child(deck)


static func _bells(
	floor: SunkenFloor, dress: Node3D, bells: Dictionary, span: Vector2, y: float, theme: SunkenTheme
) -> void:
	var first := true
	for key in ["west", "north"]:
		var at := _uv(bells[key], span, y)
		_shrine(dress, at, theme, "AirBellShrine" if first else "AirBellNorth")
		if first:
			floor.bell_at = at
			first = false
		else:
			floor.bell_north = at


static func _shrine(dress: Node3D, at: Vector3, theme: SunkenTheme, nm: String) -> void:
	var hold := Node3D.new()
	hold.name = nm
	hold.position = at
	dress.add_child(hold)
	var arch := SunkenKit.place("arch", Vector3(0, 0, 0), PI * 0.5, Vector3(4.5, 6.2, 6.0))
	SunkenKit.scatter(hold, "arch", [arch], theme.masonry, "Arch")
	var bell := MeshInstance3D.new()
	bell.mesh = SunkenMeshes.bell()
	bell.material_override = theme.bronze
	bell.position = Vector3(0, 3.1, 0)
	bell.scale = Vector3.ONE * 1.35
	hold.add_child(bell)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.4, 0)
	lamp.light_color = Color(1.0, 0.72, 0.38)
	lamp.light_energy = 4.5
	lamp.omni_range = 16.0
	hold.add_child(lamp)
	var lantern := SunkenKit.place("lantern", Vector3(1.4, 0, 1.1), 0.3, Vector3(1.8, 1.8, 1.8))
	SunkenKit.scatter(hold, "lantern", [lantern], theme.bronze, "Lantern")


static func _murals(dress: Node3D, pts: PackedVector3Array, spire: Vector3, theme: SunkenTheme) -> void:
	if pts.size() < 2:
		return
	var hold := Node3D.new()
	hold.name = "CultMurals"
	dress.add_child(hold)
	var walls: Array = []
	for sample in _samples(pts, 6.5):
		var dir: Vector3 = sample["dir"]
		var at: Vector3 = sample["at"]
		var out := Vector3(-dir.z, 0, dir.x)
		if out.dot(at - spire) < 0.0:
			out = -out
		var yaw := atan2(dir.x, dir.z)
		var face := Basis(Vector3.UP, yaw).x
		if face.dot(spire - at) < 0.0:
			yaw += PI
		walls.append(SunkenKit.place("wall", at + out * 3.6, yaw, Vector3(2.4, 6.5, 6.2)))
		var mural := MeshInstance3D.new()
		mural.mesh = SunkenMeshes.doorway_glow()
		mural.material_override = theme.mural
		mural.position = at + out * 3.35 + Vector3(0, 2.2, 0)
		mural.rotation.y = yaw + PI * 0.5
		mural.scale = Vector3(2.4, 1.3, 1)
		hold.add_child(mural)
	SunkenKit.scatter(hold, "wall", walls, theme.masonry, "MuralWall")


static func _vaults(dress: Node3D, pts: PackedVector3Array, theme: SunkenTheme, y: float) -> void:
	if pts.is_empty():
		return
	var at := pts[pts.size() / 2]
	at.y = y
	var hold := Node3D.new()
	hold.name = "HymnVaults"
	hold.position = at
	dress.add_child(hold)
	var arches: Array = []
	for i in 3:
		var x := (float(i) - 1.0) * 4.2
		arches.append(SunkenKit.place("arch", Vector3(x, 0, 0), PI * 0.5, Vector3(3.6, 5.0, 4.4)))
	SunkenKit.scatter(hold, "arch", arches, theme.masonry, "VaultArches")
	for i in 2:
		var slab := MeshInstance3D.new()
		slab.name = "Tablet%d" % i
		slab.mesh = SunkenMeshes.tablet()
		slab.material_override = theme.tablet
		slab.position = Vector3(-1.4 + float(i) * 2.8, 0, 2.2)
		slab.rotation.x = -0.12
		hold.add_child(slab)


static func _shaft(dress: Node3D, at: Vector3, theme: SunkenTheme, _walk_y: float) -> void:
	var hold := Node3D.new()
	hold.name = "Shaft"
	hold.position = at
	dress.add_child(hold)
	var fall := MeshInstance3D.new()
	fall.name = "Waterfall"
	fall.mesh = SunkenMeshes.waterfall(14.0, 3.2)
	fall.material_override = theme.water_mat
	fall.position = Vector3(0, 0, -2.4)
	hold.add_child(fall)
	var mouth: Array = [SunkenKit.place("arch", Vector3(0, 0, -1.2), 0.0, Vector3(5.0, 7.5, 7.0))]
	SunkenKit.scatter(hold, "arch", mouth, theme.masonry, "ShaftArch")
	var wind := OmniLight3D.new()
	wind.position = Vector3(0, 8.0, 0)
	wind.light_color = Color(0.7, 0.85, 1.0)
	wind.light_energy = 3.0
	wind.omni_range = 18.0
	hold.add_child(wind)


static func _gameplay(floor: SunkenFloor, data: Dictionary, span: Vector2, y: float, theme: SunkenTheme) -> void:
	var row := _row(data, floor.floor_no)
	if row.is_empty():
		return
	floor.spawn_local = _uv(row["spawn"], span, y)
	floor.pad_local = _uv(row["pad"], span, y)
	_pad(floor, floor.spawn_local, y)
	_pad(floor, floor.pad_local, y)
	if row.has("enemy"):
		floor.enemy_local = _uv(row["enemy"], span, y)
	if row.has("stairs"):
		floor.exit_local = _uv(row["stairs"], span, y)
		_pad(floor, floor.exit_local, y)
		var step := SunkenKit.place("stair", floor.exit_local, 0.4, Vector3(3.2, 1.4, 4.0))
		var hold := floor.get_node("Dress") as Node3D
		SunkenKit.scatter(hold, "stair", [step], theme.stone, "DownStairs")
	if row.has("boss"):
		floor.exit_local = _uv(row["boss"], span, y)
		floor.boss_local = floor.exit_local
	if row.has("sarcophagus"):
		floor.sarcophagus_local = _uv(row["sarcophagus"], span, y)
	if row.has("waystone"):
		floor.waystone_local = _uv(row["waystone"], span, y)
	if row.has("door"):
		floor.door_local = _uv(row["door"], span, y)


static func _lights(floor: Node3D, _dress: Node3D, spire: Vector3, theme: SunkenTheme) -> void:
	var world := WorldEnvironment.new()
	world.name = "Atmosphere"
	world.environment = theme.environment()
	floor.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "DayGlow"
	sun.rotation_degrees = Vector3(-48, -36, 0)
	sun.light_color = Color(0.78, 0.9, 0.98)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_blend_splits = true
	floor.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = spire + Vector3(0, 18, 0)
	fill.light_color = Color(0.45, 0.7, 0.78)
	fill.light_energy = 2.2
	fill.omni_range = 160.0
	floor.add_child(fill)
