// ============================================================
//  SYNC QUEUE — SIE COLIMA 2027  (Fase 5 · Pieza 3)
//  Sincroniza los pendientes de IndexedDB hacia Supabase.
//  Estrategia B: verifica CURP en el servidor ANTES de subir,
//  para no duplicar. Si ya existe, marca 'conflicto' (Pieza 4).
//  Requiere: offline_db.js (OfflineDB) y supabase_client.js (SDB).
// ============================================================

const SyncQueue = {

  _sincronizando: false,   // candado anti-concurrencia
  _onCambio: null,         // callback opcional para refrescar la UI

  // Permite a la página registrar una función que se llama
  // cada vez que cambia el estado (para actualizar badges/listas).
  onCambio(fn) { this._onCambio = fn; },
  _notificar(info) { if (typeof this._onCambio === 'function') this._onCambio(info); },

  // ── Sincronizar todos los pendientes ────────────────────
  async sincronizar({ silencioso = false } = {}) {
    // Sin conexión real: no intentamos nada.
    if (!navigator.onLine) {
      if (!silencioso) console.log('🔌 Sin conexión: sincronización pospuesta.');
      return { subidos: 0, conflictos: 0, errores: 0, sinConexion: true };
    }
    // Candado: evita dos corridas simultáneas que dupliquen.
    if (this._sincronizando) {
      return { subidos: 0, conflictos: 0, errores: 0, yaEnCurso: true };
    }
    if (typeof OfflineDB === 'undefined' || typeof SDB === 'undefined') {
      console.warn('SyncQueue: faltan OfflineDB o SDB.');
      return { subidos: 0, conflictos: 0, errores: 0 };
    }

    this._sincronizando = true;
    let subidos = 0, conflictos = 0, errores = 0;

    try {
      await SDB.waitReady();
      const pendientes = await OfflineDB.listarPendientes();
      if (!pendientes.length) {
        return { subidos: 0, conflictos: 0, errores: 0, vacio: true };
      }

      for (const reg of pendientes) {
        try {
          // 1. ¿Ya existe esa CURP en el servidor? → conflicto.
          if (reg.ciudadano?.curp && reg.ciudadano.curp.length === 18) {
            const { data: existente } = await SDB.buscarPorCURP(reg.ciudadano.curp);
            if (existente) {
              await OfflineDB.actualizar(reg.local_id, {
                sync_status:  'conflicto',
                conflicto_id: existente.id,        // id del registro que ya está en BD
                ultimo_error: 'CURP ya existe en el servidor',
              });
              conflictos++;
              continue;   // no se sube; la Pieza 4 lo resolverá
            }
          }

          // 2. Insertar ciudadano (marcado ya como 'synced' en BD).
          const ciudadanoData = { ...reg.ciudadano, sync_status: 'synced' };
          const { data: ciudadano, error: errC } = await SDB.guardarCiudadano(ciudadanoData);
          if (errC) throw new Error(errC.message || 'Error al insertar ciudadano');

          // 3. Insertar candidatura vinculada con el id real.
          if (reg.candidatura) {
            const candidaturaData = { ...reg.candidatura, ciudadano_id: ciudadano.id };
            await SDB.guardarCandidatura(candidaturaData);
          }

          // 4. Auditoría + borrar de la cola local.
          await SDB.log('SYNC_CIUDADANO', 'ciudadanos', ciudadano.id, { local_id: reg.local_id });
          await OfflineDB.eliminar(reg.local_id);
          subidos++;

        } catch (errReg) {
          // Falla puntual: guardamos el error y reintentamos luego.
          console.error('Error sincronizando', reg.local_id, errReg);
          await OfflineDB.actualizar(reg.local_id, {
            intentos:     (reg.intentos || 0) + 1,
            ultimo_error: errReg.message || String(errReg),
          });
          errores++;
        }
      }

      if (!silencioso) {
        console.log(`✅ Sync: ${subidos} subidos, ${conflictos} conflictos, ${errores} errores.`);
      }

      // Resolución automática de conflictos (Pieza 4): "gana el primero".
      // Archiva en auditoría y descarta los duplicados detectados arriba.
      if (conflictos > 0 && typeof Conflictos !== 'undefined') {
        try {
          const r = await Conflictos.resolver();
          if (!silencioso && r.resueltos > 0) Conflictos.avisar(r.descartados);
        } catch (e) {
          console.error('Error resolviendo conflictos:', e);
        }
      }

      this._notificar({ subidos, conflictos, errores });
      return { subidos, conflictos, errores };

    } finally {
      this._sincronizando = false;
    }
  },

  // ── Conteos rápidos para la UI ───────────────────────────
  async resumen() {
    if (typeof OfflineDB === 'undefined') return { pendientes: 0, conflictos: 0 };
    const todos = await OfflineDB.listarTodos();
    return {
      pendientes:  todos.filter(r => r.sync_status === 'pending').length,
      conflictos:  todos.filter(r => r.sync_status === 'conflicto').length,
    };
  },

  // ── Arranque automático ──────────────────────────────────
  // Sincroniza al volver el internet y al cargar la página.
  iniciar() {
    // Cuando el navegador recupera conexión:
    window.addEventListener('online', () => {
      console.log('🌐 Conexión recuperada — sincronizando pendientes...');
      this.sincronizar();
    });
    // Intento inicial al cargar (por si quedaron pendientes de antes).
    if (navigator.onLine) {
      setTimeout(() => this.sincronizar({ silencioso: true }), 2000);
    }
  },
};

// Arranque automático al cargar el script.
if (typeof window !== 'undefined') {
  document.addEventListener('DOMContentLoaded', () => SyncQueue.iniciar());
}
