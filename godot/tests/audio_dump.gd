# ============================================================================
# audio_dump.gd — выгрузка синтезированного звука в WAV.
#
# Слушать звук из кода нельзя, поэтому проверка такая: собрать все буферы,
# записать их на диск и заодно напечатать пик каждого. Пик близко к 1.0 —
# звук на пределе, около нуля — тишина, и то и другое означает ошибку
# в синтезе.
# ============================================================================
extends Node

func _ready() -> void:
	await get_tree().process_frame
	var dir := "user://audio"
	DirAccess.make_dir_recursive_absolute(dir)
	print("папка: ", ProjectSettings.globalize_path(dir))

	# Ждём фоновую сборку обеих тем.
	var guard := 0
	while (Mus._menu == null or Mus._combat == null) and guard < 1800:
		guard += 1
		await get_tree().process_frame
	# Тема может быть и синтезированной (AudioStreamWAV), и собранной из
	# файлов (AudioStreamMP3 либо плейлист). Жёсткий тип здесь ронял тест
	# с «Trying to assign value of type AudioStreamMP3»: музыка стала
	# файловой, а выгрузка про это не знала.
	for pair in [["menu", Mus._menu], ["combat", Mus._combat]]:
		var loop: AudioStream = pair[1]
		if loop == null:
			print("ОШИБКА: тема «%s» не собралась" % pair[0])
			continue
		var wav := loop as AudioStreamWAV
		if wav == null:
			print("музыка «%s»: %s из файлов, %.1f с — выгружать нечего"
				% [pair[0], loop.get_class(), loop.get_length()])
			continue
		var samples: int = wav.data.size() / 2
		print("музыка «%s»: %.1f с, %d КБ" % [pair[0],
			float(samples) / float(Synth.RATE), wav.data.size() / 1024])
		wav.save_to_wav(dir + "/music_%s.wav" % pair[0])

	# Звуки собираются в фоновом потоке. Ждать их обязательно: раньше тест
	# успевал случайно — музыка синтезировалась дольше и держала паузу.
	# Как только музыка стала файловой, тест начал падать на первом же звуке.
	guard = 0
	while not Sfx._streams.has("shoot") and guard < 1800:
		guard += 1
		await get_tree().process_frame
	if not Sfx._streams.has("shoot"):
		print("ОШИБКА: звуки не собрались")
		get_tree().quit(1)
		return

	for type in ["shoot", "shoot_heavy", "explosion", "hit", "clang",
			"crumble", "crack", "airstrike", "water", "pickup", "levelup"]:
		var variants: Array = Sfx._streams[type]
		var st: AudioStreamWAV = variants[0]
		print("  %-13s вариантов %d, %.2f с, пик %.2f" % [
			type, variants.size(),
			float(st.data.size() / 2) / float(Synth.RATE), _peak(st)])
		st.save_to_wav(dir + "/sfx_%s.wav" % type)

	print("готово")
	get_tree().quit()

func _peak(st: AudioStreamWAV) -> float:
	var d := st.data
	var m := 0
	var i := 0
	while i < d.size() - 1:
		var v: int = d[i] | (d[i + 1] << 8)
		if v >= 32768:
			v -= 65536
		m = maxi(m, absi(v))
		i += 2
	return float(m) / 32767.0
