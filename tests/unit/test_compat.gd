extends TestCase
## Step 90 done check: Windows <-> Linux co-op data. Golden values pinned on Linux; the
## same tests run in the Windows export (step 87) must give the same bytes and hashes.
##  - canonical JSON: key order independent, LF only, trailing LF, pinned sha256;
##  - item codes and loot rolls from fixed seeds pinned;
##  - character files written twice are byte-identical (no timestamps in the hash part);
##  - a peer with a different data fingerprint is rejected with a clear reason.

const GOLDEN_CANON := "4a87d6ed2541e0046ed4b8b87387a210a497cf7d390c77c8003f2fe8f65ee6d1"
const GOLDEN_SAMPLES := [
	"EM1-0M09G-00002-03THG",
	"EM1-0M180-00002-432Y8",
	"EM1-0M290-00002-82QYR",
	"EM1-0M39G-00002-C277G",
	"EM1-0R2D0-00000-CF548",
	"Basic Earth Charm",
	"Uncommon Earth Arcane Conduit",
]

var _port := 26900 + randi_range(0, 300) * 2


func test_canonical_bytes() -> void:
	var a := Compat.canonical({"z": 1, "a": {"y": 0.1, "b": [1.5, "é"]}, "m": true})
	var b := Compat.canonical({"m": true, "a": {"b": [1.5, "é"], "y": 0.1}, "z": 1})
	check(a == b, "key order does not matter")
	check(not a.contains("\r") and a.ends_with("\n"), "LF only + trailing LF")
	check(Compat.sha(a) == GOLDEN_CANON, "pinned hash (got %s)" % Compat.sha(a))


func test_item_codes_and_loot_pinned() -> void:
	var s := Compat.samples()
	check(Array(s) == GOLDEN_SAMPLES, "samples %s" % [s])
	check(Compat.fingerprint().length() == 16, "fingerprint")


func test_character_bytes_identical() -> void:
	var w := Node3D.new()
	w.position = Vector3(-9000, 5000, 0)
	runner_tree.root.add_child(w)
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	p.add_xp(250)
	var d1 := CharacterSave.capture(p)
	var d2 := CharacterSave.capture(p)
	d1.erase("saved_at")
	d2.erase("saved_at")
	check(Compat.canonical(d1) == Compat.canonical(d2), "same character -> same bytes")
	var path := CharacterSave.path_for("compat test 90")
	CharacterSave.write(p, path)
	var raw := FileAccess.get_file_as_string(path)
	check(not raw.contains("\r") and not raw.contains(OS.get_user_data_dir()), "no CR, no OS paths in the file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	w.queue_free()


func _wait(cond: Callable, frames := 300) -> bool:
	for i in frames:
		if cond.call():
			return true
		await runner_tree.process_frame
	return bool(cond.call())


func test_data_mismatch_rejected() -> void:
	_port += 1
	var w := Node.new()
	runner_tree.root.add_child(w)
	var h := NetSession.new()
	h.name = "H90"
	var c := NetSession.new()
	c.name = "C90"
	w.add_child(h)
	w.add_child(c)
	check(h.host(NetTransport.make("enet"), _port, {"name": "H"}), "host")
	Compat.fingerprint_override = "0000000000000000"
	check(c.join(NetTransport.make("enet"), "127.0.0.1:%d" % _port, {"name": "C"}), "join")
	Compat.fingerprint_override = ""
	check(await _wait(func(): return c.state == NetSession.State.IDLE), "rejected")
	check(c.last_reason.contains("game data mismatch"), c.last_reason)
	check(h.roster.size() == 1, "not admitted")
	h.leave("done")
	for i in 3:
		await runner_tree.process_frame
	w.queue_free()
