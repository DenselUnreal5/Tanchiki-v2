# Огнемёт: пиксельные эффекты

Создано встроенным imagegen. PNG: 1774 × 887, RGBA с прозрачным фоном.
4 ряда по 8 кадров, слева направо, сверху вниз:
1. muzzle — 24 кадров/с, однократно.
2. flame_stream — 20 кадров/с, зациклено.
3. impact — 18 кадров/с, однократно.
4. fire_burst — 14 кадров/с, однократно.

Ресурс flamethrower_shots.tres содержит 32 AtlasTexture и 4 анимации SpriteFrames.
Сцена flamethrower_shots_preview.tscn повторяет анимации для просмотра (F6 в Godot).
Для игры назначьте ресурс узлу AnimatedSprite2D, Texture Filter = Nearest.
Начальный масштаб: 0.2–0.3, затем подберите под размер танка.
Направление первых двух рядов — вправо; точку выхода вспышки нужно совместить с дулом.

Это сгенерированный набор графики, не подключённый к боевой отрисовке.
Ячейки нарезаны с округлением до целых пикселей (221–222 px).
Перед интеграцией необходима проверка привязки и крайних частиц: некоторые
языки пламени и разряды доходят до границ ячеек, возможна подрезка.
PNG и структура атласа проверены; запуск сцены в Godot не проверен.

## Промпт генерации

Create a new pixel art VFX spritesheet matching the previously shown tank combat effects style, for a detailed top-down 1990s military pixel game. Transparent RGBA background. Landscape 2:1 canvas, requested 2048x1024. STRICT 8 columns x 4 rows of equal square cells, exactly 32 isolated sprites. Each row is a coherent 8-frame animation read left to right. Stable cell-center pivot, all sprites have 20% empty padding within their cell, no overlap across cells. Hard pixel edges, hand-crafted pixel clusters, dark colored outlines, limited palette, no antialiasing, no soft glow, no gradients, no text, no labels, no grid lines, no checkerboard, no scenery or tanks. Row 1 fires RIGHT; row 2 travels RIGHT with tail LEFT. Rows 3 and 4 are viewed straight down and expand around the cell center. Keep pixel scale and silhouettes consistent across the full sheet. Row 1: flamethrower nozzle ignition, a tiny cream ignition grows into a short fierce rightward orange flame, then breaks into tiny embers. Row 2: sustained rightward flame jet animation, narrow base at left of cell opening into ragged broad flame tongues to the right, 8 equally sized flowing frames for looping fire, cream-yellow hot center, orange body and dark vermilion edges, NO metal projectile. Row 3: flame hitting a surface seen from overhead, bright flash blossoms into asymmetric curling fire tongues then dwindles to embers. Row 4: overhead napalm fire burst, ignition blooms into lobed rolling orange flame, charcoal smoke and final scattered embers. Palette cream, gold, amber, orange, deep red and warm charcoal gray. Distinct energetic flame silhouettes.
