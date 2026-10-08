extends SceneTree

func _init() -> void:
	print("=== STARTING FULL COMPILATION INTEGRITY CHECK ===")
	var scripts_to_check := [
		"res://scripts/config.gd",
		"res://scripts/i18n.gd",
		"res://scripts/profile.gd",
		"res://scripts/audio.gd",
		"res://scripts/music.gd",
		"res://scripts/settings.gd",
		"res://scripts/fonts.gd",
		"res://scripts/net/net.gd",
		"res://scripts/steam_stats.gd",
		"res://scripts/weekly.gd",
		"res://scripts/daily.gd",
		"res://scripts/entities.gd",
		"res://scripts/tank.gd",
		"res://scripts/world.gd",
		"res://scripts/world_view.gd",
		"res://scripts/tile_cache.gd",
		"res://scripts/tile_bake_view.gd",
		"res://scripts/ui/ui_kit.gd",
		"res://scripts/ui/themed_panel.gd",
		"res://scripts/ui/menu_scene.gd",
		"res://scripts/ui/menu_tank_view.gd",
		"res://scripts/ui/main_menu.gd",
		"res://scripts/ui/splash.gd",
		"res://scripts/ui/hud.gd",
		"res://scripts/ui/ui_root.gd",
		"res://scripts/game.gd",
	]

	var failed := 0
	for path in scripts_to_check:
		var res = load(path)
		if res == null:
			print("ОШИБКА: Не удалось загрузить/скомпилировать: " + path)
			failed += 1
		else:
			print("OK: " + path)

	print("=== COMPILATION CHECK COMPLETED with failures: %d ===" % failed)
	if failed == 0:
		print("ВСЕ СКРИПТЫ УСПЕШНО СКОМПИЛИРОВАНЫ!")
		quit(0)
	else:
		quit(1)
