// ============================================================
//  CONFLICTOS — SIE COLIMA 2027  (Fase 5 · Pieza 4)
//  Regla: "gana el primero". Cuando una CURP capturada offline
//  ya existe en el servidor, el registro local se DESCARTA, pero
//  antes se ARCHIVA en audit_log (no se pierde el rastro).
//  Se ejecuta automáticamente al terminar cada sincronización.
//  Requiere: offline_db.js (OfflineDB) y supabase_client.js (SDB).
// ============================================================

const Conflictos = {

  // ── Resolver todos los conflictos pendientes ─────────────
  // Recorre los registros marcados 'conflicto' por SyncQueue,
  // los archiva en auditoría y los elimina de la cola local.
  async resolver() {
    if (typeof OfflineDB === 'undefined') return { resueltos: 0 };

    const todos = await OfflineDB.listarTodos();
    const conflictivos = todos.filter(r => r.sync_status === 'conflicto');
    if (!conflictivos.length) return { resueltos: 0, descartados: [] };

    let resueltos = 0;
    const descartados = [];

    for (const reg of conflictivos) {
      try {
        // 1. Archivar en auditoría ANTES de descartar (deja evidencia).
        await SDB.log('CONFLICTO_DESCARTADO', 'ciudadanos', reg.conflicto_id || null, {
          motivo:          'CURP duplicada — gana el primero',
          curp:            reg.ciudadano?.curp || null,
          nombre_descartado: [
            reg.ciudadano?.nombre,
            reg.ciudadano?.apellido_paterno,
            reg.ciudadano?.apellido_materno,
          ].filter(Boolean).join(' '),
          dispositivo:     reg.dispositivo || null,
          capturista_id:   reg.ciudadano?.capturista_id || null,
          registro_ganador: reg.conflicto_id || null,
          capturado_en:    reg.creado_en || null,
          datos_descartados: reg.ciudadano || null,
        });

        // 2. Eliminar de IndexedDB (ya quedó archivado).
        await OfflineDB.eliminar(reg.local_id);

        descartados.push({
          curp:   reg.ciudadano?.curp || '',
          nombre: [reg.ciudadano?.nombre, reg.ciudadano?.apellido_paterno].filter(Boolean).join(' '),
        });
        resueltos++;

      } catch (err) {
        // Si falla el archivado (p.ej. sin conexión), lo dejamos
        // como 'conflicto' para reintentar en la próxima ronda.
        console.error('No se pudo archivar conflicto', reg.local_id, err);
      }
    }

    if (resueltos) {
      console.log(`🔀 Conflictos resueltos: ${resueltos} registro(s) duplicado(s) descartado(s).`);
    }
    return { resueltos, descartados };
  },

  // ── Aviso amigable al capturista ─────────────────────────
  // Llamar tras resolver() si quieres notificar en pantalla.
  avisar(descartados) {
    if (!descartados || !descartados.length) return;
    const lista = descartados
      .map(d => `• ${d.nombre || d.curp}`)
      .join('\n');
    alert(
      'ℹ️ ' + descartados.length + ' registro(s) ya estaban capturados por otro ' +
      'capturista y NO se duplicaron:\n\n' + lista +
      '\n\n(Quedó registrado en la auditoría.)'
    );
  },
};
