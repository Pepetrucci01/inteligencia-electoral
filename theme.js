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
  sistemaMeta:    208717,        // número — se formatea automáticamente (meta Colima 2027 depurada)
  sistemaAnio:    2027,          // año de la elección
  fechaEleccion:  '2027-06-06', // ISO — para cuenta regresiva (fecha oficial elección)

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
  // REGLA: --accent (y toda la paleta) SIEMPRE en versión legible sobre fondo
  // oscuro, porque los módulos los usan para TEXTO (.kv, .pb-pct, etc.).
  // El color crudo del partido vive en --accent-solid (fondos, botones, logo).
  root.style.setProperty('--accent',       ensureVisibleColor(theme.colorPrimario));
  root.style.setProperty('--accent-solid', theme.colorPrimario);
  root.style.setProperty('--accent-text',  ensureVisibleColor(theme.colorPrimario)); // compat: se conserva
  root.style.setProperty('--cyan',   ensureVisibleColor(theme.colorSecundario));
  root.style.setProperty('--red',    ensureVisibleColor(theme.colorAlerta));
  root.style.setProperty('--green',  ensureVisibleColor(theme.colorExito));
  root.style.setProperty('--amber',  ensureVisibleColor(theme.colorAdvertencia));

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
    // Si el primario es muy oscuro, el cuadro del logo usa la versión aclarada
    // para no fundirse con el sidebar (las iniciales van en blanco encima).
    el.style.background = theme.logoUrl ? 'transparent' : ensureVisibleColor(theme.colorPrimario);
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
  // [SWAP LUIS] Fuente única: si el JSON horneado está cargado, su meta_estatal
  // manda sobre el default del tema. En Fase 4 esto vendrá de configuracion_sistema.
  const metaVal = (typeof IE_METAS_CASILLA !== 'undefined' && IE_METAS_CASILLA.meta_estatal)
                    ? IE_METAS_CASILLA.meta_estatal : theme.sistemaMeta;
  const metaFmt = Number(metaVal).toLocaleString('es-MX');
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

  // Gradiente barras de progreso (versión visible si el primario es muy oscuro)
  const pbColor = ensureVisibleColor(theme.colorPrimario);
  const darker = adjustColor(pbColor, -40);
  document.querySelectorAll('.pb-fill').forEach(el => {
    el.style.background = `linear-gradient(90deg, ${darker}, ${pbColor})`;
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

/**
 * Versión LEGIBLE del color primario para textos/bordes sobre fondo oscuro.
 * Si el color es muy oscuro (ej. negro, guinda), se aclara automáticamente.
 * Los fondos de botones siguen usando --accent puro (texto blanco encima).
 */
function ensureVisibleColor(hex) {
  try {
    let h = String(hex || '').trim().replace('#','');
    if (h.length === 3) h = h[0]+h[0]+h[1]+h[1]+h[2]+h[2];   // soporta #abc
    if (!/^[0-9a-fA-F]{6}$/.test(h)) return DEFAULT_THEME.colorPrimario; // inválido → azul default
    const num = parseInt(h, 16);
    const r = (num >> 16) & 0xff, g = (num >> 8) & 0xff, b = num & 0xff;
    const lum = (0.2126*r + 0.7152*g + 0.0722*b) / 255; // luminancia relativa
    if (lum >= 0.28) return '#' + h.toLowerCase();       // ya es legible
    return adjustColor('#' + h, Math.round((0.42 - lum) * 400)); // aclarar
  } catch(e) { return DEFAULT_THEME.colorPrimario; }
}

/**
 * Regresar al tema default (azul / fondos originales).
 * Borra el tema guardado y re-aplica DEFAULT_THEME en el DOM.
 * El admin puede llamar resetTheme() en su botón "Restaurar default".
 */
function resetTheme() {
  try { localStorage.removeItem(THEME_KEY); } catch(e) {}
  const theme = Object.assign({}, DEFAULT_THEME);
  applyTheme(theme);
  return theme;
}

// Auto-aplicar al cargar
(function() {
  const theme = loadTheme();
  applyTheme(theme);
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => applyTheme(theme));
  }
})();
