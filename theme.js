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
 *    sistema-meta     → meta estatal (ej. "208,717")
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
  // [SWAP LUIS ✓ Fase 4] Prioridad de fuentes para la meta estatal:
  //   1. _META_SUPABASE  → valor vivo de configuracion_sistema.sistema_meta (si ya se cargó)
  //   2. IE_METAS_CASILLA.meta_estatal → JSON horneado (208,717)
  //   3. theme.sistemaMeta → default del tema (fallback final)
  // La carga desde Supabase es asíncrona (cargarMetaEstatalSupabase); mientras
  // llega, se pinta el horneado para que no haya parpadeo ni cero.
  let metaVal;
  if (typeof _META_SUPABASE === 'number' && _META_SUPABASE > 0) {
    metaVal = _META_SUPABASE;
  } else if (typeof IE_METAS_CASILLA !== 'undefined' && IE_METAS_CASILLA.meta_estatal) {
    metaVal = IE_METAS_CASILLA.meta_estatal;
  } else {
    metaVal = theme.sistemaMeta;
  }
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

// ══════════════════════════════════════════════════════════════════
//  META ESTATAL DINÁMICA — Fase 4 (T20)
//  Lee configuracion_sistema.sistema_meta con el access_token de la sesión.
//  Fallback obligatorio: si el fetch/RLS falla, NO toca nada y se conserva
//  el valor horneado (208,717) que applyTheme ya pintó. Nunca deja la meta
//  en blanco ni en cero por un error de red o de sesión.
// ══════════════════════════════════════════════════════════════════
let _META_SUPABASE = null; // se llena solo si Supabase responde con un número válido

