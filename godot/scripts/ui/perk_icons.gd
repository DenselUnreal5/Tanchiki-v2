# ============================================================================
# perk_icons.gd — векторные значки: 104 штуки (49 перков, 25 достижений,
# 9 улучшений гаража, 21 предмет косметики + заглушка), общие для всех трёх
# тем интерфейса (Sets.ui_theme) — меняется только цвет заливки (см.
# perk_icon_view.gd), не форма. Стиль — чистый плоский силуэт без штриховки
# и внутренних швов, по референсу пользователя (Pictures/GameCenter/
# icons pack ref/icons.webp) для 49 перков; остальные 55 — тот же язык.
#
# Каждый значок — список примитивов на сетке 64×64, без внешних файлов
# (весь интерфейс проекта рисуется процедурно). Формат примитива:
#   {"op":"poly",   "pts":[Vector2,...]}                     — заливка многоугольника
#   {"op":"line",   "a":Vector2,"b":Vector2,"w":float}        — отрезок
#   {"op":"circle", "c":Vector2,"r":float,"fill":bool,"w":float} — круг/кольцо
#   {"op":"rect",   "c":Vector2,"size":Vector2,"rot":float}   — повёрнутый прямоугольник
#   {"op":"arc",    "c":Vector2,"r":float,"a0":float,"a1":float,"w":float} — дуга (градусы)
#   {"op":"ring",   "pts":[Vector2,...],"c":Vector2,"n":int}  — фигура pts, повторённая
#                                                                n раз по кругу вокруг c
# Любой примитив может нести "shade": true — рисуется приглушённым
# shade_color вместо icon_color (см. perk_icon_view.gd) — в этом плоском
# стиле почти не используется, но поддержка не убрана, вреда от простоя нет.
# ============================================================================
class_name PerkIcons
extends RefCounted

