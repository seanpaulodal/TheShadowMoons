class_name DayNightRules
extends RefCounted
## The look of the sky through the 24 hours. Pure maths: give it an hour (0 to 24)
## and it answers with the sun, the ambient light, the sky colour, and how night
## it is. The DayNight node applies the answer to the world.

## Key moments. Everything between two of them is blended smoothly.
## night: 0 = full day, 1 = full night (the moons fade in with it).
const KEYS := [
	{"h": 0.0,  "sun": 0.0, "sun_color": "ffd9a8", "ambient": "26305a", "ambient_energy": 0.55, "sky": "070a1c", "fog": "0a0f26", "night": 1.0},
	{"h": 5.0,  "sun": 0.0, "sun_color": "ffd9a8", "ambient": "26305a", "ambient_energy": 0.55, "sky": "0a1030", "fog": "0e1634", "night": 1.0},
	{"h": 6.5,  "sun": 0.55, "sun_color": "ffb36b", "ambient": "7a5d6e", "ambient_energy": 0.75, "sky": "c4745a", "fog": "b8806a", "night": 0.35},
	{"h": 8.5,  "sun": 1.0, "sun_color": "fff1d6", "ambient": "8fa0c8", "ambient_energy": 0.9, "sky": "6fa8e0", "fog": "9cc2e8", "night": 0.0},
	{"h": 12.0, "sun": 1.15, "sun_color": "ffffff", "ambient": "9db4dc", "ambient_energy": 1.0, "sky": "7fb6f0", "fog": "a8cdf0", "night": 0.0},
	{"h": 16.5, "sun": 1.0, "sun_color": "fff0cf", "ambient": "8fa0c8", "ambient_energy": 0.9, "sky": "74aae2", "fog": "9cc2e8", "night": 0.0},
	{"h": 18.0, "sun": 0.6, "sun_color": "ff9a55", "ambient": "8a5f70", "ambient_energy": 0.75, "sky": "d0704c", "fog": "c07a5c", "night": 0.3},
	{"h": 19.5, "sun": 0.0, "sun_color": "ff8a50", "ambient": "3a3260", "ambient_energy": 0.6, "sky": "281c48", "fog": "30244e", "night": 0.85},
	{"h": 21.0, "sun": 0.0, "sun_color": "ffd9a8", "ambient": "26305a", "ambient_energy": 0.55, "sky": "070a1c", "fog": "0a0f26", "night": 1.0},
	{"h": 24.0, "sun": 0.0, "sun_color": "ffd9a8", "ambient": "26305a", "ambient_energy": 0.55, "sky": "070a1c", "fog": "0a0f26", "night": 1.0},
]


## Hour of day (0..24) from the real clock (local time), or a fixed hour from the map data.
static func hour_from_rules(rules: Dictionary, unix_time: float = -1.0) -> float:
	if str(rules.get("mode", "real_clock")) == "fixed":
		return clampf(float(rules.get("fixed_hour", 12.0)), 0.0, 23.999)
	var seconds: float
	if unix_time >= 0.0:
		seconds = fmod(unix_time + float(Time.get_time_zone_from_system().get("bias", 0)) * 60.0, 86400.0)
	else:
		var now := Time.get_time_dict_from_system(false)
		seconds = float(int(now["hour"]) * 3600 + int(now["minute"]) * 60 + int(now["second"]))
	var scale := maxf(0.0, float(rules.get("time_scale", 1.0)))
	if scale != 1.0:
		var running := float(Time.get_ticks_msec()) / 1000.0
		seconds = fmod(seconds + running * (scale - 1.0), 86400.0)
	return seconds / 3600.0


## The sky at an hour: {"sun_energy", "sun_color", "ambient_color", "ambient_energy",
## "sky_color", "fog_color", "night" (0..1), "sun_elevation" (degrees, negative = below the
## horizon), "sun_yaw" (degrees)}.
static func state_for_hour(hour: float) -> Dictionary:
	var h := fposmod(hour, 24.0)
	var lower: Dictionary = KEYS[0]
	var upper: Dictionary = KEYS[KEYS.size() - 1]
	for i in range(KEYS.size() - 1):
		if h >= float(KEYS[i]["h"]) and h <= float(KEYS[i + 1]["h"]):
			lower = KEYS[i]
			upper = KEYS[i + 1]
			break
	var span := float(upper["h"]) - float(lower["h"])
	var t := 0.0 if span <= 0.0 else (h - float(lower["h"])) / span
	t = t * t * (3.0 - 2.0 * t)      # smooth blend

	# The sun climbs from 6:00, is highest at 12:00 and sets at 18:00.
	var elevation := 75.0 * sin((h - 6.0) / 12.0 * PI)
	return {
		"sun_energy": lerpf(float(lower["sun"]), float(upper["sun"]), t),
		"sun_color": Color(str(lower["sun_color"])).lerp(Color(str(upper["sun_color"])), t),
		"ambient_color": Color(str(lower["ambient"])).lerp(Color(str(upper["ambient"])), t),
		"ambient_energy": lerpf(float(lower["ambient_energy"]), float(upper["ambient_energy"]), t),
		"sky_color": Color(str(lower["sky"])).lerp(Color(str(upper["sky"])), t),
		"fog_color": Color(str(lower["fog"])).lerp(Color(str(upper["fog"])), t),
		"night": lerpf(float(lower["night"]), float(upper["night"]), t),
		"sun_elevation": elevation,
		"sun_yaw": (h - 12.0) * 15.0,
	}


## "14:05".
@warning_ignore("integer_division")
static func format_hour(hour: float) -> String:
	var minutes_total := int(floor(fposmod(hour, 24.0) * 60.0 + 0.001))    # the 0.001 absorbs float error (14.6 h)
	return "%02d:%02d" % [minutes_total / 60, minutes_total % 60]


## A short word for the time of day, for the HUD.
static func period_name(hour: float) -> String:
	var h := fposmod(hour, 24.0)
	if h < 5.0 or h >= 20.0:
		return "Night"
	if h < 8.0:
		return "Dawn"
	if h < 17.0:
		return "Day"
	return "Dusk"
