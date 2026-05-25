// ============================================================
//  CLIENTE SUPABASE — SIE COLIMA 2027
//  Incluir en TODOS los módulos que necesiten BD:
//  <script src="supabase_client.js"></script>
//
//  ie-staging  → desarrollo y pruebas
//  VOTERA      → producción
// ============================================================

// ── Detectar ambiente ────────────────────────────────────────
const IS_STAGING = window.location.hostname === 'localhost' 
  || window.location.hostname === '127.0.0.1'
  || window.location.hostname.includes('staging')
  || window.location.hostname.includes('inteligencia-electoral.vercel.app');

// ── Credenciales ─────────────────────────────────────────────
const SUPABASE_CONFIG = {
  staging: {
    url:  'https://dyirhwwmykskpuvzcafx.supabase.co',
    key:  'sb_publishable_15ryvEoNMYqJr4bHm7fi0g_BcvPMMrK'
  },
  production: {
    url:  'https://jawymbrpglddhhlizifk.supabase.co',
    key:  'sb_publishable_sFoiB-_SwBEONPhxg9-LnQ_0k2f2zzY'
  }
};

const ENV = IS_STAGING ? 'staging' : 'production';
const { url: SUPA_URL, key: SUPA_KEY } = SUPABASE_CONFIG[ENV];

// ── Inicializar cliente Supabase ──────────────────────────────
// Carga la librería de Supabase dinámicamente
(function loadSupabase() {
  const script = document.createElement('script');
  script.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';
  script.onload = () => {
    window.supabase = window.supabase.createClient(SUPA_URL, SUPA_KEY);
    console.log(`✅ Supabase conectado [${ENV.toUpperCase()}]`);
    // Disparar evento para que los módulos sepan que está listo
    document.dispatchEvent(new Event('supabase-ready'));
  };
  script.onerror = () => {
    console.error('❌ No se pudo cargar Supabase — verifica conexión a internet');
  };
  document.head.appendChild(script);
})();

// ============================================================
//  API — Funciones de acceso a la BD
// ============================================================

