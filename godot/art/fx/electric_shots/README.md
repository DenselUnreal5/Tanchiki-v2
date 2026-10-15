# Электрический танк: пиксельные эффекты

Создано встроенным imagegen. PNG: 1774 × 887, RGBA с прозрачным фоном.
4 ряда по 8 кадров, слева направо, сверху вниз:
1. muzzle — 24 кадров/с, однократно.
2. projectile — 20 кадров/с, зациклено.
3. impact — 22 кадров/с, однократно.
4. discharge — 18 кадров/с, однократно.

Ресурс electric_shots.tres содержит 32 AtlasTexture и 4 анимации SpriteFrames.
Сцена electric_shots_preview.tscn повторяет анимации для просмотра (F6 в Godot).
Для игры назначьте ресурс узлу AnimatedSprite2D, Texture Filter = Nearest.
Начальный масштаб: 0.2–0.3, затем подберите под размер танка.
Направление первых двух рядов — вправо; точку выхода вспышки нужно совместить с дулом.

Это сгенерированный набор графики, не подключённый к боевой отрисовке.
Ячейки нарезаны с округлением до целых пикселей (221–222 px).
Перед интеграцией необходима проверка привязки и крайних частиц: некоторые
языки пламени и разряды доходят до границ ячеек, возможна подрезка.
PNG и структура атласа проверены; запуск сцены в Godot не проверен.

## Промпт генерации

Create a new pixel art VFX spritesheet matching the previously shown tank combat effects style, for a detailed top-down 1990s military pixel game. Transparent RGBA background. Landscape 2:1 canvas, requested 2048x1024. STRICT 8 columns x 4 rows of equal square cells, exactly 32 isolated sprites. Each row is a coherent 8-frame animation read left to right. Stable cell-center pivot, all sprites have 20% empty padding within their cell, no overlap across cells. Hard pixel edges, hand-crafted pixel clusters, dark colored outlines, limited palette, no antialiasing, no soft glow, no gradients, no text, no labels, no grid lines, no checkerboard, no scenery or tanks. Row 1 fires RIGHT; row 2 travels RIGHT with tail LEFT. Rows 3 and 4 are viewed straight down and expand around the cell center. Keep pixel scale and silhouettes consistent across the full sheet. Row 1: electric cannon muzzle flash, tiny icy white spark becomes a jagged right-facing blue electrical fork then fragments into tiny cyan sparks. Row 2: electric bolt travels RIGHT, compact white-cyan spearhead with branching angular cobalt lightning tail to the LEFT; eight changing bolt patterns, consistent length, no fire or smoke. Row 3: electric hit, white pinpoint expands into sharp radial branching cyan-blue lightning and detached square sparks, dissipating. Row 4: large radial electrical overload, central spark becomes bright white-cyan starburst with irregular branching lightning arms, then disintegrates into separated blue arcs and tiny sparks. Palette white, pale cyan, bright cyan, electric blue, cobalt, dark navy, occasional muted violet shadows. Crisp square stepped lightning, no smooth glow.
