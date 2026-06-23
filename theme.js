/**
 * ══════════════════════════════════════════════════════
 *  INTELIGENCIA ELECTORAL — Motor de Temas
 *  theme.js  ·  Incluir en TODOS los módulos
 * ══════════════════════════════════════════════════════
 *
 *  USO: Agregar antes de </body> en cada módulo:
 *    <script src="theme.js"></script>
 *
 *  El admin guarda el tema con saveTheme(config).
 *  Cada módulo lo carga automáticamente al iniciar.
 *
 *  data-theme attributes disponibles en HTML:
 *    partido-nombre   → nombre del software/partido
 *    partido-slogan   → slogan o subtítulo
 *    logo-img         → <img> del logo
 *    logo-inicial     → div con iniciales
 *    sistema-meta     → meta estatal (ej. "197,297")
 *    sistema-anio     → año de elección (ej. "2027")
 *    sistema-titulo   → "NombreSoftware · Estado AÑO"
 *    dias-eleccion    → cuenta regresiva en días
 * ══════════════════════════════════════════════════════
 */

const THEME_KEY = 'electoral_theme_v1';

/** Tema por defecto */
const DEFAULT_THEME = {
  // Identidad del software
  partidoNombre:  'Inteligencia Electoral',
  partidoSlogan:  'Sistema de control territorial',
  logoUrl:        '',
  logoInicial:    'IE',

  // Datos operativos del cliente
  sistemaEstado:  'Colima',
  sistemaMeta:    197297,        // número — se formatea automáticamente
  sistemaAnio:    2027,          // año de la elección
  fechaEleccion:  '2027-06-01', // ISO — para cuenta regresiva

  // Paleta
  colorPrimario:    '#3b82f6',
  colorSecundario:  '#06b6d4',
  colorAlerta:      '#ef4444',
  colorExito:       '#22c55e',
  colorAdvertencia: '#f59e0b',

  // Fondos
  bgBase:  '#0a0e1a',
  bgPanel: '#0f1526',
  bgCard:  '#141b2e',
  bgCard2: '#1a2238',
};

/* ── Lectura / escritura ── */
function loadTheme() {
  try {
    const s = localStorage.getItem(THEME_KEY);
    if (s) return Object.assign({}, DEFAULT_THEME, JSON.parse(s));
  } catch(e) {}
  return Object.assign({}, DEFAULT_THEME);
}

function saveTheme(config) {
  const theme = Object.assign(loadTheme(), config);
  localStorage.setItem(THEME_KEY, JSON.stringify(theme));
  applyTheme(theme);
  return theme;
}

function getTheme() { return loadTheme(); }

/* ── Aplicar tema al DOM ── */
function applyTheme(theme) {
  theme = theme || loadTheme();
  const root = document.documentElement;

  // Colores CSS
  root.style.setProperty('--accent',   theme.colorPrimario);
  root.style.setProperty('--cyan',     theme.colorSecundario);
  root.style.setProperty('--red',      theme.colorAlerta);
  root.style.setProperty('--green',    theme.colorExito);
  root.style.setProperty('--amber',    theme.colorAdvertencia);

  // Fondos
  root.style.setProperty('--bg',  theme.bgBase);
  root.style.setProperty('--bg2', theme.bgPanel);
  root.style.setProperty('--bg3', theme.bgCard);
  root.style.setProperty('--bg4', theme.bgCard2);

  // Logo imagen
  document.querySelectorAll('[data-theme="logo-img"]').forEach(el => {
    if (theme.logoUrl) { el.src = theme.logoUrl; el.style.display = 'block'; }
    else               { el.style.display = 'none'; }
  });

  // Logo iniciales
  document.querySelectorAll('[data-theme="logo-inicial"]').forEach(el => {
    // Limpiar nodos de texto manteniendo el <img> si existe
    el.childNodes.forEach(n => { if (n.nodeType === 3) n.textContent = ''; });
    // Poner iniciales como primer texto
    const ini = theme.logoInicial || 'IE';
    el.insertAdjacentText('afterbegin', ini);
    el.style.background = theme.logoUrl ? 'transparent' : theme.colorPrimario;
  });

  // Nombre del partido/software
  document.querySelectorAll('[data-theme="partido-nombre"]').forEach(el => {
    el.textContent = theme.partidoNombre;
  });

  // Slogan
  document.querySelectorAll('[data-theme="partido-slogan"]').forEach(el => {
    el.textContent = theme.partidoSlogan;
  });

  // Meta estatal (formateada con comas)
  const metaFmt = Number(theme.sistemaMeta).toLocaleString('es-MX');
  document.querySelectorAll('[data-theme="sistema-meta"]').forEach(el => {
    el.textContent = metaFmt;
  });

  // Año de elección
  document.querySelectorAll('[data-theme="sistema-anio"]').forEach(el => {
    el.textContent = theme.sistemaAnio;
  });

  // Título compuesto: "NombreSoftware · Estado AÑO"
  document.querySelectorAll('[data-theme="sistema-titulo"]').forEach(el => {
    el.textContent = `${theme.partidoNombre} · ${theme.sistemaEstado} ${theme.sistemaAnio}`;
  });

  // Cuenta regresiva: días a la elección
  try {
    const dias = Math.ceil((new Date(theme.fechaEleccion) - new Date()) / 864e5);
    document.querySelectorAll('[data-theme="dias-eleccion"]').forEach(el => {
      el.textContent = dias > 0 ? dias : '0';
    });
  } catch(e) {}

  // Gradiente barras de progreso
  const darker = adjustColor(theme.colorPrimario, -40);
  document.querySelectorAll('.pb-fill').forEach(el => {
    el.style.background = `linear-gradient(90deg, ${darker}, ${theme.colorPrimario})`;
  });

  // Actualizar <title> de la página si tiene data-theme-title
  const titleEl = document.querySelector('title[data-theme]');
  if (titleEl) {
    titleEl.textContent = `${theme.partidoNombre} — ${theme.sistemaEstado} ${theme.sistemaAnio}`;
  }
}

