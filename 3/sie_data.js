// SISTEMA DE INTELIGENCIA ELECTORAL — COLIMA 2027
// Datos compartidos entre módulos

const MUNICIPIOS = [{"nombre": "MANZANILLO", "secciones": 79, "meta": 51442.0, "lista_nominal": 150178, "facil": 21, "medio": 34, "dificil": 24, "avance": 0}, {"nombre": "COLIMA", "secciones": 99, "meta": 48030.0, "lista_nominal": 134925, "facil": 48, "medio": 39, "dificil": 12, "avance": 0}, {"nombre": "VILLA DE ALVAREZ", "secciones": 70, "meta": 34952.0, "lista_nominal": 115181, "facil": 42, "medio": 24, "dificil": 4, "avance": 0}, {"nombre": "TECOMAN", "secciones": 62, "meta": 29211.0, "lista_nominal": 94105, "facil": 8, "medio": 33, "dificil": 21, "avance": 0}, {"nombre": "CUAUHTEMOC", "secciones": 18, "meta": 8061.0, "lista_nominal": 24719, "facil": 13, "medio": 3, "dificil": 2, "avance": 0}, {"nombre": "ARMERIA", "secciones": 21, "meta": 7337.0, "lista_nominal": 21148, "facil": 5, "medio": 10, "dificil": 6, "avance": 0}, {"nombre": "COMALA", "secciones": 13, "meta": 6292.0, "lista_nominal": 18367, "facil": 11, "medio": 2, "dificil": 0, "avance": 0}, {"nombre": "COQUIMATLAN", "secciones": 15, "meta": 5049.0, "lista_nominal": 16600, "facil": 7, "medio": 5, "dificil": 3, "avance": 0}, {"nombre": "MINATITLAN", "secciones": 7, "meta": 4329.0, "lista_nominal": 8434, "facil": 6, "medio": 0, "dificil": 1, "avance": 0}, {"nombre": "IXTLAHUACAN", "secciones": 8, "meta": 2593.0, "lista_nominal": 5257, "facil": 8, "medio": 0, "dificil": 0, "avance": 0}];
const DISTRITOS_L = [{"nombre": "DL-1 COLIMA", "num": 1, "secciones": 29, "meta": 14228.0, "facil": 11, "medio": 18, "dificil": 0, "avance": 0}, {"nombre": "DL-2 COLIMA", "num": 2, "secciones": 38, "meta": 13523.0, "facil": 23, "medio": 12, "dificil": 3, "avance": 0}, {"nombre": "DL-3 COLIMA", "num": 3, "secciones": 22, "meta": 12220.0, "facil": 7, "medio": 8, "dificil": 7, "avance": 0}, {"nombre": "DL-4 COLIMA", "num": 4, "secciones": 22, "meta": 12914.0, "facil": 17, "medio": 3, "dificil": 2, "avance": 0}, {"nombre": "DL-5 COQUIMATLAN", "num": 5, "secciones": 27, "meta": 10586.0, "facil": 11, "medio": 12, "dificil": 4, "avance": 0}, {"nombre": "DL-6 CUAUHTEMOC", "num": 6, "secciones": 26, "meta": 15083.0, "facil": 20, "medio": 4, "dificil": 2, "avance": 0}, {"nombre": "DL-7 VILLA DE ALVAREZ", "num": 7, "secciones": 20, "meta": 12477.0, "facil": 10, "medio": 9, "dificil": 1, "avance": 0}, {"nombre": "DL-8 VILLA DE ALVAREZ", "num": 8, "secciones": 31, "meta": 11353.0, "facil": 22, "medio": 7, "dificil": 2, "avance": 0}, {"nombre": "DL-9 ARMERIA", "num": 9, "secciones": 33, "meta": 12609.0, "facil": 7, "medio": 18, "dificil": 8, "avance": 0}, {"nombre": "DL-10 TECOMAN", "num": 10, "secciones": 22, "meta": 10235.0, "facil": 3, "medio": 14, "dificil": 5, "avance": 0}, {"nombre": "DL-11 MANZANILLO", "num": 11, "secciones": 18, "meta": 13125.0, "facil": 4, "medio": 8, "dificil": 6, "avance": 0}, {"nombre": "DL-12 MANZANILLO", "num": 12, "secciones": 9, "meta": 10617.0, "facil": 6, "medio": 3, "dificil": 0, "avance": 0}, {"nombre": "DL-13 MANZANILLO", "num": 13, "secciones": 27, "meta": 13046.0, "facil": 6, "medio": 12, "dificil": 9, "avance": 0}, {"nombre": "DL-14 MINATITLAN", "num": 14, "secciones": 20, "meta": 13711.0, "facil": 9, "medio": 3, "dificil": 8, "avance": 0}, {"nombre": "DL-15 TECOMAN", "num": 15, "secciones": 19, "meta": 10396.0, "facil": 3, "medio": 11, "dificil": 5, "avance": 0}, {"nombre": "DL-16 TECOMAN", "num": 16, "secciones": 29, "meta": 11172.0, "facil": 10, "medio": 8, "dificil": 11, "avance": 0}];
const MUN_COLORS = {"COLIMA": "#e94560", "COMALA": "#0f9b8e", "COQUIMATLAN": "#f5a623", "CUAUHTEMOC": "#7b68ee", "VILLA DE ALVAREZ": "#50c878", "ARMERIA": "#ff6b6b", "IXTLAHUACAN": "#4ecdc4", "MANZANILLO": "#45b7d1", "MINATITLAN": "#96ceb4", "TECOMAN": "#ffd93d"};
const DF_COLORS = {"COLIMA": "#e94560", "VALLE DE LAS GARZAS": "#0f9b8e"};
const DL_COLORS = {"DL-1 COLIMA": "#e94560", "DL-2 COLIMA": "#ff6b35", "DL-3 COLIMA": "#f7c59f", "DL-4 COLIMA": "#c8a2c8", "DL-5 COQUIMATLAN": "#004e89", "DL-6 CUAUHTEMOC": "#1a936f", "DL-7 VILLA DE ALVAREZ": "#88d498", "DL-8 VILLA DE ALVAREZ": "#45b7d1", "DL-9 ARMERIA": "#ffd93d", "DL-10 TECOMAN": "#ff6b6b", "DL-11 MANZANILLO": "#4ecdc4", "DL-12 MANZANILLO": "#96ceb4", "DL-13 MANZANILLO": "#7b68ee", "DL-14 MINATITLAN": "#50c878", "DL-15 TECOMAN": "#f5a623", "DL-16 TECOMAN": "#0f9b8e"};

