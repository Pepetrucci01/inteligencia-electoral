/* ============================================================
   VOTERA(TM) - Inteligencia Electoral
   (c) 2026 MEFT Consulting - RFC: CUOJ7808208Z2
   observabilidad.js  v2 - 2 sep 2026
   ------------------------------------------------------------
   UNA linea por modulo, dos destinos:

     <script src="observabilidad.js"><\/script>

   1) SENTRY  -> te avisa por correo en el momento, con el stack
                 completo. Proyecto 'votera' (separado del SIIF).
   2) log_errores en Supabase -> el registro se queda en casa,
                 con rol y licencia, para el panel de soporte y
                 para responder tickets.

   Para nombrar el modulo (opcional, si el archivo no lo dice):
     <script>window.VOTERA_MODULO = 'war_room';<\/script>

   ── PRIVACIDAD (lo mas importante de este archivo) ──────────
   Sentry es un TERCERO. A un tercero no le mandamos datos de
   ciudadanos. Por eso:
     - Session Replay y Tracing APAGADOS en duro aqui, no en el
       panel de Sentry. Un switch en un panel lo mueve cualquiera;
       esto solo se cambia tocando el codigo.
     - sendDefaultPii: false  (no manda IP ni cookies)
     - beforeSend limpia la URL: se queda solo con la ruta, sin
       parametros, por si alguno trae CURP, telefono o un token.
     - Se descartan errores de extensiones del navegador y de
       scripts externos, que ensucian sin decir nada.

   Regla de la casa: falla en silencio SIEMPRE. El reportero de
   errores jamas debe causar un error ni molestar al usuario.
   ============================================================ */
