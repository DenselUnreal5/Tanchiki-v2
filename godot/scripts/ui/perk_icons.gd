@tool
class_name PerkIcons
extends RefCounted

static var ICONS := {
	"_default": [
		{"op": "circle", "c": Vector2(32, 32), "r": 18, "fill": false, "w": 6},
	],

	"rapid_fire": [
		{"op": "poly", "pts": [Vector2(6,4), Vector2(26,4), Vector2(44,12), Vector2(26,20), Vector2(6,20), Vector2(18,12)]},
		{"op": "poly", "pts": [Vector2(6,24), Vector2(26,24), Vector2(44,32), Vector2(26,40), Vector2(6,40), Vector2(18,32)]},
		{"op": "poly", "pts": [Vector2(6,44), Vector2(26,44), Vector2(44,52), Vector2(26,60), Vector2(6,60), Vector2(18,52)]},
	],
	"double_shot": [
		{"op": "line", "a": Vector2(10,32), "b": Vector2(38,18), "w": 6},
		{"op": "poly", "pts": [Vector2(34,8), Vector2(52,10), Vector2(40,24)]},
		{"op": "line", "a": Vector2(10,32), "b": Vector2(38,46), "w": 6},
		{"op": "poly", "pts": [Vector2(34,56), Vector2(52,54), Vector2(40,40)]},
	],
	"fan_shot": [
		{"op": "circle", "c": Vector2(32,32), "r": 6, "fill": true},
		{"op": "ring", "c": Vector2(32,32), "n": 3, "pts": [Vector2(32,32), Vector2(32,6), Vector2(44,16)]},
	],
	"explosive": [
		{"op": "poly", "pts": [Vector2(34,4), Vector2(46,22), Vector2(46,56), Vector2(22,56), Vector2(22,22)]},
		{"op": "poly", "pts": [Vector2(4,24), Vector2(14,16), Vector2(14,32), Vector2(4,40)]},
	],
	"piercing": [
		{"op": "poly", "pts": [Vector2(40,24), Vector2(56,32), Vector2(40,40), Vector2(28,40), Vector2(28,24)]},
		{"op": "line", "a": Vector2(6,26), "b": Vector2(20,26), "w": 4},
		{"op": "line", "a": Vector2(4,32), "b": Vector2(22,32), "w": 4},
		{"op": "line", "a": Vector2(6,38), "b": Vector2(20,38), "w": 4},
	],
	"heavy_shell": [
		{"op": "poly", "pts": [Vector2(52,32), Vector2(30,20), Vector2(30,44)]},
		{"op": "rect", "c": Vector2(18,32), "size": Vector2(26,10), "rot": 0},
		{"op": "poly", "pts": [Vector2(6,24), Vector2(18,32), Vector2(6,40)]},
	],
	"light_shell": [
		{"op": "rect", "c": Vector2(32,42), "size": Vector2(12,32), "rot": 0},
		{"op": "poly", "pts": [Vector2(26,26), Vector2(38,26), Vector2(32,4)]},
	],
	"siege": [
		{"op": "poly", "pts": [Vector2(24,52), Vector2(24,26), Vector2(32,6), Vector2(40,26), Vector2(40,52)]},
		{"op": "rect", "c": Vector2(32,56), "size": Vector2(22,8), "rot": 0},
	],
	"lumberjack": [
		{"op": "poly", "pts": [Vector2(22,10), Vector2(48,2), Vector2(58,18), Vector2(48,32), Vector2(22,24)]},
		{"op": "rect", "c": Vector2(16,50), "size": Vector2(8,46), "rot": -8},
	],
	"concrete_breaker": [
		{"op": "rect", "c": Vector2(32,8), "size": Vector2(8,14), "rot": 0},
		{"op": "poly", "pts": [Vector2(32,14), Vector2(44,30), Vector2(32,58), Vector2(20,30)]},
		{"op": "circle", "c": Vector2(32,26), "r": 4, "shade": true},
	],
	"can_opener": [
		{"op": "poly", "pts": [Vector2(46,6), Vector2(56,16), Vector2(24,48), Vector2(18,42)]},
		{"op": "rect", "c": Vector2(20,46), "size": Vector2(18,4), "rot": -45},
		{"op": "rect", "c": Vector2(14,52), "size": Vector2(14,10), "rot": 45},
	],
	"coolant": [
		{"op": "poly", "pts": [Vector2(10,24), Vector2(26,24), Vector2(40,10), Vector2(40,54), Vector2(26,40), Vector2(10,40)]},
		{"op": "line", "a": Vector2(48,20), "b": Vector2(58,20), "w": 4},
		{"op": "line", "a": Vector2(48,32), "b": Vector2(60,32), "w": 4},
		{"op": "line", "a": Vector2(48,44), "b": Vector2(58,44), "w": 4},
	],
	"overclock": [
		{"op": "poly", "pts": [Vector2(6,54), Vector2(6,44), Vector2(58,10)]},
		{"op": "line", "a": Vector2(30,26), "b": Vector2(56,10), "w": 6},
		{"op": "poly", "pts": [Vector2(40,6), Vector2(60,8), Vector2(52,26)]},
	],
	"heat_sink": [
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(52,4), "rot": 0},
		{"op": "rect", "c": Vector2(32,60), "size": Vector2(52,4), "rot": 0},
		{"op": "rect", "c": Vector2(14,32), "size": Vector2(7,52), "rot": 0},
		{"op": "rect", "c": Vector2(25,32), "size": Vector2(7,52), "rot": 0},
		{"op": "rect", "c": Vector2(36,32), "size": Vector2(7,52), "rot": 0},
		{"op": "rect", "c": Vector2(47,32), "size": Vector2(7,52), "rot": 0},
		{"op": "rect", "c": Vector2(58,32), "size": Vector2(7,52), "rot": 0},
	],
	"thermal": [
		{"op": "rect", "c": Vector2(32,26), "size": Vector2(12,36), "rot": 0},
		{"op": "circle", "c": Vector2(32,48), "r": 13, "fill": true},
	],
	"quick_vent": [
		{"op": "rect", "c": Vector2(32,20), "size": Vector2(10,28), "rot": 0},
		{"op": "poly", "pts": [Vector2(16,36), Vector2(48,36), Vector2(32,58)]},
	],
	"nitro": [
		{"op": "poly", "pts": [Vector2(32,2), Vector2(40,14), Vector2(44,26), Vector2(44,48), Vector2(20,48), Vector2(20,26), Vector2(24,14)]},
		{"op": "poly", "pts": [Vector2(20,40), Vector2(6,56), Vector2(20,56)]},
		{"op": "poly", "pts": [Vector2(44,40), Vector2(58,56), Vector2(44,56)]},
		{"op": "poly", "pts": [Vector2(22,48), Vector2(32,64), Vector2(42,48)]},
	],
	"overdrive": [
		{"op": "rect", "c": Vector2(32,38), "size": Vector2(24,40), "rot": 0},
		{"op": "rect", "c": Vector2(32,14), "size": Vector2(12,12), "rot": 0},
		{"op": "rect", "c": Vector2(32,4), "size": Vector2(6,8), "rot": 0},
	],
	"bulwark": [
		{"op": "poly", "pts": [Vector2(32,6), Vector2(54,14), Vector2(54,32), Vector2(32,60), Vector2(10,32), Vector2(10,14)]},
		{"op": "rect", "c": Vector2(18,10), "size": Vector2(8,8), "rot": 0},
		{"op": "rect", "c": Vector2(32,6), "size": Vector2(8,10), "rot": 0},
		{"op": "rect", "c": Vector2(46,10), "size": Vector2(8,8), "rot": 0},
	],
	"shockwave": [
		{"op": "circle", "c": Vector2(32,32), "r": 6, "fill": true},
		{"op": "circle", "c": Vector2(32,32), "r": 18, "fill": false, "w": 5},
		{"op": "circle", "c": Vector2(32,32), "r": 29, "fill": false, "w": 5},
	],

	"heavy_armor": [
		{"op": "poly", "pts": [Vector2(32,4), Vector2(54,12), Vector2(54,30), Vector2(32,62), Vector2(10,30), Vector2(10,12)]},
	],
	"thick_armor": [
		{"op": "poly", "pts": [Vector2(32,6), Vector2(56,14), Vector2(56,32), Vector2(32,58), Vector2(8,32), Vector2(8,14)]},
		{"op": "rect", "c": Vector2(32,30), "size": Vector2(36,8), "rot": 0, "shade": true},
	],
	"shield": [
		{"op": "line", "a": Vector2(32,4), "b": Vector2(54,12), "w": 5},
		{"op": "line", "a": Vector2(54,12), "b": Vector2(54,30), "w": 5},
		{"op": "line", "a": Vector2(54,30), "b": Vector2(32,62), "w": 5},
		{"op": "line", "a": Vector2(32,62), "b": Vector2(10,30), "w": 5},
		{"op": "line", "a": Vector2(10,30), "b": Vector2(10,12), "w": 5},
		{"op": "line", "a": Vector2(10,12), "b": Vector2(32,4), "w": 5},
		{"op": "poly", "pts": [Vector2(36,14), Vector2(24,34), Vector2(32,34), Vector2(28,50), Vector2(44,28), Vector2(35,28)]},
	],
	"regen": [
		{"op": "poly", "pts": [Vector2(26,18), Vector2(38,18), Vector2(38,26), Vector2(46,26), Vector2(46,38), Vector2(38,38), Vector2(38,46), Vector2(26,46), Vector2(26,38), Vector2(18,38), Vector2(18,26), Vector2(26,26)]},
	],
	"reflect": [
		{"op": "line", "a": Vector2(8,20), "b": Vector2(32,44), "w": 6},
		{"op": "line", "a": Vector2(32,44), "b": Vector2(56,12), "w": 6},
		{"op": "poly", "pts": [Vector2(44,8), Vector2(60,10), Vector2(50,22)]},
	],
	"evasion": [
		{"op": "line", "a": Vector2(6,48), "b": Vector2(22,28), "w": 6},
		{"op": "line", "a": Vector2(22,28), "b": Vector2(38,44), "w": 6},
		{"op": "line", "a": Vector2(38,44), "b": Vector2(52,16), "w": 6},
		{"op": "poly", "pts": [Vector2(44,10), Vector2(60,12), Vector2(50,26)]},
	],
	"smoke": [
		{"op": "poly", "pts": [Vector2(18,46), Vector2(9,42), Vector2(8,32), Vector2(15,25), Vector2(16,15), Vector2(28,8), Vector2(40,12), Vector2(45,20), Vector2(54,22), Vector2(58,32), Vector2(54,42), Vector2(44,46)]},
	],
	"repair": [
		{"op": "line", "a": Vector2(20,44), "b": Vector2(44,20), "w": 9},
		{"op": "arc", "c": Vector2(14,50), "r": 11, "a0": 30, "a1": 300, "w": 9},
		{"op": "arc", "c": Vector2(50,14), "r": 11, "a0": 210, "a1": 480, "w": 9},
	],

	"sprinter": [
		{"op": "circle", "c": Vector2(38,10), "r": 7, "fill": true},
		{"op": "poly", "pts": [Vector2(30,20), Vector2(42,18), Vector2(46,32), Vector2(38,34), Vector2(34,26)]},
		{"op": "line", "a": Vector2(36,30), "b": Vector2(20,40), "w": 6},
		{"op": "line", "a": Vector2(20,40), "b": Vector2(10,36), "w": 6},
		{"op": "line", "a": Vector2(40,32), "b": Vector2(50,50), "w": 6},
		{"op": "line", "a": Vector2(50,50), "b": Vector2(44,60), "w": 6},
		{"op": "line", "a": Vector2(40,32), "b": Vector2(28,52), "w": 6},
		{"op": "line", "a": Vector2(28,52), "b": Vector2(34,60), "w": 6},
	],
	"road_king": [
		{"op": "rect", "c": Vector2(32,40), "size": Vector2(56,20), "rot": 0},
		{"op": "rect", "c": Vector2(14,40), "size": Vector2(8,4), "rot": 0, "shade": true},
		{"op": "rect", "c": Vector2(32,40), "size": Vector2(8,4), "rot": 0, "shade": true},
		{"op": "rect", "c": Vector2(50,40), "size": Vector2(8,4), "rot": 0, "shade": true},
	],
	"quick_reload": [
		{"op": "arc", "c": Vector2(32,32), "r": 22, "a0": -50, "a1": 220, "w": 7},
		{"op": "poly", "pts": [Vector2(48,10), Vector2(60,16), Vector2(46,22)]},
		{"op": "circle", "c": Vector2(32,32), "r": 5, "fill": true},
	],
	"all_terrain": [
		{"op": "rect", "c": Vector2(32,36), "size": Vector2(44,14), "rot": 0},
		{"op": "rect", "c": Vector2(28,24), "size": Vector2(20,12), "rot": 0},
		{"op": "circle", "c": Vector2(16,44), "r": 7, "fill": true},
		{"op": "circle", "c": Vector2(48,44), "r": 7, "fill": true},
	],
	"grip": [
		{"op": "rect", "c": Vector2(32,50), "size": Vector2(52,6), "rot": 0},
		{"op": "poly", "pts": [Vector2(14,44), Vector2(20,44), Vector2(17,26)]},
		{"op": "poly", "pts": [Vector2(29,44), Vector2(35,44), Vector2(32,20)]},
		{"op": "poly", "pts": [Vector2(44,44), Vector2(50,44), Vector2(47,26)]},
	],

	"mines": [
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
	"scavenger": [
		{"op": "poly", "pts": [Vector2(20,10), Vector2(26,2), Vector2(30,14), Vector2(34,14), Vector2(38,2), Vector2(44,10), Vector2(50,20), Vector2(50,38), Vector2(40,54), Vector2(24,54), Vector2(14,38), Vector2(14,20)]},
		{"op": "poly", "pts": [Vector2(20,26), Vector2(28,26), Vector2(24,34)], "shade": true},
		{"op": "poly", "pts": [Vector2(36,26), Vector2(44,26), Vector2(40,34)], "shade": true},
	],
	"keen_ear": [
		{"op": "poly", "pts": [Vector2(24,8), Vector2(42,10), Vector2(52,26), Vector2(48,46), Vector2(34,58), Vector2(26,50), Vector2(36,42), Vector2(38,28), Vector2(24,24)]},
	],
	"muffler": [
		{"op": "poly", "pts": [Vector2(32,8), Vector2(46,32), Vector2(46,40), Vector2(18,40), Vector2(18,32)]},
		{"op": "rect", "c": Vector2(32,46), "size": Vector2(36,6), "rot": 0},
		{"op": "line", "a": Vector2(10,14), "b": Vector2(54,50), "w": 5},
	],
	"breaker": [
		{"op": "poly", "pts": [Vector2(44,32), Vector2(22,20), Vector2(22,44)]},
		{"op": "poly", "pts": [Vector2(14,32), Vector2(19,20), Vector2(24,32), Vector2(19,44)]},
	],
	"silencer": [
		{"op": "rect", "c": Vector2(38,28), "size": Vector2(40,8), "rot": 0},
		{"op": "rect", "c": Vector2(8,28), "size": Vector2(14,14), "rot": 0},
		{"op": "poly", "pts": [Vector2(8,35), Vector2(16,35), Vector2(16,54), Vector2(8,54)]},
	],
	"ram": [
		{"op": "rect", "c": Vector2(30,36), "size": Vector2(36,20), "rot": 0},
		{"op": "rect", "c": Vector2(30,20), "size": Vector2(18,12), "rot": 0},
		{"op": "poly", "pts": [Vector2(48,26), Vector2(60,32), Vector2(48,46)]},
		{"op": "circle", "c": Vector2(18,50), "r": 7, "fill": true},
		{"op": "circle", "c": Vector2(42,50), "r": 7, "fill": true},
	],
	"amphibious": [
		{"op": "poly", "pts": [Vector2(10,30), Vector2(54,30), Vector2(46,44), Vector2(18,44)]},
		{"op": "rect", "c": Vector2(32,20), "size": Vector2(6,20), "rot": 0},
		{"op": "poly", "pts": [Vector2(35,10), Vector2(50,20), Vector2(35,24)]},
		{"op": "line", "a": Vector2(6,52), "b": Vector2(16,52), "w": 4},
		{"op": "line", "a": Vector2(20,52), "b": Vector2(30,52), "w": 4},
		{"op": "line", "a": Vector2(34,52), "b": Vector2(44,52), "w": 4},
		{"op": "line", "a": Vector2(48,52), "b": Vector2(58,52), "w": 4},
	],
	"forest": [
		{"op": "poly", "pts": [Vector2(32,4), Vector2(46,24), Vector2(37,24), Vector2(50,42), Vector2(39,42), Vector2(32,54), Vector2(25,42), Vector2(14,42), Vector2(27,24), Vector2(18,24)]},
		{"op": "rect", "c": Vector2(32,58), "size": Vector2(8,10), "rot": 0},
	],
	"deep_freeze": [
		{"op": "line", "a": Vector2(32,8), "b": Vector2(32,56), "w": 5},
		{"op": "line", "a": Vector2(8,32), "b": Vector2(56,32), "w": 5},
		{"op": "line", "a": Vector2(15,15), "b": Vector2(49,49), "w": 5},
		{"op": "line", "a": Vector2(49,15), "b": Vector2(15,49), "w": 5},
		{"op": "poly", "pts": [Vector2(32,24), Vector2(40,32), Vector2(32,40), Vector2(24,32)]},
	],
	"frost_dash": [
		{"op": "poly", "pts": [Vector2(44,32), Vector2(24,14), Vector2(30,32), Vector2(24,50)]},
		{"op": "poly", "pts": [Vector2(30,32), Vector2(10,14), Vector2(16,32), Vector2(10,50)]},
		{"op": "line", "a": Vector2(4,22), "b": Vector2(14,22), "w": 3},
		{"op": "line", "a": Vector2(2,32), "b": Vector2(12,32), "w": 3},
		{"op": "line", "a": Vector2(4,42), "b": Vector2(14,42), "w": 3},
	],
	"chilled_barrel": [
		{"op": "rect", "c": Vector2(12,32), "size": Vector2(12,22), "rot": 0},
		{"op": "rect", "c": Vector2(34,32), "size": Vector2(32,10), "rot": 0},
		{"op": "rect", "c": Vector2(52,32), "size": Vector2(8,16), "rot": 0},
		{"op": "poly", "pts": [Vector2(24,37), Vector2(28,37), Vector2(26,52)]},
		{"op": "poly", "pts": [Vector2(34,37), Vector2(38,37), Vector2(36,56)]},
		{"op": "poly", "pts": [Vector2(44,37), Vector2(48,37), Vector2(46,50)]},
	],
	"corrosive_acid": [
		{"op": "rect", "c": Vector2(32,14), "size": Vector2(12,12), "rot": 0},
		{"op": "poly", "pts": [Vector2(26,20), Vector2(38,20), Vector2(50,46), Vector2(14,46)]},
		{"op": "circle", "c": Vector2(32,54), "r": 5, "fill": true},
	],
	"acid_cloud": [
		{"op": "circle", "c": Vector2(32,28), "r": 14, "fill": true},
		{"op": "circle", "c": Vector2(20,36), "r": 12, "fill": true},
		{"op": "circle", "c": Vector2(44,36), "r": 12, "fill": true},
		{"op": "circle", "c": Vector2(32,44), "r": 10, "fill": true},
		{"op": "circle", "c": Vector2(12,20), "r": 3, "fill": true},
		{"op": "circle", "c": Vector2(52,22), "r": 3, "fill": true},
	],
	"corroding_armor": [
		{"op": "poly", "pts": [Vector2(14,12), Vector2(32,8), Vector2(50,12), Vector2(52,34), Vector2(32,56), Vector2(12,34)]},
		{"op": "poly", "pts": [Vector2(28,16), Vector2(38,26), Vector2(30,34), Vector2(42,42), Vector2(32,48)], "shade": true},
	],
	"magnet": [
		{"op": "arc", "c": Vector2(32,30), "r": 20, "a0": 20, "a1": 160, "w": 12},
		{"op": "rect", "c": Vector2(15,46), "size": Vector2(10,20), "rot": 0},
		{"op": "rect", "c": Vector2(49,46), "size": Vector2(10,20), "rot": 0},
		{"op": "rect", "c": Vector2(15,54), "size": Vector2(10,6), "rot": 0},
		{"op": "rect", "c": Vector2(49,54), "size": Vector2(10,6), "rot": 0},
	],
	"sniper": [
		{"op": "rect", "c": Vector2(30,34), "size": Vector2(50,6), "rot": 0},
		{"op": "poly", "pts": [Vector2(8,32), Vector2(8,44), Vector2(0,50), Vector2(0,38)]},
		{"op": "rect", "c": Vector2(40,24), "size": Vector2(4,14), "rot": 0},
		{"op": "rect", "c": Vector2(40,17), "size": Vector2(18,6), "rot": 0},
	],
	"berserk": [
		{"op": "poly", "pts": [Vector2(24,6), Vector2(40,6), Vector2(50,20), Vector2(50,40), Vector2(38,56), Vector2(26,56), Vector2(14,40), Vector2(14,20)]},
		{"op": "circle", "c": Vector2(12,22), "r": 7},
		{"op": "circle", "c": Vector2(52,22), "r": 7},
		{"op": "poly", "pts": [Vector2(18,24), Vector2(28,20), Vector2(28,26)], "shade": true},
		{"op": "poly", "pts": [Vector2(46,24), Vector2(36,20), Vector2(36,26)], "shade": true},
		{"op": "rect", "c": Vector2(32,42), "size": Vector2(18,5), "rot": 0, "shade": true},
	],
	"kamikaze": [
		{"op": "poly", "pts": [Vector2(32,10), Vector2(42,22), Vector2(42,48), Vector2(22,48), Vector2(22,22)]},
		{"op": "poly", "pts": [Vector2(22,40), Vector2(10,54), Vector2(22,54)]},
		{"op": "poly", "pts": [Vector2(42,40), Vector2(54,54), Vector2(42,54)]},
		{"op": "poly", "pts": [Vector2(14,10), Vector2(22,2), Vector2(30,10), Vector2(22,18)]},
	],
	"turbo": [
		{"op": "circle", "c": Vector2(32,32), "r": 24, "fill": false, "w": 6},
		{"op": "circle", "c": Vector2(32,32), "r": 6, "fill": true},
		{"op": "ring", "c": Vector2(32,32), "n": 3, "pts": [Vector2(32,32), Vector2(32,10), Vector2(44,18)]},
	],
	"shadow": [
		{"op": "poly", "pts": [Vector2(16,58), Vector2(16,28), Vector2(20,14), Vector2(32,6), Vector2(44,14), Vector2(48,28), Vector2(48,58), Vector2(42,50), Vector2(36,58), Vector2(32,50), Vector2(28,58), Vector2(22,50)]},
	],
	"vampire": [
		{"op": "poly", "pts": [Vector2(32,6), Vector2(50,18), Vector2(50,36), Vector2(32,58), Vector2(14,36), Vector2(14,18)]},
		{"op": "poly", "pts": [Vector2(22,34), Vector2(30,34), Vector2(24,50)], "shade": true},
		{"op": "poly", "pts": [Vector2(42,34), Vector2(34,34), Vector2(40,50)], "shade": true},
	],

	"ach_first_blood": [
		{"op": "circle", "c": Vector2(32,32), "r": 26, "fill": false, "w": 6},
		{"op": "circle", "c": Vector2(32,32), "r": 14, "fill": false, "w": 6},
		{"op": "circle", "c": Vector2(32,32), "r": 5, "fill": true},
	],
	"ach_kill_10": [
		{"op": "line", "a": Vector2(10,16), "b": Vector2(32,40), "w": 10},
		{"op": "line", "a": Vector2(32,40), "b": Vector2(54,16), "w": 10},
	],
	"ach_kill_50": [
		{"op": "line", "a": Vector2(10,10), "b": Vector2(54,54), "w": 9},
		{"op": "line", "a": Vector2(54,10), "b": Vector2(10,54), "w": 9},
		{"op": "circle", "c": Vector2(10,10), "r": 6, "fill": true},
		{"op": "circle", "c": Vector2(54,10), "r": 6, "fill": true},
		{"op": "circle", "c": Vector2(10,54), "r": 6, "fill": true},
		{"op": "circle", "c": Vector2(54,54), "r": 6, "fill": true},
	],
	"ach_kill_250": [
		{"op": "poly", "pts": [Vector2(38,4), Vector2(58,20), Vector2(58,34), Vector2(30,34), Vector2(30,20)]},
		{"op": "rect", "c": Vector2(22,48), "size": Vector2(8,32), "rot": 20},
	],
	"ach_ram_10": [
		{"op": "poly", "pts": [Vector2(8,10), Vector2(8,54), Vector2(54,32)]},
		{"op": "rect", "c": Vector2(14,32), "size": Vector2(8,36), "rot": 0},
	],
	"ach_ram_50": [
		{"op": "poly", "pts": [Vector2(6,8), Vector2(6,56), Vector2(50,32)]},
		{"op": "rect", "c": Vector2(12,32), "size": Vector2(8,40), "rot": 0},
		{"op": "poly", "pts": [Vector2(50,32), Vector2(60,22), Vector2(58,32), Vector2(60,42)]},
	],
	"ach_bricks_100": [
		{"op": "rect", "c": Vector2(16,18), "size": Vector2(24,14), "rot": 0},
		{"op": "rect", "c": Vector2(44,18), "size": Vector2(24,14), "rot": 0},
		{"op": "rect", "c": Vector2(30,34), "size": Vector2(24,14), "rot": 0},
		{"op": "rect", "c": Vector2(6,34), "size": Vector2(16,14), "rot": 0},
		{"op": "rect", "c": Vector2(56,34), "size": Vector2(16,14), "rot": 0},
		{"op": "rect", "c": Vector2(16,50), "size": Vector2(24,14), "rot": 0},
		{"op": "rect", "c": Vector2(44,50), "size": Vector2(24,14), "rot": 0},
	],
	"ach_bricks_500": [
		{"op": "rect", "c": Vector2(18,44), "size": Vector2(20,16), "rot": -12},
		{"op": "rect", "c": Vector2(42,40), "size": Vector2(18,16), "rot": 10},
		{"op": "rect", "c": Vector2(30,54), "size": Vector2(22,14), "rot": 4},
		{"op": "rect", "c": Vector2(14,26), "size": Vector2(14,12), "rot": 18},
		{"op": "rect", "c": Vector2(46,24), "size": Vector2(14,12), "rot": -16},
		{"op": "rect", "c": Vector2(32,14), "size": Vector2(16,12), "rot": 6},
	],
	"ach_medkits_25": [
		{"op": "circle", "c": Vector2(32,32), "r": 26, "fill": false, "w": 6},
		{"op": "poly", "pts": [Vector2(26,16), Vector2(38,16), Vector2(38,26), Vector2(48,26), Vector2(48,38), Vector2(38,38), Vector2(38,48), Vector2(26,48), Vector2(26,38), Vector2(16,38), Vector2(16,26), Vector2(26,26)]},
	],
	"ach_medkits_100": [
		{"op": "poly", "pts": [Vector2(24,10), Vector2(40,10), Vector2(40,24), Vector2(54,24), Vector2(54,40), Vector2(40,40), Vector2(40,54), Vector2(24,54), Vector2(24,40), Vector2(10,40), Vector2(10,24), Vector2(24,24)]},
	],
	"ach_wins_5": [
		{"op": "poly", "pts": [Vector2(18,8), Vector2(46,8), Vector2(42,32), Vector2(32,40), Vector2(22,32)]},
		{"op": "arc", "c": Vector2(14,16), "r": 10, "a0": -90, "a1": 90, "w": 5},
		{"op": "arc", "c": Vector2(50,16), "r": 10, "a0": 90, "a1": 270, "w": 5},
		{"op": "rect", "c": Vector2(32,48), "size": Vector2(8,16), "rot": 0},
		{"op": "rect", "c": Vector2(32,58), "size": Vector2(24,6), "rot": 0},
	],
	"ach_wins_25": [
		{"op": "poly", "pts": [Vector2(10,26), Vector2(18,50), Vector2(46,50), Vector2(54,26), Vector2(44,38), Vector2(32,16), Vector2(20,38)]},
		{"op": "rect", "c": Vector2(32,54), "size": Vector2(44,8), "rot": 0},
	],
	"ach_games_10": [
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(56,26), "rot": 0},
		{"op": "circle", "c": Vector2(42,26), "r": 5, "fill": true},
		{"op": "circle", "c": Vector2(50,34), "r": 5, "fill": true},
	],
	"ach_games_50": [
		{"op": "rect", "c": Vector2(32,52), "size": Vector2(36,12), "rot": 0},
		{"op": "rect", "c": Vector2(32,34), "size": Vector2(10,30), "rot": 0},
		{"op": "circle", "c": Vector2(32,16), "r": 14, "fill": true},
	],
	"ach_long_20": [
		{"op": "circle", "c": Vector2(32,32), "r": 22, "fill": false, "w": 5},
		{"op": "line", "a": Vector2(32,2), "b": Vector2(32,18), "w": 5},
		{"op": "line", "a": Vector2(32,46), "b": Vector2(32,62), "w": 5},
		{"op": "line", "a": Vector2(2,32), "b": Vector2(18,32), "w": 5},
		{"op": "line", "a": Vector2(46,32), "b": Vector2(62,32), "w": 5},
	],
	"ach_lowhp_10": [
		{"op": "poly", "pts": [Vector2(16,50), Vector2(14,32), Vector2(20,24), Vector2(44,24), Vector2(50,32), Vector2(48,50)]},
		{"op": "rect", "c": Vector2(31,56), "size": Vector2(30,10), "rot": 0},
	],
	"ach_streak_10": [
		{"op": "line", "a": Vector2(32,4), "b": Vector2(54,12), "w": 5},
		{"op": "line", "a": Vector2(54,12), "b": Vector2(54,30), "w": 5},
		{"op": "line", "a": Vector2(54,30), "b": Vector2(32,62), "w": 5},
		{"op": "line", "a": Vector2(32,62), "b": Vector2(10,30), "w": 5},
		{"op": "line", "a": Vector2(10,30), "b": Vector2(10,12), "w": 5},
		{"op": "line", "a": Vector2(10,12), "b": Vector2(32,4), "w": 5},
		{"op": "poly", "pts": [Vector2(32,20), Vector2(35,28), Vector2(44,28), Vector2(37,33), Vector2(40,42), Vector2(32,37), Vector2(24,42), Vector2(27,33), Vector2(20,28), Vector2(29,28)]},
	],
	"ach_rapid_5": [
		{"op": "poly", "pts": [Vector2(32,2), Vector2(38,24), Vector2(60,20), Vector2(42,34), Vector2(54,54), Vector2(32,42), Vector2(10,54), Vector2(22,34), Vector2(4,20), Vector2(26,24)]},
	],
	"ach_bridge_defender": [
		{"op": "arc", "c": Vector2(32,50), "r": 26, "a0": 180, "a1": 360, "w": 7},
		{"op": "rect", "c": Vector2(14,52), "size": Vector2(8,20), "rot": 0},
		{"op": "rect", "c": Vector2(50,52), "size": Vector2(8,20), "rot": 0},
		{"op": "rect", "c": Vector2(32,50), "size": Vector2(56,6), "rot": 0},
	],
	"ach_demolition": [
		{"op": "rect", "c": Vector2(20,42), "size": Vector2(12,36), "rot": 0},
		{"op": "rect", "c": Vector2(32,42), "size": Vector2(12,36), "rot": 0},
		{"op": "rect", "c": Vector2(44,42), "size": Vector2(12,36), "rot": 0},
		{"op": "line", "a": Vector2(32,24), "b": Vector2(40,8), "w": 4},
		{"op": "circle", "c": Vector2(42,6), "r": 5, "fill": true},
	],
	"ach_demolition_master": [
		{"op": "circle", "c": Vector2(30,40), "r": 22, "fill": true},
		{"op": "line", "a": Vector2(40,22), "b": Vector2(50,8), "w": 5},
		{"op": "circle", "c": Vector2(52,6), "r": 6, "fill": false, "w": 4},
	],
	"ach_eagle_ear": [
		{"op": "poly", "pts": [Vector2(8,44), Vector2(20,30), Vector2(18,36), Vector2(30,22), Vector2(26,30), Vector2(40,16), Vector2(34,26), Vector2(50,10), Vector2(40,34), Vector2(56,30), Vector2(30,48), Vector2(18,52)]},
	],
	"ach_ability_50": [
		{"op": "poly", "pts": [Vector2(32,4), Vector2(38,28), Vector2(60,32), Vector2(38,36), Vector2(32,60), Vector2(26,36), Vector2(4,32), Vector2(26,28)]},
	],
	"ach_ability_250": [
		{"op": "circle", "c": Vector2(32,32), "r": 7, "fill": true},
		{"op": "ring", "c": Vector2(32,32), "n": 3, "pts": [Vector2(32,32), Vector2(32,4), Vector2(46,14)]},
	],
	"ach_damage_1000": [
		{"op": "poly", "pts": [Vector2(26,4), Vector2(38,4), Vector2(42,16), Vector2(42,40), Vector2(22,40), Vector2(22,16)]},
		{"op": "poly", "pts": [Vector2(22,40), Vector2(14,50), Vector2(22,50)]},
		{"op": "poly", "pts": [Vector2(42,40), Vector2(50,50), Vector2(42,50)]},
		{"op": "poly", "pts": [Vector2(20,58), Vector2(32,52), Vector2(44,58), Vector2(32,62)]},
	],
	"ach_boss_1": [
		{"op": "circle", "c": Vector2(32,36), "r": 22, "fill": true},
		{"op": "poly", "pts": [Vector2(10,30), Vector2(2,6), Vector2(20,20)]},
		{"op": "poly", "pts": [Vector2(54,30), Vector2(62,6), Vector2(44,20)]},
		{"op": "rect", "c": Vector2(32,38), "size": Vector2(34,8), "rot": 0, "shade": true},
	],
	"ach_boss_10": [
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(56,8), "rot": 45},
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(56,8), "rot": -45},
		{"op": "circle", "c": Vector2(32,32), "r": 6, "fill": true},
	],
	"ach_rank_sergeant": [
		{"op": "poly", "pts": [Vector2(8,26), Vector2(32,6), Vector2(56,26), Vector2(56,36), Vector2(32,18), Vector2(8,36)]},
		{"op": "poly", "pts": [Vector2(8,44), Vector2(32,24), Vector2(56,44), Vector2(56,54), Vector2(32,36), Vector2(8,54)]},
	],
	"ach_rank_general": [
		{"op": "poly", "pts": [Vector2(32,2), Vector2(39,24), Vector2(62,24), Vector2(43,38), Vector2(50,60), Vector2(32,47), Vector2(14,60), Vector2(21,38), Vector2(2,24), Vector2(25,24)]},
	],
	"ach_money_5000": [
		{"op": "poly", "pts": [Vector2(20,20), Vector2(44,20), Vector2(54,40), Vector2(46,58), Vector2(18,58), Vector2(10,40)]},
		{"op": "rect", "c": Vector2(32,14), "size": Vector2(10,10), "rot": 0},
		{"op": "circle", "c": Vector2(32,40), "r": 8, "shade": true},
	],
	"ach_money_20000": [
		{"op": "rect", "c": Vector2(32,44), "size": Vector2(52,28), "rot": 0},
		{"op": "arc", "c": Vector2(32,30), "r": 26, "a0": 180, "a1": 360, "w": 10},
		{"op": "rect", "c": Vector2(32,40), "size": Vector2(10,14), "rot": 0, "shade": true},
	],
	"ach_defense_wave_10": [
		{"op": "rect", "c": Vector2(32,42), "size": Vector2(36,36), "rot": 0},
		{"op": "rect", "c": Vector2(10,20), "size": Vector2(10,14), "rot": 0},
		{"op": "rect", "c": Vector2(54,20), "size": Vector2(10,14), "rot": 0},
		{"op": "rect", "c": Vector2(32,18), "size": Vector2(10,18), "rot": 0},
		{"op": "rect", "c": Vector2(32,36), "size": Vector2(20,6), "rot": 0, "shade": true},
	],

	"upg_dmg": [
		{"op": "rect", "c": Vector2(30,36), "size": Vector2(44,14), "rot": 0},
		{"op": "rect", "c": Vector2(8,36), "size": Vector2(16,20), "rot": 0},
		{"op": "poly", "pts": [Vector2(52,36), Vector2(64,26), Vector2(58,36), Vector2(64,46)]},
	],
	"upg_fire_rate": [
		{"op": "arc", "c": Vector2(32,32), "r": 22, "a0": -50, "a1": 220, "w": 8},
		{"op": "poly", "pts": [Vector2(48,8), Vector2(60,16), Vector2(46,22)]},
	],
	"upg_bullet_speed": [
		{"op": "poly", "pts": [Vector2(38,24), Vector2(56,32), Vector2(38,40), Vector2(24,40), Vector2(24,24)]},
		{"op": "line", "a": Vector2(4,24), "b": Vector2(16,24), "w": 5},
		{"op": "line", "a": Vector2(2,32), "b": Vector2(20,32), "w": 5},
		{"op": "line", "a": Vector2(4,40), "b": Vector2(16,40), "w": 5},
	],
	"upg_max_hp": [
		{"op": "line", "a": Vector2(32,4), "b": Vector2(54,12), "w": 6},
		{"op": "line", "a": Vector2(54,12), "b": Vector2(54,30), "w": 6},
		{"op": "line", "a": Vector2(54,30), "b": Vector2(32,62), "w": 6},
		{"op": "line", "a": Vector2(32,62), "b": Vector2(10,30), "w": 6},
		{"op": "line", "a": Vector2(10,30), "b": Vector2(10,12), "w": 6},
		{"op": "line", "a": Vector2(10,12), "b": Vector2(32,4), "w": 6},
	],
	"upg_damage_taken": [
		{"op": "poly", "pts": [Vector2(32,4), Vector2(54,16), Vector2(54,42), Vector2(32,60), Vector2(10,42), Vector2(10,16)]},
	],
	"upg_speed": [
		{"op": "poly", "pts": [Vector2(8,50), Vector2(8,14), Vector2(30,32)]},
		{"op": "poly", "pts": [Vector2(32,50), Vector2(32,14), Vector2(54,32)]},
	],
	"upg_ram": [
		{"op": "poly", "pts": [Vector2(8,10), Vector2(8,54), Vector2(50,32)]},
		{"op": "rect", "c": Vector2(14,32), "size": Vector2(8,40), "rot": 0},
		{"op": "line", "a": Vector2(50,32), "b": Vector2(60,22), "w": 5},
		{"op": "line", "a": Vector2(50,32), "b": Vector2(60,42), "w": 5},
	],
	"upg_pickup_radius": [
		{"op": "arc", "c": Vector2(32,30), "r": 20, "a0": 20, "a1": 160, "w": 12},
		{"op": "rect", "c": Vector2(15,46), "size": Vector2(10,20), "rot": 0},
		{"op": "rect", "c": Vector2(49,46), "size": Vector2(10,20), "rot": 0},
		{"op": "rect", "c": Vector2(15,54), "size": Vector2(10,6), "rot": 0},
		{"op": "rect", "c": Vector2(49,54), "size": Vector2(10,6), "rot": 0},
	],
	"upg_regen": [
		{"op": "circle", "c": Vector2(32,32), "r": 24, "fill": false, "w": 7},
		{"op": "poly", "pts": [Vector2(27,20), Vector2(37,20), Vector2(37,27), Vector2(44,27), Vector2(44,37), Vector2(37,37), Vector2(37,44), Vector2(27,44), Vector2(27,37), Vector2(20,37), Vector2(20,27), Vector2(27,27)]},
	],

	"cos_camo_none": [
		{"op": "line", "a": Vector2(14,14), "b": Vector2(50,14), "w": 5},
		{"op": "line", "a": Vector2(50,14), "b": Vector2(50,50), "w": 5},
		{"op": "line", "a": Vector2(50,50), "b": Vector2(14,50), "w": 5},
		{"op": "line", "a": Vector2(14,50), "b": Vector2(14,14), "w": 5},
	],
	"cos_camo_digital": [
		{"op": "rect", "c": Vector2(16,16), "size": Vector2(14,14), "rot": 0},
		{"op": "rect", "c": Vector2(44,16), "size": Vector2(14,14), "rot": 0},
		{"op": "rect", "c": Vector2(30,30), "size": Vector2(14,14), "rot": 0},
		{"op": "rect", "c": Vector2(16,44), "size": Vector2(14,14), "rot": 0},
		{"op": "rect", "c": Vector2(44,44), "size": Vector2(14,14), "rot": 0},
	],
	"cos_camo_splinter": [
		{"op": "poly", "pts": [Vector2(6,10), Vector2(30,6), Vector2(22,26), Vector2(4,30)]},
		{"op": "poly", "pts": [Vector2(36,4), Vector2(58,14), Vector2(42,30), Vector2(30,20)]},
		{"op": "poly", "pts": [Vector2(8,38), Vector2(26,34), Vector2(30,54), Vector2(10,60)]},
		{"op": "poly", "pts": [Vector2(38,36), Vector2(60,40), Vector2(56,60), Vector2(34,56)]},
	],
	"cos_camo_tiger": [
		{"op": "rect", "c": Vector2(16,20), "size": Vector2(36,8), "rot": -24},
		{"op": "rect", "c": Vector2(32,36), "size": Vector2(40,8), "rot": -24},
		{"op": "rect", "c": Vector2(46,52), "size": Vector2(30,8), "rot": -24},
	],
	"cos_camo_desert": [
		{"op": "arc", "c": Vector2(16,60), "r": 26, "a0": -60, "a1": 0, "w": 8},
		{"op": "arc", "c": Vector2(50,60), "r": 26, "a0": 180, "a1": 240, "w": 8},
		{"op": "circle", "c": Vector2(48,16), "r": 10, "fill": true},
	],
	"cos_camo_urban": [
		{"op": "rect", "c": Vector2(12,44), "size": Vector2(14,32), "rot": 0},
		{"op": "rect", "c": Vector2(28,36), "size": Vector2(14,48), "rot": 0},
		{"op": "rect", "c": Vector2(44,48), "size": Vector2(14,24), "rot": 0},
		{"op": "rect", "c": Vector2(58,42), "size": Vector2(10,36), "rot": 0},
	],
	"cos_camo_winter": [
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
	"cos_hull_stripes": [
		{"op": "rect", "c": Vector2(20,20), "size": Vector2(50,8), "rot": -30},
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(50,8), "rot": -30},
		{"op": "rect", "c": Vector2(44,44), "size": Vector2(50,8), "rot": -30},
	],
	"cos_hull_star": [
		{"op": "poly", "pts": [Vector2(32,4), Vector2(40,24), Vector2(60,24), Vector2(44,38), Vector2(50,58), Vector2(32,46), Vector2(14,58), Vector2(20,38), Vector2(4,24), Vector2(24,24)]},
	],
	"cos_hull_flames": [
		{"op": "poly", "pts": [Vector2(32,4), Vector2(44,22), Vector2(40,30), Vector2(48,36), Vector2(44,54), Vector2(32,60), Vector2(20,54), Vector2(16,38), Vector2(24,34), Vector2(20,22)]},
	],
	"cos_hull_cross": [
		{"op": "poly", "pts": [Vector2(22,6), Vector2(42,6), Vector2(42,22), Vector2(58,22), Vector2(58,42), Vector2(42,42), Vector2(42,58), Vector2(22,58), Vector2(22,42), Vector2(6,42), Vector2(6,22), Vector2(22,22)]},
	],
	"cos_hull_chevrons": [
		{"op": "line", "a": Vector2(10,16), "b": Vector2(32,32), "w": 8},
		{"op": "line", "a": Vector2(32,32), "b": Vector2(54,16), "w": 8},
		{"op": "line", "a": Vector2(10,40), "b": Vector2(32,56), "w": 8},
		{"op": "line", "a": Vector2(32,56), "b": Vector2(54,40), "w": 8},
	],
	"cos_track_none": [
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
	"cos_turret_none": [
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
	"cos_turret_night": [
		{"op": "circle", "c": Vector2(32,30), "r": 20, "fill": true},
		{"op": "rect", "c": Vector2(50,30), "size": Vector2(24,8), "rot": 0},
		{"op": "arc", "c": Vector2(20,14), "r": 8, "a0": 30, "a1": 330, "w": 4},
	],
	"cos_skin_none": [
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(36,44), "rot": 0},
	],
	"cos_skin_cyberpunk": [
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(38,38), "rot": 0},
		{"op": "poly", "pts": [Vector2(36,12), Vector2(24,32), Vector2(32,32), Vector2(28,52), Vector2(40,30), Vector2(32,30)]},
	],
	"cos_skin_magma": [
		{"op": "poly", "pts": [Vector2(32,8), Vector2(52,54), Vector2(12,54)]},
		{"op": "circle", "c": Vector2(32,36), "r": 8, "fill": true},
	],
	"cos_skin_steampunk": [
		{"op": "circle", "c": Vector2(32,32), "r": 18, "fill": false, "w": 6},
		{"op": "circle", "c": Vector2(32,32), "r": 8, "fill": true},
	],
	"cos_skin_void": [
		{"op": "arc", "c": Vector2(32,32), "r": 20, "a0": 0, "a1": 360, "w": 4},
		{"op": "poly", "pts": [Vector2(32,10), Vector2(36,28), Vector2(54,32), Vector2(36,36), Vector2(32,54), Vector2(28,36), Vector2(10,32), Vector2(28,28)]},
	],
	"cos_skin_dragon": [
		{"op": "poly", "pts": [Vector2(32,8), Vector2(50,22), Vector2(44,52), Vector2(32,60), Vector2(20,52), Vector2(14,22)]},
		{"op": "circle", "c": Vector2(32,32), "r": 6, "fill": true},
	],
	"cos_skin_toxic": [
		{"op": "circle", "c": Vector2(32,32), "r": 6, "fill": true},
		{"op": "arc", "c": Vector2(32,32), "r": 18, "a0": -30, "a1": 30, "w": 8},
		{"op": "arc", "c": Vector2(32,32), "r": 18, "a0": 90, "a1": 150, "w": 8},
		{"op": "arc", "c": Vector2(32,32), "r": 18, "a0": 210, "a1": 270, "w": 8},
	],
	"cos_skin_golden_emperor": [
		{"op": "poly", "pts": [Vector2(14,48), Vector2(50,48), Vector2(52,24), Vector2(40,36), Vector2(32,18), Vector2(24,36), Vector2(12,24)]},
		{"op": "circle", "c": Vector2(32,54), "r": 4, "fill": true},
	],
	"cos_skin_arctic_frost": [
		{"op": "line", "a": Vector2(32,10), "b": Vector2(32,54), "w": 6},
		{"op": "line", "a": Vector2(14,22), "b": Vector2(50,42), "w": 6},
		{"op": "line", "a": Vector2(14,42), "b": Vector2(50,22), "w": 6},
		{"op": "circle", "c": Vector2(32,32), "r": 5, "fill": true},
	],
	"cos_hull_skull": [
		{"op": "circle", "c": Vector2(32,24), "r": 16, "fill": true},
		{"op": "rect", "c": Vector2(32,44), "size": Vector2(18,12), "rot": 0},
	],
	"cos_hull_dragon_crest": [
		{"op": "poly", "pts": [Vector2(32,8), Vector2(48,22), Vector2(52,42), Vector2(32,56), Vector2(12,42), Vector2(16,22)]},
	],
	"cos_hull_biohazard": [
		{"op": "circle", "c": Vector2(32,32), "r": 6, "fill": true},
		{"op": "arc", "c": Vector2(32,32), "r": 18, "a0": -30, "a1": 30, "w": 6},
		{"op": "arc", "c": Vector2(32,32), "r": 18, "a0": 90, "a1": 150, "w": 6},
		{"op": "arc", "c": Vector2(32,32), "r": 18, "a0": 210, "a1": 270, "w": 6},
	],
	"cos_hull_lightning_bolt": [
		{"op": "poly", "pts": [Vector2(36,6), Vector2(18,30), Vector2(32,30), Vector2(26,58), Vector2(46,26), Vector2(32,26)]},
	],
	"cos_hull_shark_mouth": [
		{"op": "arc", "c": Vector2(32,24), "r": 20, "a0": 30, "a1": 150, "w": 8},
		{"op": "poly", "pts": [Vector2(20,38), Vector2(24,48), Vector2(28,38), Vector2(32,48), Vector2(36,38), Vector2(40,48), Vector2(44,38)]},
	],
	"cos_hull_wings": [
		{"op": "poly", "pts": [Vector2(32,32), Vector2(8,16), Vector2(12,38)]},
		{"op": "poly", "pts": [Vector2(32,32), Vector2(56,16), Vector2(52,38)]},
	],
	"cos_hull_bullseye": [
		{"op": "circle", "c": Vector2(32,32), "r": 20, "fill": false, "w": 4},
		{"op": "circle", "c": Vector2(32,32), "r": 12, "fill": false, "w": 4},
		{"op": "circle", "c": Vector2(32,32), "r": 4, "fill": true},
	],
	"cos_track_neon_cyan": [
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(44,14), "rot": 0},
		{"op": "line", "a": Vector2(10,32), "b": Vector2(54,32), "w": 4},
	],
	"cos_track_magma_track": [
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(44,14), "rot": 0},
		{"op": "circle", "c": Vector2(32,18), "r": 6, "fill": true},
	],
	"cos_track_plasma": [
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(44,14), "rot": 0},
		{"op": "circle", "c": Vector2(32,32), "r": 8, "fill": true},
	],
	"cos_track_emerald_track": [
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(44,14), "rot": 0},
		{"op": "circle", "c": Vector2(22,32), "r": 6, "fill": true},
		{"op": "circle", "c": Vector2(42,32), "r": 6, "fill": true},
	],
	"cos_track_carbon_track": [
		{"op": "rect", "c": Vector2(32,32), "size": Vector2(44,14), "rot": 0},
	],
	"cos_turret_cyber_turret": [
		{"op": "circle", "c": Vector2(32,30), "r": 20, "fill": true},
		{"op": "rect", "c": Vector2(50,30), "size": Vector2(24,8), "rot": 0},
		{"op": "line", "a": Vector2(20,30), "b": Vector2(44,30), "w": 4},
	],
	"cos_turret_magma_turret": [
		{"op": "circle", "c": Vector2(32,30), "r": 20, "fill": true},
		{"op": "rect", "c": Vector2(50,30), "size": Vector2(24,8), "rot": 0},
		{"op": "circle", "c": Vector2(32,30), "r": 8, "fill": true},
	],
	"cos_turret_plasma_turret": [
		{"op": "circle", "c": Vector2(32,30), "r": 20, "fill": true},
		{"op": "rect", "c": Vector2(50,30), "size": Vector2(24,8), "rot": 0},
		{"op": "circle", "c": Vector2(32,30), "r": 6, "fill": false, "w": 4},
	],
	"cos_turret_steampunk_turret": [
		{"op": "circle", "c": Vector2(32,30), "r": 20, "fill": true},
		{"op": "rect", "c": Vector2(50,30), "size": Vector2(24,8), "rot": 0},
		{"op": "circle", "c": Vector2(32,30), "r": 8, "fill": false, "w": 3},
	],
	"cos_turret_chrome_turret": [
		{"op": "circle", "c": Vector2(32,30), "r": 20, "fill": true},
		{"op": "rect", "c": Vector2(50,30), "size": Vector2(24,8), "rot": 0},
		{"op": "arc", "c": Vector2(32,30), "r": 14, "a0": 180, "a1": 270, "w": 4},
	],
}

