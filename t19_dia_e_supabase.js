/* ============================================================================
 * T19 — Capa Día E en vivo (Swap 2 del visor, Fase 4, rama desarrollo)
 * Sustituye la SIMULACIÓN temporal (slider de hora) por el ESTADO ACTUAL real
 * leído de reportes_casilla_eleccion + casillas vía Supabase (polling 60s).
 *
 * DECISIÓN DE PRODUCTO (10 jul): "Estado ACTUAL en vivo".
 *   - Con datos reales NO hay dimensión de hora arrastrable → se oculta el slider.
 *   - El mapa muestra cómo está cada sección AHORA; se refresca cada 60s.
 *
 * CONTRATO PRESERVADO (no romper — el visor pinta con estas firmas):
 *   statsSeccionDiaE(sec)      -> { n, inst, rep, votos, metaP }
 *   getDiaEColorSeccion(sec)   -> color (#hex)
 *   actualizarResumenDiaE()    -> escribe #dia-e-resumen
 *
 * FALLBACK OBLIGATORIO: si el fetch falla, RLS devuelve objeto de error, o la
 * tabla aún no existe, NO se toca nada: las funciones originales (simulación)
 * siguen operando y el slider reaparece. La demo nunca se rompe.
 *
 * ✅ ESQUEMA CONFIRMADO contra la BD (10 jul 2026). Columnas reales:
 *   casilla_id (uuid → casillas.id) · abierta/cerrada (bool) · votos_partido (int)
 *   hora_apertura (time) · licencia_id (uuid) · votos_total · lista_nominal
 * ⚠️ El join es por casilla_id (UUID), NO por casilla_completa (texto INE).
 *   Por eso T18 ahora expone `cid` en cada casilla del contrato. Si T18 no
 *   corre antes, no hay `cid` y esta capa cae al fallback de simulación.
 * ========================================================================== */
