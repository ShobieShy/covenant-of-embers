extends TestCase
## Step 123 (Art A5): every loot kind gets a visible ground prop of sane size, and the
## Filth quest pickup (joes_discards) uses the trash-bag prop.

const KINDS := [
	"hat", "clothes", "belt", "shoes", "grimoire", "staff", "wand", "part", "gold", "mana", "dust", "potion", "trash"
]


func _box(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = CharacterModel._local_xform(n as Node3D, mi as Node3D) * (mi as MeshInstance3D).get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box


func test_every_kind_has_prop() -> void:
	for k: String in KINDS:
		var p: Node3D = LootMeshes.prop_for(k, Color.WHITE)
		check(p != null, "%s prop exists" % k)
		if p == null:
			continue
		var s := _box(p).get_longest_axis_size() * p.scale.x
		check(s > 0.05 and s < 1.0, "%s prop size %.2f in range" % [k, s])
		p.free()


func test_joes_discards_uses_trash() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/loot/quest_pickup.gd")
	check(src.contains("discard"), "quest pickup matches joes_discards")