static var TEXTURE_PATHS := {
	"rapid_fire": "res://art/perks/rapid_fire.png",
	"double_shot": "res://art/perks/double_shot.png",
	"fan_shot": "res://art/perks/fan_shot.png",
	"explosive": "res://art/perks/explosive.png",
	"piercing": "res://art/perks/piercing.png",
	"heavy_armor": "res://art/perks/heavy_armor.png",
	"regen": "res://art/perks/regen.png",
	"reflect": "res://art/perks/reflect.png",
	"evasion": "res://art/perks/evasion.png",
	"shield": "res://art/perks/shield.png",
	"sprinter": "res://art/perks/sprinter.png",
	"mines": "res://art/perks/mines.png",
	"ram": "res://art/perks/ram.png",
	"thick_armor": "res://art/perks/thick_armor.png",
	"amphibious": "res://art/perks/amphibious.png",
	"magnet": "res://art/perks/magnet.png",
	"sniper": "res://art/perks/sniper.png",
	"berserk": "res://art/perks/berserk.png",
	"kamikaze": "res://art/perks/kamikaze.png",
	"turbo": "res://art/perks/turbo.png",
	"shadow": "res://art/perks/shadow.png",
	"vampire": "res://art/perks/vampire.png",
	"siege": "res://art/perks/siege.png",
	"nitro": "res://art/perks/nitro.png",
	"overdrive": "res://art/perks/overdrive.png",
	"bulwark": "res://art/perks/bulwark.png",
	"shockwave": "res://art/perks/shockwave.png",
	"heat_sink": "res://art/perks/heat_sink.png",
	"thermal": "res://art/perks/thermal.png",
	"quick_vent": "res://art/perks/quick_vent.png",
	"heavy_shell": "res://art/perks/heavy_shell.png",
	"light_shell": "res://art/perks/light_shell.png",
	"road_king": "res://art/perks/road_king.png",
	"all_terrain": "res://art/perks/all_terrain.png",
	"lumberjack": "res://art/perks/lumberjack.png",
	"concrete_breaker": "res://art/perks/concrete_breaker.png",
	"can_opener": "res://art/perks/can_opener.png",
	"scavenger": "res://art/perks/scavenger.png",
	"keen_ear": "res://art/perks/keen_ear.png",
	"muffler": "res://art/perks/muffler.png",
	"coolant": "res://art/perks/coolant.png",
	"overclock": "res://art/perks/overclock.png",
	"grip": "res://art/perks/grip.png",
	"breaker": "res://art/perks/breaker.png",
	"silencer": "res://art/perks/silencer.png",
	"smoke": "res://art/perks/smoke.png",
	"repair": "res://art/perks/repair.png",
	"quick_reload": "res://art/perks/quick_reload.png",
	"forest": "res://art/perks/forest.png",
	"predator": "res://art/perks/predator.png",
	"lightning_lord": "res://art/perks/lightning_lord.png",
	"sky_strike": "res://art/perks/sky_strike.png",
	"chain_lightning": "res://art/perks/chain_lightning.png",
	"deep_freeze": "res://art/perks/deep_freeze.png",
	"frost_dash": "res://art/perks/frost_dash.png",
	"chilled_barrel": "res://art/perks/chilled_barrel.png",
	"corrosive_acid": "res://art/perks/corrosive_acid.png",
	"acid_cloud": "res://art/perks/acid_cloud.png",
	"corroding_armor": "res://art/perks/corroding_armor.png",
	"acid_bomb": "res://art/perks/corrosive_acid.png",
	"bot_rapid": "res://art/perks/rapid_fire.png",
	"bot_speed": "res://art/perks/sprinter.png",
	"bot_tough": "res://art/perks/heavy_armor.png",
	"bot_double": "res://art/perks/double_shot.png",
	"bot_nitro": "res://art/perks/nitro.png",
	"bot_wave": "res://art/perks/shockwave.png",
	"bot_accurate": "res://art/perks/sniper.png",
	"bot_regen": "res://art/perks/regen.png",
	"bot_heavy": "res://art/perks/heavy_shell.png",
	"bot_evasion": "res://art/perks/evasion.png",
	"bot_lightning_lord": "res://art/perks/lightning_lord.png",
	"bot_sky_strike": "res://art/perks/sky_strike.png",
	"bot_chain_lightning": "res://art/perks/chain_lightning.png",
	"bot_boss_twin": "res://art/perks/bot_boss_twin.png",
	"bot_boss_barrage": "res://art/perks/bot_boss_barrage.png",
	"upg_dmg": "res://art/upgrades/dmg.png",
	"upg_fire_rate": "res://art/upgrades/fire_rate.png",
	"upg_bullet_speed": "res://art/upgrades/bullet_speed.png",
	"upg_max_hp": "res://art/upgrades/max_hp.png",
	"upg_damage_taken": "res://art/upgrades/damage_taken.png",
	"upg_speed": "res://art/upgrades/speed.png",
	"upg_ram": "res://art/upgrades/ram.png",
	"upg_pickup_radius": "res://art/upgrades/pickup_radius.png",
	"upg_regen": "res://art/upgrades/regen.png",
	"cannon_standard": "res://art/cannons/standard.png",
	"cannon_ice": "res://art/cannons/ice.png",
	"cannon_acid": "res://art/cannons/acid.png",
	"weapon_gatling": "res://art/weapons/gatling.png",
	"weapon_rockets": "res://art/weapons/rockets.png",
	"weapon_shotgun": "res://art/weapons/shotgun.png",
}

static var _textures := {}

static func make_view(id: String, px: float, color: Color = Color.WHITE) -> Control:
	var v := PerkIconView.new()
	v.perk_id = id
	v.icon_color = color
	v.icon_size = Vector2(px, px)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return v

static func texture_of(id: String) -> Texture2D:
	if not TEXTURE_PATHS.has(id):
		return null
	if not _textures.has(id):
		_textures[id] = load(TEXTURE_PATHS[id])
	return _textures[id]
