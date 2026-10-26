class_name AssemblyStation
extends Node3D
## Magic Assembly Station (BUILD_PLAN step 25; Magewar magic_assembly_station.gd). The
## station only moves items between the player's backpack and Assembly (rules + stats):
##  * preview(base, parts)  = Assembly.assemble, nothing consumed (Magewar preview_staff/wand);
##  * assemble(player, base, parts): base staff/wand (bare, from the backpack) + parts (from
##    the backpack) -> the assembled wieldable in the backpack; emits crafting_completed
##    here and on the EventBus (Magewar crafting_completed);
##  * disassemble(player, w): an assembled wieldable in the backpack -> its parts + a bare
##    base back in the backpack; refused when the backpack lacks room.
## Reinterpreted: Magewar duplicates a fixed starter template; here the player picks the
## base (PLAN "the base staff/wand is the spell"), and it comes back on disassembly.
## Magewar's selected_* slots / UI are the step 30 screen; `last_error` is the refusal.

signal crafting_completed(item: WieldableInstance)

const GROUP := &"assembly_stations"
const REACH := 3.0
const MARKER := "WaveSpawns/station"  ## step 46: a level's station spot (else beside the start)
const PROMPT := "[F] %s"

@export var station_name := "Magic Assembly Station"
@export var can_craft_staffs := true
@export var can_craft_wands := true

var last_error := ""
var crafted := 0


## Step 46: a station with its block mesh, placed at the level's MARKER when it has one,
## else at `fallback` (Midden: beside the start).
static func place(parent: Node, level: Node, fallback: Vector3) -> AssemblyStation:
	var st := AssemblyStation.new()
	st.name = "AssemblyStation"
	var box := CSGBox3D.new()
	box.size = Vector3(1.2, 1.0, 0.8)
	box.position.y = 0.5
	st.add_child(box)
	parent.add_child(st)
	var at := level.get_node_or_null(MARKER) as Node3D if level else null
	if at:
		st.global_transform = at.global_transform
	else:
		st.global_position = fallback
	return st


## The shared station prompt for whichever station is in reach ("" when none).
static func prompt_for(p: Player) -> String:
	var t := Interaction.target(p) if p and not p.ui_open else null
	return (t as AssemblyStation).interact_prompt() if t is AssemblyStation else ""


func _ready() -> void:
	Interaction.register(self, 1.0, 0.9)
	add_to_group(GROUP)


func interact_prompt() -> String:
	return PROMPT % station_name


## Looked at (t60u camera-centre cone/sphere-cast, Interaction) and within range.
func in_reach(p: Player) -> bool:
	return near(p) and Interaction.is_target(p, self)


## Plain proximity (attunement, bot walking); interaction itself goes by look (t60u).
func near(p: Player) -> bool:
	return p != null and is_inside_tree() and p.global_position.distance_to(global_position) <= REACH + 1.0


func allows(type: WieldableDef.Type) -> bool:
	return can_craft_wands if type == WieldableDef.Type.WAND else can_craft_staffs


func check(base: WieldableInstance, parts: Array) -> PackedStringArray:
	var errs := PackedStringArray()
	if base == null or base.def == null:
		errs.append("Choose a base staff or wand.")
		return errs
	if base.assembled:
		errs.append("The base is already assembled; disassemble it first.")
	if not allows(base.type()):
		errs.append("This station can't craft a %s." % Assembly.TYPE_NAMES[base.type()])
	errs.append_array(Assembly.check(base.def, parts))
	return errs


func preview(base: WieldableInstance, parts: Array) -> WieldableInstance:
	if not check(base, parts).is_empty():
		return null
	return Assembly.assemble(base.def, parts)


func assemble(p: Player, base: WieldableInstance, parts: Array) -> WieldableInstance:
	last_error = ""
	var errs := check(base, parts)
	if errs.is_empty() and not p.inventory.has(base):
		errs.append("The base must be in your backpack.")
	for part in parts:
		if errs.is_empty() and not p.inventory.has(part):
			errs.append("Every part must be in your backpack.")
	if not errs.is_empty():
		last_error = errs[0]
		return null
	var w := Assembly.assemble(base.def, parts)
	p.inventory.remove(base)
	for part in parts:
		p.inventory.remove(part)
	p.inventory.add(w)
	crafted += 1
	crafting_completed.emit(w)
	GameEvents.bus().crafting_completed.emit(p, w)
	return w


func disassemble(p: Player, w: WieldableInstance) -> Array[WieldablePart]:
	last_error = ""
	var out: Array[WieldablePart] = []
	if w == null or not w.assembled or not p.inventory.has(w):
		last_error = "Choose an assembled staff or wand in your backpack."
		return out
	var parts := Assembly.disassemble(w)
	if p.inventory.free_slots() + 1 < parts.size() + 1:
		last_error = PickupCollector.HINT_FULL
		p.show_hint(last_error)
		return out
	p.inventory.remove(w)
	for part in parts:
		p.inventory.add(part)
	p.inventory.add(WieldableInstance.of(w.def))
	return parts
