// ============================================================================
// hud.js — игровой интерфейс поверх канваса.
//
// Панель строится по числу игроков и позиционируется внутри их областей
// просмотра. В старой версии HUD был жёстко один и всегда показывал первого
// игрока: у второго не было ни полоски HP, ни перков, ни счёта.
// ============================================================================

import { MODES, TEAM_COLORS, TICK_HZ } from './config.js';
import { perkIcon, perkName, anyPerkIcon } from './perks.js';

const FEED_LIFE = 300; // тиков
const FEED_MAX = 6;

/** Иконки погодных условий для HUD. */
const WEATHER_ICONS = {
  clear: '☀️',
  rain: '🌧',
  fog: '🌫',
  storm: '⛈',
};

export class Hud {
  /**
   * @param {HTMLElement} root контейнер #hud
   * @param {import('./render.js').Renderer} renderer
   */
  constructor(root, renderer) {
    this.root = root;
    this.renderer = renderer;
    /** @type {Map<number, object>} панели по индексу игрока */
    this.panels = new Map();
    /** @type {{text:string,color:string,life:number}[]} */
    this.feed = [];
    this.feedDirty = true;

    this.feedEl = document.createElement('div');
    this.feedEl.className = 'kill-feed';
    this.root.appendChild(this.feedEl);

    this.bannerEl = document.createElement('div');
    this.bannerEl.className = 'hud-banner';
    this.root.appendChild(this.bannerEl);
    this.bannerTimer = 0;

    this.scoreboardEl = document.createElement('div');
    this.scoreboardEl.className = 'scoreboard';
    this.root.appendChild(this.scoreboardEl);
    this.scoreboardVisible = false;
  }

  // ------------------------------------------------------------------ сборка
  /** Пересобирает панели под текущий состав игроков. */
  build(players) {
    for (const panel of this.panels.values()) panel.el.remove();
    this.panels.clear();

    for (const player of players) {
      const palette = TEAM_COLORS[player.colorKey] ?? TEAM_COLORS.neutral;
      const el = document.createElement('div');
      el.className = 'hud-panel';
      el.innerHTML = `
        <div class="hud-row">
          <div class="hud-left">
            <div class="hud-name" style="color:${palette.trim}"></div>
            <div class="bar hp-bar"><div class="bar-fill hp-fill"></div><div class="bar-fill shield-fill"></div></div>
            <div class="hud-hp"></div>
          </div>
          <div class="hud-right">
            <div class="hud-score"></div>
            <div class="hud-objective"></div>
            <div class="hud-weather"></div>
          </div>
        </div>
        <div class="hud-bottom">
          <div class="hud-xp-label"></div>
          <div class="bar xp-bar"><div class="bar-fill xp-fill"></div></div>
          <div class="hud-perks"></div>
        </div>
        <canvas class="minimap" width="200" height="114"></canvas>
      `;
      this.root.appendChild(el);
      this.panels.set(player.index, {
        el,
        name: el.querySelector('.hud-name'),
        hpFill: el.querySelector('.hp-fill'),
        shieldFill: el.querySelector('.shield-fill'),
        hpText: el.querySelector('.hud-hp'),
        score: el.querySelector('.hud-score'),
        objective: el.querySelector('.hud-objective'),
        weather: el.querySelector('.hud-weather'),
        xpLabel: el.querySelector('.hud-xp-label'),
        xpFill: el.querySelector('.xp-fill'),
        perks: el.querySelector('.hud-perks'),
        minimap: el.querySelector('.minimap'),
        lastPerks: '',
      });
      this.panels.get(player.index).name.textContent = player.name;
    }
    this.layout(players);
  }

  /** Позиционирует панели по областям просмотра. */
  layout(players) {
    const split = players.length > 1;
    for (const player of players) {
      const panel = this.panels.get(player.index);
      if (!panel) continue;
      const vp = player.viewport;
      panel.el.style.left = `${vp.x}px`;
      panel.el.style.top = `${vp.y}px`;
      panel.el.style.width = `${vp.w}px`;
      panel.el.style.height = `${vp.h}px`;
      panel.el.classList.toggle('split', split);
      // В разделённом экране места мало — миникарта меньше.
      const mmW = split ? 140 : 200;
      const mmH = Math.round((mmW * 114) / 200);
      panel.minimap.width = mmW;
      panel.minimap.height = mmH;
      panel.minimap.style.width = `${mmW}px`;
      panel.minimap.style.height = `${mmH}px`;
    }
    this.feedEl.classList.toggle('split', split);
  }

