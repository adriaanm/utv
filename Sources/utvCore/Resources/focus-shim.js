// utv tvOS d-pad focus shim.
//
// The tvOS focus engine doesn't walk the DOM, so the Siri Remote can't
// navigate inside a WKWebView on its own. This script keeps a "current
// focused element" pointer in the page, draws an outline ring around it,
// and exposes window._utvFocus.{move,activate,rescan} that the native
// host view calls from pressesBegan:withEvent:.
//
// Phase 1 scope: arrow navigation + select. Player keyboard mapping,
// search/text-entry handoff, iframe walk are deferred — see
// docs/tvos-dpad-navigation.md.

(function () {
  if (window._utvFocus) return;

  var FOCUSABLE = [
    'a[href]',
    'button:not([disabled])',
    '[role="button"]:not([aria-disabled="true"])',
    '[tabindex]:not([tabindex="-1"])',
    'input:not([disabled])',
    'select:not([disabled])',
    'video',
  ].join(', ');

  var current = null;
  var rescanTimer = null;

  function visible(el) {
    if (el.disabled) return false;
    var r = el.getBoundingClientRect();
    if (r.width < 4 || r.height < 4) return false;
    var s = getComputedStyle(el);
    if (s.visibility === 'hidden' || s.display === 'none' || s.pointerEvents === 'none') return false;
    if (parseFloat(s.opacity || '1') < 0.05) return false;
    if (r.bottom < -200 || r.top > innerHeight + 200) return false;
    if (r.right < -200 || r.left > innerWidth + 200) return false;
    return true;
  }

  function scan() {
    var nodes = document.querySelectorAll(FOCUSABLE);
    var out = [];
    for (var i = 0; i < nodes.length; i++) {
      if (visible(nodes[i])) out.push(nodes[i]);
    }
    return out;
  }

  function center(r) {
    return { x: (r.left + r.right) / 2, y: (r.top + r.bottom) / 2 };
  }

  function setFocus(el) {
    if (current === el) return;
    if (current) current.classList.remove('utv-focused');
    current = el;
    if (el) {
      el.classList.add('utv-focused');
      el.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'smooth' });
      try { el.focus({ preventScroll: true }); } catch (e) {}
    }
  }

  function pickInitial() {
    var list = scan();
    if (list.length === 0) { current = null; return; }
    // Prefer the play button on YouTube — it's the action the user almost
    // always wants on first arrival. Fall back to the first focusable.
    var play = document.querySelector('.ytp-play-button, button[aria-label*="Play"]');
    if (play && visible(play)) { setFocus(play); return; }
    setFocus(list[0]);
  }

  function nearest(dir) {
    if (!current || !document.contains(current)) { pickInitial(); return; }
    var list = scan();
    var fromR = current.getBoundingClientRect();
    var from = center(fromR);

    var best = null;
    var bestScore = Infinity;

    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      if (el === current) continue;
      var r = el.getBoundingClientRect();
      var c = center(r);
      var dx = c.x - from.x;
      var dy = c.y - from.y;

      var inDir = false, primary = 0, secondary = 0;
      switch (dir) {
        case 'up':    inDir = dy < -2; primary = -dy; secondary = Math.abs(dx); break;
        case 'down':  inDir = dy >  2; primary =  dy; secondary = Math.abs(dx); break;
        case 'left':  inDir = dx < -2; primary = -dx; secondary = Math.abs(dy); break;
        case 'right': inDir = dx >  2; primary =  dx; secondary = Math.abs(dy); break;
      }
      if (!inDir) continue;
      // Penalize off-axis distance heavily so we hop to the next item in the
      // travel direction rather than diagonally jumping to a closer-overall
      // element on a different row/column.
      var score = primary + secondary * 3;
      if (score < bestScore) { bestScore = score; best = el; }
    }
    if (best) setFocus(best);
  }

  function activate() {
    if (!current) return;
    // Synthetic click + keydown(Enter) covers most listeners. Some sites bind
    // to mousedown/mouseup separately — escalate later if YouTube needs it.
    try { current.click(); } catch (e) {}
    var ev = new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', bubbles: true, cancelable: true });
    current.dispatchEvent(ev);
  }

  function injectStyle() {
    if (document.getElementById('utv-focus-style')) return;
    var s = document.createElement('style');
    s.id = 'utv-focus-style';
    s.textContent =
      '.utv-focused { outline: 4px solid #ff5500 !important;' +
      ' outline-offset: 2px !important;' +
      ' box-shadow: 0 0 16px 4px rgba(255,85,0,0.55) !important;' +
      ' transition: outline 80ms ease, box-shadow 80ms ease !important; }';
    (document.head || document.documentElement).appendChild(s);
  }

  function bootstrap() {
    injectStyle();
    setTimeout(pickInitial, 600);
  }
  if (document.readyState === 'complete' || document.readyState === 'interactive') {
    bootstrap();
  } else {
    document.addEventListener('DOMContentLoaded', bootstrap);
  }

  var observer = new MutationObserver(function () {
    if (rescanTimer) clearTimeout(rescanTimer);
    rescanTimer = setTimeout(function () {
      if (current && !document.contains(current)) {
        current = null;
        pickInitial();
      }
    }, 250);
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });

  window._utvFocus = {
    move: nearest,
    activate: activate,
    rescan: pickInitial,
  };
})();
