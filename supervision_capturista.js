/* ============================================================================
 * MODO SUPERVISIÓN — panel_capturista_personal.html
 * Fase 4 · rama desarrollo · 10 jul 2026
 *
 * PROBLEMA
 *   El panel personal se construye alrededor de DOS ejes de identidad:
 *     CAP_ID      → qué registros veo  (ciudadanos.capturista_id)
 *     SECCION_CAP → qué alertas recibo (alertas.seccion)
 *   Ambos salen de la sesión. Pero un super_admin/admin NO tiene sección
 *   asignada (usuarios.seccion = null, y con razón: no es de campo).
 *   Resultado: "MI SECCIÓN: —", alertas nunca consultadas, y el header
 *   mostrando "Capturista 17 · Secc. 138" que es HTML HORNEADO (L224-227),
 *   no la sesión. Ni era su panel, ni el panel avisaba que no lo era.
 *
 * DECISIÓN (10 jul): MODO SUPERVISIÓN.
 *   Un rol de mando SÍ puede ver el panel, pero explícitamente: elige QUÉ
 *   capturista inspeccionar. No finge ser él.
 *   Coherente con el patrón de Coordinador General que ya usa el proyecto
 *   (get_mi_municipio() IS NULL = alcance estatal, no "está roto").
 *
 * NO TOCA el flujo del capturista real: si la sesión trae `seccion`, este
 * script no hace nada y el panel funciona exactamente igual que hoy.
 * ========================================================================== */
