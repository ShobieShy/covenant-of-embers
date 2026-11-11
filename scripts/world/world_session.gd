class_name WorldSession
extends RefCounted
## OW10: how a run sits in the seamless world. Where it starts (plan section 9: a played
## intro opens in the Mage Association interior and its front door drops you at the Town
## Square; a skipped intro starts at the Old Oak; a save resumes at progress.world_pos after
## SaveMigration), and what main.gd adds to progress (world_pos, region, fog, interior).


## {"pos": Vector3 (or INF when indoors), "interior": String ("" outdoors)}.
static func start_spot(data: Dictionary, intro_mode: String) -> Dictionary:
	if data.is_empty():  # a fresh run
		if intro_mode == GameFlow.INTRO_SKIP:
			return {"pos": SaveMigration.entrance("old_oak"), "interior": ""}
		return {"pos": Vector3.INF, "interior": "mage_association"}
	SaveMigration.migrate(data)
	var pr: Dictionary = data.get("progress", {})
	var inside := String(pr.get("interior", ""))
	var f := StoryFlags.new()
	f.from_dict(pr.get("flags", {}))
	if IntroDirector.active(f):
		var lvl := String(IntroDirector.LEVEL.get(IntroDirector.beat(f), ""))
		var saved_level := String(pr.get("level_id", ""))
		if Interiors.LINKS.has(lvl):
			inside = lvl  # the beat itself is indoors
		elif Interiors.LINKS.has(saved_level):
			inside = saved_level  # a save still standing in the Association hall
	if Interiors.LINKS.has(inside):
		return {"pos": Vector3.INF, "interior": inside}
	var wp: Array = pr.get("world_pos", [])
	var pos := (
		Vector3(float(wp[0]), float(wp[1]), float(wp[2]))
		if wp.size() == 3
		else SaveMigration.entrance(SaveMigration.FALLBACK_LEVEL)
	)
	return {"pos": pos, "interior": ""}


## The level whose entrance is nearest `p` (outdoors).
static func nearest_level(p: Vector3) -> String:
	var best := SaveMigration.FALLBACK_LEVEL
	var bd := INF
	for l in WorldMap.LEVEL_REGION:
		var d := Vector2(p.x, p.z).distance_to(Vector2(SaveMigration.entrance(l).x, SaveMigration.entrance(l).z))
		if d < bd:
			bd = d
			best = l
	return best
