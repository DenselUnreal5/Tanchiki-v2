class_name SteamStats
extends RefCounted

const STAT_KEYS := [
	"totalKills", "gamesPlayed", "gamesWon", "bricksDestroyed",
	"ramKills", "longKills", "lowHpKills", "healthPacksCollected",
]

const LEADERBOARDS := {
	"ffa": "HighScore_FFA",
	"ctf": "HighScore_CTF",
	"koth": "HighScore_KOTH",
	"defense": "HighScore_Defense",
}

static var _warned := false

static func api_name(id: String) -> String:
	return "ACH_" + id.to_upper()

static func ready() -> bool:
	if not Engine.has_singleton("Steam"):
		return false
	return NetTransport.SteamTransport.boot()

static func _steam() -> Object:
	return Engine.get_singleton("Steam")

static func unlock(id: String) -> bool:
	if not ready():
		return false
	var steam: Object = _steam()
	var name := api_name(id)
	var ok: bool = steam.setAchievement(name)
	if not ok and not _warned:
		_warned = true
		print("[Steam] достижение «%s» не принято — не заведено в Steamworks" % name)
	steam.storeStats()
	return ok

static func push_all(unlocked: Array) -> int:
	if not ready():
		return 0
	var sent := 0
	for id in unlocked:
		if _steam().setAchievement(api_name(String(id))):
			sent += 1
	_steam().storeStats()
	return sent

static func push_stats(stats: Dictionary) -> int:
	if not ready():
		return 0
	var sent := 0
	for key in STAT_KEYS:
		if not stats.has(key):
			continue
		if _steam().setStatInt(key, int(stats[key])):
			sent += 1
	_steam().storeStats()
	return sent

static func push_score(score: int, mode: String) -> bool:
	if not ready() or score <= 0:
		return false
	_steam().findLeaderboard(String(LEADERBOARDS.get(mode, "HighScore")))
	_pending_score = score
	return true

static var _pending_score := 0

static func on_leaderboard_found(found: bool) -> void:
	if not found or _pending_score <= 0 or not ready():
		return
	_steam().uploadLeaderboardScore(_pending_score, true)
	_pending_score = 0
