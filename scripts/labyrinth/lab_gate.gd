class_name LabGate
extends RefCounted
## Crater checkpoint. `current` 1-5 is a Warrens floor. 6, 7 and 8 are pads in the one
## Blightcoil cavern. 9-13 are one Slagworks floor each. 0 with the King still alive is
## floor 1. 0 with the King dead waits for the host to pick. The Railhead is a third
## choice only after the Matriarch is dead too.

const KING := "goblin_king"
const SUMP := 6
const CANOPY := 7
const CROWN := 8
const BOSS := "blightmaw_matriarch"


static func is_cavern(n: int) -> bool:
	return n >= SUMP and n <= CROWN


static func needs_choice(state: LabyrinthState) -> bool:
	return state != null and state.current == 0 and state.bosses.has(KING)


## The checkpoint to enter, or -1 when the host still has to pick.
static func resolve(state: LabyrinthState, choice: int) -> int:
	var c := 0 if state == null else state.current
	if c >= 1 and c <= 5:
		return c
	if is_cavern(c):
		return c
	if SlagworksFloor.is_floor(c):
		return c
	if state == null or not state.bosses.has(KING):
		return 1
	if choice == 1 or choice == SUMP:
		return choice
	# A Railhead choice while the Matriarch is alive does not enter.
	if choice == SlagworksFloor.FIRST and state.bosses.has(BOSS):
		return SlagworksFloor.FIRST
	return -1


## Picker rows. The Railhead appears only when both bosses are dead.
static func choices(state: LabyrinthState) -> Array:
	var out: Array = [1, SUMP]
	if state != null and state.bosses.has(KING) and state.bosses.has(BOSS):
		out.append(SlagworksFloor.FIRST)
	return out


static func banner(floor_no: int) -> String:
	if floor_no == SUMP:
		return "The Blightcoil, Sump"
	if is_cavern(floor_no):
		return "The Blightcoil"
	if SlagworksFloor.is_floor(floor_no):
		return "The Slagworks, %s" % String(SlagworksFloor.NAMES.get(floor_no, ""))
	return "Goblin Warrens, floor %d" % floor_no


static func choice_label(floor_no: int) -> String:
	if floor_no == SUMP:
		return "The Blightcoil, Sump"
	if floor_no == SlagworksFloor.FIRST:
		return "The Slagworks, Railhead"
	return "Goblin Warrens, floor 1"
