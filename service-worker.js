// ============================================================
//  SERVICE WORKER — SIE COLIMA 2027  (Fase 5 · Pieza 5)
//  Cachea SOLO el módulo de captura y sus dependencias para
//  que la app abra sin internet en campo.
//
//  ⚠️ Al cambiar cualquier archivo cacheado, SUBE CACHE_VERSION
//     (v1 → v2...). Eso borra el caché viejo automáticamente y
//     evita servir versiones obsoletas.
// ============================================================

const CACHE_VERSION = 'sie-captura-v2';

// Archivos propios: se sirven "network-first" (fresco si hay red).
const ARCHIVOS_APP = [
  './modulo_captura.html',
  './theme.js',
  './supabase_client.js',
  './offline_db.js',
  './sync_queue.js',
  './conflictos.js',
];

// Recursos externos estables: "cache-first" (no cambian).
const RECURSOS_EXTERNOS = [
  'https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@300;400;500;600&display=swap',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',
];

// Dominios que NUNCA se cachean (datos en vivo).
const NO_CACHEAR = [
  'api.renapo.gob.mx',         // consulta CURP en vivo
  '.supabase.co',              // base de datos
  'supabase.co/rest',
  'supabase.co/auth',
];

// ── INSTALACIÓN: precachear lo esencial ──────────────────────
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((cache) => {
      // addAll falla si UN archivo falla; por eso los añadimos
      // tolerando errores individuales (mejor algo que nada).
      return Promise.allSettled([
        ...ARCHIVOS_APP.map(u => cache.add(u).catch(e => console.warn('SW no cacheó', u, e))),
        ...RECURSOS_EXTERNOS.map(u => cache.add(u).catch(e => console.warn('SW no cacheó', u, e))),
      ]);
    })
  );
  self.skipWaiting();   // activa la versión nueva de inmediato
});

// ── ACTIVACIÓN: borrar cachés de versiones anteriores ────────
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((claves) =>
      Promise.all(
        claves
          .filter(k => k.startsWith('sie-captura-') && k !== CACHE_VERSION)
          .map(k => caches.delete(k))
      )
    )
  );
  self.clients.claim();
});

// ── Utilidad: ¿esta URL no debe cachearse? ──────────────────
function esNoCacheable(url) {
  return NO_CACHEAR.some(d => url.includes(d));
}

// ── FETCH: interceptar peticiones ────────────────────────────
self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = req.url;

  // Solo GET; nunca POST/PUT (inserts a Supabase, etc.).
  if (req.method !== 'GET') return;

  // Datos en vivo: dejar pasar directo a la red, sin caché.
  if (esNoCacheable(url)) return;

  // Recursos externos estables: cache-first.
  if (RECURSOS_EXTERNOS.some(r => url.startsWith(r.split('?')[0]))) {
    event.respondWith(
      caches.match(req).then(hit => hit || fetch(req).then(resp => {
        const copia = resp.clone();
        caches.open(CACHE_VERSION).then(c => c.put(req, copia));
        return resp;
      }).catch(() => hit))
    );
    return;
  }

  // Archivos propios y navegación: network-first con fallback a caché.
  event.respondWith(
    fetch(req)
      .then(resp => {
        // Solo cachear respuestas EXITOSAS (status 200, tipo básico).
        // Esto evita guardar errores 404/500 (que vienen como HTML) y
        // servirlos después por error — la causa del bug del token '<'.
        if (resp && resp.status === 200 && resp.type === 'basic') {
          const copia = resp.clone();
          caches.open(CACHE_VERSION).then(c => c.put(req, copia));
        }
        return resp;
      })
      .catch(() =>
        // Sin red: servir de caché. Si es navegación y no hay copia,
        // devolver el módulo de captura cacheado como respaldo.
        caches.match(req).then(hit =>
          hit || caches.match('./modulo_captura.html')
        )
      )
  );
});