// Session management
const SIE = {
  getUser: function() {
    const u = sessionStorage.getItem('sie_user');
    return u ? JSON.parse(u) : null;
  },
  setUser: function(user) {
    sessionStorage.setItem('sie_user', JSON.stringify(user));
  },
  logout: function() {
    sessionStorage.removeItem('sie_user');
    window.location.href = 'index.html';
  },
  checkAuth: function(allowedRoles) {
    const u = this.getUser();
    if(!u) { window.location.href = 'index.html'; return null; }
    if(allowedRoles && !allowedRoles.includes(u.rol)) {
      window.location.href = 'index.html'; return null;
    }
    return u;
  },
  fmt: function(n) { return Math.round(n||0).toLocaleString('es-MX'); },
  getBarColor: function(p) { return p>=100?'#00ff88':p>=70?'#00cc66':p>=40?'#ffaa00':'#ff4466'; },
};

const PERMS = {
  administrador: ['dashboard','mapa','captura','simpatizantes','avance','estructura','usuarios'],
  coordinador:   ['dashboard','mapa','simpatizantes','avance','estructura'],
  lider:         ['dashboard','mapa','captura','simpatizantes','avance'],
  capturista:    ['captura','simpatizantes'],
};

const ROL_ICONS = {administrador:'👑',coordinador:'🗺',lider:'🏅',capturista:'👤'};
const ROL_NAMES = {administrador:'Administrador',coordinador:'Coordinador',lider:'Líder de Sección',capturista:'Capturista'};
