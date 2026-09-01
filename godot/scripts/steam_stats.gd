# ============================================================================
# steam_stats.gd — достижения, статистика и таблица рекордов в Steam.
#
# Прогресс игры остаётся своим: profile.json — источник правды, и игра
# полностью работает без Steam. Этот слой только ОТРАЖАЕТ его наружу, чтобы
# достижения были видны в профиле Steam, а рекорд попадал в общую таблицу.
#
# Отражение односторонее и это осознанно. Тянуть достижения обратно из Steam
# значило бы, что удалённый профиль можно восстановить чужой машиной, а монеты
# за достижения начислить дважды. Steam здесь витрина, а не хранилище.
#
# Всё молча ничего не делает, когда Steam недоступен: сборка без расширения
# и запуск без клиента — обычные случаи, а не ошибка.
#
# ВАЖНО про App ID. С тестовым 480 (Spacewar) вызовы проходят, но имена наших
# достижений в нём не заведены, и Steam их не примет. Заработает это только
# на своём App ID, где достижения объявлены в Steamworks с теми же именами,
# что выдаёт api_name().
# ============================================================================
class_name SteamStats
extends RefCounted

## Ключи статистики профиля, которые имеет смысл отдавать в Steam.
## Именно по ним в Steamworks удобно строить достижения на стороне Valve.
const STAT_KEYS := [
	"totalKills", "gamesPlayed", "gamesWon", "bricksDestroyed",
	"ramKills", "longKills", "lowHpKills", "healthPacksCollected",
]

## Имя таблицы рекордов. Создаётся в Steamworks; findOrCreateLeaderboard
## заводит её на лету только для App ID, где это разрешено.
const LEADERBOARD := "HighScore"

static var _warned := false

## Имя достижения в Steamworks. Соглашение простое и обратимое: наш ключ
## в верхнем регистре с префиксом. То же имя заводится в Steamworks.
static func api_name(id: String) -> String:
	return "ACH_" + id.to_upper()

## Steam доступен и инициализирован?
static func ready() -> bool:
	if not Engine.has_singleton("Steam"):
		return false
	return NetTransport.SteamTransport.boot()

static func _steam() -> Object:
	return Engine.get_singleton("Steam")

# ------------------------------------------------------------- достижения
## Отмечает одно достижение. Возвращает true, если Steam его принял.
##
## Steam хранит достижения сам и повторную выдачу игнорирует, поэтому
## проверять «а не выдано ли уже» здесь незачем.
static func unlock(id: String) -> bool:
	if not ready():
		return false
	var steam: Object = _steam()
	var name := api_name(id)
	var ok: bool = steam.setAchievement(name)
	if not ok and not _warned:
		_warned = true
		# Один раз на запуск: на тестовом App ID это ожидаемо и засыпать
		# консоль одинаковыми строками ни к чему.
		print("[Steam] достижение «%s» не принято — не заведено в Steamworks" % name)
	steam.storeStats()
	return ok

## Отправляет все уже открытые достижения. Нужно на запуске: игрок мог
## открыть их без Steam, и в профиле они обязаны появиться задним числом.
static func push_all(unlocked: Array) -> int:
	if not ready():
		return 0
	var sent := 0
	for id in unlocked:
		if _steam().setAchievement(api_name(String(id))):
			sent += 1
	_steam().storeStats()
	return sent

# ------------------------------------------------------------- статистика
## Отдаёт числовые показатели профиля. Steam умеет строить по ним свои
## достижения, и тогда их не приходится дублировать в игре.
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

# ---------------------------------------------------------- таблица рекордов
## Кладёт счёт в таблицу. Steam сам оставит лучший результат игрока.
##
## Поиск таблицы асинхронный: ответ приходит колбэком, поэтому загрузка идёт
## следом за ним, а не сразу. Здесь только запуск поиска.
static func push_score(score: int) -> bool:
	if not ready() or score <= 0:
		return false
	_steam().findLeaderboard(LEADERBOARD)
	_pending_score = score
	return true

static var _pending_score := 0

## Вызывается из обработчика сигнала leaderboard_find_result.
static func on_leaderboard_found(found: bool) -> void:
	if not found or _pending_score <= 0 or not ready():
		return
	# Метод оставляет лучший результат: отправка худшего ничего не портит.
	_steam().uploadLeaderboardScore(_pending_score, true)
	_pending_score = 0
