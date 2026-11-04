class_name LabGate
extends RefCounted
## Act II gate checkpoint (PLAN_0.7.0_ACT2.md KTD3). `current` 1-5 is a Warrens floor.
## 6, 7 and 8 are pads in the one Blightcoil cavern. 0 with the King still alive is
## floor 1. 0 with the King dead waits for the host to pick floor 1 or the Sump.

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
	if state == null or not state.bosses.has(KING):
		return 1
	if choice == 1 or choice == SUMP:
		return choice
	return -1


static func banner(floor_no: int) -> String:
	if floor_no == SUMP:
		return "The Blightcoil, Sump"
	if is_cavern(floor_no):
		return "The Blightcoil"
	return "Goblin Warrens, floor %d" % floor_no


static func choice_label(floor_no: int) -> String:
	if floor_no == SUMP:
		return "The Blightcoil, Sump"
	return "Goblin Warrens, floor 1"
