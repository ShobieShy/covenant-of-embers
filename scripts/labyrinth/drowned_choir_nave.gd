class_name DrownedChoirNave
extends Node3D
## The Choir nave. Pillars, pews, and the coral sarcophagus. Instanced by the
## sunken layout so the arena is a scene, not a loose pile of markers.


func dress(theme: SunkenTheme, size: Vector2) -> void:
	_pillars(theme, size)
	_pews(theme, size)
	_walls(theme, size)
	_coffin(theme, size)
	_windows(theme, size)
	var lamp := OmniLight3D.new()
	lamp.name = "NaveLight"
	lamp.position = Vector3(0, 6.5, 0)
	lamp.light_color = Color(0.65, 0.55, 0.9)
	lamp.light_energy = 3.5
	lamp.omni_range = 28.0
	add_child(lamp)


func _pillars(theme: SunkenTheme, size: Vector2) -> void:
	var xforms: Array = []
	var rows := 6
	for i in rows:
		var z := lerpf(-size.y * 0.36, size.y * 0.32, float(i) / float(rows - 1))
		var scale := Vector3(7.0, 5.8, 7.0)
		xforms.append(SunkenKit.place("pillar", Vector3(-size.x * 0.36, 0, z), 0.0, scale))
		xforms.append(SunkenKit.place("pillar", Vector3(size.x * 0.36, 0, z), 0.0, scale))
	SunkenKit.scatter(self, "pillar", xforms, theme.stone, "Pillars")


func _pews(theme: SunkenTheme, size: Vector2) -> void:
	var xforms: Array = []
	var scale := Vector3(2.4, 3.4, 3.6)
	for row in 4:
		var z := lerpf(size.y * 0.05, size.y * 0.32, float(row) / 3.0)
		for side in [-1.0, 1.0]:
			var at := Vector3(side * size.x * 0.16, 0, z)
			xforms.append(SunkenKit.place("bench", at, PI * 0.5, scale))
	SunkenKit.scatter(self, "bench", xforms, theme.pew, "Pews")


func _walls(theme: SunkenTheme, size: Vector2) -> void:
	var xforms: Array = []
	var scale := Vector3(3.2, 5.2, 4.4)
	var bays := 5
	for i in bays:
		var z := lerpf(-size.y * 0.34, size.y * 0.28, float(i) / float(bays - 1))
		xforms.append(SunkenKit.place("window", Vector3(-size.x * 0.48, 0, z), 0.0, scale))
		xforms.append(SunkenKit.place("window", Vector3(size.x * 0.48, 0, z), PI, scale))
	for i in 4:
		var x := lerpf(-size.x * 0.28, size.x * 0.28, float(i) / 3.0)
		xforms.append(SunkenKit.place("arch", Vector3(x, 0, -size.y * 0.46), PI * 0.5, Vector3(3.0, 5.6, 5.0)))
	SunkenKit.scatter(self, "window", xforms.slice(0, bays * 2), theme.masonry, "Clerestory")
	var north: Array = []
	for i in 4:
		north.append(xforms[bays * 2 + i])
	SunkenKit.scatter(self, "arch", north, theme.masonry, "NorthArcade")


func _coffin(theme: SunkenTheme, size: Vector2) -> void:
	var body := MeshInstance3D.new()
	body.name = "SarcophagusMesh"
	body.mesh = SunkenMeshes.sarcophagus()
	body.material_override = theme.stone
	body.position = Vector3(size.x * 0.08, 0, -size.y * 0.28)
	add_child(body)
	var crack := MeshInstance3D.new()
	crack.name = "Crack"
	crack.mesh = SunkenMeshes.crack()
	crack.material_override = theme.violet
	crack.position = Vector3(0.15, 0.7, 1.15)
	crack.rotation.x = -PI * 0.5
	body.add_child(crack)
	for i in 4:
		var coral := MeshInstance3D.new()
		coral.mesh = SunkenMeshes.coral(20 + i, i)
		coral.material_override = theme.coral(i)
		coral.position = Vector3(-0.7 + float(i) * 0.45, 0.2, 1.3 if i % 2 == 0 else -1.3)
		coral.scale = Vector3.ONE * 0.85
		body.add_child(coral)


func _windows(theme: SunkenTheme, size: Vector2) -> void:
	for side in [-1.0, 1.0]:
		var glass := MeshInstance3D.new()
		glass.mesh = SunkenMeshes.doorway_glow()
		glass.material_override = theme.violet
		glass.position = Vector3(side * size.x * 0.47, 1.6, -size.y * 0.05)
		glass.rotation.y = PI * 0.5
		glass.scale = Vector3(2.2, 1.1, 1.0)
		add_child(glass)
