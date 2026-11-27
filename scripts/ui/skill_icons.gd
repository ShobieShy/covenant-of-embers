class_name SkillIcons
extends RefCounted
## Element medallions for the skill tree and the carry slots.
## ids: arcane, fire, water, earth, air, light, dark, and ember for the core tree.

const DIR := "res://assets/original/ui_scribe/icons/"


static func texture(id: String) -> Texture2D:
	var path := DIR + id + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
