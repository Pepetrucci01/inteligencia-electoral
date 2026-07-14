// ============================================================
//  CLIENTE SUPABASE — SIE COLIMA 2027
// ============================================================

// [FIX 12 jul] La deteccion anterior solo matcheaba el dominio EXACTO de
// produccion ('inteligencia-electoral.vercel.app'), pero Vercel genera un hash
// unico por deploy en cada preview de la rama desarrollo. Por ejemplo:
//   inteligencia-electoral-9ftvrknhv-votera-s-projects.vercel.app
// Ese hostname NO contiene 'inteligencia-electoral.vercel.app', asi que
// IS_STAGING daba false -> el preview intentaba conectarse al proyecto de
// PRODUCCION, que AUN NO EXISTE -> net::ERR_NAME_NOT_RESOLVED en todo.
//
// Ahora es AL REVES: production SOLO cuando el dominio es exactamente el de
// produccion. Cualquier otra cosa (local, previews, ramas) usa staging.
// Es el default seguro: si la deteccion falla, se va a staging, no a un
// proyecto inexistente ni -peor- a datos reales de clientes.
const HOST = window.location.hostname;

// Dominios de PRODUCCION. Añadir aqui el dominio final cuando exista (votera.mx).
const DOMINIOS_PRODUCCION = [
  'inteligencia-electoral.vercel.app',
  // 'votera.mx',
  // 'www.votera.mx',
];

const IS_PRODUCTION = DOMINIOS_PRODUCCION.includes(HOST);
const IS_STAGING = !IS_PRODUCTION;

const SUPABASE_CONFIG = {
  staging: {
    url: 'https://dyirhwwmykskpuvzcafx.supabase.co',
    key: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR5aXJod3dteWtza3B1dnpjYWZ4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1NTk3ODgsImV4cCI6MjA5NTEzNTc4OH0.2xe4cHqORGng1hnYPJ9ZiyT0r87fMijbUEJqBy3-xoI'
  },
  production: {
    url: 'https://jawymbrpglddhhlizifk.supabase.co',
    key: 'sb_publishable_sFoiB-_SwBEONPhxg9-LnQ_0k2f2zzY'
  }
};

const ENV = IS_STAGING ? 'staging' : 'production';
const { url: SUPA_URL, key: SUPA_KEY } = SUPABASE_CONFIG[ENV];

// [FIX 12 jul] El proyecto de PRODUCCION aun NO EXISTE (ESTRUCTURA_MAESTRA §4.3:
// "Proyecto Supabase de PRODUCCION separado del staging" = pendiente).
// Si alguien despliega al dominio de produccion antes de crearlo, el resultado
// es una cascada de net::ERR_NAME_NOT_RESOLVED dificil de diagnosticar.
// Este aviso lo hace explicito desde el primer segundo.
if (ENV === 'production') {
  console.warn(
    '⚠️ AMBIENTE: PRODUCTION (' + SUPA_URL + ').\n' +
    'Si el proyecto Supabase de produccion aun no existe, TODAS las peticiones\n' +
    'fallaran con ERR_NAME_NOT_RESOLVED. Verificar antes de desplegar a main.'
  );
}