(function () {
  'use strict';

  var SENTRY_DSN = 'https://1448fc71c5aa0d9475cc091afc3e3384@o4511929249300480.ingest.de.sentry.io/4512017285513296';
  var SENTRY_CDN = 'https://browser.sentry-cdn.com/8.42.0/bundle.min.js';

  var SUPA_URL = 'https://dyirhwwmykskpuvzcafx.supabase.co';
  var SUPA_ANON = window.SUPABASE_KEY ||
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR5aXJod3dteWtza3B1dnpjYWZ4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1NTk3ODgsImV4cCI6MjA5NTEzNTc4OH0.2xe4cHqORGng1hnYPJ9ZiyT0r87fMijbUEJqBy3-xoI';

  var enviados = 0;
  var vistos = {};

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

  /* La direccion puede traer datos en los parametros. Se conserva
     solo la ruta, que es lo unico que sirve para saber donde trono. */
  function urlLimpia(u) {
    try {
      var x = new URL(u || location.href);
      return x.origin + x.pathname;
    } catch (e) { return '(url no legible)'; }
  }

  /* Ruido que no vale la pena: extensiones del navegador, scripts
     de terceros, y el clasico "Script error" sin detalle que
     produce cualquier recurso de otro dominio. */
  var RUIDO = [
    /extension:\/\//i, /^chrome:\/\//i, /moz-extension/i, /safari-extension/i,
    /^Script error\.?$/i, /ResizeObserver loop/i,
    /beacon\.min\.js/i, /googletagmanager/i, /gtag/i
  ];
  function esRuido(txt) {
    if (!txt) return false;
    for (var i = 0; i < RUIDO.length; i++) { if (RUIDO[i].test(txt)) return true; }
    return false;
  }

  /* ── (1) SENTRY ─────────────────────────────────────────── */
  function iniciarSentry() {
    try {
      if (!window.Sentry || !window.Sentry.init) return;
      var s = sesion();
      window.Sentry.init({
        dsn: SENTRY_DSN,
        integrations: [],             // sin Replay, sin Tracing
        replaysSessionSampleRate: 0,
        replaysOnErrorSampleRate: 0,
        tracesSampleRate: 0,
        sendDefaultPii: false,        // sin IP, sin cookies
        // Coincidencia EXACTA. Antes se usaba "empieza con
        // inteligencia-electoral", y la rama desarrollo tambien
        // empieza asi: los errores de las pruebas se mezclaban
        // con los de produccion y no habia forma de separarlos.
        environment: ['votera.mx', 'www.votera.mx',
                      'inteligencia-electoral.vercel.app'
                     ].indexOf(location.hostname) >= 0 ? 'produccion' : 'preview',
        initialScope: {
          tags: { modulo: modulo(), rol: (s && s.rol) || 'sin_sesion' },
          // Solo el id y el rol. Nunca nombre, correo ni telefono.
          user: (s && s.id) ? { id: String(s.id) } : undefined
        },
        beforeSend: function (evento) {
          try {
            var msg = (evento.exception && evento.exception.values &&
                       evento.exception.values[0] &&
                       evento.exception.values[0].value) || evento.message || '';
            if (esRuido(msg)) { return null; }
            if (evento.request) {
              if (evento.request.url) { evento.request.url = urlLimpia(evento.request.url); }
              delete evento.request.cookies;
              delete evento.request.headers;
            }
          } catch (e) {
            return null;   // si la limpieza falla, mejor no mandar nada
          }
          return evento;
        }
      });
    } catch (e) { /* silencio */ }
  }

  // El SDK se carga aparte para no retrasar el modulo. Si no carga
  // (sin internet, bloqueador de anuncios), el resto sigue igual.
  (function cargarSentry() {
    try {
      var t = document.createElement('script');
      t.src = SENTRY_CDN;
      t.crossOrigin = 'anonymous';
      t.async = true;
      t.onload = iniciarSentry;
      t.onerror = function () { /* silencio: Supabase sigue recibiendo */ };
      (document.head || document.documentElement).appendChild(t);
    } catch (e) { /* silencio */ }
  })();

  /* ── (2) SUPABASE: log_errores ──────────────────────────── */
  function reportar(mensaje, stack) {
    try {
      if (esRuido(mensaje)) return;
      var s = sesion();
      if (!s || !s.access_token) return;   // sin sesion no hay a quien cargarselo
      if (enviados >= 10) return;          // freno por sesion de pagina
      var clave = String(mensaje).slice(0, 120);
      if (vistos[clave]) return;           // mismo error, una sola vez
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
          p_url: urlLimpia(location.href).slice(0, 300),
          p_agente: navigator.userAgent.slice(0, 300)
        })
      }).catch(function () { /* silencio */ });
    } catch (e) { /* el reportero nunca truena */ }
  }

  /* ── Escuchas ───────────────────────────────────────────── */
  window.addEventListener('error', function (ev) {
    if (!ev) return;
    var msg = ev.message || 'error sin mensaje';
    var stack = (ev.error && ev.error.stack) ||
      ((ev.filename || '') + ':' + (ev.lineno || 0));
    reportar(msg, stack);
  });

  window.addEventListener('unhandledrejection', function (ev) {
    if (!ev) return;
    var razon = ev.reason;
    var msg = (razon && razon.message) ? razon.message : String(razon || 'promesa rechazada');
    var stack = (razon && razon.stack) ? razon.stack : null;
    reportar('unhandled: ' + msg, stack);
  });

  /* Reporte manual, para avisar algo que no lanza excepcion:
       window.reportarErrorVotera('encuestas', 'el catalogo llego vacio'); */
  window.reportarErrorVotera = function (mod, mensaje) {
    var prev = window.VOTERA_MODULO;
    if (mod) { window.VOTERA_MODULO = mod; }
    reportar(mensaje, null);
    try {
      if (window.Sentry && window.Sentry.captureMessage) {
        window.Sentry.captureMessage(String(mensaje).slice(0, 300));
      }
    } catch (e) { /* silencio */ }
    window.VOTERA_MODULO = prev;
  };
})();
