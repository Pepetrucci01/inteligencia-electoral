// ─── DATOS COMPARTIDOS — SIE COLIMA 2027 ────────────────────────────────────

const MUNICIPIOS_DATA = [
  {nombre:'ARMERIA',secciones:19,meta:9976,lista_nominal:27641,facil:8,medio:7,dificil:4,avance:0},
  {nombre:'COLIMA',secciones:79,meta:44881,lista_nominal:131071,facil:38,medio:28,dificil:13,avance:0},
  {nombre:'COMALA',secciones:14,meta:6025,lista_nominal:18085,facil:5,medio:7,dificil:2,avance:0},
  {nombre:'COQUIMATLAN',secciones:19,meta:8543,lista_nominal:24872,facil:7,medio:8,dificil:4,avance:0},
  {nombre:'CUAUHTEMOC',secciones:22,meta:9361,lista_nominal:27628,facil:9,medio:9,dificil:4,avance:0},
  {nombre:'IXTLAHUACAN',secciones:8,meta:3271,lista_nominal:9536,facil:3,medio:3,dificil:2,avance:0},
  {nombre:'MANZANILLO',secciones:79,meta:51442,lista_nominal:150178,facil:21,medio:34,dificil:24,avance:0},
  {nombre:'MINATITLAN',secciones:10,meta:4156,lista_nominal:11892,facil:4,medio:4,dificil:2,avance:0},
  {nombre:'TECOMAN',secciones:63,meta:33972,lista_nominal:99619,facil:27,medio:26,dificil:10,avance:0},
  {nombre:'VILLA DE ALVAREZ',secciones:79,meta:25670,lista_nominal:88392,facil:47,medio:24,dificil:8,avance:0},
];

const MUNICIPIOS = MUNICIPIOS_DATA;

const DISTRITOS_L = [
  {nombre:'DL-1 COLIMA',num:1,secciones:29,meta:14228,facil:11,medio:18,dificil:0,avance:0},
  {nombre:'DL-2 COLIMA',num:2,secciones:18,meta:9562,facil:8,medio:10,dificil:0,avance:0},
  {nombre:'DL-3 COLIMA',num:3,secciones:15,meta:8234,facil:7,medio:8,dificil:0,avance:0},
  {nombre:'DL-4 COLIMA',num:4,secciones:17,meta:12857,facil:12,medio:5,dificil:0,avance:0},
  {nombre:'DL-5 COQUIMATLAN',num:5,secciones:33,meta:14568,facil:12,medio:14,dificil:7,avance:0},
  {nombre:'DL-6 CUAUHTEMOC',num:6,secciones:36,meta:15922,facil:14,medio:15,dificil:7,avance:0},
  {nombre:'DL-7 VILLA DE ALVAREZ',num:7,secciones:28,meta:10234,facil:13,medio:10,dificil:5,avance:0},
  {nombre:'DL-8 VILLA DE ALVAREZ',num:8,secciones:22,meta:8976,facil:10,medio:9,dificil:3,avance:0},
  {nombre:'DL-9 ARMERIA',num:9,secciones:26,meta:12341,facil:9,medio:11,dificil:6,avance:0},
  {nombre:'DL-10 TECOMAN',num:10,secciones:24,meta:11234,facil:10,medio:10,dificil:4,avance:0},
  {nombre:'DL-11 MANZANILLO',num:11,secciones:22,meta:13456,facil:7,medio:9,dificil:6,avance:0},
  {nombre:'DL-12 MANZANILLO',num:12,secciones:21,meta:12789,facil:6,medio:10,dificil:5,avance:0},
  {nombre:'DL-13 MANZANILLO',num:13,secciones:20,meta:11234,facil:5,medio:9,dificil:6,avance:0},
  {nombre:'DL-14 MINATITLAN',num:14,secciones:18,meta:9876,facil:7,medio:7,dificil:4,avance:0},
  {nombre:'DL-15 TECOMAN',num:15,secciones:22,meta:10234,facil:9,medio:9,dificil:4,avance:0},
  {nombre:'DL-16 TECOMAN',num:16,secciones:21,meta:11552,facil:9,medio:8,dificil:4,avance:0},
];

const MUN_COLORS = {
  'ARMERIA':'#ff6b6b','COLIMA':'#e94560','COMALA':'#0f9b8e',
  'COQUIMATLAN':'#f5a623','CUAUHTEMOC':'#7b68ee','IXTLAHUACAN':'#4ecdc4',
  'MANZANILLO':'#45b7d1','MINATITLAN':'#96ceb4','TECOMAN':'#ffd93d',
  'VILLA DE ALVAREZ':'#50c878'
};

const DF_COLORS = {'COLIMA':'#e94560','VALLE DE LAS GARZAS':'#0f9b8e'};

const DL_COLORS = {
  'DL-1 COLIMA':'#e94560','DL-2 COLIMA':'#ff6b35','DL-3 COLIMA':'#f7c59f',
  'DL-4 COLIMA':'#c8a2c8','DL-5 COQUIMATLAN':'#004e89','DL-6 CUAUHTEMOC':'#1a936f',
  'DL-7 VILLA DE ALVAREZ':'#88d498','DL-8 VILLA DE ALVAREZ':'#45b7d1',
  'DL-9 ARMERIA':'#ffd93d','DL-10 TECOMAN':'#ff6b6b','DL-11 MANZANILLO':'#4ecdc4',
  'DL-12 MANZANILLO':'#96ceb4','DL-13 MANZANILLO':'#7b68ee','DL-14 MINATITLAN':'#50c878',
  'DL-15 TECOMAN':'#f5a623','DL-16 TECOMAN':'#0f9b8e'
};

// ─── SESIÓN ──────────────────────────────────────────────────────────────────
const SIE = {
  getUser() {
    const u = sessionStorage.getItem('sie_user');
    return u ? JSON.parse(u) : null;
  },
  setUser(user) {
    sessionStorage.setItem('sie_user', JSON.stringify(user));
  },
  logout() {
    sessionStorage.clear();
    window.location.href = 'index.html';
  },
  checkAuth(allowedRoles) {
    const u = this.getUser();
    if(!u) { window.location.href = 'index.html'; return null; }
    if(allowedRoles && !allowedRoles.includes(u.rol)) {
      window.location.href = 'index.html'; return null;
    }
    return u;
  },
  fmt(n) { return Math.round(n||0).toLocaleString('es-MX'); },
  getBarColor(p) { return p>=100?'#00ff88':p>=70?'#00cc66':p>=40?'#ffaa00':'#ff4466'; },
};

// ─── PERMISOS POR ROL ────────────────────────────────────────────────────────
const PERMS = {
  administrador: ['dashboard','mapa','captura','simpatizantes','avance','estructura','usuarios'],
  coordinador:   ['dashboard','mapa','simpatizantes','avance','estructura'],
  lider:         ['dashboard','mapa','captura','simpatizantes','avance'],
  capturista:    ['captura','simpatizantes'],
};

const ROL_ICONS = {
  administrador:'👑', coordinador:'🗺', lider:'🏅', capturista:'👤'
};
const ROL_NAMES = {
  administrador:'Administrador', coordinador:'Coordinador',
  lider:'Líder de Sección', capturista:'Capturista'
};
