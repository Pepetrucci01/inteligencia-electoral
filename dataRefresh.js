// ══════════════════════════════════════════════════════════════════
// dataRefresh.js — Refresco periódico para paneles de mando (T11-14)
// ──────────────────────────────────────────────────────────────────
// Helper genérico y reutilizable. Envuelve una función de carga (que
// YA sabe leer sus datos y repintar su DOM) y la reejecuta en un
// intervalo, con las protecciones que un panel en vivo necesita:
//
//   • NO SOLAPA: si un tick anterior sigue en vuelo, este se salta.
//     (Evita apilar fetches cuando la red va lenta o el intervalo es
//      corto — la causa clásica de "Failed to fetch" en cascada.)
//   • PAUSA EN BACKGROUND: si la pestaña no está visible, no dispara.
//     Al volver al foco, refresca UNA vez de inmediato y reanuda.
//     (Ahorra cuota de Supabase y batería en pantallas de mando que
//      quedan abiertas todo el día.)
//   • ERRORES SILENCIOSOS: cualquier throw de la función se loguea
//     como warn y el ciclo CONTINÚA. Un fallo puntual (token
//     renovándose, recarga en caliente de Live Server abortando el
//     fetch) nunca detiene el refresco.
//
// Uso:
//   const r = createRefresher({
//     fn: cargarDesdeRPC,          // async o sync; su valor se ignora
//     intervalMs: 30000,           // default 30s
//     label: 'war-room'            // para los logs
//   });
//   r.start();                     // arranca el ciclo
//   r.stop();                      // lo detiene y limpia todo
//
// El intervalo se lee EN CADA TICK, así que puedes cambiarlo en vivo:
//   r.setInterval(10000);         // p.ej. bajar a 10s el día E
// ══════════════════════════════════════════════════════════════════
(function (global) {
  'use strict';

  function createRefresher(config) {
    const fn         = config && config.fn;
    const label      = (config && config.label) || 'refresh';
    let   intervalMs = (config && config.intervalMs) || 30000;

    if (typeof fn !== 'function') {
      console.warn(`[dataRefresh:${label}] fn no es una función; refresher inerte.`);
      return { start(){}, stop(){}, setInterval(){}, isRunning: () => false };
    }

    let timerId   = null;   // id del setTimeout activo
    let inFlight  = false;  // hay un tick ejecutándose ahora mismo
    let running   = false;  // el ciclo está encendido
    let visHooked = false;  // ya enganchamos visibilitychange

    // Programa el siguiente tick leyendo intervalMs en el momento
    // (permite cambiarlo en caliente sin reiniciar el refresher).
    function schedule() {
      if (!running) return;
      clearTimeout(timerId);
      timerId = setTimeout(tick, intervalMs);
    }

    async function tick() {
      if (!running) return;

      // Pestaña en background → no gastamos; reprogramamos y salimos.
      // visibilitychange se encarga de refrescar al volver al foco.
      if (typeof document !== 'undefined' && document.hidden) {
        schedule();
        return;
      }

      // Un tick anterior sigue corriendo → saltamos éste.
      if (inFlight) {
        schedule();
        return;
      }

      inFlight = true;
      try {
        await fn();
      } catch (e) {
        // Nunca romper el ciclo por un fallo puntual.
        console.warn(`[dataRefresh:${label}] tick falló (se reintenta):`, e);
      } finally {
        inFlight = false;
        schedule();
      }
    }

    // Al volver al foco: refresco inmediato (si no hay uno en vuelo).
    function onVisibility() {
      if (!running) return;
      if (typeof document !== 'undefined' && !document.hidden && !inFlight) {
        clearTimeout(timerId);   // adelantamos el próximo tick a "ya"
        tick();
      }
    }

    return {
      start() {
        if (running) return;
        running = true;
        if (!visHooked && typeof document !== 'undefined') {
          document.addEventListener('visibilitychange', onVisibility);
          visHooked = true;
        }
        console.log(`[dataRefresh:${label}] iniciado · cada ${intervalMs / 1000}s`);
        schedule();
      },
      stop() {
        running = false;
        clearTimeout(timerId);
        timerId = null;
        if (visHooked && typeof document !== 'undefined') {
          document.removeEventListener('visibilitychange', onVisibility);
          visHooked = false;
        }
        console.log(`[dataRefresh:${label}] detenido`);
      },
      // Cambia el intervalo en vivo; el nuevo valor aplica al próximo tick.
      setInterval(ms) {
        if (typeof ms === 'number' && ms > 0) {
          intervalMs = ms;
          console.log(`[dataRefresh:${label}] intervalo → ${ms / 1000}s`);
          if (running) schedule();   // reprograma con el nuevo valor
        }
      },
      isRunning: () => running,
    };
  }

  global.createRefresher = createRefresher;
})(window);
