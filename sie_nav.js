// ─── NAVEGACIÓN COMPARTIDA — SIE COLIMA 2027 ────────────────────────────────

const PAGES = [
  {id:'dashboard',     label:'📊 Dashboard',     file:'dashboard.html'},
  {id:'mapa',          label:'🗺 Mapa',           file:'mapa.html'},
  {id:'captura',       label:'✍️ Capturar',       file:'captura.html'},
  {id:'simpatizantes', label:'👥 Simpatizantes',  file:'simpatizantes.html'},
  {id:'avance',        label:'📈 Avance',         file:'avance.html'},
  {id:'estructura',    label:'🏗 Estructura',     file:'estructura.html'},
  {id:'usuarios',      label:'⚙️ Usuarios',       file:'usuarios.html'},
];

// Páginas que requieren login para entrar
const PROTECTED = ['captura','simpatizantes','usuarios'];

// Páginas que requieren rol administrador
const ADMIN_ONLY = ['usuarios'];

function buildNav(activePage) {
  const u = SIE.getUser();

  // ── Topbar ──────────────────────────────────────────────────────────────
  const topbar = document.getElementById('topbar');
  if(topbar) {
    if(u) {
      topbar.innerHTML = `
        <h1>🗺 INTELIGENCIA ELECTORAL — COLIMA 2027</h1>
        <div class="top-right">
          <div class="user-badge">
            <div class="rdot" style="background:${u.color}"></div>
            <span>${u.nombre} — ${u.rol.toUpperCase()}</span>
          </div>
          <button class="btn-out" onclick="SIE.logout()">Cerrar sesión</button>
        </div>`;
    } else {
      topbar.innerHTML = `
        <h1>🗺 INTELIGENCIA ELECTORAL — COLIMA 2027</h1>
        <div class="top-right">
          <button class="btn-out" onclick="window.location.href='index.html'" 
            style="border-color:#e94560;color:#e94560;">
            🔐 Iniciar Sesión
          </button>
        </div>`;
    }
  }

  // ── Nav bar ─────────────────────────────────────────────────────────────
  const navEl = document.getElementById('nav');
  if(navEl) {
    navEl.innerHTML = PAGES.map(p => {
      const isActive = p.id === activePage;
      const isProtected = PROTECTED.includes(p.id);
      const isAdminOnly = ADMIN_ONLY.includes(p.id);

      // Ocultar Usuarios si no es admin
      if(isAdminOnly && (!u || u.rol !== 'administrador')) return '';

      // Permisos por rol
      let allowed = true;
      if(isProtected && !u) allowed = false;
      if(u) {
        const perms = PERMS[u.rol] || [];
        allowed = perms.includes(p.id);
      }

      const cls = `nav-btn${isActive?' active':''}${!allowed?' locked':''}`;
      const action = allowed
        ? `window.location.href='${p.file}'`
        : isProtected && !u
          ? `window.location.href='index.html'`
          : `void(0)`;

      const lockIcon = !allowed && isProtected && !u ? ' 🔐' : !allowed ? ' 🔒' : '';

      return `<button class="${cls}" onclick="${action}">${p.label}${lockIcon}</button>`;
    }).join('');
  }

  // ── Role banner (si existe en la página) ────────────────────────────────
  const bannerEl = document.getElementById('role-banner');
  if(bannerEl && u) {
    bannerEl.className = `rb ${u.rol}`;
    bannerEl.innerHTML = `
      <div class="rb-icon">${ROL_ICONS[u.rol]}</div>
      <div class="rb-info">
        <h2>${u.nombre}</h2>
        <p>${ROL_NAMES[u.rol]} — ${u.licencia}</p>
        <span class="terr">📍 ${u.territorio}</span>
      </div>`;
  }

  // ── Verificar acceso a páginas protegidas ────────────────────────────────
  if(PROTECTED.includes(activePage) && !u) {
    window.location.href = 'index.html';
    return null;
  }
  if(ADMIN_ONLY.includes(activePage) && (!u || u.rol !== 'administrador')) {
    window.location.href = 'dashboard.html';
    return null;
  }

  return u;
}
