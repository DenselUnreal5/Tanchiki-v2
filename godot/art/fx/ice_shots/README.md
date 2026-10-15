# Ледяная пушка — эффекты

Создано встроенным imagegen. PNG 1774 × 887, RGBA с прозрачным фоном.
32 кадра: 4 строки по 8 кадров, слева направо.

1. muzzle — ледяная вспышка дула, 24 кадра/с, однократно.
2. ice_shards — залп из гранёных ледяных осколков вправо, 16 кадров/с, цикл.
3. impact — попадание с разлетающейся ледяной крошкой, 20 кадров/с, однократно.
4. freeze_loop — венец кристаллов вокруг замороженной цели, 10 кадров/с, цикл.

## Godot

Откройте ice_shots_preview.tscn и запустите F6 для просмотра.
Ресурс ice_shots.tres содержит SpriteFrames с 32 AtlasTexture.
Назначьте его AnimatedSprite2D, включите Texture Filter = Nearest.
Начальный масштаб 0.2–0.3; подберите отдельно для каждого эффекта.
Направление выстрела — вправо; совместите вспышку с дулом и вращайте по направлению ствола.
Для однократных эффектов удаляйте узел после animation_finished.

freeze_loop предназначен для наложения вокруг корпуса противника. Привяжите его
позицию к цели, подберите масштаб так, чтобы корпус оставался виден в центре.
Запускайте play("freeze_loop") при заморозке и убирайте эффект при снятии статуса,
гибели или удалении цели. Продолжительность задаёт игровой статус заморозки,
а не длина анимации: один цикл занимает 0.8 секунды и может повторяться любое время.
Сам набор графики не останавливает танк и не меняет баланс или длительность статуса.

## Проверка

PNG и структура атласа проверены. Запуск в Godot не проверен.
Эффекты пока не подключены к боевой отрисовке.
Это сгенерированный лист: ячейки нарезаны с округлением (221–222 px).
Перед интеграцией проверьте стабильность привязки, переход последнего кадра к первому,
прозрачность центра венца поверх реального танка и крайние частицы у границ ячеек.

## Промпт

Use case: stylized-concept. Create a pixel art ICE CANNON combat VFX spritesheet matching the detailed 1990s top-down military pixel-game effects sheets shown earlier. Genuine transparent RGBA background. Landscape 2:1 canvas, requested 2048x1024. STRICT 8 columns x 4 rows of equal square cells, exactly 32 isolated sprites, one frame in each cell. NO labels, grid, text, checkerboard, tanks or terrain. Every sprite must fit inside the central 65% of its own cell with generous fully transparent padding; no particles crossing into adjacent cells. Coherent 8-frame animations, left to right, consistent pivot and scale. Row 1 MUZZLE: rightward ice cannon muzzle discharge: tiny pale icy flash, expands into a jagged short burst of faceted ice chips and frost, then dissipates into separated tiny ice flecks. Row 2 ICE SHARDS: eight loopable frames of a compact volley of three pointed solid crystalline ice shards flying RIGHT, largest sharp shard leading, two smaller shards offset above and below, tiny frozen particle wake trailing LEFT. Clearly solid angular glassy blue ice crystals with white highlighted facets and dark desaturated blue edges, NOT lightning, fire or a liquid blob. Keep projectile silhouette and size consistent, only change small sparkle and trail details. Row 3 IMPACT: an ice shard strikes, initial white pinpoint grows into radial angular crystal shatter with chunky triangular ice fragments, then fragments scatter and disappear, top-down view. Row 4 FREEZE STATUS LOOP: eight consistent-size frames of a top-down ring/crown of irregular angular ice crystals encasing the perimeter of a frozen tank, BUT DO NOT DRAW THE TANK. Large completely transparent empty center in every frame so game tank remains visible beneath. Ring diameter stays identical, subtle shimmering highlights and tiny shifting frost specks make a seamless looping status effect; no growth or shrinking across this row. Can overlay on a frozen enemy for several seconds. Restrained palette snow white, pale ice blue, muted cyan, steel blue, deep desaturated navy outlines. Hand-placed chunky square pixel clusters, sharp stepped pixel edges, flat faceted shading. Match existing tank pixel-art scale. No soft gradients, no blurred glow, no smooth vector shapes, no electric forks, no smoke clouds. All 32 individual effects fully inside their cells.
