/**
 * auth-guard.js — Inteligencia Electoral
 * Incluir en TODAS las páginas protegidas antes de cualquier otro script.
 * Carga window._sesion desde localStorage y redirige si no hay sesión válida.
 */

const SESION_DURACION_HORAS = 8;
const SESION_KEY = 'electoral_sesion';
const SUPABASE_URL = 'https://dyirhwwmykskpuvzcafx.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR5aXJod3dteWtza3B1dnpjYWZ4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1NTk3ODgsImV4cCI6MjA5NTEzNTc4OH0.2xe4cHqORGng1hnYPJ9ZiyT0r87fMijbUEJqBy3-xoI';

// ── Cargar sesión ──────────────────────────────────────────────
(function () {
  try {
    const raw = localStorage.getItem(SESION_KEY);
    if (!raw) return redirigirLogin();

    const sesion = JSON.parse(raw);
    if (!sesion || !sesion.ts || !sesion.access_token) return redirigirLogin();

    const horas = (Date.now() - sesion.ts) / 3600000;
    if (horas >= SESION_DURACION_HORAS) {
      localStorage.removeItem(SESION_KEY);
      return redirigirLogin();
    }

    // ✅ Sesión válida — exponer globalmente
    window._sesion = {
      usuario_id:    sesion.id,
      nombre:        sesion.nombre,
      email:         sesion.email,
      rol:           sesion.rol,
      licencia_id:   sesion.licencia_id || null,
      municipio:     sesion.municipio || '',
      seccion:       sesion.seccion || null,
      access_token:  sesion.access_token,
      refresh_token: sesion.refresh_token,
      ts:            sesion.ts,
    };

  } catch (e) {
    console.error('auth-guard error:', e);
    redirigirLogin();
  }
})();

// [FIX 7 sep] ¿Estamos dentro del iframe del hub? Toda navegación al login
// debe hacerse en la ventana COMPLETA: si se hace en el iframe, el login queda
// embebido y al entrar de nuevo se carga un hub dentro del hub.
function _enIframe() {
  try { return window.top !== window.self; } catch (e) { return true; }
}
function _irALogin(reemplazar) {
  try {
    const destino = _enIframe() ? window.top : window;
    if (reemplazar) destino.location.replace('login.html');
    else destino.location.href = 'login.html';
  } catch (e) {
    // Sin acceso a window.top (no debería pasar: mismo origen). Último recurso.
    window.location.href = 'login.html';
  }
}

function redirigirLogin() {
  if (!window.location.pathname.endsWith('login.html')) {
    _irALogin(false);
  }
}

// [FIX 7 sep] Pantalla "sin acceso" para un módulo abierto dentro del hub con
// un rol que no lo permite. Antes rebotaba al login (dentro del iframe). Ahora
// tapa el módulo con un aviso claro y deja al usuario regresar al inicio.
function mostrarSinAcceso(rol, rolesPermitidos) {
  const pintar = () => {
    if (document.getElementById('ie-sin-acceso')) return;
    const o = document.createElement('div');
    o.id = 'ie-sin-acceso';
    o.style.cssText = 'position:fixed;inset:0;z-index:2147483000;background:#0a0e1a;color:#e8edf5;' +
      'display:flex;align-items:center;justify-content:center;padding:24px;text-align:center;' +
      "font-family:'IBM Plex Sans',system-ui,sans-serif;";
    o.innerHTML =
      '<div style="max-width:380px">' +
        '<div style="font-size:40px;margin-bottom:12px">🔒</div>' +
        '<div style="font-size:17px;font-weight:600;margin-bottom:8px">No tienes acceso a este módulo</div>' +
        '<div style="font-size:12px;color:#8a9ab5;line-height:1.5;font-family:\'IBM Plex Mono\',monospace">' +
          'Tu rol actual (<b style="color:#e8edf5">' + (rol || 'sin sesión') + '</b>) no incluye este módulo.<br>' +
          'Si acabas de cambiar de usuario, recarga el sistema.</div>' +
        '<div style="display:flex;gap:8px;justify-content:center;margin-top:18px;flex-wrap:wrap">' +
          '<button onclick="try{window.top.location.reload()}catch(e){location.reload()}" style="background:#3b82f6;color:#fff;border:none;border-radius:6px;padding:9px 16px;font-size:12px;cursor:pointer;font-family:inherit">↻ Recargar sistema</button>' +
          '<button onclick="try{window.parent.postMessage({tipo:\'ie:volver-al-hub\'},\'*\')}catch(e){}" style="background:rgba(255,255,255,.06);color:#e8edf5;border:1px solid rgba(255,255,255,.13);border-radius:6px;padding:9px 16px;font-size:12px;cursor:pointer;font-family:inherit">⌂ Ir al inicio</button>' +
        '</div>' +
      '</div>';
    (document.body || document.documentElement).appendChild(o);
  };
  if (document.body) pintar(); else document.addEventListener('DOMContentLoaded', pintar);
}

