class_name SlagSeal
extends QuestPickup
## One of Joe's three slag seals. The quest counts `slag_seal`. The stable id is
## a story flag `seal:<id>`, so a reload does not spawn it again. `mark:` stays
## the Act II seed and is not used here.

var flag_id := ""
var flags: StoryFlags


static func make_seal(id: String, story: StoryFlags) -> SlagSeal:
	var m := SlagSeal.new()
	m.flag_id = id
	m.flags = story
	m.item_id = "slag_seal"
	m.display_name = "Slag seal"
	m.name = "Seal_" + id
	return m


func collect(p: Player) -> void:
	if flags != null and flag_id != "":
		flags.set_flag("seal:" + flag_id)
	super.collect(p)