(function loadSupabase() {
  const script = document.createElement('script');
  script.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';
  script.onload = async () => {
    // Crear cliente con auth manual: NO dejamos que el SDK refresque
    // ni persista la sesión por su cuenta, porque la sesión la
    // gestionamos nosotros (electoral_sesion + supaFetch en theme.js).
    // Si el SDK también refresca, compite por el refresh_token (que es
    // de un solo uso) y provoca 400 Bad Request en /auth/v1/token.
    window.supabase = window.supabase.createClient(SUPA_URL, SUPA_KEY, {
      auth: {
        autoRefreshToken: false,   // lo maneja supaFetch (theme.js)
        persistSession:   false,   // la sesión vive en electoral_sesion
        detectSessionInUrl: false,
      },
    });
    console.log(`✅ Supabase conectado [${ENV.toUpperCase()}]`);

    // ── Restaurar sesión desde localStorage ──────────────────
    try {
      const sesionRaw = localStorage.getItem('electoral_sesion');
      if (sesionRaw) {
        const sesion = JSON.parse(sesionRaw);
        if (sesion.access_token && sesion.refresh_token) {
          await window.supabase.auth.setSession({
            access_token:  sesion.access_token,
            refresh_token: sesion.refresh_token,
          });
          console.log('✅ Sesión restaurada para:', sesion.email);
        }
      }
    } catch(e) {
      console.warn('No se pudo restaurar sesión:', e);
    }

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

  async waitReady() {
    if (window.supabase) return;
    await new Promise(resolve => document.addEventListener('supabase-ready', resolve, {once: true}));
  },

  async buscarPorCURP(curp) {
    await this.waitReady();
    const { data, error } = await window.supabase
      .from('ciudadanos')
      .select('id, nombre, apellido_paterno, apellido_materno, curp')
      .eq('curp', curp)
      .maybeSingle();
    return { data, error };
  },

  async buscarPorTel(telefono) {
    await this.waitReady();
    const { data, error } = await window.supabase
      .from('ciudadanos')
      .select('id, nombre, apellido_paterno, telefono')
      .eq('telefono', telefono)
      .maybeSingle();
    return { data, error };
  },

  async guardarCiudadano(datos) {
    await this.waitReady();
    const { data, error } = await window.supabase
      .from('ciudadanos')
      .insert([datos])
      .select()
      .single();
    return { data, error };
  },

  async guardarCandidatura(datos) {
    await this.waitReady();
    const { data, error } = await window.supabase
      .from('ciudadanos_candidaturas')
      .insert([datos]);
    return { data, error };
  },

  async log(accion, tabla, registroId, datosNuevo = null) {
    try {
      await this.waitReady();
      const { data: { user } } = await window.supabase.auth.getUser();
      await window.supabase
        .from('audit_log')
        .insert([{
          accion,
          tabla:       tabla || null,
          registro_id: registroId || null,
          detalle:     datosNuevo ? JSON.stringify(datosNuevo) : null,
          usuario_id:  user?.id || null,
        }]);
    } catch(e) {
      console.warn('Audit log skipped:', e.message);
    }
  },

  async getCasillasInstalacion() {
    await this.waitReady();
    const { data, error } = await window.supabase
      .from('casillas')
      .select(`id, numero_seccion, numero_casilla, tipo_casilla, estatus_casilla,
               municipio, lat, lng, hora_apertura, incidencias_apertura,
               presidente_casilla, lista_nominal, activo`)
      .eq('activo', true)
      .order('municipio')
      .order('numero_seccion');
    return { data, error };
  },

  async getResumenInstalacion() {
    await this.waitReady();
    const { data, error } = await window.supabase
      .from('casillas')
      .select('estatus_casilla')
      .eq('activo', true);
    if (error) return { data: null, error };
    const resumen = {
      total:        data.length,
      instalada:    data.filter(c => c.estatus_casilla === 'instalada').length,
      no_instalada: data.filter(c => c.estatus_casilla === 'no_instalada').length,
      suspendida:   data.filter(c => c.estatus_casilla === 'suspendida').length,
      sin_reporte:  data.filter(c => !c.estatus_casilla).length,
    };
    resumen.pct = resumen.total > 0
      ? Math.round((resumen.instalada / resumen.total) * 100) : 0;
    return { data: resumen, error: null };
  },

  async getSeccionesColima(municipio = null) {
    await this.waitReady();
    let query = window.supabase
      .from('secciones_electorales_colima')
      .select(`id, seccion, municipio, id_municipio, distrito_federal, distrito_local,
               lat, lon, lista_nominal, total_votos, votos_morena, votos_priand, votos_mc,
               afluencia, estatus_afluencia, meta_proyectada, refuerzo_prioritario, metodologia`)
      .order('seccion');
    if (municipio) query = query.eq('municipio', municipio);
    const { data, error } = await query;
    return { data, error };
  },

};

// ============================================================
//  TERRITORIO — Helper para filtrar queries por licencia
// ============================================================

const TERRITORIO = {

  get() {
    try {
      const s = JSON.parse(localStorage.getItem('electoral_sesion') || 'null');
      return s?.territorio || { tipo: 'estado' };
    } catch(e) { return { tipo: 'estado' }; }
  },

  // Aplicar filtro a query de Supabase
  aplicar(query, opts = {}) {
    const t = this.get();
    const campoMun = opts.campoMunicipio || 'municipio';
    const campoDf  = opts.campoDF        || 'distrito_federal';
    const campoDl  = opts.campoDL        || 'distrito_local';
    switch(t.tipo) {
      case 'estado': break;
      case 'mun':
        if(t.id_municipio) query = query.eq('id_municipio', t.id_municipio);
        else if(t.municipio) query = query.ilike(campoMun, t.municipio);
        break;
      case 'df':
        if(t.id) query = query.eq(campoDf, t.id);
        break;
      case 'dl':
        if(t.id) query = query.eq(campoDl, t.id);
        break;
    }
    return query;
  },

  // Filtrar array en memoria
  perteneceArray(item, opts = {}) {
    const t = this.get();
    if(t.tipo === 'estado') return true;
    const campoMun = opts.campoMunicipio || 'municipio';
    const campoDf  = opts.campoDF        || 'distrito_federal';
    const campoDl  = opts.campoDL        || 'distrito_local';
    switch(t.tipo) {
      case 'mun':
        if(t.id_municipio) return item.id_municipio === t.id_municipio;
        if(t.municipio) return (item[campoMun]||'').toLowerCase() === t.municipio.toLowerCase();
        return true;
      case 'df': return String(item[campoDf]) === String(t.id);
      case 'dl': return String(item[campoDl]) === String(t.id);
      default:   return true;
    }
  },

  label() {
    const t = this.get();
    switch(t.tipo) {
      case 'estado': return 'Todo el estado';
      case 'mun':    return `Municipio: ${t.municipio || t.id_municipio}`;
      case 'df':     return `Distrito Federal ${t.id}`;
      case 'dl':     return `Distrito Local ${t.id}`;
      default:       return 'Sin definir';
    }
  },

  esEstado() { return this.get().tipo === 'estado'; },
};

console.log(`🗺 SIE Colima 2027 | Ambiente: ${ENV.toUpperCase()} | ${SUPA_URL}`);
