class_name ZoneChests
extends RefCounted
## Step 158 (TERRAIN_MAPS_PLAN sections 6 and 10): the open-zone chests. TOML [[chest]] ->
## Level/Chests/<name> markers (meta tier, requires_flag); main spawns a VaultChest at each.
## Ids are namespaced <level>:<name>; opening sets the story flag "chest:<level>:<name>",
## so a looted chest stays open across saves. Tiers set the rarity floor; a vault-tier
## chest stays locked until its requires_flag (a lever puzzle, a boss) is set.

const FLOOR := {"normal": "basic", "hidden": "uncommon", "vault": "rare"}
const PREFIX := "chest:"


static func chest_id(level: String, name: String) -> String:
	return "%s:%s" % [level, name]


static func setup(
	holder: Node, level: Node3D, here: String, player: Player, flags: StoryFlags, dropper: LootDropper
) -> Array[VaultChest]:
	var out: Array[VaultChest] = []
	var marks := level.get_node_or_null(^"Chests") if level else null
	if marks == null:
		return out
	for m in marks.get_children():
		var tier := String(m.get_meta(&"tier", "normal"))
		var c := VaultChest.new()
		c.name = "Chest_" + String(m.name)
		c.player = player
		c.dropper = dropper
		c.floor_rarity = String(FLOOR.get(tier, "basic"))
		c.set_meta(&"chest_id", chest_id(here, String(m.name)))
		c.set_meta(&"tier", tier)
		holder.add_child(c)
		c.global_transform = (m as Node3D).global_transform
		var need := String(m.get_meta(&"requires_flag", ""))
		var id := PREFIX + chest_id(here, String(m.name))
		if flags and flags.has(id):
			c.locked = false
			c.open_chest_quiet()
		else:
			c.locked = not need.is_empty() and not (flags and flags.has(need))
			if c.locked and flags:
				flags.changed.connect(
					func(f: String, _v: int) -> void:
						if f == need and is_instance_valid(c):
							c.unlock()
				)
			if flags:
				c.opened.connect(func(_d: Array[LootDrop]) -> void: flags.set_flag(id))
		out.append(c)
	return out
