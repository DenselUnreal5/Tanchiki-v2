# ============================================================================
# fonts.gd — шрифты игры. Автозагрузка «Fonts».
#
# Веб-версия рисует эмодзи (🔫 💥 🏆) прямо в интерфейсе. В Godot системный
# шрифт их не содержит, поэтому к основному шрифту цепляется запасной
# эмодзи-шрифт: Segoe UI Emoji на Windows, Noto/Apple на других системах.
# ============================================================================
extends Node

var regular: Font
var bold: Font
var emoji: Font

func _ready() -> void:
	emoji = _system(["Segoe UI Emoji", "Noto Color Emoji", "Apple Color Emoji", "Symbola"])
	var base := _system(["Segoe UI", "Tahoma", "DejaVu Sans", "Noto Sans", "Arial", "sans-serif"])
	base.fallbacks = [emoji]
	regular = base

	var b := FontVariation.new()
	b.base_font = base
	b.variation_embolden = 0.55
	b.fallbacks = [emoji]
	bold = b

func _system(names: Array) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f
