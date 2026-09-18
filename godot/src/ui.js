// ============================================================================
// ui.js — экраны вне игрового процесса: меню, пауза, выбор перка, галерея,
// итоги партии.
//
// Ui ничего не знает о правилах игры: он только показывает данные и сообщает
// о действиях пользователя через колбэки.
// ============================================================================

import { DIFFICULTY, MODES, MAX_EQUIPPED_PERKS } from './config.js';
import { PERKS, PERK_CATEGORIES, getPerk, perkIcon, unlockLevelOf, filterPerksForMode } from './perks.js';
import { UPGRADES, UPGRADE_CATEGORIES, upgradeCost } from './upgrades.js';
import { ACHIEVEMENTS } from './achievements.js';
import { dailySelection } from './daily.js';
import { ALL_COSMETICS, COSMETICS_BY_TYPE } from './cosmetics.js';
import { STAT_KEYS } from './profile.js';
import { defaultServerUrl, shuffled } from './utils.js';
import { t, dn, getLang, setLang, applyStatic } from './i18n.js';

/** Сколько вариантов показывать при повышении уровня. */
const PERK_CHOICES = 3;

/** Названия статистик для экрана «Статистика». */
const STAT_LABELS = {
  ramKills: 'Убийства тараном',
  bricksDestroyed: 'Разрушено кирпичей',
  waterEntries: 'Входов в воду',
  treesDriven: 'Смято деревьев',
  healthPacksCollected: 'Подобрано аптечек',
  gamesWon: 'Побед',
  gamesPlayed: 'Партий сыграно',
  timesDied: 'Смертей',
  totalKills: 'Всего убийств',
  rapidKills: 'Лучшее: убийств за 10 сек',
  cleanStreak: 'Лучшая серия без урона',
  damageInGame: 'Лучший урон за партию',
  longKills: 'Убийства с 400 px',
  lowHpKills: 'Убийства при HP ≤ 40%',
};

export class Ui {
  /**
   * @param {object} handlers
   * @param {() => void} handlers.onStart
   * @param {() => void} handlers.onRestart
   * @param {() => void} handlers.onMenu
   * @param {() => void} handlers.onResume
   * @param {(player: object, perkId: string|null) => void} handlers.onPerkChosen
   * @param {(on: boolean) => void} handlers.onSoundToggle
   * @param {() => void} handlers.onResetProgress
   */
  constructor(handlers) {
    this.h = handlers;
    this.settings = { gameType: 'single', mode: 'ffa', difficulty: 'medium', level: 1, color1: 'p1', color2: 'p2' };
    this.el = {
      menu: document.getElementById('menu'),
      menuInfo: document.getElementById('menu-info'),
      hints: document.getElementById('menu-hints'),
      menuSettings: document.getElementById('menu-settings'),
      menuModeBtn: document.getElementById('btn-select-mode'),
      pause: document.getElementById('pause'),
      gameover: document.getElementById('gameover'),
      goTitle: document.getElementById('go-title'),
      goBody: document.getElementById('go-body'),
      perkSelect: document.getElementById('perk-select'),
      perkBody: document.getElementById('perk-body'),
      gallery: document.getElementById('gallery'),
      galleryBody: document.getElementById('gallery-body'),
      gallerySub: document.getElementById('gallery-sub'),
      garage: document.getElementById('garage'),
      garageBody: document.getElementById('garage-body'),
      garageSub: document.getElementById('garage-sub'),
      stats: document.getElementById('stats'),
      statsBody: document.getElementById('stats-body'),
      statsSub: document.getElementById('stats-sub'),
      achievements: document.getElementById('achievements'),
      achievementsBody: document.getElementById('achievements-body'),
      achievementsSub: document.getElementById('achievements-sub'),
      daily: document.getElementById('daily'),
      dailyBody: document.getElementById('daily-body'),
      dailySub: document.getElementById('daily-sub'),
      soundBtn: document.getElementById('btn-sound'),
    };

    this.#bindMenu();
    this.#bindButtons();
    applyStatic();
    this.#refreshLangBtn();

    const onlineUrl = document.getElementById('online-url');
    if (onlineUrl && (!onlineUrl.value || onlineUrl.value === 'ws://localhost:8123')) {
      onlineUrl.value = defaultServerUrl();
    }
  }