const SDB = {

  // ── CIUDADANOS / SIMPATIZANTES ──────────────────────────────

  /** Esperar a que el cliente esté listo */
  async waitReady() {
    if(window.supabase) return;
    await new Promise(resolve => document.addEventListener('supabase-ready', resolve, {once:true}));
  },

  /** Buscar ciudadano por CURP (anti-duplicados) */
  async buscarPorCURP(curp) {
    await this.waitReady();
    const { data, error } = await window.supabase
      .from('ciudadanos')
      .select('id, nombre, apellido_paterno, apellido_materno, curp')
      .eq('curp', curp)
      .single();
    return { data, error };
  },

  /** Buscar ciudadano por teléfono */
  async buscarPorTel(telefono) {
    await this.waitReady();
    const { data, error } = await window.supabase
      .from('ciudadanos')
      .select('id, nombre, apellido_paterno, telefono')
      .eq('telefono', telefono)
      .maybeSingle();
    return { data, error };
  },

  /** Guardar nuevo ciudadano */
  async guardarCiudadano(datos) {
    await this.waitReady();
    const { data, error } = await window.supabase
      .from('ciudadanos')
      .insert([datos])
      .select()
      .single();
    return { data, error };
  },

  /** Guardar vínculo ciudadano ↔ candidatura */
  async guardarCandidatura(datos) {
    await this.waitReady();
    const { data, error } = await window.supabase
      .from('ciudadanos_candidaturas')
      .insert([datos])
      .select()
      .single();
    return { data, error };
  },

  /** Obtener lista de ciudadanos con filtros */
  async listarCiudadanos({ seccion, municipio, nivel, limite = 50, offset = 0 } = {}) {
    let query = window.supabase
      .from('ciudadanos')
      .select(`
        id, nombre, apellido_paterno, apellido_materno, edad, sexo,
        telefono, curp, clave_elector, seccion_electoral, municipio,
        origen, created_at, compromiso,
        es_influencia, es_apoyo, es_riesgo,
        responsable_id, capturista_id,
        validado, duplicado
      `)
      .order('created_at', { ascending: false })
      .range(offset, offset + limite - 1);

    if (seccion)   query = query.eq('seccion_electoral', seccion);
    if (municipio) query = query.eq('municipio', municipio);
    if (nivel)     query = query.eq('compromiso', nivel);

    const { data, error } = await query;
    return { data, error };
  },

  /** Actualizar nivel de compromiso */
  async actualizarNivel(ciudadanoId, candidaturaId, nivelNuevo, usuarioId) {
    // Obtener nivel anterior para historial
    const { data: actual } = await window.supabase
      .from('ciudadanos_candidaturas')
      .select('compromiso')
      .eq('ciudadano_id', ciudadanoId)
      .eq('candidatura_id', candidaturaId)
      .single();

    // Actualizar nivel
    const { data, error } = await window.supabase
      .from('ciudadanos_candidaturas')
      .update({ compromiso: nivelNuevo })
      .eq('ciudadano_id', ciudadanoId)
      .eq('candidatura_id', candidaturaId);

    // Guardar historial
    if (!error && actual) {
      await window.supabase
        .from('ciudadanos_historial_nivel')
        .insert([{
          ciudadano_id: ciudadanoId,
          candidatura_id: candidaturaId,
          nivel_anterior: actual.compromiso,
          nivel_nuevo: nivelNuevo,
          usuario_id: usuarioId
        }]);
    }

    return { data, error };
  },

  // ── SECCIONES ───────────────────────────────────────────────

  /** Obtener secciones activas con meta */
  async getSecciones(municipioId = null) {
    let query = window.supabase
      .from('secciones_electorales')
      .select('*')
      .eq('activo', true)
      .order('numero');

    if (municipioId) query = query.eq('municipio_id', municipioId);
    const { data, error } = await query;
    return { data, error };
  },

  // ── AVANCE ──────────────────────────────────────────────────

  /** Avance por municipio (usa vista war_room_municipios) */
  async getAvanceMunicipios() {
    const { data, error } = await window.supabase
      .from('war_room_municipios')
      .select('*');
    return { data, error };
  },

  /** Avance por sección (usa vista war_room_secciones) */
  async getAvanceSecciones(municipioId = null) {
    let query = window.supabase
      .from('war_room_secciones')
      .select('*');
    if (municipioId) query = query.eq('municipio_id', municipioId);
    const { data, error } = await query;
    return { data, error };
  },

  /** Resumen del capturista actual */
  async getResumenCapturista(usuarioId) {
    const { data, error } = await window.supabase
      .from('panel_capturistas_resumen')
      .select('*')
      .eq('usuario_id', usuarioId)
      .single();
    return { data, error };
  },

  // ── USUARIOS ────────────────────────────────────────────────

  /** Obtener usuario actual por auth_user_id */
  async getUsuarioActual() {
    const { data: { user } } = await window.supabase.auth.getUser();
    if (!user) return { data: null, error: 'No autenticado' };

    const { data, error } = await window.supabase
      .from('usuarios')
      .select('*, municipios(nombre), distritos(nombre)')
      .eq('auth_user_id', user.id)
      .single();
    return { data, error };
  },

  // ── LICENCIAS ───────────────────────────────────────────────

  /** Aceptar términos de una licencia */
  async aceptarTerminos(licenciaId, usuarioNombre) {
    const { data, error } = await window.supabase
      .from('licencias')
      .update({
        terminos_aceptados: true,
        terminos_fecha: new Date().toISOString(),
        terminos_usuario: usuarioNombre
      })
      .eq('id', licenciaId);
    return { data, error };
  },

  // ── AUDITORÍA ───────────────────────────────────────────────

  /** Registrar acción en auditoría */
  async log(accion, tabla, registroId, datosNuevo = null) {
    const { data: { user } } = await window.supabase.auth.getUser();
    await window.supabase
      .from('audit_log')
      .insert([{
        accion,
        tabla,
        registro_id: registroId,
        datos_nuevo: datosNuevo,
        usuario_id: user?.id
      }]);
  }
};

// ── Helper: mostrar ambiente en consola ──────────────────────
console.log(`🗺 SIE Colima 2027 | Ambiente: ${ENV.toUpperCase()} | ${SUPA_URL}`);
