class_name BitStream
extends RefCounted
## MSB-first bit packing for Ember Mark item codes (BUILD_PLAN step 20; ItemCodes).
## Write fixed-width unsigned fields with write(), read them back with read(); reading past
## the end returns 0 and sets `overrun` (a truncated code). One byte per bit internally:
## codes are tiny, clarity beats speed. (No static constructor returning BitStream:
## Godot #86540, see step 18.)

var bits := PackedByteArray()
var pos := 0
var overrun := false


## Appends the low `width` bits of `value` (0 <= value < 2^width), most significant first.
func write(value: int, width: int) -> void:
	for i in range(width - 1, -1, -1):
		bits.append((value >> i) & 1)


## Next `width` bits as an unsigned int (0 and `overrun` = true when not enough are left).
func read(width: int) -> int:
	if pos + width > bits.size():
		overrun = true
		pos = bits.size()
		return 0
	var v := 0
	for i in width:
		v = (v << 1) | bits[pos + i]
	pos += width
	return v


func remaining() -> int:
	return bits.size() - pos


## True when every unread bit is 0.
func rest_is_zero() -> bool:
	for i in range(pos, bits.size()):
		if bits[i] != 0:
			return false
	return true


## The bits as bytes, the last one padded with 0 bits.
func to_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	var i := 0
	while i < bits.size():
		var b := 0
		for k in 8:
			b = (b << 1) | (bits[i + k] if i + k < bits.size() else 0)
		out.append(b)
		i += 8
	return out


## Replaces the content with `bytes` (8 bits each) and rewinds.
func load_bytes(bytes: PackedByteArray) -> void:
	bits = PackedByteArray()
	for b in bytes:
		write(b, 8)
	pos = 0
	overrun = false