  show() {
    this.root.style.display = 'block';
  }

  hide() {
    this.root.style.display = 'none';
    this.hideScoreboard();
  }

  // ------------------------------------------------------------------ обновление
  /**
   * @param {import('./world.js').World} world
   * @param {import('./profile.js').Profile} profile
   */
  update(world, profile) {
    for (const player of world.players) {
      const panel = this.panels.get(player.index);
      const tank = player.tank;
      if (!panel || !tank) continue;

      const hpRatio = Math.max(0, tank.hp / tank.maxHP);
      panel.hpFill.style.width = `${hpRatio * 100}%`;
      panel.hpFill.style.background = hpRatio > 0.5 ? '#44cc44' : hpRatio > 0.25 ? '#cccc44' : '#cc4444';
      const shieldRatio = Math.min(1, tank.shieldHP / 30);
      panel.shieldFill.style.width = `${shieldRatio * 100}%`;
      panel.shieldFill.style.display = tank.shieldHP > 0 ? 'block' : 'none';
      panel.hpText.textContent =
        `${Math.ceil(tank.hp)} / ${tank.maxHP} HP` + (tank.shieldHP > 0 ? ` +${Math.ceil(tank.shieldHP)} щит` : '');

      panel.score.textContent = `Счёт ${player.score}`;

      const progress = world.progressFor(player);
      if (world.mode === 'defense') {
        const baseHp = world.base ? Math.ceil(world.base.hp) : 0;
        const left = progress.current;
        const state = world.waveState === 'delay' ? '…' : `${left} в поле`;
        // Только первый игрок владеет авиаударом — индикатор у него же.
        let strike = '';
        if (player.index === 0) {
          strike =
            world.airstrikeCooldown > 0
              ? `  ✈ ${Math.ceil(world.airstrikeCooldown / TICK_HZ)}с`
              : '  ✈ ГОТОВ (F)';
        }
        panel.objective.textContent =
          `Волна ${world.wave} / ${MODES.defense.waves}   🏰 ${baseHp} HP   (${state})${strike}`;
      } else if (world.mode === 'koth') {
        const left = Math.max(0, world.timeLimit - world.tick);
        const sec = Math.ceil(left / 60);
        panel.objective.textContent =
          `Выживших ${progress.current} / ${progress.total}   ⏱ ${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;
      } else if (world.mode === 'ffa') {
        panel.objective.textContent = `Фраги ${progress.current} / ${progress.target}   ✝ ${player.deaths}`;
      } else {
        panel.objective.textContent =
          `Флаги ${world.teamScore.player} : ${world.teamScore.enemy}` +
          ` (до ${MODES.ctf.capLimit})` +
          (tank.carryingFlag ? '  ⚑ у вас флаг!' : '');
      }

      // Индикатор погоды и времени суток.
      const w = world.weather;
      if (w) {
        const icon = WEATHER_ICONS[w.condition] ?? '🌤';
        panel.weather.textContent = `${icon} ${w.timeName}`;
      }

      const need = player.xpToNextLevel();
      panel.xpFill.style.width = `${Math.min(100, (player.sessionXP / need) * 100)}%`;
      panel.xpLabel.textContent =
        `Ур. ${player.sessionLevel} · ${player.sessionXP}/${need} XP` +
        `   |   Профиль ${profile.globalLevel} · ${profile.globalXP}/${profile.xpToNextLevel()}`;

      // Перки перерисовываем только при изменении набора.
      const key = player.perkIds.join(',');
      if (key !== panel.lastPerks) {
        panel.lastPerks = key;
        panel.perks.innerHTML = '';
        for (const id of player.perkIds) {
          const slot = document.createElement('div');
          slot.className = 'perk-slot';
          slot.textContent = `${perkIcon(id)} ${perkName(id)}`;
          panel.perks.appendChild(slot);
        }
      }

      this.renderer.drawMinimap(panel.minimap, world, player);
    }

    this.#tickFeed();
    if (this.bannerTimer > 0 && --this.bannerTimer === 0) this.bannerEl.classList.remove('visible');
    if (this.scoreboardVisible) this.#renderScoreboard(world);
  }

  // ------------------------------------------------------------------ лента
  addFeed(text, color = '#ffffff') {
    this.feed.unshift({ text, color, life: FEED_LIFE });
    while (this.feed.length > FEED_MAX) this.feed.pop();
    this.feedDirty = true;
  }

  clearFeed() {
    this.feed.length = 0;
    this.feedDirty = true;
  }

  #tickFeed() {
    let changed = false;
    let w = 0;
    for (const entry of this.feed) {
      entry.life--;
      if (entry.life > 0) this.feed[w++] = entry;
      else changed = true;
    }
    if (w !== this.feed.length) this.feed.length = w;
    if (!this.feedDirty && !changed) {
      // Обновляем только прозрачность угасающих строк — без пересборки DOM.
      const nodes = this.feedEl.children;
      for (let i = 0; i < nodes.length && i < this.feed.length; i++) {
        nodes[i].style.opacity = this.feed[i].life < 60 ? String(this.feed[i].life / 60) : '1';
      }
      return;
    }
    this.feedDirty = false;
    this.feedEl.innerHTML = '';
    for (const entry of this.feed) {
      const div = document.createElement('div');
      div.className = 'kill-entry';
      div.style.borderLeftColor = entry.color;
      div.style.opacity = entry.life < 60 ? String(entry.life / 60) : '1';
      div.textContent = entry.text;
      this.feedEl.appendChild(div);
    }
  }

  // ------------------------------------------------------------------ баннер
  /** Крупное сообщение в центре (открыт перк, забрали флаг и т.п.). */
  banner(text, color = '#ffee55', ticks = 150) {
    this.bannerEl.textContent = text;
    this.bannerEl.style.color = color;
    this.bannerEl.classList.add('visible');
    this.bannerTimer = ticks;
  }

  // ------------------------------------------------------------------ табло
  toggleScoreboard(world) {
    this.scoreboardVisible = !this.scoreboardVisible;
    this.scoreboardEl.classList.toggle('visible', this.scoreboardVisible);
    if (this.scoreboardVisible && world) this.#renderScoreboard(world);
  }

  hideScoreboard() {
    this.scoreboardVisible = false;
    this.scoreboardEl.classList.remove('visible');
  }

  #renderScoreboard(world) {
    const rows = world.scoreboard();
    const target = world.mode === 'ffa' ? MODES.ffa.fragLimit : MODES.ctf.capLimit;
    const head =
      world.mode === 'defense'
        ? `Оборона — волна ${world.wave} из ${MODES.defense.waves}`
        : world.mode === 'koth'
          ? 'Царь горы — побеждает последний выживший'
          : world.mode === 'ffa'
            ? `Каждый за себя — до ${target} фрагов`
            : `Захват флага — Свои ${world.teamScore.player} : ${world.teamScore.enemy} Враги (до ${target})`;

    let html = `<div class="sb-title">${head}</div>`;
    html += '<table><thead><tr><th>#</th><th>Танк</th><th>Фраги</th><th>Смерти</th><th>Перки</th></tr></thead><tbody>';
    rows.forEach((r, i) => {
      const palette = TEAM_COLORS[r.colorKey] ?? TEAM_COLORS.neutral;
      const cls = r.isHuman ? ' class="human"' : '';
      html +=
        `<tr${cls}><td>${i + 1}</td>` +
        `<td><span class="dot" style="background:${palette.body}"></span>${escapeHtml(r.name)}${r.alive ? '' : ' <span class="dead">†</span>'}</td>` +
        `<td>${r.kills}</td><td>${r.deaths}</td>` +
        `<td class="sb-perks">${r.perks.map(anyPerkIcon).join(' ')}</td></tr>`;
    });
    html += '</tbody></table><div class="sb-hint">Tab — скрыть</div>';
    this.scoreboardEl.innerHTML = html;
  }
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
