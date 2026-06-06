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

function redirigirLogin() {
  if (!window.location.pathname.endsWith('login.html')) {
    window.location.href = 'login.html';
  }
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
  window.location.href = 'login.html';
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