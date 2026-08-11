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

    const onlineUrl = document.getElementById('online-url');
    if (onlineUrl && (!onlineUrl.value || onlineUrl.value === 'ws://localhost:8123')) {
      onlineUrl.value = defaultServerUrl();
    }
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
    on('btn-reset', () => {
      if (window.confirm('Сбросить весь прогресс профиля? Открытые перки будут потеряны.')) {
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

  #refreshSoundBtn() {
    if (this.el.soundBtn) this.el.soundBtn.textContent = this.soundOn ? '🔊 Звук' : '🔇 Звук';
  }

  /** Подсказки по управлению зависят от выбранного типа игры. */
  #refreshHints() {
    if (!this.el.hints) return;
    const p1 = [
      '<b>Игрок 1:</b> <kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> движение',
      '<kbd>мышь</kbd> прицел',
      '<kbd>ЛКМ</kbd> выстрел',
      '<kbd>E</kbd> мина',
    ];
    const p2 = [
      '<b>Игрок 2:</b> <kbd>↑</kbd><kbd>←</kbd><kbd>↓</kbd><kbd>→</kbd> движение',
      '<kbd>&lt;</kbd> <kbd>&gt;</kbd> башня',
      '<kbd>Пр. Shift</kbd> выстрел',
      '<kbd>Num .</kbd> мина',
    ];
    const common = ['<kbd>P</kbd>/<kbd>Esc</kbd> пауза', '<kbd>Tab</kbd> табло'];
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
      `Профиль: уровень <b>${profile.globalLevel}</b> &nbsp;·&nbsp; ` +
      `${profile.globalXP} / ${need} XP &nbsp;·&nbsp; ` +
      `перков открыто <b>${profile.unlocked.size}</b> из ${PERKS.length}` +
      ` &nbsp;·&nbsp; монет <b>${profile.money} 🪙</b>` +
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
      `<div class="perk-who">${escapeHtml(player.name)} — уровень ${player.sessionLevel}</div>` +
      `<div class="perk-sub">Профиль ${profile.globalLevel} &nbsp;·&nbsp; ` +
      `экипировано ${player.perkIds.length}/${MAX_EQUIPPED_PERKS}` +
      (queueLeft > 0 ? ` &nbsp;·&nbsp; ещё выборов: ${queueLeft}` : '') +
      `</div>`;
    body.appendChild(head);

    if (choices.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'perk-empty';
      empty.textContent =
        available.length === 0
          ? 'Пока нет открытых перков. Набирайте опыт профиля — они откроются.'
          : 'Все доступные перки уже экипированы.';
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
          `<div class="perk-name">${escapeHtml(perk.name)}</div>` +
          `<div class="perk-desc">${escapeHtml(perk.desc)}</div>`;
        card.addEventListener('click', () => this.h.onPerkChosen(player, id));
        grid.appendChild(card);
      }
      body.appendChild(grid);
    }

    // Экипированные — можно снять. Пересчёт характеристик делает Player.
    if (player.perkIds.length > 0) {
      const wrap = document.createElement('div');
      wrap.className = 'perk-equipped';
      wrap.innerHTML = '<div class="perk-eq-label">Экипировано (нажмите, чтобы снять)</div>';
      const row = document.createElement('div');
      row.className = 'perk-eq-row';
      for (const id of [...player.perkIds]) {
        const perk = getPerk(id);
        if (!perk) continue;
        const chip = document.createElement('button');
        chip.className = 'perk-chip';
        chip.innerHTML = `<span>${perk.icon}</span> ${escapeHtml(perk.name)} <span class="x">✕</span>`;
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
    skip.textContent = 'Продолжить без выбора';
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
      `Уровень профиля ${p.globalLevel} · открыто ${p.unlocked.size} из ${PERKS.length}`;

    const body = this.el.galleryBody;
    body.innerHTML = '';

    for (const cat of PERK_CATEGORIES) {
      const perks = PERKS.filter((x) => x.category === cat.id);
      if (!perks.length) continue;

      const title = document.createElement('div');
      title.className = 'gallery-section';
      title.style.color = cat.color;
      title.textContent = cat.name;
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
      badge = '<div class="gc-badge">Открыт</div>';
    } else if (perk.challenge) {
      const pr = profile.challengeProgress(perk.id);
      const pct = Math.min(100, (pr.current / pr.need) * 100);
      extra =
        `<div class="gc-task">${escapeHtml(pr.desc)}</div>` +
        `<div class="gc-progress">${pr.current} / ${pr.need}</div>` +
        `<div class="gc-bar"><div style="width:${pct}%"></div></div>`;
    } else {
      const lvl = unlockLevelOf(perk.id);
      extra = `<div class="gc-task">Откроется на уровне профиля ${lvl ?? '?'}</div>`;
    }

    card.innerHTML =
      badge +
      `<div class="gc-icon">${perk.icon}</div>` +
      `<div class="gc-name">${escapeHtml(perk.name)}</div>` +
      `<div class="gc-desc">${escapeHtml(perk.desc)}</div>` +
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
      `Монеты: <b>${p.money}</b> 🪙 · Улучшения танка действуют на обоих игроков в партии`;

    const body = this.el.garageBody;
    body.innerHTML = '';

    for (const cat of UPGRADE_CATEGORIES) {
      const ups = UPGRADES.filter((u) => u.category === cat.id);
      if (!ups.length) continue;

      const title = document.createElement('div');
      title.className = 'gallery-section';
      title.style.color = cat.color;
      title.textContent = cat.name;
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
    cosTitle.textContent = 'Косметика';
    body.appendChild(cosTitle);

    for (const [type, items] of Object.entries(COSMETICS_BY_TYPE)) {
      const typeNames = { hull: 'Корпус', track: 'Гусеницы', turret: 'Башня' };
      const t = document.createElement('div');
      t.className = 'gallery-subsection';
      t.textContent = typeNames[type] ?? type;
      body.appendChild(t);

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
      `<div class="up-name">${escapeHtml(c.name)}</div>` +
      `<div class="up-desc">${owned ? (equipped ? 'Надето' : 'Куплено') : `Цена: ${c.price} 🪙`}</div>` +
      `</div>` +
      `<div class="up-buy">` +
      (owned
        ? `<button class="btn-small" data-equip="${c.id}" ${equipped ? 'disabled' : ''}>` +
          (equipped ? 'Надето' : 'Надеть') +
          `</button>`
        : `<button class="btn-small" data-buy="${c.id}" ${canBuy ? '' : 'disabled'}>` +
          `Купить · ${c.price} 🪙</button>`) +
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
      `<div class="up-name">${escapeHtml(up.name)}</div>` +
      `<div class="up-desc">${escapeHtml(up.desc)}</div>` +
      `<div class="up-bar">${upgradeBar(up.maxLevel, level)}</div>` +
      `</div>` +
      `<div class="up-buy">` +
      (maxed
        ? `<span class="up-max">МАКС</span>`
        : `<button class="btn-small" data-buy="${up.id}" ${canBuy ? '' : 'disabled'}>` +
          `Улучшить · ${cost} 🪙</button>`) +
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

    this.el.statsSub.textContent =
      `Уровень профиля <b>${p.globalLevel}</b> · ${p.globalXP} / ${p.xpToNextLevel()} XP · ` +
      `перков ${p.unlocked.size}/${PERKS.length} · монет <b>${p.money}</b> 🪙`;

    const body = this.el.statsBody;
    body.innerHTML = '';

    const table = document.createElement('table');
    table.className = 'stats-table';
    for (const key of STAT_KEYS) {
      const label = STAT_LABELS[key] ?? key;
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
      `Открыто <b>${unlocked.length}</b> из ${ACHIEVEMENTS.length} · награда всего <b>${totalReward} 🪙</b>`;

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
        `<div class="gc-name">${escapeHtml(a.name)}</div>` +
        `<div class="gc-desc">${escapeHtml(a.desc)}</div>` +
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
    this.el.dailySub.innerHTML = `Награды сбрасываются в полночь · выполнено <b>${done}</b> из ${quests.length}`;

    const body = this.el.dailyBody;
    body.innerHTML = '';
    for (const q of quests) {
      const pr = p.dailyProgress(q.id);
      const pct = Math.min(100, (pr.current / pr.need) * 100);
      const card = document.createElement('div');
      card.className = 'daily-card' + (pr.claimed ? ' claimed' : pr.current >= pr.need ? ' done' : '');
      const btn = pr.claimed
        ? `<span class="daily-ok">Получено ✓</span>`
        : `<button class="btn-small" data-claim="${q.id}" ${pr.current >= pr.need ? '' : 'disabled'}>` +
          `Забрать · ${q.reward} 🪙</button>`;
      card.innerHTML =
        `<div class="gc-icon">${q.icon}</div>` +
        `<div class="up-info">` +
        `<div class="up-name">${escapeHtml(q.name)}</div>` +
        `<div class="up-desc">${escapeHtml(q.desc)}</div>` +
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
    this.el.gameover.classList.add('visible');
    this.el.gameover.classList.toggle('victory', win);

    if (hotseat && result.winnerPlayerIndex !== null) {
      const winner = world.players[result.winnerPlayerIndex];
      this.el.goTitle.textContent = `ПОБЕДИЛ ${winner ? winner.name.toUpperCase() : 'ИГРОК'}`;
    } else {
      this.el.goTitle.textContent = win ? 'ПОБЕДА!' : 'ПОРАЖЕНИЕ';
    }

    const diff = DIFFICULTY[world.difficultyKey];
    const modeName = MODES[world.mode]?.name ?? (world.mode === 'ffa' ? MODES.ffa.name : MODES.ctf.name);

    let html = `<div class="go-reason">${escapeHtml(result.reason)}</div>`;
    html += `<div class="go-meta">${modeName} · ${diff.name} · уровень ${formatLevel(world)}</div>`;

    html += '<div class="go-players">';
    for (const player of world.players) {
      html +=
        `<div class="go-player">` +
        `<div class="go-pname">${escapeHtml(player.name)}</div>` +
        `<div>Фраги: <b>${player.kills}</b> &nbsp; Смерти: <b>${player.deaths}</b></div>` +
        (world.mode === 'ctf' ? `<div>Захваты флага: <b>${player.captures}</b></div>` : '') +
        `<div>Счёт: <b>${player.score}</b></div>` +
        `<div>Урона нанесено: <b>${Math.round(player.damageDealt)}</b></div>` +
        `<div>Уровень в партии: <b>${player.sessionLevel}</b></div>` +
        `<div class="go-perks">${player.perkIds.map((id) => perkIcon(id)).join(' ') || '—'}</div>` +
        `</div>`;
    }
    html += '</div>';

    html +=
      `<div class="go-profile">Профиль: уровень <b>${profile.globalLevel}</b>, ` +
      `${profile.globalXP}/${profile.xpToNextLevel()} XP, ` +
      `перков ${profile.unlocked.size}/${PERKS.length}</div>`;

    // Награда за партию.
    const rw = result.rewards;
    if (rw) {
      const total = rw.kills + rw.captures + rw.wins;
      const parts = [];
      if (rw.kills) parts.push(`убийства ${rw.kills}`);
      if (rw.captures) parts.push(`флаги ${rw.captures}`);
      if (rw.wins) parts.push(`победа ${rw.wins}`);
      html +=
        `<div class="go-rewards">Награда: <b>+${total} 🪙</b>` +
        (parts.length ? ` <span class="go-rewards-sub">(${parts.join(' + ')})</span>` : '') +
        `</div>`;
    }

    // Итоговая таблица.
    const rows = world.scoreboard().slice(0, 8);
    html += '<table class="go-table"><thead><tr><th>#</th><th>Танк</th><th>Фраги</th><th>Смерти</th></tr></thead><tbody>';
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
  return lvl === 'random' ? 'случайный' : String(lvl ?? 1);
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
