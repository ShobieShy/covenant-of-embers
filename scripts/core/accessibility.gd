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

const RARITY_MARKS: PackedStringArray = ["●", "▲", "■", "◆", "★", "✶"]
const ELEMENT_MARKS: PackedStringArray = ["✦", "▲", "●", "■", "◇", "☆", "▼"]
const NAMED_MARK := "✶"
const SUBTITLE_PRESETS: PackedFloat64Array = [0.85, 1.0, 1.35, 1.75]
const PRESET_NAMES: PackedStringArray = ["Small", "Medium", "Large", "Extra large"]
const CROSSHAIR_COLORS: Array[Color] = [
	Color(1, 1, 1, 0.9), Color(1, 0.92, 0.2, 0.95), Color(0.3, 0.95, 1, 0.95), Color(0.2, 1, 0.45, 0.95)
]

static var colorblind := Mode.OFF
static var subtitles := true
static var subtitle_scale := 1.0
static var subtitle_bg := 0.72
static var show_speaker := true
static var text_scale := 1.0
static var shake := 1.0
static var flash_reduction := false
static var crosshair_size := 1.0
static var crosshair_swatch := 0
static var high_contrast := false


static func reset() -> void:
	colorblind = Mode.OFF
	subtitles = true
	subtitle_scale = 1.0
	subtitle_bg = 0.72
	show_speaker = true
	text_scale = 1.0
	shake = 1.0
	flash_reduction = false
	crosshair_size = 1.0
	crosshair_swatch = 0
	high_contrast = false


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
	return roundi(BASE_FONT * subtitle_scale * text_scale)


static func rarity_mark(rarity_id: String) -> String:
	var i := Rarity.IDS.find(rarity_id)
	return RARITY_MARKS[i] if i >= 0 else ""


static func element_mark(e: int) -> String:
	return ELEMENT_MARKS[e] if e >= 0 and e < ELEMENT_MARKS.size() else ""


## Pearlescent when the filter is off. A palette slot when a colour-blind mode is on.
static func named_color(base: Color) -> Color:
	if colorblind == Mode.OFF:
		return base
	return (RARITY_T if colorblind == Mode.TRITANOPIA else RARITY_RG)[Rarity.Tier.UNIQUE]


static func crosshair_color() -> Color:
	return CROSSHAIR_COLORS[clampi(crosshair_swatch, 0, CROSSHAIR_COLORS.size() - 1)]


static func preset_scale(preset: int) -> float:
	return SUBTITLE_PRESETS[clampi(preset, 0, SUBTITLE_PRESETS.size() - 1)]


static func elite_mark(affix: String, rare: bool) -> String:
	if rare:
		return NAMED_MARK
	match affix:
		"burning":
			return "▲"
		"warded":
			return "■"
		"swift":
			return "»"
		"splitting":
			return "✕"
		_:
			return "●"
