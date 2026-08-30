# ============================================================================
# net_protocol.gd — упаковка состояния мира в байты.
#
# Снапшот уходит по сети двадцать раз в секунду каждому клиенту, поэтому
# формат бинарный, а не JSON: словарь с сорока танками весит около шести
# килобайт, тот же снапшот в байтах — восемьсот.
#
# Углы и здоровье квантуются. Точность в четверть градуса и в одну единицу
# HP на экране неразличима, а размер снапшота это режет вдвое: угол вместо
# четырёх байт занимает два.
#
# Координаты остаются float32 намеренно. Их можно было бы ужать до int16
# с шагом в полпикселя, но карта у режимов разного размера, и любая ошибка
# в масштабе даёт «телепорты» — экономия трёхсот байт того не стоит.
# ============================================================================
class_name NetProtocol
extends RefCounted

## Версия формата. Клиент с другой версией отвергается на входе: разошедшийся
## протокол выглядит как случайные телепорты танков, и искать причину потом
## куда дороже, чем сверить число.
const VERSION := 1

# ------------------------------------------------------------------ снапшот
## Полное состояние партии на текущий тик.
##   tanks   — [{id, x, y, body, turret, hp, flags}]
##   bullets — [{x, y, vx, vy, team}]
static func encode_snapshot(tick: int, tanks: Array, bullets: Array,
		extra: Dictionary) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.put_u32(tick)

	buf.put_u16(tanks.size())
	for t in tanks:
		buf.put_u16(int(t.net_id))
		buf.put_float(t.x)
		buf.put_float(t.y)
		buf.put_u16(_angle_to_u16(t.body_angle))
		buf.put_u16(_angle_to_u16(t.turret_angle))
		buf.put_u16(clampi(int(round(t.hp)), 0, 65535))
		buf.put_u16(clampi(int(round(t.shield_hp)), 0, 65535))
		# Битовое поле вместо отдельных байт на каждый признак.
		var flags := 0
		if t.alive:
			flags |= 1
		if t.turbo_timer > 0:
			flags |= 2
		if t.spawn_protect > 0:
			flags |= 4
		if t.flag != null:
			flags |= 8
		if t.shadow_timer > 0:
			flags |= 16
		if t.ability_timer > 0:
			flags |= 32
		buf.put_u8(flags)

	buf.put_u16(bullets.size())
	for b in bullets:
		buf.put_float(b.x)
		buf.put_float(b.y)
		# Скорость нужна клиенту для доводки между снапшотами: без неё
		# пуля дёргается на каждом пакете.
		buf.put_16(clampi(int(round(b.vx * 64.0)), -32768, 32767))
		buf.put_16(clampi(int(round(b.vy * 64.0)), -32768, 32767))
		buf.put_u8(1 if b.from_player else 0)

	# Хвост режима: счёт, волна, база. Мелочь, но без неё HUD у клиента врёт.
	buf.put_var(extra)
	return buf.data_array

static func decode_snapshot(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = data
	var out := {"tick": buf.get_u32(), "tanks": [], "bullets": [], "extra": {}}

	var n := buf.get_u16()
	for i in n:
		out["tanks"].append({
			"id": buf.get_u16(),
			"x": buf.get_float(),
			"y": buf.get_float(),
			"body": _u16_to_angle(buf.get_u16()),
			"turret": _u16_to_angle(buf.get_u16()),
			"hp": float(buf.get_u16()),
			"shield": float(buf.get_u16()),
			"flags": buf.get_u8(),
		})

	var m := buf.get_u16()
	for i in m:
		out["bullets"].append({
			"x": buf.get_float(),
			"y": buf.get_float(),
			"vx": float(buf.get_16()) / 64.0,
			"vy": float(buf.get_16()) / 64.0,
			"player": buf.get_u8() == 1,
		})

	out["extra"] = buf.get_var()
	return out

# ------------------------------------------------------------------- команда
## Ввод одного игрока за тик. Летит от клиента к хосту шестьдесят раз
## в секунду, поэтому ужат до тринадцати байт.
static func encode_command(cmd: Dictionary) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	# Направление движения — два байта вместо двух float: оно всегда
	# в пределах [-1, 1].
	buf.put_8(clampi(int(round(float(cmd["mx"]) * 100.0)), -127, 127))
	buf.put_8(clampi(int(round(float(cmd["my"]) * 100.0)), -127, 127))
	buf.put_float(float(cmd["ax"]))
	buf.put_float(float(cmd["ay"]))
	var bits := 0
	if bool(cmd["fire"]):
		bits |= 1
	if bool(cmd["mine"]):
		bits |= 2
	if bool(cmd["dash"]):
		bits |= 4
	if bool(cmd["airstrike"]):
		bits |= 8
	if bool(cmd.get("ability", false)):
		bits |= 16
	buf.put_u8(bits)
	return buf.data_array

static func decode_command(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	buf.data_array = data
	var mx := float(buf.get_8()) / 100.0
	var my := float(buf.get_8()) / 100.0
	var ax := buf.get_float()
	var ay := buf.get_float()
	var bits := buf.get_u8()
	return {
		"mx": mx, "my": my, "ax": ax, "ay": ay,
		"fire": (bits & 1) != 0,
		"mine": (bits & 2) != 0,
		"dash": (bits & 4) != 0,
		"airstrike": (bits & 8) != 0,
		"ability": (bits & 16) != 0,
	}

# -------------------------------------------------------------- квантование
static func _angle_to_u16(a: float) -> int:
	return int(fposmod(a, TAU) / TAU * 65536.0) & 0xFFFF

static func _u16_to_angle(v: int) -> float:
	return float(v) / 65536.0 * TAU