async function cargarMetaEstatalSupabase() {
  try {
    const sesion = _leerSesionAlcance();
    // Sin sesión o sin licencia_id (uuid como string): no consultar, quedarse con horneado.
    const licenciaId = sesion && sesion.licencia_id ? String(sesion.licencia_id) : null;
    if (!licenciaId) return;
    if (typeof supaFetch !== 'function') return; // supaFetch aún no disponible

    const url = _SUPA_URL_THEME
      + '/rest/v1/configuracion_sistema'
      + '?select=sistema_meta'
      + '&licencia_id=eq.' + encodeURIComponent(licenciaId)
      + '&limit=1';

    const res = await supaFetch(url, { method: 'GET' });
    // RLS o red fallando: NO actualizar UI (fallback = horneado).
    if (!res || !res.ok) return;

    const data = await res.json();
    if (!Array.isArray(data) || data.length === 0) return;

    const val = Number(data[0].sistema_meta);
    if (!Number.isFinite(val) || val <= 0) return; // dato inválido: conservar horneado

    // Éxito: cachear y repintar solo las tarjetas de meta.
    _META_SUPABASE = val;
    // [T20/21] Publicar como fuente única para el resto de módulos (visor T18,
    //  War Room, Reportes). Leen window.SISTEMA_META con fallback al horneado.
    window.SISTEMA_META = val;
    try { window.dispatchEvent(new CustomEvent('sistema-meta-ready', { detail: val })); } catch (e) {}
    applyTheme(loadTheme());
  } catch (e) {
    // Cualquier error: silencioso, se conserva el valor horneado ya pintado.
    console.warn('Meta estatal: usando valor horneado (Supabase no disponible)', e);
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

// ══════════════════════════════════════════════════════════════════
//  AUTO-REFRESH DE TOKEN + supaFetch()
//  ────────────────────────────────────────────────────────────────
//  Problema: el access_token de Supabase expira en 1 hora. Cuando
//  caduca, los fetch/RPC dan 401 y los módulos caen a simulados.
//  El refresh_token dura mucho más; con él se obtiene un token nuevo.
//
//  supaFetch(url, options) envuelve fetch() y:
//    1. Refresca proactivamente si el token está por expirar (>55 min).
//    2. Si aun así da 401, refresca de forma reactiva y reintenta 1 vez.
//  Úsalo en lugar de fetch() para llamadas autenticadas a Supabase.
// ══════════════════════════════════════════════════════════════════
const _SUPA_URL_THEME = 'https://dyirhwwmykskpuvzcafx.supabase.co';
const _SUPA_ANON_THEME = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR5aXJod3dteWtza3B1dnpjYWZ4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1NTk3ODgsImV4cCI6MjA5NTEzNTc4OH0.2xe4cHqORGng1hnYPJ9ZiyT0r87fMijbUEJqBy3-xoI';
const _SESION_KEY_THEME = 'electoral_sesion';

let _refrescandoToken = null; // evita refrescos paralelos

async function refrescarTokenSupabase() {
  // Si ya hay un refresh en curso, esperar a ese (no lanzar otro)
  if (_refrescandoToken) return _refrescandoToken;

  _refrescandoToken = (async () => {
    try {
      const raw = localStorage.getItem(_SESION_KEY_THEME);
      if (!raw) return false;
      const sesion = JSON.parse(raw);
      if (!sesion?.refresh_token) return false;

      const res = await fetch(
        `${_SUPA_URL_THEME}/auth/v1/token?grant_type=refresh_token`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'apikey': _SUPA_ANON_THEME },
          body: JSON.stringify({ refresh_token: sesion.refresh_token }),
        }
      );
      if (!res.ok) {
        console.warn('🔑 No se pudo refrescar el token (status ' + res.status + ')');
        // 400/401 = el refresh_token ya no sirve (expiró tras semanas, o
        // fue consumido). La sesión está muerta: limpiar para forzar
        // re-login en el próximo guard. (Errores de red NO expulsan.)
        if (res.status === 400 || res.status === 401) {
          window._refreshTokenInvalido = true;
        }
        return false;
      }
      const data = await res.json();
      if (!data.access_token) return false;

      // Actualizar la sesión guardada con el token nuevo
      sesion.access_token  = data.access_token;
      sesion.refresh_token = data.refresh_token || sesion.refresh_token;
      sesion.ts = Date.now();
      localStorage.setItem(_SESION_KEY_THEME, JSON.stringify(sesion));
      if (window._sesion) {
        window._sesion.access_token  = sesion.access_token;
        window._sesion.refresh_token = sesion.refresh_token;
        window._sesion.ts = sesion.ts;
      }

      // Sincronizar el cliente SDK de Supabase (módulos que lo usan,
      // como captura) para que sus llamadas usen el token fresco.
      // Como el SDK tiene autoRefreshToken:false, no compite: solo
      // recibe el token que nosotros gestionamos.
      try {
        if (window.supabase?.auth?.setSession) {
          // [FIX 15 jul] CON await: setSession es async. Sin await, un INSERT
          // disparado justo despues corria con auth.uid() null → get_mi_licencia()
          // null → 403 RLS en ciudadanos. Esperamos a que el token quede asentado.
          await window.supabase.auth.setSession({
            access_token:  sesion.access_token,
            refresh_token: sesion.refresh_token,
          });
        }
      } catch (e) { /* el SDK puede no estar cargado en este módulo */ }

      console.log('🔑 Token de Supabase refrescado correctamente');
      return true;
    } catch (e) {
      console.warn('🔑 Error al refrescar token:', e);
      return false;
    } finally {
      _refrescandoToken = null;
    }
  })();

  return _refrescandoToken;
}

function _tokenActual() {
  try {
    return JSON.parse(localStorage.getItem(_SESION_KEY_THEME))?.access_token || _SUPA_ANON_THEME;
  } catch (e) { return _SUPA_ANON_THEME; }
}

async function supaFetch(url, options = {}) {
  // Refresh proactivo si la sesión tiene >55 min (token casi expirado)
  try {
    const s = JSON.parse(localStorage.getItem(_SESION_KEY_THEME) || 'null');
    if (s?.ts && (Date.now() - s.ts) / 60000 > 55) {
      await refrescarTokenSupabase();
    }
  } catch (e) {}

  const armarHeaders = () => ({
    'apikey': _SUPA_ANON_THEME,
    'Authorization': 'Bearer ' + _tokenActual(),
    ...(options.headers || {}),
  });

  let res = await fetch(url, { ...options, headers: armarHeaders() });

  // Refresh reactivo: si dio 401, refrescar y reintentar UNA vez
  if (res.status === 401) {
    const ok = await refrescarTokenSupabase();
    if (ok) {
      res = await fetch(url, { ...options, headers: armarHeaders() });
    }
  }
  return res;
}

