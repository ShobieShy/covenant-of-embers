class_name ZoneChests
extends RefCounted
## Step 158 (TERRAIN_MAPS_PLAN sections 6 and 10): the open-zone chests. TOML [[chest]] ->
## Level/Chests/<name> markers (meta tier, requires_flag); main spawns a VaultChest at each.
## Ids are namespaced <level>:<name>; opening sets the story flag "chest:<level>:<name>",
## so a looted chest stays open across saves. Tiers set the rarity floor; a vault-tier
## chest stays locked until its requires_flag (a lever puzzle, a boss) is set.

const FLOOR := {"normal": "basic", "hidden": "uncommon", "vault": "rare"}
const PREFIX := "chest:"
## Step 161: zone lever puzzles. An anchor named lever_<group>_<n> spawns an armed
## BreachSwitch; pulling it sets "lever:<level>:<anchor>", and once every lever of the group
## is pulled the flag "levers_<group>" is set (a vault chest's requires_flag).
const LEVER := "lever_"


static func lever_group(anchor: String) -> String:
	var s := anchor.trim_prefix(LEVER)
	var i := s.rfind("_")
	return s.substr(0, i) if i > 0 else s


static func setup_levers(
	holder: Node, level: Node3D, here: String, player: Player, flags: StoryFlags
) -> Array[BreachSwitch]:
	var out: Array[BreachSwitch] = []
	var h := level.get_node_or_null(^"Anchors") if level else null
	if h == null:
		return out
	var groups := {}
	for m in h.get_children():
		var an := String(m.name)
		if not an.begins_with(LEVER):
			continue
		var g := lever_group(an)
		var sw := BreachSwitch.new()
		sw.name = "Lever_" + an.trim_prefix(LEVER)
		sw.player = player
		sw.armed = true
		sw.opens = "levers_" + g
		holder.add_child(sw)
		sw.global_transform = (m as Node3D).global_transform
		var id := "lever:%s:%s" % [here, an]
		sw.set_meta(&"flag", id)
		if flags and flags.has(id):
			sw.is_pressed = true
			sw._refresh()
		if not groups.has(g):
			groups[g] = []
		(groups[g] as Array).append(sw)
		out.append(sw)
	for g in groups:
		var sws: Array = groups[g]
		for sw in sws:
			(sw as BreachSwitch).pressed.connect(
				func(s: BreachSwitch) -> void:
					if flags == null:
						return
					flags.set_flag(String(s.get_meta(&"flag")))
					if sws.all(func(x: BreachSwitch) -> bool: return x.is_pressed):
						flags.set_flag("levers_" + String(g))
			)
	return out


static func chest_id(level: String, name: String) -> String:
	return "%s:%s" % [level, name]


static func setup(
	holder: Node, level: Node3D, here: String, player: Player, flags: StoryFlags, dropper: LootDropper
) -> Array[VaultChest]:
	var out: Array[VaultChest] = []
	var marks := level.get_node_or_null(^"Chests") if level else null
	if marks == null:
		return out
	setup_levers(holder, level, here, player, flags)
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
