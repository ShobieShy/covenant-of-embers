class_name BlightMark
extends QuestPickup
## One of Crazy Joe's three ritual marks. The quest counts `joe_mark`. The stable id
## is a story flag `mark:<id>`, so a reload does not spawn it again and the Labyrinth
## block does not grow a new key.

var flag_id := ""
var flags: StoryFlags


static func make_mark(id: String, story: StoryFlags) -> BlightMark:
	var m := BlightMark.new()
	m.flag_id = id
	m.flags = story
	m.item_id = "joe_mark"
	m.display_name = "Joe's mark"
	m.name = "Mark_" + id
	return m


func _ready() -> void:
	super._ready()
	var tex := BlightcoilKit.texture("ritual_mark_decal")
	if tex == null:
		return
	var d := Decal.new()
	d.name = "RitualMark"
	d.texture_albedo = tex
	d.size = Vector3(1.2, 0.8, 1.2)
	d.position.y = 0.35
	add_child(d)


func collect(p: Player) -> void:
	if flags != null and flag_id != "":
		flags.set_flag("mark:" + flag_id)
	super.collect(p)
