class_name Descent
extends RefCounted
## The Abyss is one labyrinth's finite replay after its story boss. Endless Descent
## starts only after that replay is beaten. Story floors stay the handmade kits.
## Covenant Escalation's cap rises with Endless depth. The class in code stays Vigil.

const BOSSES := {
	"warrens": "goblin_king",
	"blightcoil": "blightmaw_matriarch",
	"slagworks": "forgemaw",
	"sunken": "drowned_choir",
}


static func abyss_open(state: LabyrinthState, labyrinth_id: String) -> bool:
	if state == null or not BOSSES.has(labyrinth_id):
		return false
	return state.bosses.has(String(BOSSES[labyrinth_id]))


static func finish_abyss(state: LabyrinthState, labyrinth_id: String) -> bool:
	if not abyss_open(state, labyrinth_id) or state.abyss.has(labyrinth_id):
		return false
	state.abyss.append(labyrinth_id)
	return true


static func endless_open(state: LabyrinthState, labyrinth_id: String) -> bool:
	return state != null and state.abyss.has(labyrinth_id)


static func tier_cap(depth: int) -> int:
	return clampi(depth, 0, Vigil.MAX_TIER)


static func set_tier(depth: int, requested: int) -> int:
	return clampi(requested, 0, tier_cap(depth))


## A generated floor past the story. `depth` is the Endless Descent depth, and it is
## also the remix count, so a deeper floor is a different seed.
static func endless_floor(state: LabyrinthState, labyrinth_id: String, depth: int) -> Dictionary:
	if not endless_open(state, labyrinth_id) or depth < 1:
		return {}
	var seed := FloorGen.floor_seed(state.save_seed, labyrinth_id, 1000 + depth, depth)
	var kit := FloorGen.load_kit()
	if kit.has("error"):
		return {}
	var fl := FloorGen.generate(kit, seed)
	fl["depth"] = depth
	fl["tier_cap"] = tier_cap(depth)
	return fl
