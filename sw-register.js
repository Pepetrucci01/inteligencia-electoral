// ============================================================
//  SW REGISTER — SIE COLIMA 2027  (Fase 5 · Pieza 5)
//  Registra el Service Worker. Incluir SOLO en las páginas que
//  deben funcionar offline (por ahora: modulo_captura.html).
// ============================================================

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./service-worker.js')
      .then(reg => {
        console.log('🛠 Service Worker registrado:', reg.scope);

        // Detectar cuando hay una versión nueva esperando.
        reg.addEventListener('updatefound', () => {
          const nuevo = reg.installing;
          if (!nuevo) return;
          nuevo.addEventListener('statechange', () => {
            if (nuevo.state === 'installed' && navigator.serviceWorker.controller) {
              console.log('🔄 Nueva versión disponible. Recarga para actualizar.');
            }
          });
        });
      })
      .catch(err => console.warn('⚠️ No se pudo registrar Service Worker:', err));
  });
} else {
  console.warn('Este navegador no soporta Service Workers — la app no abrirá offline.');
}
