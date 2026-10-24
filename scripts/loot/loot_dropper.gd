class_name LootDropper
extends Node
## Kill → loot (BUILD_PLAN step 22). Listens to GameEvents.bus().enemy_killed (once per
## death; the enemy is still in the tree that tick, so its position/def are read in the
## handler and the node is never kept), rolls DropRoller.roll_enemy on the killer's
## per-player rng and spawns one LootPickup per drop around the corpse under `parent`.
## Training dummies respawn and have no loot in Magewar → no drops for them.
## Order (Magewar _finalize_death: rewards first, then _drop_loot): XP (step 27) must
## connect to enemy_killed before this node, or be granted from `before_drops`.
## rng: one stream per player = make_peer_rng(seed_base, peer_id) (PLAN §30.2: the host
## rolls, clients regenerate). Single-player slice: peer 1.

signal drops_spawned(pickups: Array[LootPickup], enemy_id: String, at: Vector3)

const SCATTER := 0.6  ## m ring radius when a kill drops several items
const LIFT := 0.05  ## m above the corpse's feet

@export var seed_base := "covenant"
@export var peer_id := 1
var parent: Node3D  ## where pickups go (defaults to this node's parent)
var luck := 0.0  ## from the player (0 until a stat gives luck)
var vigil: Vigil  ## step 28: null/tier 0 = shipped weights; else a shifted copy
var _vigil_table: RarityTable
var _vigil_key := ""
var rng: RandomNumberGenerator
var gold_rng: RandomNumberGenerator  ## step 59: own stream so item rolls stay as before
var spawned := 0  ## pickups spawned (all time)
var kills_seen := 0
var kills_skipped := 0
var gold_spawned := 0  ## gold pickups (not counted in `spawned`)


## Step 59: gold for one kill: base +-25 % (0 stays 0).
static func gold_for(def: EnemyDef, r: RandomNumberGenerator) -> int:
	var b := def.gold_base()
	if b <= 0:
		return 0
	return maxi(1, int(round(b * r.randf_range(0.75, 1.25))))


static func make_peer_rng(base: String, peer: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s:%d" % [base, peer])
	return r


static func drops_for(enemy_id: String) -> bool:
	return not enemy_id.ends_with("training_dummy")


func _ready() -> void:
	if rng == null:
		rng = make_peer_rng(seed_base, peer_id)
	if gold_rng == null:
		gold_rng = make_peer_rng(seed_base + ":gold", peer_id)
	if parent == null:
		parent = get_parent() as Node3D
	var bus := GameEvents.bus()
	if not bus.enemy_killed.is_connected(_on_enemy_killed):
		bus.enemy_killed.connect(_on_enemy_killed)


func _exit_tree() -> void:
	var bus := GameEvents.bus()
	if bus.enemy_killed.is_connected(_on_enemy_killed):
		bus.enemy_killed.disconnect(_on_enemy_killed)


func _on_enemy_killed(enemy: Enemy, _element: ElementTable.Element) -> void:
	if enemy == null or enemy.def == null or parent == null:
		return
	kills_seen += 1
	if not drops_for(enemy.def.id):
		kills_skipped += 1
		return
	var at := parent.to_local(enemy.global_position)
	spawn_drops(DropRoller.roll_enemy(rng, enemy.def, luck, null, rarity_table()), at, enemy.def.id)
	var g := gold_for(enemy.def, gold_rng)
	if g > 0:
		var gp := LootPickup.create_gold(g, at + Vector3(0.0, LIFT, -SCATTER * 0.5))
		parent.add_child(gp)
		gold_spawned += 1


## Step 28: the rarity table drops roll on (null = shipped default).
func rarity_table() -> RarityTable:
	if vigil == null or vigil.tier <= 0:
		return null
	var key := vigil.describe()
	if _vigil_table == null or key != _vigil_key:
		_vigil_table = vigil.table_for()
		_vigil_key = key
	return _vigil_table


func spawn_drops(drops: Array[LootDrop], at: Vector3, enemy_id := "") -> Array[LootPickup]:
	var out: Array[LootPickup] = []
	for i in drops.size():
		var off := Vector3.ZERO
		if drops.size() > 1:
			var a := TAU * i / drops.size()
			off = Vector3(cos(a), 0.0, sin(a)) * SCATTER
		var p := LootPickup.create(drops[i], at + off + Vector3.UP * LIFT)
		parent.add_child(p)
		out.append(p)
	spawned += out.size()
	if not out.is_empty():
		drops_spawned.emit(out, enemy_id, at)
	return out
