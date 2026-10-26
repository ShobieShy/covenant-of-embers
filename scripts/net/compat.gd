class_name Compat
extends RefCounted
## Windows <-> Linux co-op compatibility (BUILD_PLAN step 90). Both OSes must agree on:
##  - save/character bytes: canonical JSON (sorted keys, tab indent, LF only, trailing LF,
##    no OS paths or locale formatting), so a character file copied between OSes is
##    byte-identical and hashes the same;
##  - the build version (NetSession.version());
##  - the data fingerprint: a hash of item codes and loot rolls from fixed seeds, so two
##    builds with different item tables / rng behaviour refuse to play together instead
##    of desyncing. NetSession sends it in the hello and the host checks it.

static var fingerprint_override := ""  ## tests: pretend to be a different build
static var _cached := ""
static var terrain_override := ""  ## tests: pretend to have different maps
static var _terrain_cached := ""
## Terrain properties that decide heights, splat and navmesh (TerrainZone exports).
const TERRAIN_PROPS: PackedStringArray = [
	"size", "center", "height", "noise_seed", "spacing", "rim", "map_version", "layers", "pads", "pad_y", "blend"
]


static func canonical(data: Variant) -> String:
	var s := JSON.stringify(data, "\t", true, false).replace("\r\n", "\n").replace("\r", "\n")
	return s if s.ends_with("\n") else s + "\n"


static func sha(text: String) -> String:
	return text.sha256_text()


## Item codes + drops from fixed seeds: same tables and rng on every OS = same hash.
static func samples() -> PackedStringArray:
	var out := PackedStringArray()
	for i in 4:
		out.append(ItemCodes.encode(PartRoller.from_seed(16 + i, i % 5 as WieldablePart.PartType, "rare")))
	out.append(
		ItemCodes.encode(EquipmentRoller.from_seed(3, EquipmentItem.Slot.BELT, "mythic", ElementTable.Element.WATER))
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = 18
	for d in DropRoller.roll_enemy(rng, EnemyTable.load_default().find("heap")):
		out.append(d.describe())
	return out


## Step 155: every level's terrain settings + TerrainZone.GEN_VERSION. Heights, splat and
## navmesh tiles are pure functions of these, so equal hashes = equal maps.
static func terrain_rows() -> PackedStringArray:
	var out := PackedStringArray(["gen %d" % TerrainZone.GEN_VERSION])
	var ids: Array = GameFlow.LEVELS.keys()
	ids.sort()
	for id in ids:
		var ps := load(String(GameFlow.LEVELS[id])) as PackedScene
		var st := ps.get_state() if ps else null
		if st == null:
			out.append("%s missing" % id)
			continue
		for i in st.get_node_count():
			if String(st.get_node_path(i)) != "./Terrain":
				continue
			var props := {}
			for j in st.get_node_property_count(i):
				if TERRAIN_PROPS.has(String(st.get_node_property_name(i, j))):
					props[String(st.get_node_property_name(i, j))] = st.get_node_property_value(i, j)
			out.append("%s %s" % [id, canonical(var_to_str(props))])
	return out


static func terrain_fingerprint() -> String:
	if not terrain_override.is_empty():
		return terrain_override
	if _terrain_cached.is_empty():
		_terrain_cached = sha("\n".join(terrain_rows())).left(16)
	return _terrain_cached


static func fingerprint() -> String:
	if not fingerprint_override.is_empty():
		return fingerprint_override
	if _cached.is_empty():
		_cached = sha("\n".join(samples())).left(16)
	return _cached
