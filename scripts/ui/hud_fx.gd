class_name HudFx
extends RefCounted
## 0.3.1 P4 (M3) HUD bar feel, kept pure so tests check it headless:
##  * Chip: a bar's shown fill and its trailing "damage chip". A drop snaps the fill down at
##    once and leaves the chip where it was for CHIP_HOLD s, then the chip drains at
##    CHIP_RATE per second. A rise (heal, regen) eases the fill up (FILL_RATE) and the chip
##    rides along with it.
##  * heartbeat(): the low-health vignette alpha, nothing above LOW_HEALTH, faster and
##    stronger as health falls; steady (no pulse) under reduced motion.

const CHIP_HOLD := 0.45  ## s the chip waits after a hit
const CHIP_RATE := 0.8  ## fraction of the bar per s the chip drains
const FILL_RATE := 10.0  ## 1/s exponential ease for rises
const LOW_HEALTH := 0.3  ## fraction where the heartbeat starts
const BEAT_HZ_SLOW := 1.1  ## beats/s at LOW_HEALTH
const BEAT_HZ_FAST := 2.2  ## beats/s near 0
const VIGNETTE_MAX := 0.5  ## edge alpha at the bottom of the range, peak of a beat


class Chip:
	extends RefCounted
	var shown := 1.0
	var chip := 1.0
	var hold := 0.0
	var started := false

	## Advance toward `target` (0..1) by `dt` s.
	func step(target: float, dt: float) -> void:
		target = clampf(target, 0.0, 1.0)
		if not started:
			shown = target
			chip = target
			started = true
			return
		if target < shown - 1e-6:
			shown = target
			hold = CHIP_HOLD
		elif dt <= 0.0:
			shown = target
		else:
			shown = HudFx.smooth(shown, target, dt)
		if chip <= shown:
			chip = shown
			hold = 0.0
		elif dt > 0.0:
			if hold > 0.0:
				hold = maxf(0.0, hold - dt)
			else:
				chip = maxf(shown, chip - CHIP_RATE * dt)


## Exponential ease of `shown` toward `target`; snaps within 0.001.
static func smooth(shown: float, target: float, dt: float) -> float:
	var v := target + (shown - target) * exp(-FILL_RATE * maxf(dt, 0.0))
	return target if absf(v - target) < 1e-3 else v


## Vignette alpha for a health fraction at time `t` s (0 when healthy or dead).
static func heartbeat(frac: float, t: float, reduced_motion := false) -> float:
	if frac >= LOW_HEALTH or frac <= 0.0:
		return 0.0
	var k := 1.0 - frac / LOW_HEALTH  # 0 at the threshold, 1 near empty
	var base := VIGNETTE_MAX * (0.35 + 0.65 * k)
	if reduced_motion:
		return base * 0.7
	var hz := lerpf(BEAT_HZ_SLOW, BEAT_HZ_FAST, k)
	var ph := fposmod(t * hz, 1.0)
	# lub-dub: a strong beat then a softer one, quiet in between
	var beat := maxf(exp(-pow((ph - 0.08) / 0.06, 2.0)), 0.6 * exp(-pow((ph - 0.3) / 0.06, 2.0)))
	return base * (0.45 + 0.55 * beat)