(function () {
  'use strict';

  // ── Esquema REAL de reportes_casilla_eleccion (confirmado en BD, 10 jul) ──
  //  ⚠️ OJO: el join NO es por casilla_completa (texto INE), sino por
  //     casilla_id (uuid) → casillas.id. Por eso T18 ahora expone `cid`.
  var COLS = {
    tabla:    'reportes_casilla_eleccion',
    casilla:  'casilla_id',      // uuid → casillas.id  (NO el texto INE)
    abierta:  'abierta',         // bool
    cerrada:  'cerrada',         // bool
    votos:    'votos_partido',   // integer — votos del partido
    hora_ap:  'hora_apertura'    // time
  };

  var POLL_MS = 60000;                  // 60s (instructivo José)
  var _timer = null;
  var _real = null;                     // Map: casilla_completa(string) -> {estado, votos}
  var _lastSync = null;

  // Referencias a las funciones ORIGINALES (simulación) para el fallback.
  // IMPORTANTE: este script se carga en el <head>, ANTES de que el visor declare
  // statsSeccionDiaE/etc. más abajo en el <body>. Por hoisting de las function
  // declarations del visor, capturarlas aquí daría undefined y además el visor
  // sobrescribiría nuestros overrides. Por eso capturamos e instalamos los
  // overrides dentro de instalarOverrides(), llamado en DOMContentLoaded.
  var _origStats = null, _origResumen = null, _origColor = null;

  // ── Fetch del estado real ───────────────────────────────────────────────
  async function cargarDiaESupabase() {
    try {
      var _ses = JSON.parse(localStorage.getItem('electoral_sesion') || 'null');
      var LICENCIA_ID = (_ses && _ses.licencia_id) ? String(_ses.licencia_id) : null;

      var SUPA_URL = window.SUPABASE_URL || 'https://dyirhwwmykskpuvzcafx.supabase.co';

      // ⚠️ BUG CORREGIDO (10 jul): antes esto era `window.SUPABASE_KEY`, pero esa
      //   const NO es global (vive en el scope cerrado del visor) → llegaba
      //   undefined → se mandaba `apikey: undefined` → Supabase respondía 401
      //   ("no sé quién eres"), NO 403. Por eso el GRANT no arreglaba nada:
      //   el request ni siquiera se autenticaba. Ahora la key es autocontenida,
      //   igual que en T21.
      var SUPA_KEY = window.SUPABASE_KEY
        || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR5aXJod3dteWtza3B1dnpjYWZ4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1NTk3ODgsImV4cCI6MjA5NTEzNTc4OH0.2xe4cHqORGng1hnYPJ9ZiyT0r87fMijbUEJqBy3-xoI';

      var _fetch = window.supaFetch || fetch;
      var token = (window._sesion && window._sesion.access_token)
        || (_ses && _ses.access_token) || SUPA_KEY;

      var headers = {
        'apikey': SUPA_KEY,
        'Authorization': 'Bearer ' + token,
        'Content-Type': 'application/json'
      };

      var sel = [COLS.casilla, COLS.abierta, COLS.cerrada, COLS.votos, COLS.hora_ap].join(',');
      var url = SUPA_URL + '/rest/v1/' + COLS.tabla
        + '?select=' + encodeURIComponent(sel)
        + (LICENCIA_ID ? '&licencia_id=eq.' + encodeURIComponent(LICENCIA_ID) : '');

      var res = await _fetch(url, { method: 'GET', headers: headers });
      if (!res || !res.ok) {
        // Loguear el CUERPO del error: PostgREST dice el motivo exacto
        // (401 = token/apikey mal · 403 code 42501 = falta GRANT · RLS, etc.)
        var det = res ? await res.text().catch(function () { return ''; }) : '';
        console.warn('⚠️ T19 Día E: status ' + (res && res.status)
          + ' — se conserva la simulación.', det);
        return false;
      }

      var rows = await res.json();
      // RLS con auth.uid() nulo devuelve objeto de error, no arreglo.
      if (!Array.isArray(rows)) {
        console.warn('⚠️ T19 Día E: respuesta no-arreglo (posible RLS/error) — se conserva la simulación.');
        return false;
      }
      if (!rows.length) {
        // Aún no hay reportes cargados: no hay datos reales que pintar.
        // No es un error; simplemente no activamos el modo vivo todavía.
        return false;
      }

      // Mapa real indexado por casilla_id (uuid), que es como llega el reporte.
      // Estado explícito desde los booleanos de la tabla (mejor que inferirlo):
      //   cerrada → 'cerrada' · abierta → 'reportando'/'instalada' · ninguno → 'sin_instalar'
      var map = {};
      rows.forEach(function (r) {
        var cid = r[COLS.casilla] ? String(r[COLS.casilla]) : null;
        if (!cid) return;
        var abierta = !!r[COLS.abierta];
        var cerrada = !!r[COLS.cerrada];
        var votos   = Number(r[COLS.votos]) || 0;
        var estado = cerrada ? 'cerrada'
                   : abierta ? (votos > 0 ? 'reportando' : 'instalada')
                   : 'sin_instalar';
        map[cid] = { estado: estado, votos: votos };
      });
      _real = map;
      _lastSync = new Date();
      return true;
    } catch (e) {
      console.warn('⚠️ T19 Día E: excepción, se conserva la simulación:', e);
      return false;
    }
  }

  function hayReal() { return _real && Object.keys(_real).length > 0; }

  // ── Overrides: usan el mapa real si existe; si no, delegan al original ──────
  // stats por sección desde datos reales (misma forma {n,inst,rep,votos,metaP})
  function statsRealSeccion(sec) {
    var IE = window.IE_METAS_CASILLA;
    var sm = (IE && IE.secciones) ? IE.secciones[String(sec)] : null;
    if (!sm || !sm.casillas || !sm.casillas.length) return null;
    var inst = 0, rep = 0, votos = 0;
    sm.casillas.forEach(function (c) {
      var r = c.cid ? _real[String(c.cid)] : null;  // join por uuid (casillas.id)
      if (!r) return; // casilla sin reporte aún: cuenta como no instalada
      if (r.estado !== 'sin_instalar') inst++;
      if (r.estado === 'reportando' || r.estado === 'cerrada') rep++;
      votos += r.votos;
    });
    return { n: sm.casillas.length, inst: inst, rep: rep, votos: votos, metaP: sm.meta_proyectada || 0 };
  }

  // Instala los overrides UNA vez, tras capturar las funciones reales del visor.
  var _instalado = false;
  function instalarOverrides() {
    if (_instalado) return;
    _origStats   = window.statsSeccionDiaE;
    _origResumen = window.actualizarResumenDiaE;
    _origColor   = window.getDiaEColorSeccion;

    window.statsSeccionDiaE = function (sec) {
      if (hayReal()) return statsRealSeccion(sec);
      return _origStats ? _origStats(sec) : null;
    };

    // Color por sección: en vivo NO hay "hora"; usamos el semáforo de instalación/
    // reporte, y si todas cerraron, el de cumplimiento vs meta proyectada.
    window.getDiaEColorSeccion = function (sec) {
      if (!hayReal()) return _origColor ? _origColor(sec) : '#2a2a4a';
      var st = statsRealSeccion(sec);
      if (!st) return '#2a2a4a';
      if (st.n > 0 && st.rep === st.n) { // todas cerraron/reportaron → cumplimiento
        var pct = st.metaP > 0 ? Math.round(st.votos / st.metaP * 100) : 0;
        return (typeof getMetaColor === 'function') ? getMetaColor(pct) : '#00cc66';
      }
      if (st.inst === 0) return '#444';
      if (st.inst < st.n) return '#ff4466';
      if (st.rep  < st.n) return '#ffaa00';
      return '#00cc66';
    };

    window.actualizarResumenDiaE = function () {
      if (!hayReal()) { if (_origResumen) _origResumen(); return; }
      var IE = window.IE_METAS_CASILLA;
      if (!IE || !IE.secciones) return;
      var inst = 0, tot = 0, votos = 0;
      Object.values(IE.secciones).forEach(function (sm) {
        (sm.casillas || []).forEach(function (c) {
          tot++;
          var r = c.cid ? _real[String(c.cid)] : null;  // join por uuid
          if (r && r.estado !== 'sin_instalar') inst++;
          if (r) votos += r.votos;
        });
      });
      var metaEst = (window.SISTEMA_META && +window.SISTEMA_META)
        || (IE.meta_estatal) || 208717;
      var pctMeta = Math.round(votos / (metaEst || 1) * 100);
      var hora = _lastSync ? _lastSync.toLocaleTimeString('es-MX', { hour: '2-digit', minute: '2-digit' }) : '--:--';
      var el = document.getElementById('dia-e-resumen');
      if (el) {
        el.textContent = '🟢 EN VIVO (' + hora + ') · Instaladas: ' + inst + '/' + tot +
          ' · Votos: ' + votos.toLocaleString() + ' (' + pctMeta + '% de la meta)';
      }
    };

    _instalado = true;
  }

  // ── Slider: ocultar en modo vivo (no hay hora arrastrable) ─────────────────
  function ajustarControlVivo() {
    var slider = document.getElementById('dia-e-slider');
    var hora = document.getElementById('dia-e-hora');
    if (hayReal()) {
      if (slider) slider.style.display = 'none';
      if (hora) hora.textContent = 'EN VIVO';
      // El título "SIMULACIÓN DÍA E" ya no aplica; lo suavizamos si está presente.
      var lbl = hora && hora.previousElementSibling;
      if (lbl && /SIMULACI/i.test(lbl.textContent)) lbl.textContent = '🗳️ DÍA E — EN VIVO';
    } else {
      if (slider) slider.style.display = '';
    }
  }

  // ── Repintar la capa si está activa ────────────────────────────────────────
  function repintarSiActiva() {
    if (window.currentLayer === 'dia_e') {
      if (typeof renderSecciones === 'function') renderSecciones('dia_e');
      window.actualizarResumenDiaE();
      ajustarControlVivo();
    }
  }

  // ── Ciclo de polling: solo corre mientras la capa dia_e esté activa ────────
  async function tick() {
    var ok = await cargarDiaESupabase();
    if (ok) repintarSiActiva();
  }

  function iniciarPolling() {
    if (_timer) return;
    tick(); // inmediato
    _timer = setInterval(function () {
      if (window.currentLayer === 'dia_e') tick();
    }, POLL_MS);
  }

  // Arranque: primero instalar los overrides (ya existen las funciones del visor),
  // luego lanzar el polling. El intervalo solo trabaja en la capa dia_e.
  function arrancar() { instalarOverrides(); iniciarPolling(); }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', arrancar);
  } else {
    arrancar();
  }

  // Exponer por si el visor quiere forzar un refresh al entrar a la capa.
  window.cargarDiaESupabase = cargarDiaESupabase;
  window.refrescarDiaE = repintarSiActiva;
})();