(function () {
  'use strict';

  var ROLES_MANDO = ['super_admin', 'admin', 'coordinador'];

  // Estado del supervisor: a quién estoy mirando.
  var _viendo = null;   // { id, nombre, seccion, municipio }

  function sesion() {
    try {
      return window._sesion
        || JSON.parse(localStorage.getItem('electoral_sesion') || 'null');
    } catch (e) { return null; }
  }

  function esMando() {
    var s = sesion();
    return !!(s && ROLES_MANDO.indexOf(s.rol) !== -1);
  }

  function tieneSeccionPropia() {
    var s = sesion();
    return !!(s && s.seccion);
  }

  // ── ¿Aplica el modo supervisión? ────────────────────────────────────────
  // Solo si es rol de mando Y no tiene sección propia. Un capturista (o un
  // coordinador con sección asignada) usa el panel normal, sin cambios.
  function aplicaSupervision() {
    return esMando() && !tieneSeccionPropia();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Traer la lista de capturistas (RPC que ya existe: get_capturistas_stats)
  // ══════════════════════════════════════════════════════════════════════════
  async function listarCapturistas() {
    var s = sesion();
    var SUPA_URL = 'https://dyirhwwmykskpuvzcafx.supabase.co';
    var KEY = (typeof SUPA_KEY !== 'undefined') ? SUPA_KEY : null;
    if (!KEY) return [];
    var token = (s && s.access_token) || KEY;
    var lic = (s && s.licencia_id) || null;

    try {
      // Leemos usuarios con rol capturista de la misma licencia.
      // (usuarios.seccion es justo el dato que necesitamos para las alertas)
      var url = SUPA_URL + '/rest/v1/usuarios'
        + '?select=id,nombre,seccion,municipio,rol'
        + '&rol=eq.capturista'
        + (lic ? '&licencia_id=eq.' + encodeURIComponent(lic) : '')
        + '&order=nombre';
      var res = await fetch(url, {
        headers: { 'apikey': KEY, 'Authorization': 'Bearer ' + token }
      });
      if (!res.ok) {
        console.warn('Supervisión: no se pudo listar capturistas (' + res.status + ')');
        return [];
      }
      var data = await res.json();
      return Array.isArray(data) ? data : [];
    } catch (e) {
      console.warn('Supervisión: excepción listando capturistas:', e);
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  UI: barra de supervisión sobre el panel
  // ══════════════════════════════════════════════════════════════════════════
  function pintarBarra(capturistas) {
    if (document.getElementById('barra-supervision')) return;

    var barra = document.createElement('div');
    barra.id = 'barra-supervision';
    barra.style.cssText =
      'display:flex;align-items:center;gap:12px;flex-wrap:wrap;' +
      'padding:10px 16px;background:rgba(139,92,246,.12);' +
      'border-bottom:1px solid rgba(139,92,246,.35);' +
      'font-size:12px;color:var(--text2);';

    var etiqueta = document.createElement('span');
    etiqueta.innerHTML = '<strong style="color:#a78bfa">MODO SUPERVISIÓN</strong> · ' +
      'Estás viendo este panel como administrador, no como capturista.';

    var sel = document.createElement('select');
    sel.id = 'sel-supervision';
    sel.style.cssText =
      'padding:5px 8px;border-radius:5px;background:var(--bg2,#1a1a2e);' +
      'color:var(--text,#e5e7eb);border:1px solid rgba(139,92,246,.4);' +
      'font-size:12px;min-width:220px;';

    var opt0 = document.createElement('option');
    opt0.value = '';
    opt0.textContent = capturistas.length
      ? '— Elegir capturista a inspeccionar —'
      : '— No hay capturistas en esta licencia —';
    sel.appendChild(opt0);

    capturistas.forEach(function (c) {
      var o = document.createElement('option');
      o.value = c.id;
      var secc = c.seccion ? ('Secc. ' + c.seccion) : 'sin sección';
      var mun = c.municipio ? (' · ' + c.municipio) : '';
      o.textContent = (c.nombre || '(sin nombre)') + ' — ' + secc + mun;
      o.dataset.seccion = c.seccion || '';
      o.dataset.municipio = c.municipio || '';
      o.dataset.nombre = c.nombre || '';
      sel.appendChild(o);
    });

    sel.addEventListener('change', function () {
      var op = sel.options[sel.selectedIndex];
      if (!sel.value) { limpiarSeleccion(); return; }
      seleccionar({
        id: sel.value,
        nombre: op.dataset.nombre,
        seccion: op.dataset.seccion || null,
        municipio: op.dataset.municipio || null
      });
    });

    barra.appendChild(etiqueta);
    barra.appendChild(sel);

    var topbar = document.querySelector('.topbar');
    if (topbar && topbar.parentNode) {
      topbar.parentNode.insertBefore(barra, topbar.nextSibling);
    } else {
      document.body.insertBefore(barra, document.body.firstChild);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Reapuntar el panel al capturista elegido
  // ══════════════════════════════════════════════════════════════════════════
  function seleccionar(cap) {
    _viendo = cap;

    // Reapuntar los dos ejes de identidad. Como CAP_ID/SECCION_CAP son const
    // en el panel, publicamos overrides en window y el panel los prefiere
    // (ver el patch de panel_capturista_personal.html).
    window._SUP_CAP_ID = cap.id;
    window._SUP_SECCION = cap.seccion;

    // Actualizar el header para que NO mienta: dice a quién estás viendo.
    var nom = document.querySelector('.tb-name');
    var idd = document.querySelector('.tb-id');
    var av = document.getElementById('tb-av');
    if (nom) nom.textContent = cap.nombre || 'Capturista';
    if (idd) {
      idd.textContent = (cap.seccion ? ('Secc. ' + cap.seccion) : 'sin sección')
        + (cap.municipio ? (' · ' + cap.municipio) : '')
        + '  ·  (supervisión)';
    }
    if (av && cap.nombre) {
      av.textContent = cap.nombre.split(' ').slice(0, 2)
        .map(function (w) { return w[0]; }).join('').toUpperCase();
    }

    // Recargar los datos del capturista elegido.
    if (typeof cargarMisRegistros === 'function') cargarMisRegistros();
    if (typeof verificarAlertasCoordinador === 'function') verificarAlertasCoordinador();
  }

  function limpiarSeleccion() {
    _viendo = null;
    window._SUP_CAP_ID = null;
    window._SUP_SECCION = null;
    var nom = document.querySelector('.tb-name');
    var idd = document.querySelector('.tb-id');
    var s = sesion();
    if (nom) nom.textContent = (s && s.nombre) || 'Administrador';
    if (idd) idd.textContent = 'Modo supervisión · elige un capturista';
    if (typeof cargarMisRegistros === 'function') cargarMisRegistros();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Arranque
  // ══════════════════════════════════════════════════════════════════════════
  async function init() {
    if (!aplicaSupervision()) return;  // capturista real: no tocar nada.

    // Marca que el panel consulta para NO cargar toda la licencia mientras
    // no haya un capturista elegido (ver cargarMisRegistros).
    window._SUP_ACTIVO = true;

    var caps = await listarCapturistas();
    pintarBarra(caps);
    limpiarSeleccion();   // estado inicial: header honesto, sin datos ajenos.

    console.log('🔍 Modo supervisión activo (' + caps.length + ' capturistas disponibles).');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  window._supervision = { seleccionar: seleccionar, viendo: function () { return _viendo; } };
})();
