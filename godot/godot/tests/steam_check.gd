# ============================================================================
# steam_check.gd — что именно даёт установленное расширение GodotSteam.
#
# Проверяется не «стоит ли аддон», а ровно то, что нужно игре: есть ли класс
# MultiplayerPeer поверх Steam. Без него высокоуровневый мультиплеер Godot
# на Steam не переведёшь, сколько бы Steamworks-функций ни было доступно.
# ============================================================================
extends Node

func _ready() -> void:
	print("Godot: ", Engine.get_version_info()["string"])
	var names := [
		"Steam", "SteamMultiplayerPeer", "SteamPeer",
		"SteamMultiplayerPeerExtension", "MultiplayerPeerExtension",
	]
	for n in names:
		print("  %-32s ClassDB:%s  singleton:%s"
			% [n, ClassDB.class_exists(n), Engine.has_singleton(n)])

	if Engine.has_singleton("Steam"):
		var steam := Engine.get_singleton("Steam")
		var methods := []
		for m in steam.get_method_list():
			var mn := String(m["name"])
			if mn.begins_with("createLobby") or mn.begins_with("joinLobby") \
					or mn.begins_with("sendP2P") or mn.begins_with("readP2P") \
					or mn.begins_with("steamInit") or mn.begins_with("getSteamID"):
				methods.append(mn)
		methods.sort()
		print("  методы лобби и P2P: ", methods)
		var extra := []
		for m in steam.get_method_list():
			var mn := String(m["name"])
			if mn in ["run_callbacks", "steamShutdown", "isSteamRunning", "getPersonaName",
					"setAchievement", "getAchievement", "clearAchievement", "storeStats",
					"requestCurrentStats", "findLeaderboard", "uploadLeaderboardScore",
					"findOrCreateLeaderboard", "setStatInt", "getStatInt",
					"fileWrite", "fileRead", "isCloudEnabledForApp"]:
				extra.append(mn)
		extra.sort()
		print("  служебные: ", extra)
	if ClassDB.class_exists("SteamMultiplayerPeer"):
		print("  методы SteamMultiplayerPeer:")
		for m in ClassDB.class_get_method_list("SteamMultiplayerPeer", true):
			var args := []
			for a in m["args"]:
				args.append("%s: %s" % [a["name"], type_string(a["type"])])
			print("    %s(%s) -> %s" % [m["name"], ", ".join(args),
				type_string(m["return"]["type"])])

	# Инициализация Steam: без запущенного клиента она честно не пройдёт,
	# и это тоже надо увидеть, а не гадать.
	if Engine.has_singleton("Steam"):
		var steam := Engine.get_singleton("Steam")
		var res = steam.steamInitEx(480, true)
		print("  steamInitEx(480): ", res)
		print("  steamID: ", steam.getSteamID())

	get_tree().quit(0)
