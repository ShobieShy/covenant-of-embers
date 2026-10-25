class_name VersionInfo
extends RefCounted
## Release 0.1.1: one parser for application/config/version strings like "0.1.1-prealpha".
## Used by the main menu (release name), export (numeric PE version) and tests. The co-op
## gate (NetSession.version) still compares the full string, suffix included, on purpose.


static func current() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## {major, minor, patch, pre} - pre is the suffix after "-" ("" for a plain release).
static func parse(v: String) -> Dictionary:
	var dash := v.find("-")
	var core := v if dash < 0 else v.substr(0, dash)
	var pre := "" if dash < 0 else v.substr(dash + 1)
	var n := core.split(".")
	return {
		"major": int(n[0]) if n.size() > 0 else 0,
		"minor": int(n[1]) if n.size() > 1 else 0,
		"patch": int(n[2]) if n.size() > 2 else 0,
		"pre": pre,
	}


## "0.1.1-prealpha" -> "0.1.1.0" (Windows PE versions are numeric).
static func numeric(v: String) -> String:
	var p := parse(v)
	return "%d.%d.%d.0" % [p.major, p.minor, p.patch]


## "Pre-Alpha 0.1" for 0.1.0-prealpha, "Pre-Alpha 0.1.1" for 0.1.1-prealpha, else "v<version>".
static func release_name(v: String) -> String:
	var p := parse(v)
	if p.pre != "prealpha":
		return "v" + v
	var num := "%d.%d" % [p.major, p.minor]
	if p.patch != 0:
		num += ".%d" % p.patch
	return "Pre-Alpha " + num
