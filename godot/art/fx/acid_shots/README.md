# Кислотный танк: пиксельные эффекты

Создано встроенным imagegen. PNG: 1774 × 887, RGBA с прозрачным фоном.
4 ряда по 8 кадров, слева направо, сверху вниз:
1. muzzle — 24 кадров/с, однократно.
2. projectile — 16 кадров/с, зациклено.
3. impact — 18 кадров/с, однократно.
4. acid_cloud — 12 кадров/с, однократно.

Ресурс acid_shots.tres содержит 32 AtlasTexture и 4 анимации SpriteFrames.
Сцена acid_shots_preview.tscn повторяет анимации для просмотра (F6 в Godot).
Для игры назначьте ресурс узлу AnimatedSprite2D, Texture Filter = Nearest.
Начальный масштаб: 0.2–0.3, затем подберите под размер танка.
Направление первых двух рядов — вправо; точку выхода вспышки нужно совместить с дулом.

Это сгенерированный набор графики, не подключённый к боевой отрисовке.
Ячейки нарезаны с округлением до целых пикселей (221–222 px).
Перед интеграцией необходима проверка привязки и крайних частиц: некоторые
языки пламени и разряды доходят до границ ячеек, возможна подрезка.
PNG и структура атласа проверены; запуск сцены в Godot не проверен.

## Промпт генерации

Create a new pixel art VFX spritesheet matching the previously shown tank combat effects style, for a detailed top-down 1990s military pixel game. Transparent RGBA background. Landscape 2:1 canvas, requested 2048x1024. STRICT 8 columns x 4 rows of equal square cells, exactly 32 isolated sprites. Each row is a coherent 8-frame animation read left to right. Stable cell-center pivot, all sprites have 20% empty padding within their cell, no overlap across cells. Hard pixel edges, hand-crafted pixel clusters, dark colored outlines, limited palette, no antialiasing, no soft glow, no gradients, no text, no labels, no grid lines, no checkerboard, no scenery or tanks. Row 1 fires RIGHT; row 2 travels RIGHT with tail LEFT. Rows 3 and 4 are viewed straight down and expand around the cell center. Keep pixel scale and silhouettes consistent across the full sheet. Row 1: acid cannon muzzle discharge, tiny pale yellow-green flash expands into a jagged lime jet then evaporates into olive vapor. Row 2: flying viscous green acid globule, bright pale lime core, dark emerald outline, trailing smaller green droplets and tiny vapor wisps, eight changing motion frames. Row 3: acid hit, compact initial contact turns into a radial splatter of green droplets then breaks apart. Row 4: large corrosive burst, small bubbling green spot blooms into an irregular overhead lime and emerald splash with olive vapor, then breaks into shrinking detached vapor puffs. Palette pale yellow-green highlights, vivid lime, emerald, dark forest green, muted olive smoke. Liquid, sticky and caustic, no orange fire.
