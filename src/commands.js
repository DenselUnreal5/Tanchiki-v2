// ============================================================================
// commands.js — единый формат команды управления танком.
//
// Локальная игра и сетевой режим используют одинаковые команды: клиент
// собирает их из клавиатуры/мыши, сервер (или локальная партия) применяет
// через applyCommand. Благодаря этому логика управления совпадает в одиночке,
// «горячем стуле» и онлайне — и её можно покрыть одними и теми же тестами.
// ============================================================================

/**
 * Собирает команду из состояния ввода для игрока.
 * Точка прицела уже переведена в мировые координаты (через личную камеру).
 * @param {import('./input.js').Input} input
 * @param {import('./player.js').Player} player
 * @returns {{mx:number, my:number, ax:number, ay:number, fire:boolean, mine:boolean, dash:boolean, airstrike:boolean}}
 */
export function buildCommand(input, player) {
  const i = input;
  let mx = 0;
  let my = 0;
  if (i.isDown('KeyW') || i.isDown('ArrowUp')) my -= 1;
  if (i.isDown('KeyS') || i.isDown('ArrowDown')) my += 1;
  if (i.isDown('KeyA') || i.isDown('ArrowLeft')) mx -= 1;
  if (i.isDown('KeyD') || i.isDown('ArrowRight')) mx += 1;

  const w = player.screenToWorld(i.mouse.x, i.mouse.y);
  return {
    mx,
    my,
    ax: w.x,
    ay: w.y,
    fire: i.mouse.left || i.isDown('Space'),
    mine: i.isDown('KeyE') || i.mouse.right,
    dash: i.isDown('ShiftLeft'),
    airstrike: i.isDown('KeyF'),
  };
}

/**
 * Применяет команду к танку. Вызывается локальными схемами и сетевым сервером.
 * @param {import('./tank.js').Tank} tank
 * @param {import('./world.js').World} world
 * @param {{mx:number, my:number, ax:number, ay:number, fire:boolean, mine:boolean, dash:boolean, airstrike:boolean}} cmd
 */
export function applyCommand(tank, world, cmd) {
  if (!tank || !tank.alive || !cmd) return;
  tank.thrust(cmd.mx, cmd.my);
  tank.aimAt(cmd.ax, cmd.ay);
  if (cmd.fire) tank.shoot(world);
  if (cmd.mine) tank.placeMine(world);
  if (cmd.dash) tank.dash();
  if (cmd.airstrike) world.triggerAirstrike?.(tank.owner);
}
