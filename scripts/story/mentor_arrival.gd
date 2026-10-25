class_name MentorArrival
extends RefCounted
## The first night in the Old Oak (BUILD_PLAN step 66; Magewar npc_bob.gd): Bob arrives by
## teleport vortex, appraises the Summoned (his bob_intro dialogue) and gives the Landfill
## task + starter gear (Magewar: "a rusty dagger and a mana potion" - here a Mana Potion and
## the flag starter_gear_given). Plays once: flag bob_arrived.

const FLAG := "bob_arrived"
const NEEDS := "home_unlocked"
const STARTER_POTION := "mana_potion"


static func should_play(flags: StoryFlags) -> bool:
	return flags != null and flags.has(NEEDS) and not flags.has(FLAG)


## Plays the scene when due: sets the flags, gives the gear, opens Bob's dialogue when a
## runner is given, and adds the vortex under `parent` at `at`. Returns whether it played.
static func play(
	flags: StoryFlags, p: Player, runner: DialogueRunner = null, parent: Node = null, at := Vector3.ZERO
) -> bool:
	if not should_play(flags):
		return false
	flags.set_flag(FLAG)
	flags.set_flag("starter_gear_given")
	var potion := ConsumableItem.load_item(STARTER_POTION)
	if p and potion:
		p.equipment.add_potions(potion, 1)
	if parent:
		parent.add_child(vortex(at))
	if runner:
		runner.start("Bob")
	return true


## Greybox teleport vortex: a glowing violet torus where Bob appears.
static func vortex(at: Vector3) -> Node3D:
	var v := CSGTorus3D.new()
	v.name = "BobVortex"
	v.inner_radius = 0.6
	v.outer_radius = 1.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.6, 0.3, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.6, 0.3, 1.0)
	m.emission_energy_multiplier = 3.0
	v.material = m
	v.rotation_degrees.x = 90.0
	v.position = at + Vector3(0, 1.2, 0)
	RitualFX.dress_vortex(v)  # step 133 (FX F7)
	return v
