# Tank shot VFX

Создано встроенным imagegen. Исходный PNG с прозрачностью: 1774 × 887.
Это набор графики, ещё не подключённый к боевой отрисовке игры.

## Состав

8 кадров слева направо в каждой из 4 строк:
1. muzzle — вспышка дула и дым, 24 кадра/с.
2. projectile — снаряд со следом вправо, 16 кадров/с, цикл.
3. impact — попадание и искры, 18 кадров/с.
4. explosion — взрыв и рассеивание дыма, 14 кадров/с.

## Godot

Откройте tank_shots_preview.tscn для просмотра выбранных кадров.
Ресурс tank_shots.tres содержит 32 AtlasTexture и четыре анимации.
Назначьте его AnimatedSprite2D.sprite_frames и вызовите play("impact") и т. п.
Для одноразовых эффектов удаляйте узел по animation_finished.
Используйте Texture Filter = Nearest; начальный масштаб для игровых эффектов — около 0.2–0.3.
У вспышки и снаряда направление вправо; поворачивайте узел по направлению ствола.

Лист сгенерирован: границы ячеек округлены до целых пикселей (221–222 px).
Для окончательной интеграции стоит выровнять точку привязки вспышки к дулу и
проверить крайние искры на границах кадров в игре. Это не вручную выверенный атлас.
Сцена и ресурс подготовлены, но запуск в Godot не проверен: редактор не найден в PATH.

## Prompt

Use case: stylized-concept. Asset type: pixel art tank combat VFX animation spritesheet for a top-down 2D Godot game. Create a polished production asset on genuinely transparent background, exactly 1024x1024 pixels, a strict 8-column by 4-row grid of equal 128x256 cells. NO visible grid, text, labels, tanks, terrain or checkerboard. Every cell contains one centered isolated animation frame, consistent pivot and pixel size, ample transparent padding. Read frames left to right. Row 1: eight successive frames of a tank cannon muzzle flash pointed RIGHT, anchored at center of each cell, cream-white ignition, jagged gold-orange flame expands right then shrinks into little warm gray smoke wisps. Row 2: eight successive frames of an orange projectile with short ember and smoke wake trailing LEFT, pointed RIGHT, compact pointed cream core. Row 3: eight successive frames of shell impact viewed from directly above: pinpoint white flash grows into angular orange burst and radial gold sparks, then dissipates into warm charcoal smoke and tiny embers. Row 4: eight successive frames of larger explosive shell impact directly overhead: tiny ignition, bright fireball, lobed orange explosion, expanding dark gray smoke clusters, final separated fading smoke wisps. Style matches classic detailed 1990s top-down military tank pixel game with muted green tanks and grass, dark outlines, hand-placed blocky pixel clusters, restrained 12-color fire/smoke palette, no smooth gradients, no glow blur, no vector look, no antialiasing. Render logical pixels as crisp 2x2 pixel squares. Each sprite stays inside its own cell with at least 16 pixels of transparent margin. Same pivot per row, progressive coherent animation, striking silhouettes and readable at small game scale.
