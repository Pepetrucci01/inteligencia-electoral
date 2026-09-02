/* ============================================================
   VOTERA(TM) - Inteligencia Electoral
   (c) 2026 MEFT Consulting - RFC: CUOJ7808208Z2
   observabilidad.js - reportero de errores del frontend
   ------------------------------------------------------------
   Que hace: cuando algo truena en el navegador de cualquier
   usuario, lo manda a la tabla log_errores via el RPC
   reportar_error_js. Ahi lo ve el panel de soporte.

   Como se usa: UNA linea en cada modulo, antes de sus scripts:

     <script src="observabilidad.js"><\/script>

   y opcionalmente, para nombrar el modulo:

     <script>window.VOTERA_MODULO = 'war_room';<\/script>

   Reglas de la casa:
   - Falla en silencio SIEMPRE. El reportero de errores jamas
     debe causar un error ni molestar al usuario.
   - No manda nada sin sesion (el RPC lo exige de todos modos).
   - Se frena solo: maximo 10 reportes por sesion de pagina y
     no repite el mismo mensaje dos veces. El tope duro de
     30/usuario/hora vive en la base.
   - No manda datos de ciudadanos: solo el error, el modulo,
     la URL y el navegador.
   ============================================================ */
(function () {
  'use strict';

  var SUPA_URL = 'https://dyirhwwmykskpuvzcafx.supabase.co';
  var SUPA_ANON = window.SUPABASE_KEY ||
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR5aXJod3dteWtza3B1dnpjYWZ4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1NTk3ODgsImV4cCI6MjA5NTEzNTc4OH0.2xe4cHqORGng1hnYPJ9ZiyT0r87fMijbUEJqBy3-xoI';

  var enviados = 0;
  var vistos = {};          // mensaje -> true, para no repetir

  function sesion() {
    try { return JSON.parse(localStorage.getItem('electoral_sesion')) || null; }
    catch (e) { return null; }
  }

  function modulo() {
    if (window.VOTERA_MODULO) return String(window.VOTERA_MODULO);
    var p = (location.pathname.split('/').pop() || 'index')
      .replace(/\.html?$/i, '').replace(/^modulo_/, '');
    return p || 'desconocido';
  }

  function reportar(mensaje, stack) {
    try {
      var s = sesion();
      if (!s || !s.access_token) return;         // sin sesion no hay a quien cargarselo
      if (enviados >= 10) return;                // freno por sesion de pagina
      var clave = String(mensaje).slice(0, 120);
      if (vistos[clave]) return;                 // mismo error, una sola vez
      vistos[clave] = true;
      enviados++;

      // fetch nativo, sin wrappers: si el wrapper es lo que fallo,
      // el reporte tiene que salir de todos modos.
      fetch(SUPA_URL + '/rest/v1/rpc/reportar_error_js', {
        method: 'POST',
        headers: {
          'apikey': SUPA_ANON,
          'Authorization': 'Bearer ' + s.access_token,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          p_modulo: modulo(),
          p_mensaje: String(mensaje).slice(0, 500),
          p_stack: stack ? String(stack).slice(0, 1500) : null,
          p_url: location.href.slice(0, 300),
          p_agente: navigator.userAgent.slice(0, 300)
        })
      }).catch(function () { /* silencio */ });
    } catch (e) { /* silencio: el reportero nunca truena */ }
  }

  // Errores sincronos
  window.addEventListener('error', function (ev) {
    if (!ev) return;
    var msg = ev.message || 'error sin mensaje';
    var stack = (ev.error && ev.error.stack) ||
      ((ev.filename || '') + ':' + (ev.lineno || 0));
    reportar(msg, stack);
  });

  // Promesas sin catch (fallos de fetch, RPCs, etc.)
  window.addEventListener('unhandledrejection', function (ev) {
    if (!ev) return;
    var razon = ev.reason;
    var msg = (razon && razon.message) ? razon.message : String(razon || 'promesa rechazada');
    var stack = (razon && razon.stack) ? razon.stack : null;
    reportar('unhandled: ' + msg, stack);
  });

  // Reporte manual, por si un modulo quiere avisar algo puntual:
  //   window.reportarErrorVotera('encuestas', 'no cargo el catalogo');
  window.reportarErrorVotera = function (mod, mensaje) {
    var prev = window.VOTERA_MODULO;
    if (mod) window.VOTERA_MODULO = mod;
    reportar(mensaje, null);
    window.VOTERA_MODULO = prev;
  };
})();