// Exponer globalmente para que los módulos lo usen
window.supaFetch = supaFetch;
window.refrescarTokenSupabase = refrescarTokenSupabase;

// Refresh periódico cada 45 min (antes de que expire a los 60)
setInterval(() => {
  try {
    const s = JSON.parse(localStorage.getItem(_SESION_KEY_THEME) || 'null');
    if (s?.access_token) refrescarTokenSupabase();
  } catch (e) {}
}, 45 * 60 * 1000);

// ══════════════════════════════════════════════════════════════════
//  T20 — Cargar meta estatal viva desde Supabase al arrancar.
//  Se ejecuta aquí (final del archivo) porque supaFetch ya está definido.
//  applyTheme ya pintó el valor horneado; esto lo actualiza si Supabase
//  responde. Si falla, no pasa nada (fallback = horneado).
// ══════════════════════════════════════════════════════════════════
(function() {
  const lanzar = () => { cargarMetaEstatalSupabase(); };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', lanzar);
  } else {
    lanzar();
  }
})();

// ══════════════════════════════════════════════════════════════════
//  [18 jul · Tarea 5B José] Modo SOLO LECTURA para el rol "consulta".
//  Marca <body class="rol-consulta"> y oculta controles de escritura
//  (captura/editar/eliminar/exportar) vía CSS. Los módulos pueden marcar
//  cualquier control con la clase .accion-escritura o [data-escritura]
//  para que se oculte; además se ocultan patrones comunes por heurística.
// ══════════════════════════════════════════════════════════════════
(function aplicarModoRol() {
  const marca = () => {
    const ses = _leerSesionAlcance();
    const rol = (ses && ses.rol ? String(ses.rol) : '').toLowerCase().trim();
    if (!rol) return;
    document.body.classList.add('rol-' + rol);
    if (rol === 'consulta') {
      const st = document.createElement('style');
      st.id = 'css-solo-lectura';
      st.textContent =
        '.rol-consulta .accion-escritura,' +
        '.rol-consulta [data-escritura],' +
        '.rol-consulta .btn-capturar,' +
        '.rol-consulta .btn-editar,' +
        '.rol-consulta .btn-eliminar,' +
        '.rol-consulta .btn-exportar,' +
        '.rol-consulta .btn-nuevo{display:none !important;}';
      document.head.appendChild(st);

      // [18 jul · Tarea 5B] Auto-etiquetado: además de las clases explícitas,
      // ocultar botones cuyo onclick invoque una ACCIÓN DE ESCRITURA conocida
      // (exportar/descargar/generar/guardar/editar/eliminar/nuevo/crear). Así
      // el modo lectura cubre módulos que aún no marcaron sus botones a mano y
      // los que se agreguen a futuro. Los filtros/ver/limpiar (solo lectura) se
      // dejan intactos. Re-corre ante cambios del DOM (tablas que se repintan).
      const PATRON_ESCRITURA = /\b(export|exportar|descargar|generar|guardar|editar|eliminar|borrar|crear|nuevo|nueva|enviar|subir|importar)/i;
      const ocultarAcciones = (raiz) => {
        (raiz || document).querySelectorAll('[onclick]').forEach(el => {
          if (el.dataset._lecturaChecked) return;
          el.dataset._lecturaChecked = '1';
          const oc = el.getAttribute('onclick') || '';
          // Excluir explícitamente acciones de solo lectura frecuentes.
          if (/\b(filtrar|limpiar|toggle|ver|mostrar|abrir|cerrarModal|showTab|copiar)/i.test(oc)) return;
          if (PATRON_ESCRITURA.test(oc)) el.style.display = 'none';
        });
      };
      const arrancar = () => {
        ocultarAcciones(document);
        // Observa repintados (rankings, tablas) para volver a ocultar.
        const mo = new MutationObserver(muts => {
          muts.forEach(m => m.addedNodes && m.addedNodes.forEach(n => {
            if (n.nodeType === 1) ocultarAcciones(n);
          }));
        });
        mo.observe(document.body, { childList: true, subtree: true });
      };
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', arrancar);
      } else { arrancar(); }
    }
  };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', marca);
  } else { marca(); }
})();
