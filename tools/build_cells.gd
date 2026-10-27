extends SceneTree
## OW3: cuts every terrain level's static content (Boxes, Props, Pois) into 128 m world cells,
## res://world/cells/<cx>_<cz>.tscn, placed by the level's world_offset, plus
## world/cells/cells.json (cell -> levels, node counts). Gameplay groups (camps, spawns,
## chests, gates, exits, waystones, NPCs) stay with their level until OW4-OW6 move them.
## Deterministic: same scenes in, same cells out. Run via tools/build_world.sh.

const LEVELS := ["town_square", "old_oak", "midden", "breach"]
const GROUPS := ["Boxes", "Props", "Pois"]
const DST := "res://world/cells/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DST))
	for f in DirAccess.get_files_at(DST):
		if f.ends_with(".tscn"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DST + f))  # our own output only
	var cells := {}  # Vector2i -> Node3D root
	var info := {}
	for id in LEVELS:
		var lvl := (load("res://scenes/levels/%s.tscn" % id) as PackedScene).instantiate() as Node3D
		var wo: Vector2 = lvl.get_meta(&"world_offset", Vector2.ZERO)
		for gname in GROUPS:
			if gname in Interiors.CELL_SKIP.get(id, []):
				continue  # OW5b: instanced (Interiors), not in the world
			var g := lvl.get_node_or_null(NodePath(gname)) as Node3D
			if g == null:
				continue
			for k in g.get_children():
				var n := k as Node3D
				if n == null:
					continue
				var xf := lvl.transform * g.transform * n.transform
				var c: Vector3 = n.get_meta(&"center", xf.origin) if gname == "Pois" else xf.origin
				var w := Vector2(c.x + wo.x, c.z + wo.y)
				var cell := WorldStreamer.cell_of(w)
				if not cells.has(cell):
					var r := Node3D.new()
					r.name = "Cell_%d_%d" % [cell.x, cell.y]
					r.set_meta(&"cell", cell)
					cells[cell] = r
				var root: Node3D = cells[cell]
				var holder := root.get_node_or_null(NodePath(gname)) as Node3D
				if holder == null:
					holder = Node3D.new()
					holder.name = gname
					root.add_child(holder)
					holder.owner = root
				var kept := _owned(n, lvl)
				for d in kept:
					d.owner = null
				g.remove_child(n)
				n.name = "%s_%s" % [id, n.name]
				n.transform = Transform3D(xf.basis, xf.origin + Vector3(wo.x, 0, wo.y))
				if gname == "Pois" and n.has_meta(&"center"):
					n.set_meta(&"center", c + Vector3(wo.x, 0, wo.y))
				holder.add_child(n)
				if gname == "Boxes" and String(n.get_meta("kind", "")) == "ground":
					var m := n.get_node_or_null(^"Mesh") as MeshInstance3D
					if m:
						m.visible = false  # the world terrain paints the pads (as TerrainZone does)
				for d in kept:
					d.owner = root
				var key := "%d_%d" % [cell.x, cell.y]
				var e: Dictionary = info.get(key, {"levels": [], "nodes": 0})
				if not (e["levels"] as Array).has(id):
					(e["levels"] as Array).append(id)
				e["nodes"] = int(e["nodes"]) + 1
				info[key] = e
		lvl.free()
	for cell in cells:
		var ps := PackedScene.new()
		ps.pack(cells[cell])
		ResourceSaver.save(ps, DST + "%d_%d.tscn" % [cell.x, cell.y])
		(cells[cell] as Node).free()
	var j := FileAccess.open(DST + "cells.json", FileAccess.WRITE)
	j.store_string(JSON.stringify({"cell_size": WorldStreamer.CELL, "cells": info}, "  ", true))
	j.close()
	print("[build_cells] %d cells -> %s" % [cells.size(), DST])
	quit(0)


## The node and every descendant the level scene owns (instanced sub-scenes keep their own).
func _owned(n: Node, lvl: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for d in n.find_children("*", "", true, false):
		if d.owner == lvl:
			out.append(d)
	return out
