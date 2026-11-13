extends TestCase
## Compact co-op snapshots: 64 enemies stay under one 1,200 byte packet, and pose,
## status FX, ally, and boss phase survive the round trip.


func _rows(n: int) -> Array:
	var rows: Array = []
	for i in n:
		(
			rows
			. append(
				[
					i + 1,
					"gnawer" if i % 2 == 0 else "the_filth",
					Vector3(i * 1.25, 0.2, -i * 0.4),
					float(i) * 0.17,
					12.0 if i % 5 else 30.0,
					30.0,
					i == 3,
					i == 4,
					(Enemy.FX_BURN | Enemy.FX_STAGGER) if i == 5 else 0,
					"attack" if i % 3 == 0 else "chase",
					2 if i == 7 else 1,
				]
			)
		)
	return rows


func test_sixty_four_rows_fit_one_packet() -> void:
	var catalog := PackedStringArray(["gnawer", "the_filth"])
	var rows := _rows(64)
	var bytes := SnapCodec.encode(rows, Vector3(10, 0, 4), 123456, 99, catalog)
	check(bytes.size() <= SnapCodec.MAX_BYTES, "64 rows are %d bytes" % bytes.size())
	check(bytes.size() == SnapCodec.HEADER + 64 * SnapCodec.ROW, "fixed 16-byte rows")
	var back: Dictionary = SnapCodec.decode(bytes, catalog)
	check(bool(back["ok"]) and back["rows"].size() == 64, "all 64 came back")
	check(int(back["ack"]) == 99 and is_equal_approx(float(back["t"]), 123456.0), "time and ack")
	var far: Array = back["rows"][63]
	var want: Vector3 = rows[63][2]
	check((far[2] as Vector3).distance_to(want) < 0.02, "position within a centimeter")
	check(absf(angle_difference(float(far[3]), float(rows[63][3]))) < 0.03, "yaw")
	check(String(back["rows"][1][1]) == "the_filth" and String(back["rows"][1][9]) == "chase", "type and pose")
	check(bool(back["rows"][3][6]) and bool(back["rows"][4][7]), "dead and ally")
	check(int(back["rows"][5][8]) == (Enemy.FX_BURN | Enemy.FX_STAGGER), "status bits")
	check(int(back["rows"][7][10]) == 2, "boss phase")
	check(absf(float(back["rows"][0][4]) - 30.0) < 0.05, "full health")


func test_over_budget_drops_the_farthest() -> void:
	var catalog := PackedStringArray(["gnawer", "the_filth"])
	var rows := _rows(64)
	var room := SnapCodec.HEADER + 3 * SnapCodec.ROW
	var bytes := SnapCodec.encode(rows, Vector3.ZERO, 1, 0, catalog, room)
	check(bytes.size() <= room, "stays in the budget (%d)" % bytes.size())
	var back: Array = SnapCodec.decode(bytes, catalog)["rows"]
	check(back.size() == 3 and int(back[0][0]) == 1 and int(back[2][0]) == 3, "nearest three kept")
	var mixed := [rows[0], [9, "gnawer", Vector3(400, 0, 0), 0.0, 30.0, 30.0, false], rows[1]]
	var kept: Array = SnapCodec.decode(SnapCodec.encode(mixed, Vector3.ZERO, 1, 0, catalog), catalog)["rows"]
	check(kept.size() == 2 and int(kept[1][0]) == 2, "a pose past ±320 m is dropped")


func test_puppet_keeps_fx_pose_and_phase() -> void:
	var table := EnemyTable.load_default()
	var catalog := SnapCodec.catalog_from(table)
	var host_cw := CoopWorld.new()
	var real := Enemy.new()
	real.setup(table.find("gnawer"))
	runner_tree.root.add_child(real)
	real.global_position = Vector3(3, 1, -2)
	real.rotation.y = 1.0
	real.pose = "windup"
	real.burn_left = 2.0
	real.corrupted_left = 5.0
	var row := host_cw.snap_row(real)
	row[10] = 3
	var bytes := SnapCodec.encode([row], real.global_position, 0, 7, catalog)
	var cw := CoopWorld.new()
	cw.table = table
	cw._type_ids = catalog
	runner_tree.root.add_child(cw)
	var got: Dictionary = SnapCodec.decode(bytes, cw._type_ids)
	cw._apply_snapshot(got["rows"], int(got["ack"]))
	var pup: Enemy = cw.puppets.values()[0]
	check(pup.def.id == "gnawer", "type from the catalog")
	check(pup.global_position.distance_to(real.global_position) < 0.02, "feet")
	check(absf(pup.rotation.y - 1.0) < 0.03, "yaw")
	check(pup.net_pose == "windup" and pup.pose == "windup", "pose")
	check(pup.net_fx == Enemy.FX_BURN and pup.corrupted_left > 0.0, "status and ally")
	check(int(pup.get_meta(&"net_phase")) == 3, "phase survives on the puppet")
	var cfg: Dictionary = (load("res://scripts/net/net_session.gd") as GDScript).call(&"get_rpc_config")
	var fast: Dictionary = cfg[&"_msg_fast"]
	check(int(fast.get("channel", 0)) == 1, "unreliable traffic is channel 1")
	check(
		int(fast.get("transfer_mode", -1)) == MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED,
		"snapshots are unreliable ordered"
	)
	check(int((cfg[&"_msg"] as Dictionary).get("channel", 0)) == 0, "reliable traffic stays on channel 0")
	real.free()
	cw.free()
	host_cw.free()
