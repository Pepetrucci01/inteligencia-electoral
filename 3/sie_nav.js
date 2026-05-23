// Shared navigation component
function buildNav(activePage) {
  const u = SIE.checkAuth();
  if(!u) return;
  
  const perms = PERMS[u.rol];
  const pages = [
    {id:'dashboard', label:'📊 Dashboard',   file:'dashboard.html'},
    {id:'mapa',      label:'🗺 Mapa',         file:'mapa.html'},
    {id:'captura',   label:'✍️ Capturar',     file:'captura.html'},
    {id:'simpatizantes', label:'👥 Simpatizantes', file:'simpatizantes.html'},
    {id:'avance',    label:'📈 Avance',       file:'avance.html'},
    {id:'estructura',label:'🏗 Estructura',   file:'estructura.html'},
    {id:'usuarios',  label:'⚙️ Usuarios',     file:'usuarios.html'},
  ];

  // Topbar
  document.getElementById('topbar').innerHTML = `
    <h1>🗺 INTELIGENCIA ELECTORAL — COLIMA 2027</h1>
    <div class="top-right">
      <div class="user-badge">
        <div class="rdot" style="background:${u.color}"></div>
        <span>${u.nombre} — ${u.rol.toUpperCase()}</span>
      </div>
      <button class="btn-out" onclick="SIE.logout()">Cerrar sesión</button>
    </div>`;

  // Nav
  const nav = document.getElementById('nav');
  nav.innerHTML = pages.map(p => {
    const allowed = perms.includes(p.id);
    const isActive = p.id === activePage;
    return `<button class="nav-btn ${isActive?'active':''} ${!allowed?'locked':''}" 
      onclick="${allowed ? `window.location.href='${p.file}'` : 'void(0)'}">${p.label}</button>`;
  }).join('');

  // Role banner if element exists
  const bannerEl = document.getElementById('role-banner');
  if(bannerEl){
    bannerEl.className = `rb ${u.rol}`;
    bannerEl.innerHTML = `
      <div class="rb-icon">${ROL_ICONS[u.rol]}</div>
      <div class="rb-info">
        <h2>${u.nombre}</h2>
        <p>${ROL_NAMES[u.rol]} — ${u.licencia}</p>
        <span class="terr">📍 ${u.territorio}</span>
      </div>`;
  }
  return u;
}
