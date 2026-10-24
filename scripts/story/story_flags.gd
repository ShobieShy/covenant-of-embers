class_name StoryFlags
extends RefCounted
## Story flags (BUILD_PLAN step 62): named booleans and counters shared by dialogue,
## quests and story beats ("bob_met", "filth_defeated", "dlg_seen:bob_intro" ...).

signal changed(flag: String, value: int)

var values := {}  ## String -> int (0 = unset)


func has(flag: String) -> bool:
	return int(values.get(flag, 0)) != 0


func value(flag: String) -> int:
	return int(values.get(flag, 0))


func set_flag(flag: String, v := 1) -> void:
	if v == 0:
		clear(flag)
		return
	if int(values.get(flag, 0)) == v:
		return
	values[flag] = v
	changed.emit(flag, v)


func clear(flag: String) -> void:
	if values.erase(flag):
		changed.emit(flag, 0)


func all_of(flags: Array) -> bool:
	for f in flags:
		if not has(String(f)):
			return false
	return true


func none_of(flags: Array) -> bool:
	for f in flags:
		if has(String(f)):
			return false
	return true


func to_dict() -> Dictionary:
	return values.duplicate()


func from_dict(d: Dictionary) -> void:
	values.clear()
	for k in d:
		if int(d[k]) != 0:
			values[String(k)] = int(d[k])
