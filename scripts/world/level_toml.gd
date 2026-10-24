class_name LevelToml
extends RefCounted
## Minimal TOML subset reader for data/levels/*.toml (BUILD_PLAN step 2), so GDScript
## (tests now, runtime checks later) reads the same source of truth as
## tools/toml_to_scene.py. Supports: `#` comments, [table], [[array.of.tables]],
## key = "string" | number | true/false | single-line [array] | single-line inline table
## { key = value, ... } (step 11: data/enemies/*.toml `resist = { air = 0.25 }`,
## `weak_point = { offset = [...], size = [...] }`; values may nest arrays/tables).
## Anything else is an error (returned as {"error": "file:line: ..."}).


static func load_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "%s: cannot open" % path}
	return parse(f.get_as_text(), path)


static func parse(text: String, source: String = "toml") -> Dictionary:
	var root: Dictionary = {}
	var current: Dictionary = root
	var lines := text.split("\n")
	for i in lines.size():
		var line := _strip_comment(lines[i]).strip_edges()
		if line.is_empty():
			continue
		var where := "%s:%d" % [source, i + 1]
		if line.begins_with("[["):
			if not line.ends_with("]]"):
				return {"error": where + ": bad array-of-tables header"}
			var key := line.substr(2, line.length() - 4).strip_edges()
			if not root.has(key):
				root[key] = []
			if not (root[key] is Array):
				return {"error": where + ": '%s' is not an array of tables" % key}
			current = {}
			(root[key] as Array).append(current)
		elif line.begins_with("["):
			if not line.ends_with("]"):
				return {"error": where + ": bad table header"}
			var key := line.substr(1, line.length() - 2).strip_edges()
			if root.has(key):
				return {"error": where + ": duplicate table [%s]" % key}
			current = {}
			root[key] = current
		else:
			var eq := line.find("=")
			if eq <= 0:
				return {"error": where + ": expected key = value"}
			var key := line.substr(0, eq).strip_edges()
			if current.has(key):
				return {"error": where + ": duplicate key '%s'" % key}
			var res := _value(line.substr(eq + 1).strip_edges())
			if res.has("error"):
				return {"error": "%s: %s" % [where, res["error"]]}
			current[key] = res["value"]
	return root


static func _strip_comment(line: String) -> String:
	var in_str := false
	for i in line.length():
		var c := line[i]
		if c == '"':
			in_str = not in_str
		elif c == "#" and not in_str:
			return line.substr(0, i)
	return line


static func _value(s: String) -> Dictionary:
	if s.begins_with('"'):
		if s.length() < 2 or not s.ends_with('"'):
			return {"error": "unterminated string"}
		return {"value": s.substr(1, s.length() - 2)}
	if s == "true" or s == "false":
		return {"value": s == "true"}
	if s.begins_with("["):
		if not s.ends_with("]"):
			return {"error": "arrays must be on one line"}
		var arr: Array = []
		var parts := _split_top(s.substr(1, s.length() - 2))
		if parts.is_empty():
			return {"error": "unbalanced brackets in array"}
		for p in parts[0]:
			var r := _value(p)
			if r.has("error"):
				return r
			arr.append(r["value"])
		return {"value": arr}
	if s.begins_with("{"):
		if not s.ends_with("}"):
			return {"error": "inline tables must be on one line"}
		var tbl: Dictionary = {}
		var parts := _split_top(s.substr(1, s.length() - 2))
		if parts.is_empty():
			return {"error": "unbalanced brackets in inline table"}
		var items: PackedStringArray = parts[0]
		for p in items:
			var eq := p.find("=")
			if eq <= 0:
				return {"error": "inline table entry '%s' is not key = value" % p}
			var key := p.substr(0, eq).strip_edges()
			if not key.is_valid_ascii_identifier() and not key.replace("-", "_").is_valid_ascii_identifier():
				return {"error": "bad inline table key '%s'" % key}
			if tbl.has(key):
				return {"error": "duplicate key '%s' in inline table" % key}
			var r := _value(p.substr(eq + 1).strip_edges())
			if r.has("error"):
				return r
			tbl[key] = r["value"]
		return {"value": tbl}
	if s.is_valid_int():
		return {"value": float(s.to_int())}
	if s.is_valid_float():
		return {"value": s.to_float()}
	return {"error": "unsupported value '%s'" % s}


## Splits the inside of [ ... ] / { ... } at top-level commas (not inside nested brackets
## or strings); empty items (a trailing comma) are dropped. Returns [] when the brackets
## don't balance, else [PackedStringArray of stripped items].
static func _split_top(inner: String) -> Array:
	var items := PackedStringArray()
	var depth := 0
	var in_str := false
	var start := 0
	for i in inner.length():
		var c := inner[i]
		if c == '"':
			in_str = not in_str
		elif in_str:
			continue
		elif c == "[" or c == "{":
			depth += 1
		elif c == "]" or c == "}":
			depth -= 1
			if depth < 0:
				return []
		elif c == "," and depth == 0:
			items.append(inner.substr(start, i - start).strip_edges())
			start = i + 1
	if depth != 0 or in_str:
		return []
	items.append(inner.substr(start).strip_edges())
	var out := PackedStringArray()
	for it in items:
		if not it.is_empty():
			out.append(it)
	return [out]


static func vec3(v: Variant) -> Vector3:
	var a: Array = v
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func color(v: Variant) -> Color:
	var a: Array = v
	return Color(float(a[0]), float(a[1]), float(a[2]))


## TOML box -> its Godot transform: Y-X-Z Euler (Godot default, like the C++ engine).
static func box_transform(box: Dictionary) -> Transform3D:
	var rot := Vector3.ZERO
	if box.has("rotation_deg"):
		var d := vec3(box["rotation_deg"])
		rot = Vector3(deg_to_rad(d.x), deg_to_rad(d.y), deg_to_rad(d.z))
	return Transform3D(Basis.from_euler(rot, EULER_ORDER_YXZ), vec3(box["center"]))
