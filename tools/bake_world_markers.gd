extends SceneTree
## OW6: collects every zone level's Waystones/* and Exits/* markers at the level's
## world_offset into res://world/markers.json (x, z only; height comes from the terrain at
## run time), so the open world places waystones and exit markers without loading levels.
## godot --headless --path . -s res://tools/bake_world_markers.gd

const OUT := "res://world/markers.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	quit(
		(
			0
			if FileAccess.open(OUT, FileAccess.WRITE).store_string(
				JSON.stringify(collect(), "\t", true)
			)
			else 1
		)
	)


static func collect() -> Dictionary:
	var ways := {}
	var exits: Array = []
	for id in ["old_oak", "town_square", "midden", "breach"]:
		var lvl := (load(GameFlow.level_scene(id)) as PackedScene).instantiate() as Node3D
		var wo: Vector2 = lvl.get_meta(&"world_offset", Vector2.ZERO)
		var hold := lvl.get_node_or_null("Waystones")
		for m in hold.get_children() if hold else []:
			var p := (m as Node3D).position
			ways[String(m.name)] = [p.x + wo.x, p.z + wo.y]
		var start := lvl.get_node_or_null("PlayerStart") as Node3D
		var sp := start.position if start else Vector3.ZERO
		var main := String(FastTravel.LEVEL_POINT.get(id, ""))
		if main != "" and not ways.has(main):  # main.gd: PlayerStart + (0, 0, -2.5)
			ways[main] = [sp.x + wo.x, sp.z - 2.5 + wo.y]
		hold = lvl.get_node_or_null("Exits")
		var spots: Array = []
		for m in hold.get_children() if hold else []:
			spots.append([String(m.name), String(m.get_meta("to", "")), (m as Node3D).position])
		if spots.is_empty() and id == "midden":  # main.gd's default gates
			spots = [
				["to_breach", "breach", sp + Vector3(-3, 0, -1)],
				["to_town", "town_square", sp + Vector3(3, 0, -1)]
			]
		for e in spots:
			var p: Vector3 = e[2]
			var door := false
			for l in Interiors.LINKS.values():
				door = door or l["front"] == [id, e[0]]
			var x := {"level": id, "name": e[0], "to": e[1]}
			x["pos"] = [p.x + wo.x, p.z + wo.y]
			x["kind"] = "door" if door else "road"
			exits.append(x)
		lvl.free()
	return {"waystones": ways, "exits": exits}
