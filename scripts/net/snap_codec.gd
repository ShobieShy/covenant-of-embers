class_name SnapCodec
extends RefCounted
## Compact co-op enemy snapshots. One message stays within MAX_BYTES so it fits a single
## unreliable packet. The host sends a def.id catalog once ("kinds"); each row then carries
## a type index and a pose index instead of strings.
##
## Header (24 bytes, little-endian): version u8, count u8, reserved u16, t_ms u32, ack u32,
## origin xyz f32. Row (16 bytes): id u16, type u8, flags u8, pose u8, yaw u8,
## xyz i16 centimeters relative to the origin, health fraction u16, max health u16.
## Flags: bit0 dead, bit1 ally, bits2-4 status FX (Enemy.FX_*), bits5-7 boss phase.
## Positions farther than ±320 m from the origin are dropped. Rows are nearest-first;
## once the next row would pass MAX_BYTES the rest are dropped.

const MAX_BYTES := 1200
const HEADER := 24
const ROW := 16
const POS_LIMIT_CM := 32000
const POSES: PackedStringArray = ["idle", "detect", "chase", "windup", "attack", "recover", "hurt", "death"]

const _DEAD := 1
const _ALLY := 2
const _FX_SHIFT := 2
const _PHASE_SHIFT := 5


static func catalog_from(table: EnemyTable) -> PackedStringArray:
	var out := PackedStringArray()
	if table == null:
		return out
	for d in table.defs:
		if d != null and not d.id.is_empty() and not out.has(d.id):
			out.append(d.id)
	return out


static func ids_of(v: Variant) -> PackedStringArray:
	if v is PackedStringArray:
		return v
	var out := PackedStringArray()
	if v is Array:
		for x in v:
			out.append(String(x))
	return out


static func encode(
	rows: Array, origin: Vector3, t_ms: int, ack: int, catalog: PackedStringArray, max_bytes := MAX_BYTES
) -> PackedByteArray:
	var keep: Array = []
	var room := maxi(max_bytes, HEADER)
	for row in rows:
		if keep.size() == 255:
			break
		if not _row_ok(row, origin, catalog):
			continue
		if HEADER + (keep.size() + 1) * ROW > room:
			break
		keep.append(row)
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_u8(1)
	buf.put_u8(keep.size())
	buf.put_u16(0)
	buf.put_u32(maxi(t_ms, 0))
	buf.put_u32(maxi(ack, 0))
	buf.put_float(origin.x)
	buf.put_float(origin.y)
	buf.put_float(origin.z)
	for row in keep:
		_write_row(buf, row, origin, catalog)
	return buf.data_array


## {ok, rows, ack, t}. rows match CoopWorld.snap_row. ok is false when the bytes are not a snapshot.
static func decode(bytes: PackedByteArray, catalog: PackedStringArray) -> Dictionary:
	var none := {"ok": false, "rows": [], "ack": 0, "t": 0.0}
	if bytes.size() < HEADER:
		return none
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = bytes
	if buf.get_u8() != 1:
		return none
	var count := buf.get_u8()
	buf.get_u16()
	var t_ms := buf.get_u32()
	var ack := buf.get_u32()
	var origin := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
	if bytes.size() < HEADER + count * ROW:
		return none
	var rows: Array = []
	for _i in count:
		var row := _read_row(buf, origin, catalog)
		if not row.is_empty():
			rows.append(row)
	return {"ok": true, "rows": rows, "ack": ack, "t": float(t_ms)}


static func _row_ok(row: Array, origin: Vector3, catalog: PackedStringArray) -> bool:
	if row.size() < 7:
		return false
	var id := int(row[0])
	if id < 0 or id > 65535:
		return false
	var idx := catalog.find(String(row[1]))
	if idx < 0 or idx > 255:
		return false
	var p: Vector3 = row[2]
	return _cm_ok(p.x - origin.x) and _cm_ok(p.y - origin.y) and _cm_ok(p.z - origin.z)


static func _cm_ok(metres: float) -> bool:
	var cm := int(round(metres * 100.0))
	return cm >= -POS_LIMIT_CM and cm <= POS_LIMIT_CM


static func _write_row(buf: StreamPeerBuffer, row: Array, origin: Vector3, catalog: PackedStringArray) -> void:
	var p: Vector3 = row[2]
	var mx := maxf(0.0, float(row[5]))
	var frac := 0.0 if mx <= 0.0 else clampf(float(row[4]) / mx, 0.0, 1.0)
	buf.put_u16(int(row[0]))
	buf.put_u8(catalog.find(String(row[1])))
	buf.put_u8(_flags(row))
	buf.put_u8(_pose_index(String(row[9]) if row.size() > 9 else "idle"))
	buf.put_u8(_yaw_byte(float(row[3])))
	buf.put_16(_cm(p.x - origin.x))
	buf.put_16(_cm(p.y - origin.y))
	buf.put_16(_cm(p.z - origin.z))
	buf.put_u16(int(round(frac * 65535.0)))
	buf.put_u16(mini(int(round(mx)), 65535))


static func _read_row(buf: StreamPeerBuffer, origin: Vector3, catalog: PackedStringArray) -> Array:
	var id := buf.get_u16()
	var type_i := buf.get_u8()
	var flags := buf.get_u8()
	var pose_i := buf.get_u8()
	var yaw := float(buf.get_u8()) / 256.0 * TAU
	var pos := origin + Vector3(buf.get_16(), buf.get_16(), buf.get_16()) / 100.0
	var frac_q := buf.get_u16()
	var max_h := float(buf.get_u16())
	if type_i >= catalog.size():
		return []
	var pose := POSES[pose_i] if pose_i < POSES.size() else POSES[0]
	return [
		id,
		String(catalog[type_i]),
		pos,
		yaw,
		max_h * float(frac_q) / 65535.0,
		max_h,
		(flags & _DEAD) != 0,
		(flags & _ALLY) != 0,
		(flags >> _FX_SHIFT) & 7,
		pose,
		(flags >> _PHASE_SHIFT) & 7,
	]


static func _flags(row: Array) -> int:
	var flags := 0
	if bool(row[6]):
		flags |= _DEAD
	if row.size() > 7 and bool(row[7]):
		flags |= _ALLY
	if row.size() > 8:
		flags |= (int(row[8]) & 7) << _FX_SHIFT
	if row.size() > 10:
		flags |= clampi(int(row[10]), 0, 7) << _PHASE_SHIFT
	return flags


static func _pose_index(name: String) -> int:
	var i := POSES.find(name)
	return i if i >= 0 else 0


static func _yaw_byte(yaw: float) -> int:
	return int(round(fposmod(yaw, TAU) / TAU * 256.0)) & 255


static func _cm(metres: float) -> int:
	return clampi(int(round(metres * 100.0)), -POS_LIMIT_CM, POS_LIMIT_CM)
