/* ============================================================================
 * T21 — Módulo Encuestas: conexión a Supabase (Fase 4, rama desarrollo)
 * Conecta los 6 puntos [SWAP LUIS] de modulo_encuestas.html a:
 *   - encuestas                 (listar / crear / activar / cerrar)
 *   - respuestas_encuesta       (INSERT anónimo de entrevistas)
 *   - v_territorio_vs_opinion   (agregados para el cruce territorio↔opinión)
 * Esquema: esquema_modulo_encuestas.sql (proyecto staging dyirhwwmykskpuvzcafx).
 *
 * PRINCIPIOS (no-negociables del proyecto):
 *   - Respuestas ANÓNIMAS: jamás nombre/teléfono ni FK a ciudadanos.
 *   - Fallback obligatorio: si el fetch falla o RLS devuelve objeto de error,
 *     NO se sobreescribe con ceros — se conservan los datos demo ya pintados.
 *   - licencia_id es uuid string; claves jsonb estándar: conocimiento, imagen,
 *     intencion, firmeza, tema, aprobacion.
 *
 * ⚠️ TRES PUNTOS QUE DEPENDEN DE DECISIONES/DATOS EXTERNOS — aislados abajo:
 *   (A) MODULO_TIER  → gating por licencias.modulos_habilitados. El nombre del
 *       módulo ('encuestas') aún debe alinearse con la columna `modulos` del
 *       modelo E2/E3 (ESTRUCTURA_MAESTRA, Nota de reconciliación). AJUSTAR aquí.
 *   (B) MUNI_ID      → el form captura municipio por NOMBRE; la tabla espera
 *       municipio_id (integer). Falta la tabla/mapa de referencia real. Mientras,
 *       se manda null (columna es nullable) y se conserva el nombre en jsonb.
 *   (C) supaFetch    → este módulo NO carga theme.js; el bloque de auth es
 *       autocontenido. Si más adelante se añade theme.js, usará su supaFetch.
 * ========================================================================== */
