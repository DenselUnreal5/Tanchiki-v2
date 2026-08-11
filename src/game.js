// ============================================================================
// game.js — связывает всё вместе: цикл, состояния, события.
//
// Отличие от старой версии принципиальное: там поведение достраивалось
// «обезьяньими патчами» в конце файла (_origUpdate, _origStartGame,
// _origEndGame...), из-за чего порядок инициализации был неочевиден, а часть
// логики просто не вызывалась. Здесь один явный конечный автомат состояний.
// ============================================================================

import { TICK_MS, MAX_STEPS_PER_FRAME } from './config.js';
import { generateLevel } from './map.js';
import { World } from './world.js';
import { Player } from './player.js';
import { Renderer } from './render.js';
import { Hud } from './hud.js';
import { Ui } from './ui.js';
import { Input, MouseAimScheme, KeyboardAimScheme } from './input.js';
import { connectOnline } from './net.js';
import { Audio } from './audio.js';
import { Profile } from './profile.js';
import { getAchievement } from './achievements.js';
import { perkName, perkIcon, getPerk } from './perks.js';
import { MenuScene } from './menuscene.js';

/** Состояния игры. */
const S = {
  MENU: 'menu',
  PLAYING: 'playing',
  PAUSED: 'paused',
  PERK: 'perk',
  GAMEOVER: 'gameover',
};

export class Game {
  constructor() {
    this.canvas = document.getElementById('game-canvas');
    this.hudRoot = document.getElementById('hud');

    this.state = S.MENU;
    this.profile = new Profile();
    this.audio = new Audio();
    this.input = new Input(this.canvas);
    this.renderer = new Renderer(this.canvas);
    this.hud = new Hud(this.hudRoot, this.renderer);
    this.menuScene = new MenuScene(document.getElementById('menu-scene'));

    /** @type {World|null} */
    this.world = null;
    /** @type {Player[]} */
    this.players = [];

    /** Онлайн-партия (null в одиночке). */
    this.net = null;
    /** Сколько кадров подряд не приходит снапшот — для индикатора пинга. */
    this.netStale = 0;

    /** Накопитель времени для фиксированного шага. */
    this.accumulator = 0;
    this.lastFrame = 0;
    /** Игрок, для которого сейчас открыт выбор перка. */
    this.perkPlayer = null;
    /** Суммарный урон за партию, для челленджа «Вампир». */
    this.matchDamage = 0;

    this.ui = new Ui({
      onStart: () => this.startMatch(),
      onRestart: () => this.startMatch(),
      onMenu: () => this.toMenu(),
      onResume: () => this.resume(),
      onPerkChosen: (player, id) => this.onPerkChosen(player, id),
      onSoundToggle: (on) => this.audio.setEnabled(on),
      onResetProgress: () => this.resetProgress(),
      onGarageChanged: () => this.ui.refreshProfile(this.profile),
      onOnline: (url) => this.startOnline(url),
      onDailyClaimed: ({ reward }) => {
        this.hud.addFeed(`Задание выполнено: +${reward} 🪙`, '#ffd700');
        this.audio.play('pickup');
        this.ui.refreshProfile(this.profile);
      },
    });

    this.#bindProfileEvents();
    this.#bindHotkeys();
    this.#bindResize();
    this.#bindVisibility();

    this.resize();
    this.ui.refreshProfile(this.profile);
    this.ui.showMenu(this.profile);
  }