  /** Подпись кнопки переключения языка: показывает целевой язык. */
  #refreshLangBtn() {
    const btn = document.getElementById('btn-lang');
    if (!btn) return;
    btn.textContent = getLang() === 'ru' ? t('menu.lang.ru', null, '🌐 English') : t('menu.lang.en', null, '🌐 Русский');
  }

  // ------------------------------------------------------------------ меню
  #bindMenu() {
    this.#bindGroup('group-gametype', 'gametype', (v) => {
      this.settings.gameType = v;
      this.#refreshHints();
    });
    this.#bindGroup('group-mode', 'mode', (v) => {
      this.settings.mode = v;
    });
    this.#bindGroup('group-diff', 'diff', (v) => {
      this.settings.difficulty = v;
    });
    this.#bindGroup('group-level', 'level', (v) => {
      this.settings.level = v === 'random' ? 'random' : Number(v);
    });
    this.#bindGroup('group-color1', 'color', (v) => {
      this.settings.color1 = v;
    });
    this.#bindGroup('group-color2', 'color', (v) => {
      this.settings.color2 = v;
    });
  }

  /** Группа кнопок-переключателей с одним активным значением. */
  #bindGroup(groupId, dataKey, onPick) {
    const group = document.getElementById(groupId);
    if (!group) return;
    group.addEventListener('click', (e) => {
      const btn = e.target.closest('button[data-' + dataKey + ']');
      if (!btn) return;
      for (const b of group.querySelectorAll('button')) b.classList.remove('active');
      btn.classList.add('active');
      onPick(btn.dataset[dataKey]);
    });
  }

  #bindButtons() {
    const on = (id, fn) => document.getElementById(id)?.addEventListener('click', fn);
    on('btn-start', () => this.h.onStart());
    on('btn-select-mode', () => {
      const open = this.el.menuSettings.classList.toggle('open');
      this.el.menuModeBtn.classList.toggle('open', open);
    });
    on('btn-restart', () => this.h.onRestart());
    on('btn-tomenu', () => this.h.onMenu());
    on('btn-resume', () => this.h.onResume());
    on('btn-pause-menu', () => this.h.onMenu());
    on('btn-pause-gallery', () => this.openGallery());
    on('btn-gallery', () => this.openGallery());
    on('btn-gallery-close', () => this.closeGallery());
    on('btn-garage', () => this.openGarage());
    on('btn-garage-close', () => this.closeGarage());
    on('btn-stats', () => this.openStats());
    on('btn-stats-close', () => this.closeStats());
    on('btn-achievements', () => this.openAchievements());
    on('btn-achievements-close', () => this.closeAchievements());
    on('btn-daily', () => this.openDaily());
    on('btn-daily-close', () => this.closeDaily());
    on('btn-sound', () => {
      this.soundOn = !this.soundOn;
      this.h.onSoundToggle(this.soundOn);
      this.#refreshSoundBtn();
    });
    on('btn-lang', () => this.switchLanguage());
    on('btn-reset', () => {
      if (window.confirm(t('confirm.reset', null, 'Сбросить весь прогресс профиля? Открытые перки будут потеряны.'))) {
        this.h.onResetProgress();
      }
    });
    on('btn-online', () => {
      const url = (document.getElementById('online-url')?.value || defaultServerUrl()).trim();
      this.h.onOnline(url);
    });
    this.soundOn = true;
    this.#refreshSoundBtn();
  }

  /** Переключение языка: применяет переводы и перерисовывает открытые экраны. */
  switchLanguage() {
    setLang(getLang() === 'ru' ? 'en' : 'ru');
    applyStatic();
    this.#refreshLangBtn();
    this.#refreshSoundBtn();
    this.#refreshHints();
    if (this.el.menuInfo) this.#refreshMenuInfo(this.lastProfile);
    if (this.isGalleryOpen) this.openGallery();
    if (this.isGarageOpen) this.openGarage();
    if (this.isStatsOpen) this.openStats();
    if (this.isAchievementsOpen) this.openAchievements();
    if (this.isDailyOpen) this.openDaily();
    if (this.lastGameOver) {
      const { result, world, profile, hotseat } = this.lastGameOver;
      this.showGameOver(result, world, profile, hotseat);
    }
  }

  #refreshSoundBtn() {
    if (this.el.soundBtn) this.el.soundBtn.textContent = this.soundOn ? t('menu.sound.on', null, '🔊 Звук') : t('menu.sound.off', null, '🔇 Звук');
  }

  /** Подсказки по управлению зависят от выбранного типа игры. */
  #refreshHints() {
    if (!this.el.hints) return;
    const p1 = [
      `<b>${t('player1', null, 'Игрок 1')}:</b> <kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> ${t('hint.p1.move', null, 'движение')}`,
      `<kbd>${t('hint.p1.aim', null, 'мышь')}</kbd> ${t('hint.p1.aim2', null, 'прицел')}`,
      `<kbd>ЛКМ</kbd> ${t('hint.p1.fire', null, 'выстрел')}`,
      `<kbd>E</kbd> ${t('hint.p1.mine', null, 'мина')}`,
    ];
    const p2 = [
      `<b>${t('player2', null, 'Игрок 2')}:</b> <kbd>↑</kbd><kbd>←</kbd><kbd>↓</kbd><kbd>→</kbd> ${t('hint.p1.move', null, 'движение')}`,
      `<kbd>&lt;</kbd> <kbd>&gt;</kbd> ${t('hint.p2.turret', null, 'башня')}`,
      `<kbd>Пр. Shift</kbd> ${t('hint.p1.fire', null, 'выстрел')}`,
      `<kbd>Num .</kbd> ${t('hint.p1.mine', null, 'мина')}`,
    ];
    const common = [
      `<kbd>P</kbd>/<kbd>Esc</kbd> ${t('hint.pause', null, 'пауза')}`,
      `<kbd>Tab</kbd> ${t('hint.scoreboard', null, 'табло')}`,
    ];
    const rows = [p1.join(' &nbsp;·&nbsp; ')];
    if (this.settings.gameType === 'hotseat') rows.push(p2.join(' &nbsp;·&nbsp; '));
    rows.push(common.join(' &nbsp;·&nbsp; '));
    this.el.hints.innerHTML = rows.map((r) => `<div>${r}</div>`).join('');
  }

  showMenu(profile) {
    this.#hideAll();
    this.el.menu.classList.add('visible');
    this.#refreshHints();
    this.#refreshMenuInfo(profile);
  }

  #refreshMenuInfo(profile) {
    if (!this.el.menuInfo) return;
    const need = profile.xpToNextLevel();
    const pct = Math.min(100, (profile.globalXP / need) * 100);
    this.el.menuInfo.innerHTML =
      `${t('menu.profile', null, 'Профиль: уровень')} <b>${profile.globalLevel}</b> &nbsp;·&nbsp; ` +
      `${profile.globalXP} / ${need} XP &nbsp;·&nbsp; ` +
      `${t('menu.perks', null, 'перков открыто')} <b>${profile.unlocked.size}</b> из ${PERKS.length}` +
      ` &nbsp;·&nbsp; ${t('menu.coins', null, 'монет')} <b>${profile.money} 🪙</b>` +
      `<div class="menu-progress"><div style="width:${pct}%"></div></div>`;
  }

  #hideAll() {
    for (const key of ['menu', 'pause', 'gameover', 'perkSelect', 'gallery', 'garage', 'stats', 'achievements', 'daily']) {
      this.el[key]?.classList.remove('visible');
    }
  }

  hideAllOverlays() {
    this.#hideAll();
  }

  // ------------------------------------------------------------------ пауза
  showPause() {
    this.el.pause.classList.add('visible');
  }

  hidePause() {
    this.el.pause.classList.remove('visible');
  }

  // ------------------------------------------------------------------ выбор перка
  /**
   * Показывает выбор перка для конкретного игрока.
   * @param {import('./player.js').Player} player
   * @param {import('./profile.js').Profile} profile
   * @param {number} queueLeft сколько ещё выборов в очереди
   */
  showPerkSelect(player, profile, queueLeft, rng = Math.random) {
    // В режимах с запретами (например, «Амфибия» в «Царе горы») не предлагаем
    // такие перки вовсе — иначе игрок получит перк, который просто не работает.
    const mode = this.settings.mode;
    const available = profile
      .availablePerkIds()
      .filter((id) => !player.hasPerk(id) && filterPerksForMode([id], mode).length > 0);
    const choices = shuffled(rngWrap(rng), available).slice(0, PERK_CHOICES);

    const body = this.el.perkBody;
    body.innerHTML = '';

    const head = document.createElement('div');
    head.className = 'perk-head';
    head.innerHTML =
      `<div class="perk-who">${escapeHtml(player.name)} — ${t('perk.level', null, 'уровень')} ${player.sessionLevel}</div>` +
      `<div class="perk-sub">${t('perk.profile', null, 'Профиль')} ${profile.globalLevel} &nbsp;·&nbsp; ` +
      `${t('perk.equipped', null, 'экипировано')} ${player.perkIds.length}/${MAX_EQUIPPED_PERKS}` +
      (queueLeft > 0 ? ` &nbsp;·&nbsp; ${t('perk.left', { n: queueLeft }, 'ещё выборов: {n}')}` : '') +
      `</div>`;
    body.appendChild(head);

    if (choices.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'perk-empty';
      empty.textContent =
        available.length === 0
          ? t('perk.empty.none', null, 'Пока нет открытых перков. Набирайте опыт профиля — они откроются.')
          : t('perk.empty.all', null, 'Все доступные перки уже экипированы.');
      body.appendChild(empty);
    } else {
      const grid = document.createElement('div');
      grid.className = 'perk-grid';
      for (const id of choices) {
        const perk = getPerk(id);
        const card = document.createElement('button');
        card.className = 'perk-card';
        card.innerHTML =
          `<div class="perk-icon">${perk.icon}</div>` +
          `<div class="perk-name">${escapeHtml(dn(perk, 'name', 'perk'))}</div>` +
          `<div class="perk-desc">${escapeHtml(dn(perk, 'desc', 'perk'))}</div>`;
        card.addEventListener('click', () => this.h.onPerkChosen(player, id));
        grid.appendChild(card);
      }
      body.appendChild(grid);
    }

    // Экипированные — можно снять. Пересчёт характеристик делает Player.
    if (player.perkIds.length > 0) {
      const wrap = document.createElement('div');
      wrap.className = 'perk-equipped';
      wrap.innerHTML = `<div class="perk-eq-label">${t('perk.eq.label', null, 'Экипировано (нажмите, чтобы снять)')}</div>`;
      const row = document.createElement('div');
      row.className = 'perk-eq-row';
      for (const id of [...player.perkIds]) {
        const perk = getPerk(id);
        if (!perk) continue;
        const chip = document.createElement('button');
        chip.className = 'perk-chip';
        chip.innerHTML = `<span>${perk.icon}</span> ${escapeHtml(dn(perk, 'name', 'perk'))} <span class="x">✕</span>`;
        chip.addEventListener('click', () => {
          player.unequipPerk(id);
          this.showPerkSelect(player, profile, queueLeft, rng);
        });
        row.appendChild(chip);
      }
      wrap.appendChild(row);
      body.appendChild(wrap);
    }

    const skip = document.createElement('button');
    skip.className = 'btn-secondary perk-skip';
    skip.textContent = t('perk.skip', null, 'Продолжить без выбора');
    skip.addEventListener('click', () => this.h.onPerkChosen(player, null));
    body.appendChild(skip);

    this.el.perkSelect.classList.add('visible');
  }

  hidePerkSelect() {
    this.el.perkSelect.classList.remove('visible');
  }

  // ------------------------------------------------------------------ галерея
  openGallery(profile = this.lastProfile) {
    if (profile) this.lastProfile = profile;
    const p = this.lastProfile;
    if (!p) return;

    this.el.gallerySub.textContent =
      t('gallery.sub', { lvl: p.globalLevel, n: p.unlocked.size, total: PERKS.length }, `Уровень профиля ${p.globalLevel} · открыто ${p.unlocked.size} из ${PERKS.length}`);

    const body = this.el.galleryBody;
    body.innerHTML = '';

    for (const cat of PERK_CATEGORIES) {
      const perks = PERKS.filter((x) => x.category === cat.id);
      if (!perks.length) continue;

      const title = document.createElement('div');
      title.className = 'gallery-section';
      title.style.color = cat.color;
      title.textContent = t('cat.' + cat.id, null, cat.name);
      body.appendChild(title);

      const grid = document.createElement('div');
      grid.className = 'gallery-grid';
      for (const perk of perks) {
        grid.appendChild(this.#galleryCard(perk, p));
      }
      body.appendChild(grid);
    }
    this.el.gallery.classList.add('visible');
  }

  #galleryCard(perk, profile) {
    const unlocked = profile.isUnlocked(perk.id);
    const card = document.createElement('div');
    card.className = 'gallery-card ' + (unlocked ? 'unlocked' : 'locked');

    let badge = '';
    let extra = '';
    if (unlocked) {
      badge = `<div class="gc-badge">${t('gallery.open', null, 'Открыт')}</div>`;
    } else if (perk.challenge) {
      const pr = profile.challengeProgress(perk.id);
      const pct = Math.min(100, (pr.current / pr.need) * 100);
      const task = t('perk.' + perk.id + '.challenge', null, pr.desc);
      extra =
        `<div class="gc-task">${escapeHtml(task)}</div>` +
        `<div class="gc-progress">${pr.current} / ${pr.need}</div>` +
        `<div class="gc-bar"><div style="width:${pct}%"></div></div>`;
    } else {
      const lvl = unlockLevelOf(perk.id);
      extra = `<div class="gc-task">${t('gallery.unlockAt', { lvl: lvl ?? '?' }, `Откроется на уровне профиля ${lvl ?? '?'}`)}</div>`;
    }

    card.innerHTML =
      badge +
      `<div class="gc-icon">${perk.icon}</div>` +
      `<div class="gc-name">${escapeHtml(dn(perk, 'name', 'perk'))}</div>` +
      `<div class="gc-desc">${escapeHtml(dn(perk, 'desc', 'perk'))}</div>` +
      extra;
    return card;
  }

  closeGallery() {
    this.el.gallery.classList.remove('visible');
  }

  get isGalleryOpen() {
    return this.el.gallery?.classList.contains('visible') ?? false;
  }

  // ------------------------------------------------------------------ гараж
  /** Показывает улучшения танка и даёт тратить монеты. */
  openGarage(profile = this.lastProfile) {
    if (profile) this.lastProfile = profile;
    const p = this.lastProfile;
    if (!p) return;

    this.el.garageSub.innerHTML =
      t('garage.sub', { money: p.money }, `Монеты: <b>${p.money}</b> 🪙 · Улучшения танка действуют на обоих игроков в партии`);

    const body = this.el.garageBody;
    body.innerHTML = '';

    for (const cat of UPGRADE_CATEGORIES) {
      const ups = UPGRADES.filter((u) => u.category === cat.id);
      if (!ups.length) continue;

      const title = document.createElement('div');
      title.className = 'gallery-section';
      title.style.color = cat.color;
      title.textContent = t('cat.' + cat.id, null, cat.name);
      body.appendChild(title);

      const grid = document.createElement('div');
      grid.className = 'upgrade-grid';
      for (const up of ups) grid.appendChild(this.#upgradeCard(up, p));
      body.appendChild(grid);
    }

    // ---- косметика -------------------------------------------------------
    const cosTitle = document.createElement('div');
    cosTitle.className = 'gallery-section';
    cosTitle.style.color = '#ff88dd';
    cosTitle.textContent = t('garage.cosmetics', null, 'Косметика');
    body.appendChild(cosTitle);

    for (const [type, items] of Object.entries(COSMETICS_BY_TYPE)) {
      const typeNames = { hull: 'Корпус', track: 'Гусеницы', turret: 'Башня' };
      const t2 = document.createElement('div');
      t2.className = 'gallery-subsection';
      t2.textContent = t('cos.' + type, null, typeNames[type] ?? type);
      body.appendChild(t2);

      const grid = document.createElement('div');
      grid.className = 'upgrade-grid';
      for (const c of items) grid.appendChild(this.#cosmeticCard(c, type, p));
      body.appendChild(grid);
    }

    this.el.garage.classList.add('visible');
  }

  #cosmeticCard(c, type, profile) {
    const owned = profile.isCosmeticOwned(type, c.id);
    const equipped = profile.cosmetics[type] === c.id;
    const canBuy = !owned && !equipped && profile.money >= c.price;

    const card = document.createElement('div');
    card.className =
      'upgrade-card' +
      (equipped ? ' maxed' : '') +
      (owned || equipped ? '' : canBuy ? ' afford' : '');
    card.innerHTML =
      `<div class="up-icon">${c.icon}</div>` +
      `<div class="up-info">` +
      `<div class="up-name">${escapeHtml(dn(c, 'name', 'cos.' + type))}</div>` +
      `<div class="up-desc">${owned ? (equipped ? t('cos.equipped', null, 'Надето') : t('cos.owned', null, 'Куплено')) : t('cos.price', { price: c.price }, `Цена: ${c.price} 🪙`)}</div>` +
      `</div>` +
      `<div class="up-buy">` +
      (owned
        ? `<button class="btn-small" data-equip="${c.id}" ${equipped ? 'disabled' : ''}>` +
          (equipped ? t('cos.equipped', null, 'Надето') : t('cos.equip', null, 'Надеть')) +
          `</button>`
        : `<button class="btn-small" data-buy="${c.id}" ${canBuy ? '' : 'disabled'}>` +
          t('cos.buy', { price: c.price }, `Купить · ${c.price} 🪙`) + `</button>`) +
      `</div>`;

    card.querySelector('[data-buy]')?.addEventListener('click', () => {
      const res = profile.buyCosmetic(type, c.id);
      if (res.ok) {
        this.h.onGarageChanged?.();
        this.openGarage(profile);
      }
    });
    card.querySelector('[data-equip]')?.addEventListener('click', () => {
      const res = profile.equipCosmetic(type, c.id);
      if (res.ok) {
        this.h.onGarageChanged?.();
        this.openGarage(profile);
      }
    });
    return card;
  }

  #upgradeCard(up, profile) {
    const level = profile.upgradeLevel(up.id);
    const maxed = level >= up.maxLevel;
    const cost = maxed ? null : upgradeCost(up, level);
    const canBuy = !maxed && profile.money >= cost;

    const card = document.createElement('div');
    card.className = 'upgrade-card' + (maxed ? ' maxed' : '') + (canBuy ? ' afford' : '');
    card.innerHTML =
      `<div class="up-icon">${up.icon}</div>` +
      `<div class="up-info">` +
      `<div class="up-name">${escapeHtml(dn(up, 'name', 'upg'))}</div>` +
      `<div class="up-desc">${escapeHtml(dn(up, 'desc', 'upg'))}</div>` +
      `<div class="up-bar">${upgradeBar(up.maxLevel, level)}</div>` +
      `</div>` +
      `<div class="up-buy">` +
      (maxed
        ? `<span class="up-max">${t('upg.max', null, 'МАКС')}</span>`
        : `<button class="btn-small" data-buy="${up.id}" ${canBuy ? '' : 'disabled'}>` +
          t('upg.buy', { price: cost }, `Улучшить · ${cost} 🪙`) + `</button>`) +
      `</div>`;

    card.querySelector('[data-buy]')?.addEventListener('click', () => {
      const res = profile.buyUpgrade(up.id);
      if (res.ok) {
        this.h.onGarageChanged?.();
        this.openGarage(profile);
      }
    });
    return card;
  }

  closeGarage() {
    this.el.garage.classList.remove('visible');
  }

  get isGarageOpen() {
    return this.el.garage?.classList.contains('visible') ?? false;
  }

  // ------------------------------------------------------------------ статистика
  openStats(profile = this.lastProfile) {
    if (profile) this.lastProfile = profile;
    const p = this.lastProfile;
    if (!p) return;

    this.el.statsSub.innerHTML =
      t('stats.sub', {
        lvl: p.globalLevel,
        xp: p.globalXP,
        need: p.xpToNextLevel(),
        n: p.unlocked.size,
        total: PERKS.length,
        money: p.money,
      }, `Уровень профиля <b>${p.globalLevel}</b> · ${p.globalXP} / ${p.xpToNextLevel()} XP · ` +
        `перков ${p.unlocked.size}/${PERKS.length} · монет <b>${p.money}</b> 🪙`);

    const body = this.el.statsBody;
    body.innerHTML = '';

    const table = document.createElement('table');
    table.className = 'stats-table';
    for (const key of STAT_KEYS) {
      const label = t('stat.' + key, null, STAT_LABELS[key] ?? key);
      const row = document.createElement('tr');
      const nameCell = document.createElement('td');
      nameCell.textContent = label;
      const valueCell = document.createElement('td');
      valueCell.className = 'stats-value';
      valueCell.textContent = String(p.stats[key] ?? 0);
      row.appendChild(nameCell);
      row.appendChild(valueCell);
      table.appendChild(row);
    }
    body.appendChild(table);

    this.el.stats.classList.add('visible');
  }

  closeStats() {
    this.el.stats.classList.remove('visible');
  }

  get isStatsOpen() {
    return this.el.stats?.classList.contains('visible') ?? false;
  }

  // ------------------------------------------------------------------ достижения
  openAchievements(profile = this.lastProfile) {
    if (profile) this.lastProfile = profile;
    const p = this.lastProfile;
    if (!p) return;

    const unlocked = ACHIEVEMENTS.filter((a) => p.achievements.has(a.id));
    const totalReward = unlocked.reduce((s, a) => s + a.reward, 0);
    this.el.achievementsSub.innerHTML =
      t('achievements.sub', { n: unlocked.length, total: ACHIEVEMENTS.length, reward: totalReward },
        `Открыто <b>${unlocked.length}</b> из ${ACHIEVEMENTS.length} · награда всего <b>${totalReward} 🪙</b>`);

    const body = this.el.achievementsBody;
    body.innerHTML = '';

    const grid = document.createElement('div');
    grid.className = 'gallery-grid';
    for (const a of ACHIEVEMENTS) {
      const done = p.achievements.has(a.id);
      const cur = p.stats[a.stat] ?? 0;
      const pct = Math.min(100, (cur / a.need) * 100);
      const card = document.createElement('div');
      card.className = 'gallery-card ' + (done ? 'unlocked' : 'locked');
      card.innerHTML =
        `<div class="gc-icon">${a.icon}</div>` +
        `<div class="gc-name">${escapeHtml(dn(a, 'name', 'ach'))}</div>` +
        `<div class="gc-desc">${escapeHtml(dn(a, 'desc', 'ach'))}</div>` +
        (done
          ? `<div class="gc-badge">${a.reward} 🪙</div>`
          : `<div class="gc-progress">${Math.min(cur, a.need)} / ${a.need}</div>` +
            `<div class="gc-bar"><div style="width:${pct}%"></div></div>`);
      grid.appendChild(card);
    }
    body.appendChild(grid);

    this.el.achievements.classList.add('visible');
  }

  closeAchievements() {
    this.el.achievements.classList.remove('visible');
  }

  get isAchievementsOpen() {
    return this.el.achievements?.classList.contains('visible') ?? false;
  }

  // ------------------------------------------------------------------ ежедневные задания
  openDaily(profile = this.lastProfile) {
    if (profile) this.lastProfile = profile;
    const p = this.lastProfile;
    if (!p) return;

    const quests = dailySelection();
    let done = 0;
    for (const q of quests) if (p.dailyProgress(q.id).claimed) done++;
    this.el.dailySub.innerHTML =
      t('daily.sub', { done, total: quests.length },
        `Награды сбрасываются в полночь · выполнено <b>${done}</b> из ${quests.length}`);

    const body = this.el.dailyBody;
    body.innerHTML = '';
    for (const q of quests) {
      const pr = p.dailyProgress(q.id);
      const pct = Math.min(100, (pr.current / pr.need) * 100);
      const card = document.createElement('div');
      card.className = 'daily-card' + (pr.claimed ? ' claimed' : pr.current >= pr.need ? ' done' : '');
      const btn = pr.claimed
        ? `<span class="daily-ok">${t('daily.claimed', null, 'Получено ✓')}</span>`
        : `<button class="btn-small" data-claim="${q.id}" ${pr.current >= pr.need ? '' : 'disabled'}>` +
          t('daily.claim', { reward: q.reward }, `Забрать · ${q.reward} 🪙`) + `</button>`;
      card.innerHTML =
        `<div class="gc-icon">${q.icon}</div>` +
        `<div class="up-info">` +
        `<div class="up-name">${escapeHtml(dn(q, 'name', 'daily'))}</div>` +
        `<div class="up-desc">${escapeHtml(dn(q, 'desc', 'daily'))}</div>` +
        `<div class="gc-progress">${pr.current} / ${pr.need}</div>` +
        `<div class="gc-bar"><div style="width:${pct}%"></div></div>` +
        `</div>` +
        `<div class="up-buy">${btn}</div>`;
      card.querySelector('[data-claim]')?.addEventListener('click', () => {
        const res = p.claimDaily(q.id);
        if (res.ok) {
          this.h.onDailyClaimed?.({ reward: res.reward });
          this.openDaily(p);
        }
      });
      body.appendChild(card);
    }

    this.el.daily.classList.add('visible');
  }

  closeDaily() {
    this.el.daily.classList.remove('visible');
  }

  get isDailyOpen() {
    return this.el.daily?.classList.contains('visible') ?? false;
  }

  // ------------------------------------------------------------------ итоги
  /**
   * @param {object} result результат из World
   * @param {import('./world.js').World} world
   * @param {import('./profile.js').Profile} profile
   * @param {boolean} hotseat
   */
  showGameOver(result, world, profile, hotseat) {
    const win = result.victory;
    this.lastGameOver = { result, world, profile, hotseat };
    this.el.gameover.classList.add('visible');
    this.el.gameover.classList.toggle('victory', win);

    if (hotseat && result.winnerPlayerIndex !== null) {
      const winner = world.players[result.winnerPlayerIndex];
      this.el.goTitle.textContent = t('go.won', { name: winner ? winner.name.toUpperCase() : t('go.player', null, 'ИГРОК') }, `ПОБЕДИЛ ${winner ? winner.name.toUpperCase() : 'ИГРОК'}`);
    } else {
      this.el.goTitle.textContent = win ? t('go.victory', null, 'ПОБЕДА!') : t('go.defeat', null, 'ПОРАЖЕНИЕ');
    }

    const diff = DIFFICULTY[world.difficultyKey];
    const modeName = t('mode.' + world.mode, null, MODES[world.mode]?.name ?? (world.mode === 'ffa' ? MODES.ffa.name : MODES.ctf.name));

    let html = `<div class="go-reason">${escapeHtml(result.reason)}</div>`;
    html += `<div class="go-meta">${t('go.meta', {
      mode: modeName,
      diff: t('diff.' + world.difficultyKey, null, diff.name),
      lvl: formatLevel(world),
    }, `${modeName} · ${diff.name} · уровень ${formatLevel(world)}`)}</div>`;

    html += '<div class="go-players">';
    for (const player of world.players) {
      html +=
        `<div class="go-player">` +
        `<div class="go-pname">${escapeHtml(player.name)}</div>` +
        `<div>${t('go.frags', { n: player.kills }, 'Фраги: {n}')} &nbsp; ${t('go.deaths', { n: player.deaths }, 'Смерти: {n}')}</div>` +
        (world.mode === 'ctf' ? `<div>${t('go.captures', { n: player.captures }, 'Захваты флага: {n}')}</div>` : '') +
        `<div>${t('go.score', { n: player.score }, 'Счёт: {n}')}</div>` +
        `<div>${t('go.damage', { n: Math.round(player.damageDealt) }, 'Урона нанесено: {n}')}</div>` +
        `<div>${t('go.sessionLevel', { n: player.sessionLevel }, 'Уровень в партии: {n}')}</div>` +
        `<div class="go-perks">${player.perkIds.map((id) => perkIcon(id)).join(' ') || '—'}</div>` +
        `</div>`;
    }
    html += '</div>';

    html +=
      `<div class="go-profile">${t('go.profile', {
        lvl: profile.globalLevel,
        xp: profile.globalXP,
        need: profile.xpToNextLevel(),
        n: profile.unlocked.size,
        total: PERKS.length,
      }, `Профиль: уровень ${profile.globalLevel}, ${profile.globalXP}/${profile.xpToNextLevel()} XP, перков ${profile.unlocked.size}/${PERKS.length}`)}</div>`;

    // Награда за партию.
    const rw = result.rewards;
    if (rw) {
      const total = rw.kills + rw.captures + rw.wins;
      const parts = [];
      if (rw.kills) parts.push(t('go.reward.kills', { n: rw.kills }, `убийства ${rw.kills}`));
      if (rw.captures) parts.push(t('go.reward.captures', { n: rw.captures }, `флаги ${rw.captures}`));
      if (rw.wins) parts.push(t('go.reward.wins', { n: rw.wins }, `победа ${rw.wins}`));
      html +=
        `<div class="go-rewards">${t('go.reward', { total }, 'Награда: +{total} 🪙')}` +
        (parts.length ? ` <span class="go-rewards-sub">(${parts.join(' + ')})</span>` : '') +
        `</div>`;
    }

    // Итоговая таблица.
    const rows = world.scoreboard().slice(0, 8);
    html += `<table class="go-table"><thead><tr><th>${t('go.table.rank', null, '#')}</th><th>${t('go.table.tank', null, 'Танк')}</th><th>${t('go.table.kills', null, 'Фраги')}</th><th>${t('go.table.deaths', null, 'Смерти')}</th></tr></thead><tbody>`;
    rows.forEach((r, i) => {
      html +=
        `<tr${r.isHuman ? ' class="human"' : ''}><td>${i + 1}</td>` +
        `<td>${escapeHtml(r.name)}</td><td>${r.kills}</td><td>${r.deaths}</td></tr>`;
    });
    html += '</tbody></table>';

    this.el.goBody.innerHTML = html;
  }

  hideGameOver() {
    this.el.gameover.classList.remove('visible');
  }

  refreshProfile(profile) {
    this.lastProfile = profile;
    this.#refreshMenuInfo(profile);
  }
}

function formatLevel(world) {
  const lvl = world.level.requestedLevel;
  return lvl === 'random' ? t('go.randomLevel', null, 'случайный') : String(lvl ?? 1);
}

/** Оборачивает произвольный генератор в функцию, ожидаемую shuffled(). */
function rngWrap(rng) {
  return typeof rng === 'function' ? rng : Math.random;
}

/** Полоска прогресса улучшения: заполненные сегменты = уровень. */
function upgradeBar(max, level) {
  let html = '<div class="up-bar-track">';
  for (let i = 1; i <= max; i++) {
    html += `<span class="up-seg${i <= level ? ' filled' : ''}"></span>`;
  }
  html += '</div>';
  return html;
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (ch) => {
    switch (ch) {
      case '&':
        return '&amp;';
      case '<':
        return '&lt;';
      case '>':
        return '&gt;';
      case '"':
        return '&quot;';
      default:
        return '&#39;';
    }
  });
}