(function () {
  'use strict';

  // ── (A) Gating de módulo por tier — AJUSTAR cuando José cierre E2/E3 ────────
  var MODULO_TIER = 'encuestas'; // debe coincidir con licencias.modulos_habilitados

  // ── Config Supabase (autocontenida; este módulo no carga theme.js) ─────────
  var SUPA_URL = 'https://dyirhwwmykskpuvzcafx.supabase.co';
  var SUPA_ANON = (window.SUPABASE_KEY) || null; // si el host la define, se usa
  // Anon key del staging (misma que theme.js/visor). Solo para lecturas con RLS.
  if (!SUPA_ANON) {
    SUPA_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR5aXJod3dteWtza3B1dnpjYWZ4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1NTk3ODgsImV4cCI6MjA5NTEzNTc4OH0.2xe4cHqORGng1hnYPJ9ZiyT0r87fMijbUEJqBy3-xoI';
  }

  function sesion() {
    try { return JSON.parse(localStorage.getItem('electoral_sesion')) || null; }
    catch (e) { return null; }
  }
  function licenciaId() {
    var s = sesion();
    return (s && s.licencia_id) ? String(s.licencia_id) : null;
  }
  function usuarioId() {
    var s = sesion();
    // La sesión usa `id` (no usuario_id) — convención del proyecto.
    return (s && s.id) ? String(s.id) : null;
  }
  function token() {
    var s = sesion();
    return (window._sesion && window._sesion.access_token)
      || (s && s.access_token) || SUPA_ANON;
  }
  function headers(extra) {
    var h = {
      'apikey': SUPA_ANON,
      'Authorization': 'Bearer ' + token(),
      'Content-Type': 'application/json'
    };
    if (extra) for (var k in extra) h[k] = extra[k];
    return h;
  }
  function _fetch() { return window.supaFetch || fetch; }

  // [FIX 15 jul] Wrapper que reintenta UNA vez si la respuesta es 401/403 por
  // token vencido o sesión no lista. Refresca vía theme.js si está disponible.
  // Las funciones de abajo usan _fetchAuth() en vez de _fetch() para heredar esto.
  async function _fetchAuth(url, opts) {
    opts = opts || {};
    var res = await _fetch()(url, opts);
    if (res && (res.status === 401 || res.status === 403)
        && typeof window.refrescarTokenSupabase === 'function') {
      var ok = await window.refrescarTokenSupabase();
      if (ok) {
        // rehacer headers con el token ya refrescado
        if (opts.headers) opts.headers['Authorization'] = 'Bearer ' + token();
        res = await _fetch()(url, opts);
      }
    }
    return res;
  }

  // ── (B) [T8 15 jul] Municipio nombre → id (UUID) contra la tabla municipios.
  // Se cachea el catálogo la primera vez y se resuelve por nombre normalizado
  // (mayúsculas, sin dobles espacios). Devuelve null si no hay match (p.ej. si
  // el catálogo aún tiene placeholders sin poblar → degrada suave, como antes).
  var _munCache = null;
  function _normMun(s) {
    return (s || '').toString().trim().toUpperCase().replace(/\s+/g, ' ');
  }
  async function _cargarMunicipios() {
    if (_munCache) return _munCache;
    try {
      var url = SUPA_URL + '/rest/v1/municipios?select=id,nombre';
      var res = await _fetchAuth(url, { method: 'GET', headers: headers() });
      if (!res.ok) { _munCache = {}; return _munCache; }
      var rows = await res.json();
      _munCache = {};
      rows.forEach(function (m) { _munCache[_normMun(m.nombre)] = m.id; });
    } catch (e) { _munCache = {}; }
    return _munCache;
  }
  async function municipioId(nombre) {
    if (!nombre) return null;
    var mapa = await _cargarMunicipios();
    return mapa[_normMun(nombre)] || null;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SWAP 1 — Gating por tier: ¿esta licencia tiene el módulo Encuestas?
  // ══════════════════════════════════════════════════════════════════════════
  async function moduloHabilitado() {
    try {
      var lic = licenciaId();
      if (!lic) return true; // demo sin sesión: no bloquear
      var url = SUPA_URL + '/rest/v1/licencias'
        + '?select=modulos_habilitados&id=eq.' + encodeURIComponent(lic) + '&limit=1';
      var res = await _fetchAuth(url, { method: 'GET', headers: headers() });
      if (!res || !res.ok) return true; // ante error, no bloquear (fallback permisivo)
      var data = await res.json();
      if (!Array.isArray(data) || !data.length) return true;
      var mods = data[0].modulos_habilitados || [];
      // 'completo' habilita todo; o el módulo explícito.
      return mods.indexOf('completo') !== -1 || mods.indexOf(MODULO_TIER) !== -1;
    } catch (e) { return true; }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SWAP 2 — Leer encuestas reales (reemplaza el array ENCUESTAS demo)
  // ══════════════════════════════════════════════════════════════════════════
  async function cargarEncuestas() {
    try {
      var lic = licenciaId();
      if (!lic) return false; // demo: conservar ENCUESTAS horneadas
      var url = SUPA_URL + '/rest/v1/encuestas'
        + '?select=id,nombre,descripcion,estado,fecha_inicio,fecha_fin,preguntas,metodologia'
        + '&licencia_id=eq.' + encodeURIComponent(lic)
        + '&order=created_at.desc';
      var res = await _fetchAuth(url, { method: 'GET', headers: headers() });
      if (!res || !res.ok) { console.warn('T21: encuestas status ' + (res && res.status) + ' — demo intacto.'); return false; }
      var rows = await res.json();
      if (!Array.isArray(rows)) { console.warn('T21: encuestas no-arreglo (RLS?) — demo intacto.'); return false; }
      if (!rows.length) return false; // sin encuestas aún: no borrar el demo

      // Conteo de entrevistas por encuesta (una consulta agregada opcional).
      var conteos = await contarRespuestas(lic);

      // Mapear al shape que usa el front (ENCUESTAS demo).
      window.ENCUESTAS = rows.map(function (r) {
        return {
          id: String(r.id),
          nombre: r.nombre,
          desc: r.descripcion || '',
          estado: r.estado || 'borrador',
          ini: r.fecha_inicio || '',
          fin: r.fecha_fin || '',
          entrevistas: conteos[String(r.id)] || 0,
          metodologia: r.metodologia || {},
          preguntas: Array.isArray(r.preguntas) ? r.preguntas : []
        };
      });
      return true;
    } catch (e) { console.warn('T21: excepción cargarEncuestas — demo intacto:', e); return false; }
  }

  // Conteo de respuestas por encuesta (para la columna "entrevistas").
  async function contarRespuestas(lic) {
    var out = {};
    try {
      // PostgREST: pedir encuesta_id y contar en cliente (dataset chico por licencia).
      var url = SUPA_URL + '/rest/v1/respuestas_encuesta'
        + '?select=encuesta_id&licencia_id=eq.' + encodeURIComponent(lic);
      var res = await _fetchAuth(url, { method: 'GET', headers: headers() });
      if (!res || !res.ok) return out;
      var rows = await res.json();
      if (!Array.isArray(rows)) return out;
      rows.forEach(function (r) {
        var k = String(r.encuesta_id);
        out[k] = (out[k] || 0) + 1;
      });
    } catch (e) {}
    return out;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SWAP 3 y 4 — Activar / Cerrar (UPDATE estado)
  // ══════════════════════════════════════════════════════════════════════════
  async function actualizarEstado(id, nuevoEstado) {
    var lic = licenciaId();
    if (!lic) return true; // demo: dejar que el front cambie el estado local
    try {
      var url = SUPA_URL + '/rest/v1/encuestas'
        + '?id=eq.' + encodeURIComponent(id)
        + '&licencia_id=eq.' + encodeURIComponent(lic);
      var res = await _fetchAuth(url, {
        method: 'PATCH',
        headers: headers({ 'Prefer': 'return=minimal' }),
        body: JSON.stringify({ estado: nuevoEstado })
      });
      if (!res || !res.ok) { console.warn('T21: no se pudo cambiar estado (status ' + (res && res.status) + ').'); return false; }
      return true;
    } catch (e) { console.warn('T21: excepción actualizarEstado:', e); return false; }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SWAP 5 — Crear encuesta (INSERT)
  // ══════════════════════════════════════════════════════════════════════════
  async function insertarEncuesta(payload) {
    var lic = licenciaId();
    if (!lic) return null; // demo: el front hace unshift local
    try {
      var body = {
        licencia_id: lic,
        nombre: payload.nombre,
        descripcion: payload.desc || null,
        estado: 'borrador',
        fecha_inicio: payload.ini || null,
        fecha_fin: payload.fin || null,
        preguntas: payload.preguntas || [],
        metodologia: payload.metodologia || {},
        creado_por: usuarioId()
      };
      var url = SUPA_URL + '/rest/v1/encuestas';
      var res = await _fetchAuth(url, {
        method: 'POST',
        headers: headers({ 'Prefer': 'return=representation' }),
        body: JSON.stringify(body)
      });
      if (!res || !res.ok) { console.warn('T21: no se pudo crear encuesta (status ' + (res && res.status) + ').'); return null; }
      var rows = await res.json();
      return Array.isArray(rows) && rows.length ? String(rows[0].id) : null;
    } catch (e) { console.warn('T21: excepción insertarEncuesta:', e); return null; }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  SWAP 6 — Guardar entrevista (INSERT anónimo en respuestas_encuesta)
  // ══════════════════════════════════════════════════════════════════════════
  async function insertarRespuesta(datos) {
    var lic = licenciaId();
    if (!lic) return true; // demo: el front incrementa el contador local
    try {
      var secInt = parseInt(String(datos.seccion || '').replace(/\D/g, ''), 10);
      // [T8 15 jul] Resolver el municipio_id (UUID) antes de armar el body.
      // Si el catálogo municipios ya está poblado con nombres reales, esto
      // devuelve el id; si sigue con placeholders, devuelve null (degrada suave).
      var munId = await municipioId(datos.municipio);
      var body = {
        encuesta_id: datos.encuesta_id,
        licencia_id: lic,
        municipio_id: munId,
        seccion_id: Number.isFinite(secInt) ? secInt : null,
        usuario_id: usuarioId(),
        rango_edad: datos.rango_edad || null,
        genero: datos.genero || null,
        // ANÓNIMA: solo respuestas jsonb + demografía no identificable.
        // Se conserva el nombre en el jsonb como respaldo aunque ya haya id.
        respuestas: Object.assign({}, datos.respuestas,
          datos.municipio ? { _municipio_nombre: datos.municipio } : {})
      };
      var url = SUPA_URL + '/rest/v1/respuestas_encuesta';
      var res = await _fetchAuth(url, {
        method: 'POST',
        headers: headers({ 'Prefer': 'return=minimal' }),
        body: JSON.stringify(body)
      });
      if (!res || !res.ok) { console.warn('T21: no se pudo guardar entrevista (status ' + (res && res.status) + ').'); return false; }
      return true;
    } catch (e) { console.warn('T21: excepción insertarRespuesta:', e); return false; }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Cruce Territorio vs Opinión — v_territorio_vs_opinion (agregados)
  // ══════════════════════════════════════════════════════════════════════════
  async function cargarCruce() {
    try {
      var lic = licenciaId();
      if (!lic) return null; // demo: conservar CRUCE horneado
      var url = SUPA_URL + '/rest/v1/v_territorio_vs_opinion'
        + '?select=seccion_id,municipio_id,entrevistas,con_preferencia,indecisos,voto_firme'
        + '&licencia_id=eq.' + encodeURIComponent(lic);
      var res = await _fetchAuth(url, { method: 'GET', headers: headers() });
      if (!res || !res.ok) return null;
      var rows = await res.json();
      if (!Array.isArray(rows) || !rows.length) return null;
      return rows; // el front decide cómo agrupar/mostrar
    } catch (e) { return null; }
  }

  // ── Exponer helpers para que el front los invoque en cada punto SWAP ───────
  window.T21 = {
    moduloHabilitado: moduloHabilitado,
    cargarEncuestas: cargarEncuestas,
    actualizarEstado: actualizarEstado,
    insertarEncuesta: insertarEncuesta,
    insertarRespuesta: insertarRespuesta,
    cargarCruce: cargarCruce
  };

  // ── Arranque: intentar cargar datos reales; si hay, refrescar la UI ────────
  async function init() {
    // Gating por tier: si la licencia NO tiene el módulo, avisar (no romper demo).
    var permitido = await moduloHabilitado();
    if (!permitido) {
      console.warn('T21: la licencia no habilita el módulo Encuestas (' + MODULO_TIER + ').');
      // El host puede optar por ocultar el módulo; aquí solo avisamos.
      try { window.dispatchEvent(new CustomEvent('encuestas-no-habilitado')); } catch (e) {}
      return;
    }
    var ok = await cargarEncuestas();
    if (ok) {
      // Refrescar las vistas que dependen de ENCUESTAS.
      if (typeof renderLista === 'function') renderLista();
      if (typeof poblarSelectorEncuestas === 'function') poblarSelectorEncuestas();
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
