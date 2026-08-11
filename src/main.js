// ============================================================================
// main.js — точка входа.
//
// Цель: ни при каких условиях не оставлять игрока перед чёрным экраном без
// объяснений. Если сбой происходит на этапе загрузки модулей (например,
// страницу открыли по file:// и браузер блокирует ES-модули), срабатывает
// не-модульный «страж» в index.html. Если же сбой происходит во время игры —
// цикл кадров не умирает молча, а выводит сообщение.
// ============================================================================

import { Game } from './game.js';

function showOverlay(text, title) {
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
    (title ? title : 'Произошла ошибка') +
    `</div><div style="color:#ffdddd">${String(text)}</div></div>`;
  document.body.appendChild(box);
}

function boot() {
  let game = null;
  try {
    game = new Game();
    game.run();
    // Признак успешного старта — по нему отключается «страж» из index.html.
    window.__tanchiki = game;
  } catch (error) {
    console.error('[tanchiki] не удалось запустить игру:', error);
    showOverlay(
      String(error?.stack || error) +
        '\n\nЕсли открыто по file:// — браузер блокирует ES-модули. ' +
        'Запустите через start.cmd: он поднимет локальный сервер.',
      'Игра не запустилась',
    );
    return;
  }

  // Сбой во время игры не должен обрушивать цикл незаметно.
  window.addEventListener('error', (e) => {
    // Ошибки внутри rAF уже обрабатываются игрой; адреса других страниц и
    // ресурсов не трогаем, но логируем всё важное.
    if (e?.message) console.error('[tanchiki] window.onerror:', e.message);
  });

  window.addEventListener('unhandledrejection', (e) => {
    console.error('[tanchiki] unhandledrejection:', e?.reason);
  });
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot);
} else {
  boot();
}
