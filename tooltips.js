// ══════════════════════════════════════════════════════════════════
// tooltips.js — [T25.2] Tooltips descriptivos para tarjetas KPI
// ──────────────────────────────────────────────────────────────────
// Uso: añadir data-tip="texto" a cualquier elemento. Nada más.
// El motor se auto-inicializa y funciona también con elementos que
// aparecen DESPUÉS (tarjetas que se repintan al refrescar datos),
// porque escucha en document y lee el atributo al vuelo.
//
//   • ESCRITORIO: aparece al pasar el mouse, desaparece al salir.
//   • MÓVIL/TABLET: aparece con tap, se cierra al tocar fuera.
//   • Posicionamiento position:fixed calculado contra el viewport, así
//     que NO lo recorta el overflow:hidden de las tarjetas ni ningún
//     contenedor con scroll, y nunca se sale de la pantalla.
//   • No obstruye el dato: se coloca ARRIBA de la tarjeta; si no cabe
//     arriba, cae abajo.
// ══════════════════════════════════════════════════════════════════
(function () {
  'use strict';
  if (window.__ieTipInit) return;   // no inicializar dos veces
  window.__ieTipInit = true;

  const ESPACIO = 10;               // separación entre tarjeta y tooltip
  let tip = null;                   // el nodo del tooltip (uno solo, reutilizado)
  let anclaActual = null;           // elemento que lo tiene abierto

  // ¿El dispositivo es táctil? (decide hover vs tap)
  const esTactil = window.matchMedia('(hover: none), (pointer: coarse)').matches;

  function nodo() {
    if (!tip) {
      tip = document.createElement('div');
      tip.id = 'ie-tip';
      tip.setAttribute('role', 'tooltip');
      document.body.appendChild(tip);
    }
    return tip;
  }

  function colocar(el) {
    const t = nodo();
    const r = el.getBoundingClientRect();
    const tr = t.getBoundingClientRect();
    const vw = document.documentElement.clientWidth;
    const vh = document.documentElement.clientHeight;

    // Horizontal: centrado sobre la tarjeta, sin salirse del viewport
    let x = r.left + r.width / 2 - tr.width / 2;
    x = Math.max(8, Math.min(x, vw - tr.width - 8));

    // Vertical: arriba de la tarjeta; si no cabe, abajo
    let y = r.top - tr.height - ESPACIO;
    if (y < 8) y = Math.min(r.bottom + ESPACIO, vh - tr.height - 8);

    t.style.left = Math.round(x) + 'px';
    t.style.top  = Math.round(y) + 'px';
  }

  function abrir(el) {
    const txt = el.getAttribute('data-tip');
    if (!txt) return;
    const t = nodo();
    t.textContent = txt;
    t.style.left = '-9999px';       // medir sin parpadeo antes de colocar
    t.classList.add('on');
    colocar(el);
    anclaActual = el;
  }

  function cerrar() {
    if (tip) tip.classList.remove('on');
    anclaActual = null;
  }

  // ── Escritorio: hover ──
  if (!esTactil) {
    document.addEventListener('mouseover', (e) => {
      const el = e.target.closest('[data-tip]');
      if (el && el !== anclaActual) abrir(el);
    });
    document.addEventListener('mouseout', (e) => {
      const el = e.target.closest('[data-tip]');
      if (el && !el.contains(e.relatedTarget)) cerrar();
    });
  }

  // ── Móvil/tablet: tap para abrir, tocar fuera para cerrar ──
  document.addEventListener('click', (e) => {
    const el = e.target.closest('[data-tip]');
    if (!el) { cerrar(); return; }          // tocó fuera → cerrar
    if (el === anclaActual) { cerrar(); return; }  // segundo tap → cerrar
    if (esTactil) abrir(el);
  });

  // ── Cerrar en scroll, resize y Escape (evita tooltips "flotando") ──
  window.addEventListener('scroll', cerrar, true);
  window.addEventListener('resize', cerrar);
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') cerrar(); });
})();
