class_name EnemyBarks
extends RefCounted
## One line at aggro, hurt, and death. Presentation only.

const LINES := {
	"aggro": ["There you are.", "Don't blink.", "Mine."],
	"hurt": ["That stung.", "Again.", "You'll pay."],
	"death": ["Down.", "Not yet.", "Remember this."],
}


static func line(kind: String, enemy_id: String) -> String:
	var rows: Array = LINES.get(kind, ["..."])
	return String(rows[absi(hash(enemy_id + kind)) % rows.size()])


static func mark(e: Enemy, kind: String) -> void:
	if e == null:
		return
	var id := e.def.id if e.def != null else "foe"
	e.set_meta(&"bark", line(kind, id))
	e.set_meta(&"bark_kind", kind)