  // ------------------------------------------------------------------ запуск
  run() {
    this.lastFrame = performance.now();
    let badFrames = 0;
    const frame = (now) => {
      try {
        this.tickFrame(now);
        badFrames = 0;
      } catch (error) {
        // Один сбойный кадр не должен навсегда останавливать игру. До 5 сбоев
        // подряд просто логируем и продолжаем; если ошибка стабильная —
        // показываем её вместо чёрного экрана.
        badFrames++;
        console.error('[tanchiki] ошибка кадра:', error);
        if (badFrames >= 5) this.#showFatal(error);
      }
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  }

  #showFatal(error) {
    const existing = document.getElementById('tanchiki-error');
    if (existing) existing.remove();
    const box = document.createElement('div');
    box.id = 'tanchiki-error';
    box.style.cssText =
      'position:fixed;inset:0;display:flex;align-items:center;justify-content:center;' +
      'background:rgba(5,5,5,0.96);color:#ff7777;font:14px/1.7 "Segoe UI",Arial,sans-serif;' +
      'padding:28px;text-align:center;white-space:pre-wrap;z-index:999999;' +
      'border-top:4px solid #cc4444;box-sizing:border-box';
    box.innerHTML =
      `<div><div style="font-size:18px;font-weight:700;color:#ff8888;margin-bottom:10px">` +
      `Игра остановилась из-за ошибки</div><div style="color:#ffdddd">` +
      `${String(error?.stack || error)}</div></div>`;
    document.body.appendChild(box);
  }

