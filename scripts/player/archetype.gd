class_name Archetype
extends RefCounted
## Playable archetypes (BUILD_PLAN step 73, Q6: the Magewar Bible's Nerd / Gal / Buff /
## Loli) plus customization (name and colour for now). Each archetype is a look and one
## small perk, merged into Player.apply_bonuses() like skill ranks:
##   Nerd  +15 max mana        (the studious one)
##   Gal   -10% vendor prices  (the talker)
##   Buff  +20 max health      (the hauler)
##   Loli  +8% move speed      (the quick scout)
## The pick, name and colour live in the character save ("player" -> archetype / name /
## color), so they travel with the portable co-op character (CharacterSave), and the
## colour/name show on the other players' screens (RemotePlayer, pose keys "n" / "c").

const IDS: PackedStringArray = ["nerd", "gal", "buff", "loli"]
const DEFAULT := ""  ## no archetype yet (old saves, tests): no perk
const NAME_MAX := 20
const DATA := {
	"nerd": {"label": "Nerd", "blurb": "+15 max mana", "perks": {"max_mana": 15.0}, "color": Color(0.35, 0.6, 1.0)},
	"gal":
	{"label": "Gal", "blurb": "-10% vendor prices", "perks": {"discount_pct": 10.0}, "color": Color(1.0, 0.45, 0.7)},
	"buff": {"label": "Buff", "blurb": "+20 max health", "perks": {"max_health": 20.0}, "color": Color(0.9, 0.55, 0.2)},
	"loli": {"label": "Loli", "blurb": "+8% move speed", "perks": {"speed_pct": 8.0}, "color": Color(0.6, 1.0, 0.5)},
}


static func valid(id: String) -> String:
	return id if DATA.has(id) else DEFAULT


static func label(id: String) -> String:
	return String(DATA[id]["label"]) if DATA.has(id) else "Wanderer"


static func blurb(id: String) -> String:
	return String(DATA[id]["blurb"]) if DATA.has(id) else ""


static func perks(id: String) -> Dictionary:
	return DATA[id]["perks"] if DATA.has(id) else {}


static func default_color(id: String) -> Color:
	return DATA[id]["color"] if DATA.has(id) else Color(0.35, 0.6, 1.0)


## Trimmed, printable, at most NAME_MAX characters; "" falls back to `fallback`.
static func clean_name(n: String, fallback := "Ember") -> String:
	var out := ""
	for ch in n.strip_edges():
		if ch.unicode_at(0) >= 32:
			out += ch
	out = out.left(NAME_MAX).strip_edges()
	return out if not out.is_empty() else fallback


## Vendor price after the archetype's discount (at least 1).
static func discounted(price: int, id: String) -> int:
	var pct := float(perks(id).get("discount_pct", 0.0))
	return maxi(1, int(round(price * (1.0 - pct / 100.0)))) if pct > 0.0 else price
