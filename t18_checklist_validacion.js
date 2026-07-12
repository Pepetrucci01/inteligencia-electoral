/* ============================================================================
 * T18 — CHECKLIST DE VALIDACIÓN (pegar en la consola del visor tras el deploy)
 * Corre contra el runtime real: window.IE_METAS_CASILLA, CASILLAS, currentLayer.
 * Cifras de control de ESTRUCTURA_MAESTRA §4.0 + instructivo T18.
 * ========================================================================== */
(function () {
  var M = window.IE_METAS_CASILLA;
  var out = [];
  var ok = true;

  function check(nombre, cond, esperado, real) {
    ok = ok && cond;
    out.push((cond ? '✅' : '❌') + ' ' + nombre +
      (esperado !== undefined ? '  (esperado: ' + esperado + ' | real: ' + real + ')' : ''));
  }

  // 0) El objeto existe y tiene la forma correcta
  check('IE_METAS_CASILLA existe', !!M && !!M.secciones);
  if (!M || !M.secciones) { console.log(out.join('\n')); return; }

  var secKeys = Object.keys(M.secciones);

  // 1) Meta estatal vigente = 208,717 (main tras +19 casillas estimadas)
  check('Meta estatal', M.meta_estatal === 208717, 208717, M.meta_estatal);

  // 2) Secciones con meta = 388
  check('Secciones con meta', secKeys.length === 388, 388, secKeys.length);

  // 3) Total de casillas colgadas = 1,033
  var totalCasillas = secKeys.reduce(function (acc, k) {
    return acc + (M.secciones[k].casillas ? M.secciones[k].casillas.length : 0);
  }, 0);
  check('Total casillas', totalCasillas === 1033, 1033, totalCasillas);

  // 4) Spot check sección 85: proyectada 394 / real 408
  var s85 = M.secciones['85'];
  check('Sección 85 existe', !!s85);
  if (s85) {
    check('Sección 85 meta_proyectada', s85.meta_proyectada === 394, 394, s85.meta_proyectada);
    check('Sección 85 meta_real',       s85.meta_real === 408,       408, s85.meta_real);
  }

  // 5) casilla_completa siempre string (nunca number)
  var ccNoString = 0, cc0;
  for (var i = 0; i < secKeys.length && ccNoString === 0; i++) {
    var arr = M.secciones[secKeys[i]].casillas || [];
    for (var j = 0; j < arr.length; j++) {
      if (typeof arr[j].cc !== 'string') { ccNoString++; cc0 = arr[j].cc; break; }
    }
  }
  check('cc siempre string (nunca parseInt)', ccNoString === 0, 'string', cc0 !== undefined ? typeof cc0 : 'string');

  // 6) El visor conserva sus globals (no se rompió nada)
  check('CASILLAS global intacto', typeof CASILLAS !== 'undefined' && CASILLAS.length > 0);
  check('renderSecciones disponible', typeof renderSecciones === 'function');

  out.push('');
  out.push(ok ? '🟢 T18 OK — todas las validaciones pasaron.'
              : '🔴 T18 con fallos — revisar los ❌ de arriba (si falló el fetch, debería seguir el horneado).');
  console.log(out.join('\n'));
})();