function adjustColor(hex, amount) {
  const num = parseInt(hex.replace('#',''), 16);
  const r = Math.min(255, Math.max(0, (num >> 16) + amount));
  const g = Math.min(255, Math.max(0, ((num >> 8) & 0xff) + amount));
  const b = Math.min(255, Math.max(0, (num & 0xff) + amount));
  return '#' + ((r << 16) | (g << 8) | b).toString(16).padStart(6, '0');
}

// Auto-aplicar al cargar
(function() {
  const theme = loadTheme();
  applyTheme(theme);
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => applyTheme(theme));
  }
})();

// ══════════════════════════════════════════════════════════════════
//  BADGE DE ALCANCE — distingue Coordinador General de Municipal
//  ────────────────────────────────────────────────────────────────
//  Se auto-inyecta en la .topbar de CUALQUIER módulo que cargue
//  theme.js. No requiere editar el HTML de cada módulo.
//
//  El rol en la base es 'coordinador' para ambos tipos; se
//  distinguen por el municipio (igual que el RPC get_war_room_kpis):
//    municipio NULL/vacío  -> Coordinador General (estatal)
//    municipio asignado    -> Coordinador Municipal (su municipio)
//  super_admin / admin     -> Vista Estatal
// ══════════════════════════════════════════════════════════════════
function _leerSesionAlcance() {
  // Prioriza window._sesion (lo expone auth-guard); cae a localStorage.
  try {
    if (window._sesion && window._sesion.rol) return window._sesion;
    const raw = localStorage.getItem('electoral_sesion');
    return raw ? JSON.parse(raw) : null;
  } catch (e) { return null; }
}

function _calcularAlcance(sesion) {
  if (!sesion || !sesion.rol) return null;
  const rol = sesion.rol;
  const mun = (sesion.municipio || '').trim();

  if (rol === 'super_admin' || rol === 'admin') {
    return { texto: '🌐 Vista Estatal', clase: 'estatal' };
  }
  if (rol === 'coordinador' && !mun) {
    return { texto: '🌐 Coordinador General · Estatal', clase: 'estatal' };
  }
  if (rol === 'coordinador' && mun) {
    const munLindo = mun.charAt(0).toUpperCase() + mun.slice(1).toLowerCase();
    return { texto: '📍 Coordinador Municipal · ' + munLindo, clase: 'municipal' };
  }
  // jefe_seccion / capturista u otros: no mostrar (su alcance es obvio
  // por el propio módulo; el badge es para distinguir coordinadores).
  return null;
}

function montarBadgeAlcance() {
  try {
    // Evitar duplicados si se llama más de una vez, o si el módulo
    // ya tiene su propio badge de alcance (ej. War Room usa #badge-alcance).
    if (document.getElementById('badge-alcance-global')) return;
    if (document.getElementById('badge-alcance')) return;

    const sesion = _leerSesionAlcance();
    const info = _calcularAlcance(sesion);
    if (!info) return;   // rol sin badge (capturista, jefe_seccion, sin sesión)

    const topbar = document.querySelector('.topbar');
    if (!topbar) return; // módulo sin topbar estándar

    // Inyectar estilos una sola vez
    if (!document.getElementById('badge-alcance-css')) {
      const st = document.createElement('style');
      st.id = 'badge-alcance-css';
      st.textContent =
        '.badge-alcance-global{display:inline-flex;align-items:center;gap:6px;' +
        'font-size:11px;font-family:var(--mono,monospace);font-weight:600;' +
        'padding:4px 12px;border-radius:99px;letter-spacing:.02em;white-space:nowrap;}' +
        '.badge-alcance-global.estatal{color:var(--accent,#3b82f6);' +
        'background:rgba(59,130,246,.12);border:1px solid rgba(59,130,246,.3);}' +
        '.badge-alcance-global.municipal{color:var(--amber,#f59e0b);' +
        'background:rgba(245,158,11,.12);border:1px solid rgba(245,158,11,.3);}';
      document.head.appendChild(st);
    }

    const badge = document.createElement('div');
    badge.id = 'badge-alcance-global';
    badge.className = 'badge-alcance-global ' + info.clase;
    badge.textContent = info.texto;

    // Colocación: si hay un contenedor derecho conocido, va al inicio de él;
    // si no, se agrega al final de la topbar (que suele ser flex).
    const derecha = topbar.querySelector('.topbar-right, .tb-r');
    if (derecha) {
      derecha.insertBefore(badge, derecha.firstChild);
    } else {
      // Empujar a la derecha si la topbar es flex sin contenedor
      badge.style.marginLeft = 'auto';
      topbar.appendChild(badge);
    }
  } catch (e) {
    console.warn('No se pudo montar el badge de alcance:', e);
  }
}

// Auto-montar al cargar (espera al DOM y a que exista la sesión)
(function() {
  function intentar() {
    montarBadgeAlcance();
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', intentar);
  } else {
    intentar();
  }
  // Reintento tardío por si la sesión se hidrata después (async)
  setTimeout(intentar, 1200);
})();