static var ICONS := {
	"_default": [
		{"op": "circle", "c": Vector2(32, 32), "r": 18, "fill": false, "w": 6},
	],

	# ================================================================ ОГОНЬ
	"rapid_fire": [ # тройная стрела — Rapid Fire
		{"op": "line", "a": Vector2(8,16), "b": Vector2(42,16), "w": 6},
		{"op": "poly", "pts": [Vector2(38,8), Vector2(56,16), Vector2(38,24)]},
		{"op": "line", "a": Vector2(8,32), "b": Vector2(42,32), "w": 6},
		{"op": "poly", "pts": [Vector2(38,24), Vector2(56,32), Vector2(38,40)]},
		{"op": "line", "a": Vector2(8,48), "b": Vector2(42,48), "w": 6},
		{"op": "poly", "pts": [Vector2(38,40), Vector2(56,48), Vector2(38,56)]},
	],
	"double_shot": [ # расходящаяся двойная стрела — Double Shot
		{"op": "line", "a": Vector2(10,32), "b": Vector2(38,18), "w": 6},
		{"op": "poly", "pts": [Vector2(34,8), Vector2(52,10), Vector2(40,24)]},
		{"op": "line", "a": Vector2(10,32), "b": Vector2(38,46), "w": 6},
		{"op": "poly", "pts": [Vector2(34,56), Vector2(52,54), Vector2(40,40)]},
	],
	"fan_shot": [ # трёхлопастный веер — Fan Fire
		{"op": "circle", "c": Vector2(32,32), "r": 6, "fill": true},
		{"op": "ring", "c": Vector2(32,32), "n": 3, "pts": [Vector2(32,32), Vector2(32,6), Vector2(44,16)]},
	],
	"explosive": [ # звезда-вспышка — HEAT Round
		{"op": "poly", "pts": [Vector2(32,4), Vector2(38,24), Vector2(58,24), Vector2(42,36), Vector2(48,56), Vector2(32,44), Vector2(16,56), Vector2(22,36), Vector2(6,24), Vector2(26,24)]},
	],
	"piercing": [ # пуля со следом скорости — Piercing Shot
		{"op": "poly", "pts": [Vector2(40,24), Vector2(56,32), Vector2(40,40), Vector2(28,40), Vector2(28,24)]},
		{"op": "line", "a": Vector2(6,26), "b": Vector2(20,26), "w": 4},
		{"op": "line", "a": Vector2(4,32), "b": Vector2(22,32), "w": 4},
		{"op": "line", "a": Vector2(6,38), "b": Vector2(20,38), "w": 4},
	],
	"heavy_shell": [ # оперённый снаряд — AP Round
		{"op": "poly", "pts": [Vector2(52,32), Vector2(30,20), Vector2(30,44)]},
		{"op": "rect", "c": Vector2(18,32), "size": Vector2(26,10), "rot": 0},
		{"op": "poly", "pts": [Vector2(6,24), Vector2(18,32), Vector2(6,40)]},
	],
	"light_shell": [ # тонкая пуля с острым носиком — Light AP
		{"op": "rect", "c": Vector2(32,42), "size": Vector2(12,32), "rot": 0},
		{"op": "poly", "pts": [Vector2(26,26), Vector2(38,26), Vector2(32,4)]},
	],
	"siege": [ # тяжёлый осадный снаряд — Siege Round
		{"op": "poly", "pts": [Vector2(24,52), Vector2(24,26), Vector2(32,6), Vector2(40,26), Vector2(40,52)]},
		{"op": "rect", "c": Vector2(32,56), "size": Vector2(22,8), "rot": 0},
	],
	"lumberjack": [ # топор — Lumberjack
		{"op": "poly", "pts": [Vector2(22,10), Vector2(48,2), Vector2(58,18), Vector2(48,32), Vector2(22,24)]},
		{"op": "rect", "c": Vector2(16,50), "size": Vector2(8,46), "rot": -8},
	],
	"concrete_breaker": [ # клин, вскрывающий бетон — Concrete Breaker
		{"op": "poly", "pts": [Vector2(46,6), Vector2(58,18), Vector2(24,52), Vector2(16,44)]},
		{"op": "line", "a": Vector2(16,44), "b": Vector2(8,58), "w": 6},
	],
	"can_opener": [ # нож — Armor-Peeling Knife
		{"op": "poly", "pts": [Vector2(46,6), Vector2(56,16), Vector2(24,48), Vector2(18,42)]},
		{"op": "rect", "c": Vector2(14,52), "size": Vector2(14,10), "rot": 45},
	],
	"coolant": [ # раструб с потоком — Nozzle Blow
		{"op": "poly", "pts": [Vector2(10,24), Vector2(26,24), Vector2(40,10), Vector2(40,54), Vector2(26,40), Vector2(10,40)]},
		{"op": "line", "a": Vector2(48,20), "b": Vector2(58,20), "w": 4},
		{"op": "line", "a": Vector2(48,32), "b": Vector2(60,32), "w": 4},
		{"op": "line", "a": Vector2(48,44), "b": Vector2(58,44), "w": 4},
	],
	"overclock": [ # стрела вверх по склону — Ramp-Up
		{"op": "poly", "pts": [Vector2(6,54), Vector2(6,44), Vector2(58,10)]},
		{"op": "line", "a": Vector2(30,26), "b": Vector2(56,10), "w": 6},
		{"op": "poly", "pts": [Vector2(40,6), Vector2(60,8), Vector2(52,26)]},
	],
	"heat_sink": [ # радиатор — Radiator
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(52,4), "rot": 0},
		{"op": "rect", "c": Vector2(32,60), "size": Vector2(52,4), "rot": 0},
		{"op": "rect", "c": Vector2(14,32), "size": Vector2(7,52), "rot": 0},
		{"op": "rect", "c": Vector2(25,32), "size": Vector2(7,52), "rot": 0},
		{"op": "rect", "c": Vector2(36,32), "size": Vector2(7,52), "rot": 0},
		{"op": "rect", "c": Vector2(47,32), "size": Vector2(7,52), "rot": 0},
		{"op": "rect", "c": Vector2(58,32), "size": Vector2(7,52), "rot": 0},
	],
	"thermal": [ # термометр — Thermal Resistance
		{"op": "rect", "c": Vector2(32,26), "size": Vector2(12,36), "rot": 0},
		{"op": "circle", "c": Vector2(32,48), "r": 13, "fill": true},
	],
	"quick_vent": [ # стрела вниз — Quick Drop
		{"op": "rect", "c": Vector2(32,20), "size": Vector2(10,28), "rot": 0},
		{"op": "poly", "pts": [Vector2(16,36), Vector2(48,36), Vector2(32,58)]},
	],
	"nitro": [ # ракета — Nitro Boost
		{"op": "poly", "pts": [Vector2(32,2), Vector2(40,14), Vector2(44,26), Vector2(44,48), Vector2(20,48), Vector2(20,26), Vector2(24,14)]},
		{"op": "poly", "pts": [Vector2(20,40), Vector2(6,56), Vector2(20,56)]},
		{"op": "poly", "pts": [Vector2(44,40), Vector2(58,56), Vector2(44,56)]},
		{"op": "poly", "pts": [Vector2(22,48), Vector2(32,64), Vector2(42,48)]},
	],
	"overdrive": [ # баллон нитро — NOS Boost
		{"op": "rect", "c": Vector2(32,38), "size": Vector2(24,40), "rot": 0},
		{"op": "rect", "c": Vector2(32,14), "size": Vector2(12,12), "rot": 0},
		{"op": "rect", "c": Vector2(32,4), "size": Vector2(6,8), "rot": 0},
	],
	"bulwark": [ # щит-бастион с зубцами — Bastion
		{"op": "poly", "pts": [Vector2(32,6), Vector2(54,14), Vector2(54,32), Vector2(32,60), Vector2(10,32), Vector2(10,14)]},
		{"op": "rect", "c": Vector2(18,10), "size": Vector2(8,8), "rot": 0},
		{"op": "rect", "c": Vector2(32,6), "size": Vector2(8,10), "rot": 0},
		{"op": "rect", "c": Vector2(46,10), "size": Vector2(8,8), "rot": 0},
	],
	"shockwave": [ # ударные кольца — Shockwave
		{"op": "circle", "c": Vector2(32,32), "r": 6, "fill": true},
		{"op": "circle", "c": Vector2(32,32), "r": 18, "fill": false, "w": 5},
		{"op": "circle", "c": Vector2(32,32), "r": 29, "fill": false, "w": 5},
	],

	# ================================================================ ЗАЩИТА
	"heavy_armor": [ # щит — Heavy Armor
		{"op": "poly", "pts": [Vector2(32,4), Vector2(54,12), Vector2(54,30), Vector2(32,62), Vector2(10,30), Vector2(10,12)]},
	],
	"thick_armor": [ # блочный щит — Thick Armor
		{"op": "poly", "pts": [Vector2(32,6), Vector2(56,14), Vector2(56,32), Vector2(32,58), Vector2(8,32), Vector2(8,14)]},
		{"op": "rect", "c": Vector2(32,30), "size": Vector2(36,8), "rot": 0, "shade": true},
	],
	"shield": [ # щит с молнией — Energy Shield
		{"op": "line", "a": Vector2(32,4), "b": Vector2(54,12), "w": 5},
		{"op": "line", "a": Vector2(54,12), "b": Vector2(54,30), "w": 5},
		{"op": "line", "a": Vector2(54,30), "b": Vector2(32,62), "w": 5},
		{"op": "line", "a": Vector2(32,62), "b": Vector2(10,30), "w": 5},
		{"op": "line", "a": Vector2(10,30), "b": Vector2(10,12), "w": 5},
		{"op": "line", "a": Vector2(10,12), "b": Vector2(32,4), "w": 5},
		{"op": "poly", "pts": [Vector2(36,14), Vector2(24,34), Vector2(32,34), Vector2(28,50), Vector2(44,28), Vector2(35,28)]},
	],
	"regen": [ # крест с импульсом — Regeneration
		{"op": "poly", "pts": [Vector2(26,18), Vector2(38,18), Vector2(38,26), Vector2(46,26), Vector2(46,38), Vector2(38,38), Vector2(38,46), Vector2(26,46), Vector2(26,38), Vector2(18,38), Vector2(18,26), Vector2(26,26)]},
	],
	"reflect": [ # рикошет — Ricochet
		{"op": "line", "a": Vector2(8,20), "b": Vector2(32,44), "w": 6},
		{"op": "line", "a": Vector2(32,44), "b": Vector2(56,12), "w": 6},
		{"op": "poly", "pts": [Vector2(44,8), Vector2(60,10), Vector2(50,22)]},
	],
	"evasion": [ # зигзаг-манёвр — Evasion
		{"op": "line", "a": Vector2(6,48), "b": Vector2(22,28), "w": 6},
		{"op": "line", "a": Vector2(22,28), "b": Vector2(38,44), "w": 6},
		{"op": "line", "a": Vector2(38,44), "b": Vector2(52,16), "w": 6},
		{"op": "poly", "pts": [Vector2(44,10), Vector2(60,12), Vector2(50,26)]},
	],
	"smoke": [ # дымовое облако — Smoke Screen
		{"op": "poly", "pts": [Vector2(18,46), Vector2(9,42), Vector2(8,32), Vector2(15,25), Vector2(16,15), Vector2(28,8), Vector2(40,12), Vector2(45,20), Vector2(54,22), Vector2(58,32), Vector2(54,42), Vector2(44,46)]},
	],
	"repair": [ # гаечный ключ — Field Repair
		{"op": "line", "a": Vector2(20,44), "b": Vector2(44,20), "w": 9},
		{"op": "arc", "c": Vector2(14,50), "r": 11, "a0": 30, "a1": 300, "w": 9},
		{"op": "arc", "c": Vector2(50,14), "r": 11, "a0": 210, "a1": 480, "w": 9},
	],

	# ================================================================ СКОРОСТЬ
	"sprinter": [ # бегущая фигура — Sprinter
		{"op": "circle", "c": Vector2(38,10), "r": 7, "fill": true},
		{"op": "poly", "pts": [Vector2(30,20), Vector2(42,18), Vector2(46,32), Vector2(38,34), Vector2(34,26)]},
		{"op": "line", "a": Vector2(36,30), "b": Vector2(20,40), "w": 6},
		{"op": "line", "a": Vector2(20,40), "b": Vector2(10,36), "w": 6},
		{"op": "line", "a": Vector2(40,32), "b": Vector2(50,50), "w": 6},
		{"op": "line", "a": Vector2(50,50), "b": Vector2(44,60), "w": 6},
		{"op": "line", "a": Vector2(40,32), "b": Vector2(28,52), "w": 6},
		{"op": "line", "a": Vector2(28,52), "b": Vector2(34,60), "w": 6},
	],
	"road_king": [ # дорога с разметкой — Pavement Layer
		{"op": "rect", "c": Vector2(32,40), "size": Vector2(56,20), "rot": 0},
		{"op": "rect", "c": Vector2(14,40), "size": Vector2(8,4), "rot": 0, "shade": true},
		{"op": "rect", "c": Vector2(32,40), "size": Vector2(8,4), "rot": 0, "shade": true},
		{"op": "rect", "c": Vector2(50,40), "size": Vector2(8,4), "rot": 0, "shade": true},
	],
	"quick_reload": [ # круговая стрелка с патроном — Auto-Loader
		{"op": "arc", "c": Vector2(32,32), "r": 22, "a0": -50, "a1": 220, "w": 7},
		{"op": "poly", "pts": [Vector2(48,10), Vector2(60,16), Vector2(46,22)]},
		{"op": "circle", "c": Vector2(32,32), "r": 5, "fill": true},
	],
	"all_terrain": [ # вездеход — All-Terrain
		{"op": "rect", "c": Vector2(32,36), "size": Vector2(44,14), "rot": 0},
		{"op": "rect", "c": Vector2(28,24), "size": Vector2(20,12), "rot": 0},
		{"op": "circle", "c": Vector2(16,44), "r": 7, "fill": true},
		{"op": "circle", "c": Vector2(48,44), "r": 7, "fill": true},
	],
	"grip": [ # шипованная гусеница — Track Spikes
		{"op": "rect", "c": Vector2(32,50), "size": Vector2(52,6), "rot": 0},
		{"op": "poly", "pts": [Vector2(14,44), Vector2(20,44), Vector2(17,26)]},
		{"op": "poly", "pts": [Vector2(29,44), Vector2(35,44), Vector2(32,20)]},
		{"op": "poly", "pts": [Vector2(44,44), Vector2(50,44), Vector2(47,26)]},
	],

	# ================================================================ ОСОБЫЕ
	"mines": [ # морская мина — Mine Layer
		{"op": "circle", "c": Vector2(32,32), "r": 15, "fill": true},
		{"op": "line", "a": Vector2(32,32), "b": Vector2(32,4), "w": 6},
		{"op": "line", "a": Vector2(32,32), "b": Vector2(53,11), "w": 6},
		{"op": "line", "a": Vector2(32,32), "b": Vector2(60,32), "w": 6},
		{"op": "line", "a": Vector2(32,32), "b": Vector2(53,53), "w": 6},
		{"op": "line", "a": Vector2(32,32), "b": Vector2(32,60), "w": 6},
		{"op": "line", "a": Vector2(32,32), "b": Vector2(11,53), "w": 6},
		{"op": "line", "a": Vector2(32,32), "b": Vector2(4,32), "w": 6},
		{"op": "line", "a": Vector2(32,32), "b": Vector2(11,11), "w": 6},
	],
	"scavenger": [ # маска мародёра — Marauder
		{"op": "poly", "pts": [Vector2(32,6), Vector2(50,20), Vector2(50,38), Vector2(40,54), Vector2(24,54), Vector2(14,38), Vector2(14,20)]},
		{"op": "poly", "pts": [Vector2(20,26), Vector2(28,26), Vector2(24,34)], "shade": true},
		{"op": "poly", "pts": [Vector2(36,26), Vector2(44,26), Vector2(40,34)], "shade": true},
	],
	"keen_ear": [ # ухо — Sharp Hearing
		{"op": "poly", "pts": [Vector2(24,8), Vector2(42,10), Vector2(52,26), Vector2(48,46), Vector2(34,58), Vector2(26,50), Vector2(36,42), Vector2(38,28), Vector2(24,24)]},
	],
	"muffler": [ # колокол с перечёркиванием — Jammer
		{"op": "poly", "pts": [Vector2(32,8), Vector2(46,32), Vector2(46,40), Vector2(18,40), Vector2(18,32)]},
		{"op": "rect", "c": Vector2(32,46), "size": Vector2(36,6), "rot": 0},
		{"op": "line", "a": Vector2(10,14), "b": Vector2(54,50), "w": 5},
	],
	"breaker": [ # пуля со вспышкой разряда — HE Round
		{"op": "poly", "pts": [Vector2(44,32), Vector2(22,20), Vector2(22,44)]},
		{"op": "poly", "pts": [Vector2(14,32), Vector2(19,20), Vector2(24,32), Vector2(19,44)]},
	],
	"silencer": [ # пистолет с глушителем — Silencer
		{"op": "rect", "c": Vector2(38,28), "size": Vector2(40,8), "rot": 0},
		{"op": "rect", "c": Vector2(8,28), "size": Vector2(14,14), "rot": 0},
		{"op": "poly", "pts": [Vector2(8,35), Vector2(16,35), Vector2(16,54), Vector2(8,54)]},
	],
	# ================================================================ ЧЕЛЛЕНДЖИ
	"ram": [ # танк с усиленным носом — Ramming Prow
		{"op": "rect", "c": Vector2(30,36), "size": Vector2(36,20), "rot": 0},
		{"op": "rect", "c": Vector2(30,20), "size": Vector2(18,12), "rot": 0},
		{"op": "poly", "pts": [Vector2(48,26), Vector2(60,32), Vector2(48,46)]},
		{"op": "circle", "c": Vector2(18,50), "r": 7, "fill": true},
		{"op": "circle", "c": Vector2(42,50), "r": 7, "fill": true},
	],
	"amphibious": [ # лодка на волнах — Amphibious
		{"op": "poly", "pts": [Vector2(10,30), Vector2(54,30), Vector2(46,44), Vector2(18,44)]},
		{"op": "rect", "c": Vector2(32,20), "size": Vector2(6,20), "rot": 0},
		{"op": "poly", "pts": [Vector2(35,10), Vector2(50,20), Vector2(35,24)]},
		{"op": "line", "a": Vector2(6,52), "b": Vector2(16,52), "w": 4},
		{"op": "line", "a": Vector2(20,52), "b": Vector2(30,52), "w": 4},
		{"op": "line", "a": Vector2(34,52), "b": Vector2(44,52), "w": 4},
		{"op": "line", "a": Vector2(48,52), "b": Vector2(58,52), "w": 4},
	],
	"forest": [ # ель — без референса, свой силуэт
		{"op": "poly", "pts": [Vector2(32,4), Vector2(46,24), Vector2(37,24), Vector2(50,42), Vector2(39,42), Vector2(32,54), Vector2(25,42), Vector2(14,42), Vector2(27,24), Vector2(18,24)]},
		{"op": "rect", "c": Vector2(32,58), "size": Vector2(8,10), "rot": 0},
	],
	"magnet": [ # подковообразный магнит — Magnetic Pull
		{"op": "arc", "c": Vector2(32,30), "r": 20, "a0": 20, "a1": 160, "w": 12},
		{"op": "rect", "c": Vector2(15,46), "size": Vector2(10,20), "rot": 0},
		{"op": "rect", "c": Vector2(49,46), "size": Vector2(10,20), "rot": 0},
		{"op": "rect", "c": Vector2(15,54), "size": Vector2(10,6), "rot": 0},
		{"op": "rect", "c": Vector2(49,54), "size": Vector2(10,6), "rot": 0},
	],
	"sniper": [ # винтовка со скопом — Sniper
		{"op": "rect", "c": Vector2(30,34), "size": Vector2(50,6), "rot": 0},
		{"op": "poly", "pts": [Vector2(8,32), Vector2(8,44), Vector2(0,50), Vector2(0,38)]},
		{"op": "rect", "c": Vector2(40,24), "size": Vector2(4,14), "rot": 0},
		{"op": "rect", "c": Vector2(40,17), "size": Vector2(18,6), "rot": 0},
	],
	"berserk": [ # разъярённая маска — Berserk
		{"op": "poly", "pts": [Vector2(32,6), Vector2(50,20), Vector2(50,38), Vector2(40,54), Vector2(24,54), Vector2(14,38), Vector2(14,20)]},
		{"op": "poly", "pts": [Vector2(18,24), Vector2(28,20), Vector2(28,26)], "shade": true},
		{"op": "poly", "pts": [Vector2(46,24), Vector2(36,20), Vector2(36,26)], "shade": true},
		{"op": "rect", "c": Vector2(32,42), "size": Vector2(18,5), "rot": 0, "shade": true},
	],
	"kamikaze": [ # ракета с искрой — Kamikaze
		{"op": "poly", "pts": [Vector2(32,10), Vector2(42,22), Vector2(42,48), Vector2(22,48), Vector2(22,22)]},
		{"op": "poly", "pts": [Vector2(22,40), Vector2(10,54), Vector2(22,54)]},
		{"op": "poly", "pts": [Vector2(42,40), Vector2(54,54), Vector2(42,54)]},
		{"op": "poly", "pts": [Vector2(14,10), Vector2(22,2), Vector2(30,10), Vector2(22,18)]},
	],
	"turbo": [ # турбина — Turbo
		{"op": "circle", "c": Vector2(32,32), "r": 24, "fill": false, "w": 6},
		{"op": "circle", "c": Vector2(32,32), "r": 6, "fill": true},
		{"op": "ring", "c": Vector2(32,32), "n": 3, "pts": [Vector2(32,32), Vector2(32,10), Vector2(44,18)]},
	],
	"shadow": [ # тень-силуэт — Shadow
		{"op": "poly", "pts": [Vector2(16,58), Vector2(16,28), Vector2(20,14), Vector2(32,6), Vector2(44,14), Vector2(48,28), Vector2(48,58), Vector2(42,50), Vector2(36,58), Vector2(32,50), Vector2(28,58), Vector2(22,50)]},
	],
	"vampire": [ # клыкастое лицо — Vampire
		{"op": "poly", "pts": [Vector2(32,6), Vector2(50,18), Vector2(50,36), Vector2(32,58), Vector2(14,36), Vector2(14,18)]},
		{"op": "poly", "pts": [Vector2(22,34), Vector2(30,34), Vector2(24,50)], "shade": true},
		{"op": "poly", "pts": [Vector2(42,34), Vector2(34,34), Vector2(40,50)], "shade": true},
	],

	# ==================================================== ДОСТИЖЕНИЯ (ach_*)
	"ach_first_blood": [ # мишень — первая кровь
		{"op": "circle", "c": Vector2(32,32), "r": 26, "fill": false, "w": 6},
		{"op": "circle", "c": Vector2(32,32), "r": 14, "fill": false, "w": 6},
		{"op": "circle", "c": Vector2(32,32), "r": 5, "fill": true},
	],
	"ach_kill_10": [ # шеврон — ветеран
		{"op": "line", "a": Vector2(10,16), "b": Vector2(32,40), "w": 10},
		{"op": "line", "a": Vector2(32,40), "b": Vector2(54,16), "w": 10},
	],
	"ach_kill_50": [ # кости крест-накрест — машина для убийств
		{"op": "line", "a": Vector2(10,10), "b": Vector2(54,54), "w": 9},
		{"op": "line", "a": Vector2(54,10), "b": Vector2(10,54), "w": 9},
		{"op": "circle", "c": Vector2(10,10), "r": 6, "fill": true},
		{"op": "circle", "c": Vector2(54,10), "r": 6, "fill": true},
		{"op": "circle", "c": Vector2(10,54), "r": 6, "fill": true},
		{"op": "circle", "c": Vector2(54,54), "r": 6, "fill": true},
	],
	"ach_kill_250": [ # тесак — палач
		{"op": "poly", "pts": [Vector2(38,4), Vector2(58,20), Vector2(58,34), Vector2(30,34), Vector2(30,20)]},
		{"op": "rect", "c": Vector2(22,48), "size": Vector2(8,32), "rot": 20},
	],
	"ach_ram_10": [ # клин тарана — тарановод
		{"op": "poly", "pts": [Vector2(8,10), Vector2(8,54), Vector2(54,32)]},
		{"op": "rect", "c": Vector2(14,32), "size": Vector2(8,36), "rot": 0},
	],
	"ach_ram_50": [ # усиленный клин — бронированный таран
		{"op": "poly", "pts": [Vector2(6,8), Vector2(6,56), Vector2(50,32)]},
		{"op": "rect", "c": Vector2(12,32), "size": Vector2(8,40), "rot": 0},
		{"op": "poly", "pts": [Vector2(50,32), Vector2(60,22), Vector2(58,32), Vector2(60,42)]},
	],
	"ach_bricks_100": [ # кирпичная стена — разрушитель
		{"op": "rect", "c": Vector2(16,18), "size": Vector2(24,14), "rot": 0},
		{"op": "rect", "c": Vector2(44,18), "size": Vector2(24,14), "rot": 0},
		{"op": "rect", "c": Vector2(30,34), "size": Vector2(24,14), "rot": 0},
		{"op": "rect", "c": Vector2(6,34), "size": Vector2(16,14), "rot": 0},
		{"op": "rect", "c": Vector2(56,34), "size": Vector2(16,14), "rot": 0},
		{"op": "rect", "c": Vector2(16,50), "size": Vector2(24,14), "rot": 0},
		{"op": "rect", "c": Vector2(44,50), "size": Vector2(24,14), "rot": 0},
	],
	"ach_bricks_500": [ # груда обломков — строительный магнат
		{"op": "rect", "c": Vector2(18,44), "size": Vector2(20,16), "rot": -12},
		{"op": "rect", "c": Vector2(42,40), "size": Vector2(18,16), "rot": 10},
		{"op": "rect", "c": Vector2(30,54), "size": Vector2(22,14), "rot": 4},
		{"op": "rect", "c": Vector2(14,26), "size": Vector2(14,12), "rot": 18},
		{"op": "rect", "c": Vector2(46,24), "size": Vector2(14,12), "rot": -16},
		{"op": "rect", "c": Vector2(32,14), "size": Vector2(16,12), "rot": 6},
	],
	"ach_medkits_25": [ # крест в кольце — санитар
		{"op": "circle", "c": Vector2(32,32), "r": 26, "fill": false, "w": 6},
		{"op": "poly", "pts": [Vector2(26,16), Vector2(38,16), Vector2(38,26), Vector2(48,26), Vector2(48,38), Vector2(38,38), Vector2(38,48), Vector2(26,48), Vector2(26,38), Vector2(16,38), Vector2(16,26), Vector2(26,26)]},
	],
	"ach_medkits_100": [ # большой крест — медик полка
		{"op": "poly", "pts": [Vector2(24,10), Vector2(40,10), Vector2(40,24), Vector2(54,24), Vector2(54,40), Vector2(40,40), Vector2(40,54), Vector2(24,54), Vector2(24,40), Vector2(10,40), Vector2(10,24), Vector2(24,24)]},
	],
	"ach_wins_5": [ # кубок — первая победа
		{"op": "poly", "pts": [Vector2(18,8), Vector2(46,8), Vector2(42,32), Vector2(32,40), Vector2(22,32)]},
		{"op": "arc", "c": Vector2(14,16), "r": 10, "a0": -90, "a1": 90, "w": 5},
		{"op": "arc", "c": Vector2(50,16), "r": 10, "a0": 90, "a1": 270, "w": 5},
		{"op": "rect", "c": Vector2(32,48), "size": Vector2(8,16), "rot": 0},
		{"op": "rect", "c": Vector2(32,58), "size": Vector2(24,6), "rot": 0},
	],
	"ach_wins_25": [ # корона — чемпион
		{"op": "poly", "pts": [Vector2(10,26), Vector2(18,50), Vector2(46,50), Vector2(54,26), Vector2(44,38), Vector2(32,16), Vector2(20,38)]},
		{"op": "rect", "c": Vector2(32,54), "size": Vector2(44,8), "rot": 0},
	],
	"ach_games_10": [ # геймпад — заядлый игрок
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(56,26), "rot": 0},
		{"op": "circle", "c": Vector2(42,26), "r": 5, "fill": true},
		{"op": "circle", "c": Vector2(50,34), "r": 5, "fill": true},
	],
	"ach_games_50": [ # джойстик — легенда аркад
		{"op": "rect", "c": Vector2(32,52), "size": Vector2(36,12), "rot": 0},
		{"op": "rect", "c": Vector2(32,34), "size": Vector2(10,30), "rot": 0},
		{"op": "circle", "c": Vector2(32,16), "r": 14, "fill": true},
	],
	"ach_long_20": [ # прицел — снайпер
		{"op": "circle", "c": Vector2(32,32), "r": 22, "fill": false, "w": 5},
		{"op": "line", "a": Vector2(32,2), "b": Vector2(32,18), "w": 5},
		{"op": "line", "a": Vector2(32,46), "b": Vector2(32,62), "w": 5},
		{"op": "line", "a": Vector2(2,32), "b": Vector2(18,32), "w": 5},
		{"op": "line", "a": Vector2(46,32), "b": Vector2(62,32), "w": 5},
	],
	"ach_lowhp_10": [ # кулак — берсерк
		{"op": "poly", "pts": [Vector2(16,50), Vector2(14,32), Vector2(20,24), Vector2(44,24), Vector2(50,32), Vector2(48,50)]},
		{"op": "rect", "c": Vector2(31,56), "size": Vector2(30,10), "rot": 0},
	],
	"ach_streak_10": [ # щит со звездой — неприкасаемый
		{"op": "line", "a": Vector2(32,4), "b": Vector2(54,12), "w": 5},
		{"op": "line", "a": Vector2(54,12), "b": Vector2(54,30), "w": 5},
		{"op": "line", "a": Vector2(54,30), "b": Vector2(32,62), "w": 5},
		{"op": "line", "a": Vector2(32,62), "b": Vector2(10,30), "w": 5},
		{"op": "line", "a": Vector2(10,30), "b": Vector2(10,12), "w": 5},
		{"op": "line", "a": Vector2(10,12), "b": Vector2(32,4), "w": 5},
		{"op": "poly", "pts": [Vector2(32,20), Vector2(35,28), Vector2(44,28), Vector2(37,33), Vector2(40,42), Vector2(32,37), Vector2(24,42), Vector2(27,33), Vector2(20,28), Vector2(29,28)]},
	],
	"ach_rapid_5": [ # вспышка-звезда — шквал
		{"op": "poly", "pts": [Vector2(32,2), Vector2(38,24), Vector2(60,20), Vector2(42,34), Vector2(54,54), Vector2(32,42), Vector2(10,54), Vector2(22,34), Vector2(4,20), Vector2(26,24)]},
	],
	"ach_bridge_defender": [ # мост — защитник моста
		{"op": "arc", "c": Vector2(32,50), "r": 26, "a0": 180, "a1": 360, "w": 7},
		{"op": "rect", "c": Vector2(14,52), "size": Vector2(8,20), "rot": 0},
		{"op": "rect", "c": Vector2(50,52), "size": Vector2(8,20), "rot": 0},
		{"op": "rect", "c": Vector2(32,50), "size": Vector2(56,6), "rot": 0},
	],
	"ach_demolition": [ # связка шашек — подрывник
		{"op": "rect", "c": Vector2(20,42), "size": Vector2(12,36), "rot": 0},
		{"op": "rect", "c": Vector2(32,42), "size": Vector2(12,36), "rot": 0},
		{"op": "rect", "c": Vector2(44,42), "size": Vector2(12,36), "rot": 0},
		{"op": "line", "a": Vector2(32,24), "b": Vector2(40,8), "w": 4},
		{"op": "circle", "c": Vector2(42,6), "r": 5, "fill": true},
	],
	"ach_demolition_master": [ # бомба с искрой — мастер сноса
		{"op": "circle", "c": Vector2(30,40), "r": 22, "fill": true},
		{"op": "line", "a": Vector2(40,22), "b": Vector2(50,8), "w": 5},
		{"op": "circle", "c": Vector2(52,6), "r": 6, "fill": false, "w": 4},
	],
	"ach_eagle_ear": [ # орлиное крыло — орлиный слух
		{"op": "poly", "pts": [Vector2(8,44), Vector2(20,30), Vector2(18,36), Vector2(30,22), Vector2(26,30), Vector2(40,16), Vector2(34,26), Vector2(50,10), Vector2(40,34), Vector2(56,30), Vector2(30,48), Vector2(18,52)]},
	],
	"ach_ability_50": [ # искра — козырь в рукаве
		{"op": "poly", "pts": [Vector2(32,4), Vector2(38,28), Vector2(60,32), Vector2(38,36), Vector2(32,60), Vector2(26,36), Vector2(4,32), Vector2(26,28)]},
	],
	"ach_ability_250": [ # вертушка из трёх лопастей — мастер манёвра
		{"op": "circle", "c": Vector2(32,32), "r": 7, "fill": true},
		{"op": "ring", "c": Vector2(32,32), "n": 3, "pts": [Vector2(32,32), Vector2(32,4), Vector2(46,14)]},
	],
	"ach_damage_1000": [ # снаряд с разрывом — артобстрел
		{"op": "poly", "pts": [Vector2(26,4), Vector2(38,4), Vector2(42,16), Vector2(42,40), Vector2(22,40), Vector2(22,16)]},
		{"op": "poly", "pts": [Vector2(22,40), Vector2(14,50), Vector2(22,50)]},
		{"op": "poly", "pts": [Vector2(42,40), Vector2(50,50), Vector2(42,50)]},
		{"op": "poly", "pts": [Vector2(20,58), Vector2(32,52), Vector2(44,58), Vector2(32,62)]},
	],

	# ================================================= ГАРАЖ · УЛУЧШЕНИЯ (upg_*)
	"upg_dmg": [ # ствол с дульной вспышкой — мощный ствол
		{"op": "rect", "c": Vector2(30,36), "size": Vector2(44,14), "rot": 0},
		{"op": "rect", "c": Vector2(8,36), "size": Vector2(16,20), "rot": 0},
		{"op": "poly", "pts": [Vector2(52,36), Vector2(64,26), Vector2(58,36), Vector2(64,46)]},
	],
	"upg_fire_rate": [ # круговая стрелка — автоускоритель
		{"op": "arc", "c": Vector2(32,32), "r": 22, "a0": -50, "a1": 220, "w": 8},
		{"op": "poly", "pts": [Vector2(48,8), Vector2(60,16), Vector2(46,22)]},
	],
	"upg_bullet_speed": [ # пуля со следом скорости — тяжёлые снаряды
		{"op": "poly", "pts": [Vector2(38,24), Vector2(56,32), Vector2(38,40), Vector2(24,40), Vector2(24,24)]},
		{"op": "line", "a": Vector2(4,24), "b": Vector2(16,24), "w": 5},
		{"op": "line", "a": Vector2(2,32), "b": Vector2(20,32), "w": 5},
		{"op": "line", "a": Vector2(4,40), "b": Vector2(16,40), "w": 5},
	],
	"upg_max_hp": [ # контур щита — усиленная броня
		{"op": "line", "a": Vector2(32,4), "b": Vector2(54,12), "w": 6},
		{"op": "line", "a": Vector2(54,12), "b": Vector2(54,30), "w": 6},
		{"op": "line", "a": Vector2(54,30), "b": Vector2(32,62), "w": 6},
		{"op": "line", "a": Vector2(32,62), "b": Vector2(10,30), "w": 6},
		{"op": "line", "a": Vector2(10,30), "b": Vector2(10,12), "w": 6},
		{"op": "line", "a": Vector2(10,12), "b": Vector2(32,4), "w": 6},
	],
	"upg_damage_taken": [ # шестигранная плита — композитная броня
		{"op": "poly", "pts": [Vector2(32,4), Vector2(54,16), Vector2(54,42), Vector2(32,60), Vector2(10,42), Vector2(10,16)]},
	],
	"upg_speed": [ # двойной шеврон — форсированный мотор
		{"op": "poly", "pts": [Vector2(8,50), Vector2(8,14), Vector2(30,32)]},
		{"op": "poly", "pts": [Vector2(32,50), Vector2(32,14), Vector2(54,32)]},
	],
	"upg_ram": [ # клин с боковыми шипами — бронекаток
		{"op": "poly", "pts": [Vector2(8,10), Vector2(8,54), Vector2(50,32)]},
		{"op": "rect", "c": Vector2(14,32), "size": Vector2(8,40), "rot": 0},
		{"op": "line", "a": Vector2(50,32), "b": Vector2(60,22), "w": 5},
		{"op": "line", "a": Vector2(50,32), "b": Vector2(60,42), "w": 5},
	],
	"upg_pickup_radius": [ # подковообразный магнит — магнитный трал
		{"op": "arc", "c": Vector2(32,30), "r": 20, "a0": 20, "a1": 160, "w": 12},
		{"op": "rect", "c": Vector2(15,46), "size": Vector2(10,20), "rot": 0},
		{"op": "rect", "c": Vector2(49,46), "size": Vector2(10,20), "rot": 0},
		{"op": "rect", "c": Vector2(15,54), "size": Vector2(10,6), "rot": 0},
		{"op": "rect", "c": Vector2(49,54), "size": Vector2(10,6), "rot": 0},
	],
	"upg_regen": [ # крест в кольце — ремонтный модуль
		{"op": "circle", "c": Vector2(32,32), "r": 24, "fill": false, "w": 7},
		{"op": "poly", "pts": [Vector2(27,20), Vector2(37,20), Vector2(37,27), Vector2(44,27), Vector2(44,37), Vector2(37,37), Vector2(37,44), Vector2(27,44), Vector2(27,37), Vector2(20,37), Vector2(20,27), Vector2(27,27)]},
	],

	# =============================================== ГАРАЖ · КОСМЕТИКА (cos_*)
	"cos_camo_none": [
		{"op": "line", "a": Vector2(14,14), "b": Vector2(50,14), "w": 5},
		{"op": "line", "a": Vector2(50,14), "b": Vector2(50,50), "w": 5},
		{"op": "line", "a": Vector2(50,50), "b": Vector2(14,50), "w": 5},
		{"op": "line", "a": Vector2(14,50), "b": Vector2(14,14), "w": 5},
	],
	"cos_camo_digital": [ # пиксельная сетка — цифровой камуфляж
		{"op": "rect", "c": Vector2(16,16), "size": Vector2(14,14), "rot": 0},
		{"op": "rect", "c": Vector2(44,16), "size": Vector2(14,14), "rot": 0},
		{"op": "rect", "c": Vector2(30,30), "size": Vector2(14,14), "rot": 0},
		{"op": "rect", "c": Vector2(16,44), "size": Vector2(14,14), "rot": 0},
		{"op": "rect", "c": Vector2(44,44), "size": Vector2(14,14), "rot": 0},
	],
	"cos_camo_splinter": [ # угловатые осколки — осколочный камуфляж
		{"op": "poly", "pts": [Vector2(6,10), Vector2(30,6), Vector2(22,26), Vector2(4,30)]},
		{"op": "poly", "pts": [Vector2(36,4), Vector2(58,14), Vector2(42,30), Vector2(30,20)]},
		{"op": "poly", "pts": [Vector2(8,38), Vector2(26,34), Vector2(30,54), Vector2(10,60)]},
		{"op": "poly", "pts": [Vector2(38,36), Vector2(60,40), Vector2(56,60), Vector2(34,56)]},
	],
	"cos_camo_tiger": [ # диагональные полосы — тигр
		{"op": "rect", "c": Vector2(16,20), "size": Vector2(36,8), "rot": -24},
		{"op": "rect", "c": Vector2(32,36), "size": Vector2(40,8), "rot": -24},
		{"op": "rect", "c": Vector2(46,52), "size": Vector2(30,8), "rot": -24},
	],
	"cos_camo_desert": [ # барханы и солнце — пустыня
		{"op": "arc", "c": Vector2(16,60), "r": 26, "a0": -60, "a1": 0, "w": 8},
		{"op": "arc", "c": Vector2(50,60), "r": 26, "a0": 180, "a1": 240, "w": 8},
		{"op": "circle", "c": Vector2(48,16), "r": 10, "fill": true},
	],
	"cos_camo_urban": [ # силуэт города — город
		{"op": "rect", "c": Vector2(12,44), "size": Vector2(14,32), "rot": 0},
		{"op": "rect", "c": Vector2(28,36), "size": Vector2(14,48), "rot": 0},
		{"op": "rect", "c": Vector2(44,48), "size": Vector2(14,24), "rot": 0},
		{"op": "rect", "c": Vector2(58,42), "size": Vector2(10,36), "rot": 0},
	],
	"cos_camo_winter": [ # снежинка — зима
		{"op": "line", "a": Vector2(32,6), "b": Vector2(32,58), "w": 6},
		{"op": "line", "a": Vector2(8,19), "b": Vector2(56,45), "w": 6},
		{"op": "line", "a": Vector2(8,45), "b": Vector2(56,19), "w": 6},
		{"op": "circle", "c": Vector2(32,32), "r": 6, "fill": true},
	],
	"cos_hull_none": [
		{"op": "line", "a": Vector2(14,14), "b": Vector2(50,14), "w": 5},
		{"op": "line", "a": Vector2(50,14), "b": Vector2(50,50), "w": 5},
		{"op": "line", "a": Vector2(50,50), "b": Vector2(14,50), "w": 5},
		{"op": "line", "a": Vector2(14,50), "b": Vector2(14,14), "w": 5},
	],
	"cos_hull_stripes": [ # диагональные полосы — камуфляж корпуса
		{"op": "rect", "c": Vector2(20,20), "size": Vector2(50,8), "rot": -30},
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(50,8), "rot": -30},
		{"op": "rect", "c": Vector2(44,44), "size": Vector2(50,8), "rot": -30},
	],
	"cos_hull_star": [ # пятиконечная звезда
		{"op": "poly", "pts": [Vector2(32,4), Vector2(40,24), Vector2(60,24), Vector2(44,38), Vector2(50,58), Vector2(32,46), Vector2(14,58), Vector2(20,38), Vector2(4,24), Vector2(24,24)]},
	],
	"cos_hull_flames": [ # пламя
		{"op": "poly", "pts": [Vector2(32,4), Vector2(44,22), Vector2(40,30), Vector2(48,36), Vector2(44,54), Vector2(32,60), Vector2(20,54), Vector2(16,38), Vector2(24,34), Vector2(20,22)]},
	],
	"cos_hull_cross": [ # крест
		{"op": "poly", "pts": [Vector2(22,6), Vector2(42,6), Vector2(42,22), Vector2(58,22), Vector2(58,42), Vector2(42,42), Vector2(42,58), Vector2(22,58), Vector2(22,42), Vector2(6,42), Vector2(6,22), Vector2(22,22)]},
	],
	"cos_hull_chevrons": [ # два шеврона — шевроны
		{"op": "line", "a": Vector2(10,16), "b": Vector2(32,32), "w": 8},
		{"op": "line", "a": Vector2(32,32), "b": Vector2(54,16), "w": 8},
		{"op": "line", "a": Vector2(10,40), "b": Vector2(32,56), "w": 8},
		{"op": "line", "a": Vector2(32,56), "b": Vector2(54,40), "w": 8},
	],
	"cos_track_none": [ # гусеница-капсула — стандартные
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(44,14), "rot": 0},
		{"op": "circle", "c": Vector2(16,32), "r": 11, "fill": true},
		{"op": "circle", "c": Vector2(48,32), "r": 11, "fill": true},
	],
	"cos_track_gold": [
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(44,14), "rot": 0},
		{"op": "circle", "c": Vector2(16,32), "r": 11, "fill": true},
		{"op": "circle", "c": Vector2(48,32), "r": 11, "fill": true},
		{"op": "circle", "c": Vector2(32,14), "r": 5, "fill": true},
	],
	"cos_track_steel": [
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(44,14), "rot": 0},
		{"op": "circle", "c": Vector2(16,32), "r": 11, "fill": true},
		{"op": "circle", "c": Vector2(48,32), "r": 11, "fill": true},
		{"op": "circle", "c": Vector2(32,14), "r": 5, "fill": true},
	],
	"cos_track_ruby": [
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(44,14), "rot": 0},
		{"op": "circle", "c": Vector2(16,32), "r": 11, "fill": true},
		{"op": "circle", "c": Vector2(48,32), "r": 11, "fill": true},
		{"op": "circle", "c": Vector2(32,14), "r": 5, "fill": true},
	],
	"cos_turret_none": [ # купол башни со стволом — стандартная
		{"op": "circle", "c": Vector2(32,30), "r": 20, "fill": true},
		{"op": "rect", "c": Vector2(50,30), "size": Vector2(24,8), "rot": 0},
	],
	"cos_turret_gold": [
		{"op": "circle", "c": Vector2(32,30), "r": 20, "fill": true},
		{"op": "rect", "c": Vector2(50,30), "size": Vector2(24,8), "rot": 0},
	],
	"cos_turret_red": [
		{"op": "circle", "c": Vector2(32,30), "r": 20, "fill": true},
		{"op": "rect", "c": Vector2(50,30), "size": Vector2(24,8), "rot": 0},
	],
	"cos_turret_night": [ # купол со стволом + полумесяц — ночная
		{"op": "circle", "c": Vector2(32,30), "r": 20, "fill": true},
		{"op": "rect", "c": Vector2(50,30), "size": Vector2(24,8), "rot": 0},
		{"op": "arc", "c": Vector2(20,14), "r": 8, "a0": 30, "a1": 330, "w": 4},
	],
}
