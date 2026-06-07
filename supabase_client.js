// ============================================================
//  CLIENTE SUPABASE — SIE COLIMA 2027
// ============================================================

const IS_STAGING = window.location.hostname === 'localhost' 
  || window.location.hostname === '127.0.0.1'
  || window.location.hostname.includes('staging')
  || window.location.hostname.includes('inteligencia-electoral.vercel.app');

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

(function loadSupabase() {
  const script = document.createElement('script');
  script.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2';
  script.onload = async () => {
    window.supabase = window.supabase.createClient(SUPA_URL, SUPA_KEY);
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

console.log(`🗺 SIE Colima 2027 | Ambiente: ${ENV.toUpperCase()} | ${SUPA_URL}`);
