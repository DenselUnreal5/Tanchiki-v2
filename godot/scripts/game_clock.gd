class_name GameClock
extends RefCounted

const DAY := 86400
const WEEK_SCHEME := 2
const WEEK_DAYS := 7
const MONDAY_SHIFT := 3
const STEAM_RECHECK_MSEC := 30000

static var _steam_checked_msec := -STEAM_RECHECK_MSEC
static var _steam_ok := false
static var test_offset := 0

static func _steam_time() -> int:
	var now_msec := Time.get_ticks_msec()
	if now_msec - _steam_checked_msec >= STEAM_RECHECK_MSEC:
		_steam_checked_msec = now_msec
		_steam_ok = Engine.has_singleton("Steam") and SteamStats.ready()
	if not _steam_ok:
		return 0
	var steam: Object = Engine.get_singleton("Steam")
	if not steam.has_method("getServerRealTime"):
		return 0
	return int(steam.getServerRealTime())

static func now() -> int:
	var t := _steam_time()
	if t <= 0:
		t = int(Time.get_unix_time_from_system())
	return t + test_offset

static func local_now() -> int:
	var zone: Dictionary = Time.get_time_zone_from_system()
	return now() + int(zone.get("bias", 0)) * 60

static func local_day(unix_local: int = -1) -> int:
	var t := local_now() if unix_local < 0 else unix_local
	return int(floor(float(t) / float(DAY)))

static func date_key(unix_local: int = -1) -> String:
	var t := local_now() if unix_local < 0 else unix_local
	var d := Time.get_datetime_dict_from_unix_time(t)
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

static func week_index(unix_local: int = -1) -> int:
	return int(floor(float(local_day(unix_local) + MONDAY_SHIFT) / float(WEEK_DAYS)))

static func week_key(unix_local: int = -1) -> String:
	var w := week_index(unix_local)
	var thursday_unix := w * WEEK_DAYS * DAY
	var year: int = int(Time.get_datetime_dict_from_unix_time(thursday_unix)["year"])
	var jan1 := int(Time.get_unix_time_from_datetime_dict({
		"year": year, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0}))
	var iso_week := int(floor(float(thursday_unix - jan1) / float(DAY * WEEK_DAYS))) + 1
	return "%04d-W%02d" % [year, iso_week]

static func seconds_until_next_week() -> int:
	var t := local_now()
	var next_start_day := (week_index(t) + 1) * WEEK_DAYS - MONDAY_SHIFT
	return maxi(1, next_start_day * DAY - t)
