class_name RelicDrop
extends Resource
## A relic. The effect is applied while it is worn and gone when it is removed.

const IDS: PackedStringArray = ["ember_chip", "ward_bead", "sip_stone"]
const NAMES := {"ember_chip": "Ember Chip", "ward_bead": "Ward Bead", "sip_stone": "Sip Stone"}

@export var relic_id := "ember_chip"
@export var display_name := "Ember Chip"


static func make(id: String) -> RelicDrop:
	var r := RelicDrop.new()
	r.relic_id = id if IDS.has(id) else "ember_chip"
	r.display_name = String(NAMES.get(r.relic_id, r.relic_id))
	return r
