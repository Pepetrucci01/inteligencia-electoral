/* ============================================================================
 * T18 — Metas por casilla en el visor (Fase 4, rama desarrollo)
 * SWAP 1: reconstruye window.IE_METAS_CASILLA desde Supabase (casillas + secciones)
 *
 * Reglas de oro respetadas:
 *  - casilla_completa es TEXTO: se compara/pinta como string, jamás parseInt.
 *  - Fallback obligatorio: si el fetch falla o RLS devuelve OBJETO DE ERROR
 *    (no arreglo), NO se toca IE_METAS_CASILLA -> queda el horneado intacto.
 *  - Lectura con access_token de la sesión (mismo idiom que cargarAvanceSupabase).
 *  - No renombra funciones, claves de localStorage ni valores de rol.
 *
 * Contrato de salida (idéntico al horneado — no romper consumidores):
 *   window.IE_METAS_CASILLA = {
 *     meta_estatal: <int>,
 *     secciones: {
 *       "85": { meta_proyectada, meta_real, estructura_real,
 *               casillas: [ { cc:<casilla_completa>, cid:<casillas.id uuid>,
 *                             mp:<meta_proyectada>, mr:<meta_real> } ] }
 *     }
 *   }
 * ========================================================================== */
(function () {
  'use strict';

  // Fallback de meta estatal: main subió 204,384 -> 208,717 (+19 casillas estimadas).
  // Valor VIGENTE tras 'Update from main'. Ver ESTRUCTURA_MAESTRA §4.0.
  var META_ESTATAL_FALLBACK = 208717;

  async function cargarMetasCasillaSupabase() {
    try {
      var _ses = JSON.parse(localStorage.getItem('electoral_sesion') || 'null');
      var LICENCIA_ID = (_ses && _ses.licencia_id) ? _ses.licencia_id : null;

      // Mismo idiom de auth que cargarAvanceSupabase(): supaFetch refresca el token.
      var _fetch = window.supaFetch || fetch;
      var token = (window._sesion && window._sesion.access_token)
        || (_ses && _ses.access_token) || SUPABASE_KEY;

      var baseHeaders = {
        'apikey': SUPABASE_KEY,
        'Authorization': 'Bearer ' + token,
        'Content-Type': 'application/json'
      };

      // ── Helper de paginación ────────────────────────────────────────────
      // ⚠️ PostgREST tiene un tope de servidor (max-rows, típicamente 1000).
      //   Un &limit= mayor NO lo sobrepasa: el servidor manda. Para traer las
      //   1,033 casillas hay que PAGINAR con el header Range. Sin esto se
      //   pierden 33 filas en silencio (el síntoma era "1000 casillas" exacto).
      // ⚠️ Se pagina con limit/offset EN LA URL, no con el header Range.
      //   Los headers custom (Range, Range-Unit) disparan un preflight CORS que
      //   Supabase no permite desde todos los orígenes → 'Failed to fetch'.
      //   Con limit/offset no hay preflight. (Aquí funcionaba por el contexto
      //   del iframe, pero es frágil: mejor no depender de eso.)
      async function fetchTodo(url, headersBase) {
        var out = [];
        var TAM = 1000;          // tamaño de página
        var MAX_PAGINAS = 20;    // candado anti-bucle (20k filas máx)
        for (var p = 0; p < MAX_PAGINAS; p++) {
          var pag = url + '&limit=' + TAM + '&offset=' + (p * TAM);
          var res = await _fetch(pag, { method: 'GET', headers: headersBase });
          if (!res.ok) return { ok: false, status: res.status, res: res };
          var pagina = await res.json();
          if (!Array.isArray(pagina)) return { ok: false, status: res.status, data: pagina };
          out = out.concat(pagina);
          if (pagina.length < TAM) break;   // última página
        }
        return { ok: true, data: out };
      }

      // --- SELECT casillas (columnas nuevas T18) ---------------------------
      // licencia_id es UUID (string): filtro por igualdad de texto, sin parseInt.
      // `id` (uuid) se pide para exponerlo como `cid`: es el puente hacia T19,
      // porque reportes_casilla_eleccion.casilla_id apunta a casillas.id.
      var qCasillas = SUPABASE_URL
        + '/rest/v1/casillas'
        + '?select=id,casilla_completa,numero_seccion,meta_proyectada,meta_real,estructura_real'
        + '&order=id'   // orden estable: sin esto la paginación puede repetir/saltar filas
        + (LICENCIA_ID ? '&licencia_id=eq.' + encodeURIComponent(LICENCIA_ID) : '');

      // --- SELECT agregado seccional --------------------------------------
      // ⚠️ secciones_electorales_colima es un CATÁLOGO PÚBLICO: NO tiene columna
      //   licencia_id (su única política RLS es USING true). Filtrar por
      //   licencia_id aquí devolvía 400 Bad Request. Confirmado en BD (10 jul):
      //   columnas = id, seccion, municipio, id_municipio, distrito_*, lat, lon,
      //   lista_nominal, ..., meta_proyectada, meta_real, estructura_real.  388 filas.
      var qSecciones = SUPABASE_URL
        + '/rest/v1/secciones_electorales_colima'
        + '?select=seccion,meta_proyectada,meta_real,estructura_real';

      // Ambas consultas paginadas (secciones son 388, cabe en una página; casillas
      // son 1,033 y necesitan dos). fetchTodo devuelve {ok, data} o {ok:false,...}.
      var resArr = await Promise.all([
        fetchTodo(qCasillas,  baseHeaders),
        fetchTodo(qSecciones, baseHeaders)
      ]);
      var resC = resArr[0], resS = resArr[1];

      if (!resC.ok || !resS.ok) {
        // Loguear el CUERPO del error, no solo el status: PostgREST explica el
        // motivo (columna inexistente, RLS, etc.) y eso ahorra horas de debug.
        var detC = resC.ok ? '' : (resC.res ? await resC.res.text().catch(function () { return ''; }) : JSON.stringify(resC.data || ''));
        var detS = resS.ok ? '' : (resS.res ? await resS.res.text().catch(function () { return ''; }) : JSON.stringify(resS.data || ''));
        console.warn('⚠️ T18 metas: casillas=' + resC.status + ' secciones=' + resS.status
          + ' — se conserva el horneado.', { casillas: detC, secciones: detS });
        return;
      }

      var casillas  = resC.data;
      var secciones = resS.data;

      // RLS con auth.uid() nulo devuelve OBJETO DE ERROR, no arreglo vacío.
      // Validar explícitamente ANTES de pintar. Si no es arreglo -> fallback.
      if (!Array.isArray(casillas) || !Array.isArray(secciones)) {
        console.warn('⚠️ T18 metas: respuesta no-arreglo (posible RLS/error) — se conserva el horneado.', { casillas: casillas, secciones: secciones });
        return;
      }
      if (!casillas.length || !secciones.length) {
        console.warn('⚠️ T18 metas: arreglo vacío — se conserva el horneado.');
        return;
      }

      // --- Reconstruir el objeto en la forma exacta del horneado -----------
      var secMap = {};

      // 1) Sembrar secciones con su agregado (metas seccionales = suma de casillas).
      secciones.forEach(function (s) {
        var key = String(s.seccion);
        secMap[key] = {
          meta_proyectada: s.meta_proyectada || 0,
          meta_real: s.meta_real || 0,
          estructura_real: s.estructura_real || 0,
          casillas: []
        };
      });

      // 2) Colgar cada casilla en su sección. cc SIEMPRE string (casilla_completa).
      casillas.forEach(function (c) {
        var key = String(c.numero_seccion);
        if (!secMap[key]) {
          // Sección con casillas pero sin fila seccional: crear contenedor mínimo.
          secMap[key] = { meta_proyectada: 0, meta_real: 0, estructura_real: 0, casillas: [] };
        }
        secMap[key].casillas.push({
          cc: String(c.casilla_completa),   // texto INE (ej. 248-S1-0) — nunca parseInt
          cid: c.id ? String(c.id) : null,  // uuid de casillas.id — puente para T19
          //   (reportes_casilla_eleccion.casilla_id es uuid, NO el texto INE)
          mp: c.meta_proyectada || 0,
          mr: c.meta_real || 0
        });
      });

      // 3) Meta estatal: de configuracion_sistema si theme.js la expone; si no, fallback.
      var metaEstatal =
        (window.SISTEMA_META && +window.SISTEMA_META) ||
        (window.IE_METAS_CASILLA && window.IE_METAS_CASILLA.meta_estatal) ||
        META_ESTATAL_FALLBACK;

      // --- Publicar (reemplaza el horneado sólo si todo validó) ------------
      window.IE_METAS_CASILLA = {
        meta_estatal: metaEstatal,
        secciones: secMap
      };

      // Re-render si el visor ya pintó una capa que depende de metas.
      if (window.currentLayer === 'meta') { renderSecciones('meta'); }
      if (window.currentLayer === 'dia_e') {
        renderSecciones('dia_e');
        if (typeof actualizarResumenDiaE === 'function') actualizarResumenDiaE();
      }

      // Salvaguarda: un conteo redondo (1000, 2000...) casi siempre significa
      // truncamiento por max-rows, no un dato real. Avisar fuerte para que no
      // vuelva a pasar desapercibido.
      var nCas = casillas.length, nSec = Object.keys(secMap).length;
      if (nCas % 1000 === 0) {
        console.warn('⚠️ T18: ' + nCas + ' casillas es un número sospechosamente redondo — '
          + 'posible truncamiento de PostgREST. Revisar la paginación.');
      }
      console.log('✅ T18 metas por casilla: ' + nCas + ' casillas, ' + nSec
        + ' secciones (meta estatal ' + metaEstatal.toLocaleString() + ').');
    } catch (e) {
      // Cualquier excepción -> se conserva el horneado. Demo nunca se rompe.
      console.warn('⚠️ T18 metas: excepción, se conserva el horneado:', e);
    }
  }

  // Exponer y arrancar (se invoca junto a cargarAvanceSupabase en el arranque).
  window.cargarMetasCasillaSupabase = cargarMetasCasillaSupabase;
})();
