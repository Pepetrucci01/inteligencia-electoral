// ============================================================
//  OFFLINE DB — SIE COLIMA 2027  (Fase 5 · Pieza 1)
//  Almacén local con IndexedDB para captura sin internet.
//  No depende de Supabase. No toca nada del flujo online.
// ============================================================

const OfflineDB = {

  _db: null,
  DB_NAME: 'sie_colima_offline',
  DB_VERSION: 1,
  STORE: 'pendientes',

  // ── Abrir / crear la base local ──────────────────────────
  async open() {
    if (this._db) return this._db;
    return new Promise((resolve, reject) => {
      const req = indexedDB.open(this.DB_NAME, this.DB_VERSION);

      // Se ejecuta solo la primera vez (o al subir DB_VERSION):
      // aquí se define la estructura del almacén.
      req.onupgradeneeded = (e) => {
        const db = e.target.result;
        if (!db.objectStoreNames.contains(this.STORE)) {
          const store = db.createObjectStore(this.STORE, { keyPath: 'local_id' });
          store.createIndex('por_curp',   'curp',        { unique: false });
          store.createIndex('por_status', 'sync_status', { unique: false });
          store.createIndex('por_fecha',  'creado_en',   { unique: false });
        }
      };

      req.onsuccess = (e) => { this._db = e.target.result; resolve(this._db); };
      req.onerror   = (e) => reject(e.target.error);
    });
  },

  // ── Generar un ID temporal local único ───────────────────
  // Prefijo 'local-' para distinguirlo siempre de un UUID real de Supabase.
  _nuevoLocalId() {
    const rnd = (crypto?.randomUUID?.() || (Date.now() + '-' + Math.random().toString(16).slice(2)));
    return 'local-' + rnd;
  },

  // ── Guardar un registro pendiente ────────────────────────
  // Recibe el ciudadanoData y el candidaturaData tal cual los
  // arma modulo_captura, y los empaqueta como UN pendiente.
  async guardarPendiente(ciudadanoData, candidaturaData) {
    const db = await this.open();
    const registro = {
      local_id:     this._nuevoLocalId(),
      curp:         ciudadanoData.curp || '',
      telefono:     ciudadanoData.telefono || '',
      ciudadano:    ciudadanoData,
      candidatura:  candidaturaData,
      sync_status:  'pending',
      intentos:     0,
      ultimo_error: null,
      dispositivo:  this._idDispositivo(),
      creado_en:    new Date().toISOString(),
    };
    return new Promise((resolve, reject) => {
      const tx = db.transaction(this.STORE, 'readwrite');
      tx.objectStore(this.STORE).add(registro);
      tx.oncomplete = () => resolve(registro);
      tx.onerror    = (e) => reject(e.target.error);
    });
  },

  // ── Leer todos los pendientes (sync_status = 'pending') ──
  async listarPendientes() {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const tx    = db.transaction(this.STORE, 'readonly');
      const idx   = tx.objectStore(this.STORE).index('por_status');
      const req   = idx.getAll('pending');
      req.onsuccess = () => resolve(req.result || []);
      req.onerror   = (e) => reject(e.target.error);
    });
  },

  // ── Leer TODOS los registros (cualquier status) ──────────
  async listarTodos() {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const tx  = db.transaction(this.STORE, 'readonly');
      const req = tx.objectStore(this.STORE).getAll();
      req.onsuccess = () => resolve(req.result || []);
      req.onerror   = (e) => reject(e.target.error);
    });
  },

  // ── Buscar pendiente por CURP (para detectar duplicados) ─
  async buscarPorCURP(curp) {
    if (!curp) return null;
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const tx  = db.transaction(this.STORE, 'readonly');
      const idx = tx.objectStore(this.STORE).index('por_curp');
      const req = idx.get(curp);
      req.onsuccess = () => resolve(req.result || null);
      req.onerror   = (e) => reject(e.target.error);
    });
  },

  // ── Actualizar un registro (p.ej. marcar synced o error) ─
  async actualizar(local_id, cambios) {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const tx    = db.transaction(this.STORE, 'readwrite');
      const store = tx.objectStore(this.STORE);
      const getReq = store.get(local_id);
      getReq.onsuccess = () => {
        const reg = getReq.result;
        if (!reg) { resolve(null); return; }
        Object.assign(reg, cambios);
        store.put(reg);
      };
      tx.oncomplete = () => resolve(true);
      tx.onerror    = (e) => reject(e.target.error);
    });
  },

  // ── Eliminar un registro (tras sincronizar con éxito) ────
  async eliminar(local_id) {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(this.STORE, 'readwrite');
      tx.objectStore(this.STORE).delete(local_id);
      tx.oncomplete = () => resolve(true);
      tx.onerror    = (e) => reject(e.target.error);
    });
  },

  // ── Contar pendientes (para mostrar badge en la UI) ──────
  async contarPendientes() {
    const pend = await this.listarPendientes();
    return pend.length;
  },

  // ── ID estable del dispositivo (para Pieza 4: conflictos)─
  _idDispositivo() {
    let id = localStorage.getItem('sie_dispositivo_id');
    if (!id) {
      id = 'disp-' + (crypto?.randomUUID?.() || Date.now().toString(16));
      localStorage.setItem('sie_dispositivo_id', id);
    }
    return id;
  },
};
