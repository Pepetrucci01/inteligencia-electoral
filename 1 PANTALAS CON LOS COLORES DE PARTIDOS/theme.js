/**
 * ══════════════════════════════════════════════════════
 *  INTELIGENCIA ELECTORAL 2027 — Motor de Temas
 *  theme.js  ·  Incluir en TODOS los módulos
 * ══════════════════════════════════════════════════════
 *
 *  USO: Agregar antes de </body> en cada módulo:
 *    <script src="theme.js"></script>
 *
 *  El admin guarda el tema con saveTheme(config).
 *  Cada módulo lo carga automáticamente al iniciar.
 * ══════════════════════════════════════════════════════
 */

const THEME_KEY = ' electoral_theme_v1';

/** Tema por defecto (dark azul — estado neutro sin partido) */
const DEFAULT_THEME = {
  // Identidad
  partidoNombre: 'Inteligencia Electoral',
  partidoSlogan: 'Sistema de control territorial 2027',
  logoUrl: '',          // URL de imagen o vacío para usar iniciales
  logoInicial: 'IE',    // Iniciales cuando no hay logo

  // Paleta principal
  colorPrimario:    '#3b82f6',   // Botones, accents, highlights
  colorSecundario:  '#06b6d4',   // Estado, etiquetas secundarias
  colorAlerta:      '#ef4444',   // Admin, alertas críticas
  colorExito:       '#22c55e',   // Completado, ok
  colorAdvertencia: '#f59e0b',   // Aviso, pendiente

  // Fondos (dark por defecto — no se suelen cambiar)
  bgBase:   '#0a0e1a',
  bgPanel:  '#0f1526',
  bgCard:   '#141b2e',
  bgCard2:  '#1a2238',

  // Modo
  modoOscuro: true,
};

/**
 * Lee el tema guardado. Si no existe, devuelve el default.
 */
function loadTheme() {
  try {
    const stored = localStorage.getItem(THEME_KEY);
    if (stored) {
      return Object.assign({}, DEFAULT_THEME, JSON.parse(stored));
    }
  } catch(e) {}
  return Object.assign({}, DEFAULT_THEME);
}

/**
 * Guarda el tema en localStorage y lo aplica inmediatamente.
 * Llamar desde modulo_admin cuando el usuario guarda.
 */
function saveTheme(config) {
  const theme = Object.assign(loadTheme(), config);
  localStorage.setItem(THEME_KEY, JSON.stringify(theme));
  applyTheme(theme);
  return theme;
}

/**
 * Aplica el tema al documento actual modificando variables CSS en :root
 * y actualizando elementos de logo si existen.
 */
function applyTheme(theme) {
  theme = theme || loadTheme();
  const root = document.documentElement;

  // ── Colores principales ──
  root.style.setProperty('--accent',   theme.colorPrimario);
  root.style.setProperty('--cyan',     theme.colorSecundario);
  root.style.setProperty('--red',      theme.colorAlerta);
  root.style.setProperty('--green',    theme.colorExito);
  root.style.setProperty('--amber',    theme.colorAdvertencia);

  // ── Fondos ──
  root.style.setProperty('--bg',  theme.bgBase);
  root.style.setProperty('--bg2', theme.bgPanel);
  root.style.setProperty('--bg3', theme.bgCard);
  root.style.setProperty('--bg4', theme.bgCard2);

  // ── Logo / marca ──
  // Busca elementos con data-theme="logo-img" para poner imagen
  document.querySelectorAll('[data-theme="logo-img"]').forEach(el => {
    if (theme.logoUrl) {
      el.src = theme.logoUrl;
      el.style.display = 'block';
    } else {
      el.style.display = 'none';
    }
  });

  // Busca elementos con data-theme="logo-inicial" para poner iniciales
  document.querySelectorAll('[data-theme="logo-inicial"]').forEach(el => {
    el.textContent = theme.logoInicial || 'IE';
    el.style.background = theme.logoUrl ? 'transparent' : theme.colorPrimario;
  });

  // Busca elementos con data-theme="partido-nombre"
  document.querySelectorAll('[data-theme="partido-nombre"]').forEach(el => {
    el.textContent = theme.partidoNombre;
  });

  // Busca elementos con data-theme="partido-slogan"
  document.querySelectorAll('[data-theme="partido-slogan"]').forEach(el => {
    el.textContent = theme.partidoSlogan;
  });

  // ── Gradiente barra de progreso ──
  // Recalcula el gradiente con el color primario
  const hex = theme.colorPrimario;
  const darker = adjustColor(hex, -40);
  document.querySelectorAll('.pb-fill').forEach(el => {
    el.style.background = `linear-gradient(90deg, ${darker}, ${hex})`;
  });
}

/**
 * Oscurece o aclara un color hex.
 * amount negativo = más oscuro, positivo = más claro.
 */
function adjustColor(hex, amount) {
  const num = parseInt(hex.replace('#',''), 16);
  const r = Math.min(255, Math.max(0, (num >> 16) + amount));
  const g = Math.min(255, Math.max(0, ((num >> 8) & 0xff) + amount));
  const b = Math.min(255, Math.max(0, (num & 0xff) + amount));
  return '#' + ((r << 16) | (g << 8) | b).toString(16).padStart(6, '0');
}

/**
 * Retorna el tema actual para que otros scripts lo lean.
 */
function getTheme() {
  return loadTheme();
}

// ── Auto-aplicar al cargar cualquier módulo ──
(function() {
  const theme = loadTheme();
  // Aplica inmediato para evitar flash de colores por defecto
  applyTheme(theme);
  // También después de que el DOM esté listo
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => applyTheme(theme));
  }
})();
