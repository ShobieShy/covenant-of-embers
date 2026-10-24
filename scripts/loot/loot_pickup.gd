class_name LootPickup
extends Area3D
## A dropped item lying in the world (BUILD_PLAN step 22; Magewar loot_pickup /
## dropped item visuals reinterpreted): a small rarity-tinted emissive gem box, a thin
## vertical light beam in the rarity colour (taller for higher tiers, Borderlands-style
## readability without its assets), an OmniLight and a billboard Label3D with
## LootDrop.describe(). It is an Area3D on PICKUP_LAYER so step 23 can detect the player
## walking over it / looking at it. `drop` is the LootDrop it carries.

const PICKUP_LAYER := 5          ## physics layer 5 = pickups (1 world, 2 player, 3 enemies)
const GROUP := &"loot_pickups"
const BEAM_BASE := 1.5           ## m, Basic
const BEAM_PER_TIER := 0.5       ## m per rarity tier above Basic
const GEM_SIZE := 0.25

var drop: LootDrop
var color := Color.WHITE
var beam: MeshInstance3D
var gem: MeshInstance3D
var light: OmniLight3D
var label: Label3D

static func create(d: LootDrop, at: Vector3) -> LootPickup:
	var p := LootPickup.new()
	p.setup(d)
	p.position = at
	return p

func setup(d: LootDrop) -> void:
	drop = d
	name = "Pickup_%s" % d.rarity_id
	color = d.rarity_color()
	collision_layer = 1 << (PICKUP_LAYER - 1)
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group(GROUP)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.4
	cs.shape = sh
	cs.position.y = GEM_SIZE * 0.5
	add_child(cs)
	gem = MeshInstance3D.new()
	gem.name = "Gem"
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * GEM_SIZE
	gem.mesh = bm
	gem.position.y = GEM_SIZE * 0.5
	var gm := StandardMaterial3D.new()
	gm.albedo_color = color
	gm.emission_enabled = true
	gm.emission = color
	gm.emission_energy_multiplier = 1.5
	gem.material_override = gm
	add_child(gem)
	beam = MeshInstance3D.new()
	beam.name = "Beam"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.06
	cm.height = beam_height()
	beam.mesh = cm
	beam.position.y = cm.height * 0.5
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color = Color(color, 0.55)
	beam.material_override = mm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	light = OmniLight3D.new()
	light.name = "Light"
	light.light_color = color
	light.omni_range = 2.5
	light.light_energy = 0.8
	light.position.y = 0.5
	add_child(light)
	label = Label3D.new()
	label.name = "Label"
	label.text = d.describe()
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.004
	label.position.y = GEM_SIZE + 0.35
	add_child(label)

func beam_height() -> float:
	var t := Rarity.parse(drop.rarity_id) if drop else 0
	return BEAM_BASE + BEAM_PER_TIER * maxi(t, 0)
