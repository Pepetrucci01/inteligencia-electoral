-- ══════════════════════════════════════════════════════════════════
--  T17 · FASE 4.3 — Sistema de Alertas Reales (Coordinador → Activista)
--  Paso 1: tabla `alertas` + RLS
--  Proyecto staging: dyirhwwmykskpuvzcafx  ·  Rama: desarrollo
-- ══════════════════════════════════════════════════════════════════
--
--  ESQUEMA CONFIRMADO (10 jul 2026):
--    · La tabla `usuarios` liga con Supabase Auth por su PROPIO id:
--        usuarios.id = auth.uid()   (verificado con join a auth.users)
--      Por eso las políticas usan  u.id = auth.uid()  (NO existe auth_id).
--    · usuarios.seccion es TEXT → alertas.seccion también es TEXT
--      (así coincide el filtro y no se pierden ceros a la izquierda).
--
--  La tabla es ADITIVA: no modifica nada existente. El staging es
--  compartido con main, así que avisa a Pepe antes de ejecutar.
-- ══════════════════════════════════════════════════════════════════

create table if not exists alertas (
  id                  uuid primary key default gen_random_uuid(),
  licencia_id         uuid not null,
  seccion             text not null,              -- text: coincide con usuarios.seccion
  destinatario_nombre text,
  mensaje             text not null,
  enviada_por         uuid,                       -- auth.uid() del coordinador
  leida               boolean not null default false,
  leida_at            timestamptz,
  created_at          timestamptz not null default now()
);

alter table alertas enable row level security;

-- ── INSERT: solo roles de mando, y solo dentro de su propia licencia ──
create policy alertas_insert on alertas for insert
  with check (
    licencia_id = (select u.licencia_id from usuarios u where u.id = auth.uid())
    and (select u.rol from usuarios u where u.id = auth.uid())
        in ('super_admin','admin','coordinador')
  );

-- ── SELECT: cualquier usuario autenticado de la misma licencia ──
create policy alertas_select on alertas for select
  using (
    licencia_id = (select u.licencia_id from usuarios u where u.id = auth.uid())
  );

-- ── UPDATE: para marcar leída, misma licencia ──
create policy alertas_update on alertas for update
  using (
    licencia_id = (select u.licencia_id from usuarios u where u.id = auth.uid())
  );

-- ── Índice para el polling del panel (por sección, no leídas, recientes) ──
create index if not exists idx_alertas_seccion
  on alertas (licencia_id, seccion, leida, created_at desc);

-- ══════════════════════════════════════════════════════════════════
--  VERIFICACIÓN tras ejecutar:
--    select * from pg_policies where tablename = 'alertas';          -- 3 filas
--    select relrowsecurity from pg_class where relname = 'alertas';  -- true
-- ══════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════
--  GRANT DE TABLA (¡IMPRESCINDIBLE!)
--  Al crear una tabla por SQL, el rol `authenticated` NO recibe permiso
--  automático. Sin esto da HTTP 403 "permission denied for table alertas"
--  (code 42501) ANTES incluso de evaluar el RLS. El RLS decide QUÉ filas;
--  el GRANT decide si la tabla es accesible. Se necesitan los dos.
-- ══════════════════════════════════════════════════════════════════
grant select, insert, update on public.alertas to authenticated;
