class_name Accessibility
extends RefCounted
## Accessibility state (BUILD_PLAN step 76), set by Settings.apply_to:
##  * colour-blind palettes: RarityTable.color / ElementTable.color return these instead of
##    the data colours (Okabe-Ito based; red/green-safe for deuteranopia + protanopia, a
##    blue/yellow-safe set for tritanopia), so loot beams, cards, HUD and bolts all follow;
##  * subtitles: dialogue lines are shown (off hides the line text - for voice-over later);
##  * subtitle_scale: dialogue text size.
## Reduced motion and hold/toggle (focus, crouch) live on Settings/Player already.

enum Mode { OFF, DEUTERANOPIA, PROTANOPIA, TRITANOPIA }

const MODE_NAMES: PackedStringArray = ["Off", "Deuteranopia", "Protanopia", "Tritanopia"]
const BASE_FONT := 32  # Kenney Pixel 16 px at the theme's x2 scale (t60u)
## Rarity order = Rarity.IDS (basic, uncommon, rare, mythic, primordial, unique).
const RARITY_RG := [
	Color(0.9, 0.9, 0.9),
	Color(0.0, 0.62, 0.45),
	Color(0.0, 0.45, 0.7),
	Color(0.8, 0.47, 0.65),
	Color(0.9, 0.62, 0.0),
	Color(0.94, 0.89, 0.26)
]
const RARITY_T := [
	Color(0.9, 0.9, 0.9),
	Color(0.0, 0.62, 0.45),
	Color(0.84, 0.37, 0.0),
	Color(0.8, 0.47, 0.65),
	Color(0.95, 0.2, 0.2),
	Color(0.35, 0.7, 0.9)
]
## Element order = ElementTable.Element (arcane, fire, water, earth, air, light, dark).
const ELEMENT_RG := [
	Color(0.8, 0.47, 0.65),
	Color(0.9, 0.62, 0.0),
	Color(0.0, 0.45, 0.7),
	Color(0.55, 0.4, 0.2),
	Color(0.34, 0.71, 0.91),
	Color(0.94, 0.89, 0.26),
	Color(0.3, 0.3, 0.3)
]
const ELEMENT_T := [
	Color(0.8, 0.47, 0.65),
	Color(0.84, 0.37, 0.0),
	Color(0.0, 0.62, 0.45),
	Color(0.55, 0.4, 0.2),
	Color(0.6, 0.8, 0.8),
	Color(0.95, 0.95, 0.95),
	Color(0.3, 0.3, 0.3)
]

static var colorblind := Mode.OFF
static var subtitles := true
static var subtitle_scale := 1.0


static func reset() -> void:
	colorblind = Mode.OFF
	subtitles = true
	subtitle_scale = 1.0


static func rarity_color(rarity_id: String, base: Color) -> Color:
	var i := Rarity.IDS.find(rarity_id)
	if colorblind == Mode.OFF or i < 0:
		return base
	return (RARITY_T if colorblind == Mode.TRITANOPIA else RARITY_RG)[i]


static func element_color(e: int, base: Color) -> Color:
	if colorblind == Mode.OFF or e < 0 or e >= ELEMENT_RG.size():
		return base
	return (ELEMENT_T if colorblind == Mode.TRITANOPIA else ELEMENT_RG)[e]


static func font_size() -> int:
	return roundi(BASE_FONT * subtitle_scale)