  // ------------------------------------------------------------------ размеры
  #bindResize() {
    window.addEventListener('resize', () => this.resize());
  }

  #bindVisibility() {
    document.addEventListener('visibilitychange', () => {
      if (document.hidden && this.state === S.PLAYING) this.pause();
    });
  }

  resize() {
    const w = Math.max(320, document.documentElement.clientWidth || window.innerWidth);
    const h = Math.max(240, document.documentElement.clientHeight || window.innerHeight);
    this.renderer.resize(w, h);
    this.menuScene.resize(w, h);
    this.layoutViewports();
    if (this.players.length) this.hud.layout(this.players);
  }

  /** Раскладка областей просмотра: один экран или вертикальный сплит. */
  layoutViewports() {
    const w = this.renderer.width;
    const h = this.renderer.height;
    if (this.players.length <= 1) {
      if (this.players[0]) this.players[0].viewport = { x: 0, y: 0, w, h };
      return;
    }
    const half = Math.floor(w / 2);
    this.players[0].viewport = { x: 0, y: 0, w: half, h };
    this.players[1].viewport = { x: half, y: 0, w: w - half, h };
  }

  // ------------------------------------------------------------------ горячие клавиши
  #bindHotkeys() {
    this.input.on('down', (code) => {
      if (
        code === 'Escape' &&
        (this.ui.isGalleryOpen ||
          this.ui.isGarageOpen ||
          this.ui.isStatsOpen ||
          this.ui.isAchievementsOpen ||
          this.ui.isDailyOpen)
      ) {
        this.ui.closeGallery();
        this.ui.closeGarage();
        this.ui.closeStats();
        this.ui.closeAchievements();
        this.ui.closeDaily();
        return;
      }
      if (code === 'KeyP' || code === 'Escape') {
        if (this.state === S.PLAYING) this.pause();
        else if (this.state === S.PAUSED) this.resume();
        return;
      }
      if (code === 'Tab' && (this.state === S.PLAYING || this.state === S.PAUSED)) {
        this.hud.toggleScoreboard(this.world);
      }
    });
  }

  // ------------------------------------------------------------------ профиль
  #bindProfileEvents() {
    this.profile.on('levelup', ({ levels }) => {
      const lvl = levels[levels.length - 1];
      this.hud.addFeed(`Уровень профиля ${lvl}!`, '#ffee55');
      this.audio.play('levelup');
      this.ui.refreshProfile(this.profile);
    });
    this.profile.on('unlock', ({ ids, reason }) => {
      for (const id of ids) {
        const label = reason === 'challenge' ? 'Челлендж выполнен' : 'Новый перк';
        this.hud.addFeed(`${label}: ${perkIcon(id)} ${perkName(id)}`, '#ff66ff');
      }
      this.hud.banner(`Открыт перк: ${ids.map((id) => perkName(id)).join(', ')}`, '#ff88ff');
      this.audio.play('unlock');
      this.ui.refreshProfile(this.profile);
    });
    this.profile.on('achievement', ({ ids, reward }) => {
      const names = ids.map((id) => {
        const a = getAchievement(id);
        return a ? `${a.icon} ${a.name}` : id;
      });
      this.hud.addFeed(`Достижение: ${names.join(', ')}`, '#ffd700');
      this.hud.banner(`Достижение! +${reward} 🪙`, '#ffd700');
      this.audio.play('unlock');
      this.ui.refreshProfile(this.profile);
    });
  }

  resetProgress() {
    this.profile.reset();
    this.ui.refreshProfile(this.profile);
    this.ui.showMenu(this.profile);
  }

  // ------------------------------------------------------------------ партия
  startMatch() {
    // Звук инициализируется здесь: это гарантированно жест пользователя.
    this.audio.init();
    this.audio.setEnabled(this.ui.soundOn);

    const s = this.ui.settings;
    const hotseat = s.gameType === 'hotseat';

    this.players = [
      new Player({
        index: 0,
        name: 'Игрок 1',
        colorKey: s.color1 ?? 'p1',
        scheme: new MouseAimScheme(this.input, !hotseat),
      }),
    ];
    if (hotseat) {
      this.players.push(
        new Player({
          index: 1,
          name: 'Игрок 2',
          colorKey: s.color2 ?? 'p2',
          scheme: new KeyboardAimScheme(this.input),
        }),
      );
    }
    for (const p of this.players) {
      p.resetForMatch();
      p.upgradeMods = this.profile.upgradeMods();
      p.cosmetics = this.profile.equippedCosmetics();
    }

    this.layoutViewports();

    const level = generateLevel(s.level, s.mode);
    this.world = new World({
      map: level.map,
      level,
      mode: s.mode,
      difficulty: s.difficulty,
      players: this.players,
      audio: this.audio,
      playerLevel: this.profile.globalLevel,
    });
    this.#bindWorldEvents(this.world);

    this.matchDamage = 0;
    this.accumulator = 0;
    this.lastFrame = performance.now();

    this.renderer.clearFloaters();
    this.hud.clearFeed();
    this.hud.build(this.players);
    this.hud.show();
    this.hud.addFeed(
      s.mode === 'ffa'
        ? 'Каждый за себя: наберите фраги первым'
        : s.mode === 'koth'
          ? 'Царь горы: переживите всех на тонущей карте'
          : s.mode === 'defense'
            ? 'Оборона: удерживайте базу от волн врагов'
            : 'Захват флага: везите чужие флаги на свою базу',
      '#88ff88',
    );

    this.ui.hideAllOverlays();
    this.profile.bumpStat('gamesPlayed', 1);

    for (const p of this.players) p.updateCamera();

    // Стартовый выбор перка — как в оригинале, но по одному на игрока.
    this.state = S.PLAYING;
    for (const p of this.players) p.pendingLevelUps++;
    this.#processPerkQueue();
  }

  // ------------------------------------------------------------------ онлайн
  /**
   * Подключается к онлайн-серверу и стартует партию после получения init.
   * @param {string} url ws://host:port
   */
  startOnline(url) {
    this.audio.init();
    this.audio.setEnabled(this.ui.soundOn);

    this.state = S.PLAYING;
    this.ui.hideAllOverlays();
    this.hud.clearFeed();

    const self = this;
    this.net = connectOnline(url, {
      onReady: (world, player) => self.#onlineReady(world, player),
      onFeed: (text, color) => self.hud.addFeed(text, color),
      onDamageNumber: (n) => self.renderer.addFloater(n.x, n.y, n.text, n.color),
      onFinish: (result) => self.#onlineFinish(result),
      onError: (msg) => {
        self.hud.addFeed(`⚠ ${msg}`, '#ff6666');
        setTimeout(() => {
          if (self.net && !self.net.ready) self.toMenu();
        }, 1500);
      },
    });
  }

  /** Сервер прислал init: строим локального игрока и показываем мир. */
  #onlineReady(world, player) {
    // Локальный игрок с мышью; схема используется только для чтения команд.
    const local = new Player({
      index: world.localIndex,
      name: player?.name ?? 'Вы',
      colorKey: world.localIndex === 0 ? 'p1' : 'p2',
      scheme: new MouseAimScheme(this.input, false),
    });
    local.tank = this.net.player.tank;
    local.pendingLevelUps = 0;
    this.players = [local];
    this.world = world;
    this.net.player = local;
    this.net.world = world;

    this.layoutViewports();
    this.hud.build(this.players);
    this.hud.show();
    for (const p of this.players) p.updateCamera();
    this.hud.addFeed('Подключено к серверу. Играем!', '#88ff88');
  }

  /** Каждый кадр в онлайне: отправляем команду, обновляем камеру. */
  #onlineTick() {
    if (!this.net || !this.net.ready || !this.net.player) return;
    const p = this.net.player;
    if (p.tank?.alive && this.state === S.PLAYING) {
      const cmd = p.scheme.readCommand(p);
      this.net.sendCommand(cmd);
    }
    for (const pl of this.players) pl.updateCamera();
  }

  #onlineFinish(result) {
    if (this.state === S.GAMEOVER) return;
    this.state = S.GAMEOVER;
    this.netStale = 0;
    this.hud.hide();
    // Сервер шлёт победу от лица первого игрока; пересчитываем для себя.
    const localIndex = this.world?.localIndex ?? this.net?.player?.index;
    const win = result.winnerPlayerIndex !== null ? result.winnerPlayerIndex === localIndex : result.victory;
    this.ui.showGameOver({ ...result, victory: win }, this.world, this.profile, false);
  }

  toMenu() {
    this.state = S.MENU;
    if (this.net) {
      this.net.ws?.close();
      this.net = null;
    }
    this.world = null;
    this.players = [];
    this.perkPlayer = null;
    this.hud.hide();
    this.hud.clearFeed();
    this.renderer.clearFloaters();
    this.input.clear();
    this.ui.refreshProfile(this.profile);
    this.ui.showMenu(this.profile);
  }
  pause() {
    if (this.state !== S.PLAYING) return;
    this.state = S.PAUSED;
    this.input.clear();
    this.ui.showPause();
  }

  resume() {
    if (this.state !== S.PAUSED) return;
    this.ui.hidePause();
    this.ui.closeGallery();
    this.state = S.PLAYING;
    this.lastFrame = performance.now();
    this.accumulator = 0;
  }

  // ------------------------------------------------------------------ события мира
  #bindWorldEvents(world) {
    world.on('feed', ({ text, color }) => this.hud.addFeed(text, color));

    world.on('damageNumber', ({ x, y, text, color }) => this.renderer.addFloater(x, y, text, color));

    world.on('kill', ({ victim, killer, suicide }) => {
      if (suicide || !killer) {
        this.hud.addFeed(`${victim.name} уничтожен`, '#888888');
        return;
      }
      const color = killer.owner ? '#88ff88' : victim.owner ? '#ff6666' : '#bbbbbb';
      this.hud.addFeed(`${killer.name} ▸ ${victim.name}`, color);
    });

    world.on('playerDied', ({ player }) => {
      this.profile.bumpStat('timesDied', 1);
      this.hud.addFeed(`${player.name}: танк уничтожен`, '#cc4444');
    });

    world.on('playerDamage', ({ amount }) => {
      this.matchDamage += amount;
      this.profile.bumpStat('damageInGame', Math.round(this.matchDamage));
      this.profile.bumpDaily('damage', Math.round(amount));
    });

    world.on('globalXP', ({ amount }) => this.profile.addXP(amount));

    world.on('reward', ({ kind, amount, name }) => {
      this.profile.addMoney(amount);
      this.profile.bumpDaily('coins', amount);
      if (kind === 'kill') this.profile.bumpDaily('kills', 1);
      if (kind === 'capture') this.profile.bumpDaily('captures', 1);
      if (kind === 'win') this.profile.bumpDaily('wins', 1);
      this.hud.addFeed(`+${amount} 🪙 ${rewardLabel(kind, name)}`, '#ffd54a');
    });

    world.on('stat', ({ key, value, mode }) => {
      this.profile.bumpStat(key, value);
      if (key === 'totalKills') this.profile.bumpDaily('kills', 1);
      if (key === 'healthPacksCollected') this.profile.bumpDaily('medkits', 1);
      if (key === 'cleanStreak' && mode === 'max') this.profile.bumpDailyMax('streak', value);
    });

    world.on('botPerk', ({ tank, perk }) => {
      this.hud.addFeed(`${tank.name} получил: ${perk.icon} ${perk.name}`, '#ffaa44');
    });

    world.on('sessionLevelUp', ({ player, levels }) => {
      this.audio.play('levelup');
      this.hud.addFeed(`${player.name}: уровень ${player.sessionLevel}!`, '#ffee55');
      void levels;
    });

    world.on('flag', ({ type, tank }) => {
      if (type === 'captured' && tank?.owner) this.hud.banner('Флаг захвачен!', '#ffee55', 90);
    });

    world.on('finish', (result) => this.#onFinish(result));
  }

  #onFinish(result) {
    this.state = S.GAMEOVER;
    if (result.victory) this.profile.bumpStat('gamesWon', 1);
    this.profile.bumpDaily('games', 1);
    this.profile.checkChallenges();
    this.profile.save();
    this.hud.hide();
    this.ui.refreshProfile(this.profile);
    this.ui.showGameOver(result, this.world, this.profile, this.players.length > 1);
  }

  // ------------------------------------------------------------------ перки
  /** Показывает выбор перка следующему игроку в очереди, если он есть. */
  #processPerkQueue() {
    if (this.state === S.GAMEOVER || this.state === S.MENU) return;
    const next = this.players.find((p) => p.pendingLevelUps > 0);
    if (!next) {
      if (this.state === S.PERK) {
        this.state = S.PLAYING;
        this.ui.hidePerkSelect();
        this.lastFrame = performance.now();
        this.accumulator = 0;
      }
      this.perkPlayer = null;
      return;
    }
    this.state = S.PERK;
    this.perkPlayer = next;
    const queueLeft = this.players.reduce((n, p) => n + p.pendingLevelUps, 0) - 1;
    this.ui.showPerkSelect(next, this.profile, queueLeft, this.world?.rng ?? Math.random);
  }

  onPerkChosen(player, perkId) {
    if (perkId) {
      player.equipPerk(perkId);
      const perk = getPerk(perkId);
      this.hud.addFeed(`${player.name} взял ${perk.icon} ${perk.name}`, '#ffee55');
    }
    player.pendingLevelUps = Math.max(0, player.pendingLevelUps - 1);
    this.#processPerkQueue();
  }

  // ------------------------------------------------------------------ цикл
  tickFrame(now) {
    const dt = Math.min(250, now - this.lastFrame);
    this.lastFrame = now;

    // Онлайн: локально не считаем симуляцию, только шлём команды и рисуем.
    if (this.state === S.PLAYING && this.net) {
      this.#onlineTick();
      this.renderer.updateFloaters();
    } else if (this.state === S.PLAYING && this.world) {
      this.accumulator += dt;
      let steps = 0;
      while (this.accumulator >= TICK_MS && steps < MAX_STEPS_PER_FRAME) {
        this.world.step();
        this.renderer.updateFloaters();
        this.accumulator -= TICK_MS;
        steps++;
        // Прерываем догон, если партия завершилась или открылся выбор перка.
        if (this.world.finished) break;
        if (this.players.some((p) => p.pendingLevelUps > 0)) break;
      }
      // Если накопилось слишком много — сбрасываем остаток, чтобы игра не
      // «догоняла» рывками после сворачивания окна.
      if (this.accumulator > TICK_MS * MAX_STEPS_PER_FRAME) this.accumulator = 0;

      if (!this.world.finished && this.players.some((p) => p.pendingLevelUps > 0)) {
        this.#processPerkQueue();
      }
    }

    if (this.state === S.MENU) {
      // Фон главного меню: дождь, молнии, танк на скале, горящие остовы.
      this.menuScene.update();
      this.menuScene.draw();
    } else if (this.world) {
      this.renderer.draw(this.world);
      if (this.state === S.PLAYING || this.state === S.PAUSED || this.state === S.PERK) {
        this.hud.update(this.world, this.profile);
      }
    }
  }
}

/** Текстовое пояснение награды для фида. */
function rewardLabel(kind, name) {
  if (kind === 'kill') return `за убийство (${name})`;
  if (kind === 'capture') return `за захват флага (${name})`;
  if (kind === 'win') return 'за победу';
  return 'награда';
}
