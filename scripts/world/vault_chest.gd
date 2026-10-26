class_name VaultChest
extends Node3D
## The Breach vault chest (BUILD_PLAN step 35): guaranteed boss loot. Locked until the
## Breach opens the vault (unlock()); then `interact` within REACH (or open_chest()) spills
## its contents once through a LootDropper (pickups with beams, like kill drops).
## Contents (roll_contents): PARTS procedural parts + one equipment piece, each rolled on
## the RarityTable (luck / Vigil table apply) and raised to at least `floor_rarity`
## (default Rare). Unique stays Unique (a lucky roll is never lowered). Magewar has no
## chest; its boss loot is the golem's loot table, so the floor is plan design.

signal opened(drops: Array[LootDrop])

const GROUP := &"vault_chests"
const REACH := 2.0
const PARTS := 2
const DEFAULT_FLOOR := "rare"
const CONSECRATE_CHANCE := 0.5  ## step 36: the equipment piece is Consecrated (Rare+ only)

@export var floor_rarity := DEFAULT_FLOOR
var locked := true
var is_open := false
var player: Player
var dropper: LootDropper
var rng := RandomNumberGenerator.new()
var luck := 0.0
var table: RarityTable
var element := -1  ## -1 = roll per item; the Breach passes the boss's affinity
var _lid: MeshInstance3D


func _ready() -> void:
	Interaction.register(self, 0.5, 0.6)
	add_to_group(GROUP)
	if get_child_count() == 0:
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.2, 0.6, 0.7)
		body.mesh = bm
		body.position.y = 0.3
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.45, 0.3, 0.15)
		body.material_override = m
		add_child(body)
		_lid = MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(1.25, 0.15, 0.75)
		_lid.mesh = lm
		_lid.position.y = 0.68
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.85, 0.65, 0.2)
		gm.emission_enabled = true
		gm.emission = Color(1.0, 0.6, 0.2)
		_lid.material_override = gm
		add_child(_lid)


## Raises `id` to `floor_id` when below it.
static func at_least(id: String, floor_id: String) -> String:
	return floor_id if Rarity.parse(id) < Rarity.parse(floor_id) else id


static func roll_contents(
	r: RandomNumberGenerator,
	floor_id := DEFAULT_FLOOR,
	lk := 0.0,
	rt: RarityTable = null,
	el := -1,
	bias: PackedStringArray = [],
) -> Array[LootDrop]:
	var t := rt if rt != null else RarityTable.load_default()
	var out: Array[LootDrop] = []
	for i in PARTS:
		var pt := r.randi_range(0, WieldablePart.PART_TYPE_NAMES.size() - 1) as WieldablePart.PartType
		var rolled := t.roll(r, lk).id
		var rid := at_least(rolled, floor_id)
		var e := DropRoller._element(r, el)
		var part := PartRoller.roll(r, pt, rid, e)
		if part == null:
			continue
		var d := LootDrop.new()
		d.kind = LootDrop.Kind.PART
		d.item = part
		d.rarity_id = rid
		d.rolled_rarity_id = rolled
		d.element = part.element
		d.roll_seed = part.roll_seed
		out.append(d)
	var q := LootDrop.new()
	q.kind = LootDrop.Kind.EQUIPMENT
	q.equip_slot = r.randi_range(0, LootDrop.DROP_EQUIP_SLOTS - 1)
	q.rolled_rarity_id = t.roll(r, lk).id
	q.rarity_id = at_least(q.rolled_rarity_id, floor_id)
	q.element = DropRoller._element(r, el)
	q.roll_seed = r.randi()
	q.item = EquipmentRoller.from_seed(q.roll_seed, q.equip_slot, q.rarity_id, q.element)
	if q.item != null and Rarity.parse(q.rarity_id) >= Rarity.parse("rare") and r.randf() < CONSECRATE_CHANCE:
		(q.item as EquipmentItem).consecration = Consecrations.roll(r, bias)
	out.append(q)
	return out


func unlock() -> void:
	locked = false


func interact_prompt() -> String:
	return "[F] Open chest" if not locked and not is_open else ""


## Looked at (t60u camera-centre cone/sphere-cast, Interaction) and within range.
func in_reach(p: Player) -> bool:
	return near(p) and Interaction.is_target(p, self)


## Plain proximity (attunement, bot walking); interaction itself goes by look (t60u).
func near(p: Player) -> bool:
	return p != null and is_inside_tree() and p.global_position.distance_to(global_position) <= REACH + 1.0


## Opens once (unlocked only): rolls, spawns pickups via `dropper` when set, emits opened.
func open_chest() -> Array[LootDrop]:
	var none: Array[LootDrop] = []
	if locked or is_open:
		return none
	is_open = true
	var bias := PackedStringArray()  # step 72: tree-aware consecration weights
	var ps := get_tree().get_nodes_in_group(Player.GROUP) if is_inside_tree() else []
	if not ps.is_empty():
		bias = Consecrations.bias_for(ps[0] as Player)
	var drops := roll_contents(rng, floor_rarity, luck, table, element, bias)
	if dropper != null and dropper.parent != null:
		dropper.spawn_drops(drops, dropper.parent.to_local(global_position + Vector3(0, 0.2, 1.0)), "vault_chest")
	if _lid:
		_lid.rotation_degrees.x = -70.0
		_lid.position = Vector3(0, 0.9, -0.35)
	opened.emit(drops)
	return drops


## Step 158: an already-looted zone chest (its flag is set): shown open, no loot.
func open_chest_quiet() -> void:
	is_open = true
	if _lid:
		_lid.rotation_degrees.x = -70.0
		_lid.position = Vector3(0, 0.9, -0.35)


func _unhandled_input(event: InputEvent) -> void:
	if locked or is_open or player == null or player.ui_open:
		return
	if event.is_action_pressed(&"interact") and in_reach(player):
		open_chest()
		get_viewport().set_input_as_handled()