// ── Defensa en profundidad: exigir rol al cargar un módulo ─────
// Uso en cada módulo sensible, justo después de cargar auth-guard.js:
//   exigirRol(['admin','super_admin']);
// Si el rol de la sesión no está en la lista, rebota a login.
// Esto protege aunque alguien abra el archivo por URL directa
// (ocultar el botón en el menú NO es suficiente).
function exigirRol(rolesPermitidos) {
  const rol = window._sesion?.rol;
  if (!rol || !rolesPermitidos.includes(rol)) {
    console.warn('Acceso denegado para rol:', rol, '— se requiere:', rolesPermitidos.join('/'));
    // [FIX 7 sep] Dentro del hub: aviso en el iframe (no login embebido).
    // Abierto por URL directa: rebota al login como siempre.
    if (_enIframe() && rol) { mostrarSinAcceso(rol, rolesPermitidos); }
    else { _irALogin(true); }
    return false;
  }
  return true;
}

// ── Ocultar elementos del menú según rol ──────────────────────
// Marca en el HTML con data-rol="admin,super_admin" los enlaces/botones
// que solo ciertos roles deben ver. Esta función los oculta si el rol
// actual no aplica. Llamar tras DOMContentLoaded.
function aplicarVisibilidadPorRol() {
  const rol = window._sesion?.rol;
  document.querySelectorAll('[data-rol]').forEach(el => {
    const permitidos = (el.getAttribute('data-rol') || '').split(',').map(s => s.trim());
    if (!permitidos.includes(rol)) el.style.display = 'none';
  });
}
if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', aplicarVisibilidadPorRol);
}

// ── Cerrar sesión ──────────────────────────────────────────────
function cerrarSesion() {
  // Invalidar token en Supabase
  if (window._sesion?.access_token) {
    fetch(`${SUPABASE_URL}/auth/v1/logout`, {
      method: 'POST',
      headers: {
        'apikey': SUPABASE_ANON,
        'Authorization': `Bearer ${window._sesion.access_token}`,
      },
    }).catch(() => {});
  }
  localStorage.removeItem(SESION_KEY);
  // [FIX 7 sep] Salir desde el header de un módulo dentro del hub llevaba el
  // login AL IFRAME. Ahora siempre sale en la ventana completa.
  _irALogin(false);
}

// ── Refresh de token (cada 30 min) ────────────────────────────
async function refreshToken() {
  const sesion = window._sesion;
  if (!sesion?.refresh_token) return;

  try {
    const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SUPABASE_ANON,
      },
      body: JSON.stringify({ refresh_token: sesion.refresh_token }),
    });

    if (!res.ok) return;
    const data = await res.json();

    // Actualizar tokens en localStorage y window._sesion
    const raw = JSON.parse(localStorage.getItem(SESION_KEY));
    raw.access_token  = data.access_token;
    raw.refresh_token = data.refresh_token;
    raw.ts = Date.now();
    localStorage.setItem(SESION_KEY, JSON.stringify(raw));

    window._sesion.access_token  = data.access_token;
    window._sesion.refresh_token = data.refresh_token;
    window._sesion.ts = Date.now();

  } catch (e) {
    console.warn('refresh token falló:', e);
  }
}

// Refresh automático cada 30 minutos
setInterval(refreshToken, 30 * 60 * 1000);

// ── Helper para fetch autenticado a Supabase ──────────────────
function supabaseFetch(path, options = {}) {
  const headers = {
    'apikey': SUPABASE_ANON,
    'Authorization': `Bearer ${window._sesion?.access_token}`,
    'Content-Type': 'application/json',
    ...(options.headers || {}),
  };
  return fetch(`${SUPABASE_URL}/rest/v1/${path}`, { ...options, headers });
}