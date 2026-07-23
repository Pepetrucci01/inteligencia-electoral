-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 31: ENDURECER ESCRITURAS EN `ciudadanos`
-- Proyecto staging: dyirhwwmykskpuvzcafx · 22 jul 2026 · rama desarrollo
--
-- HALLAZGO (auditoría RLS vs guards del frontend, 22 jul):
--
-- 1) INSERT SIN FILTRO DE ROL
--    Las políticas `ciudadanos_insert` y `ciudadanos_capturista_insert` solo
--    exigían `licencia_id = get_mi_licencia()`. Como las políticas RLS se
--    combinan con OR, bastaba con esas para que CUALQUIER rol autenticado de
--    la licencia pudiera insertar — incluido `consulta`, que la interfaz
--    presenta como SOLO LECTURA (theme.js le oculta los botones de escritura).
--    O sea: la protección vivía en la UI, no en la capa que manda. Con la
--    consola del navegador, un rol `consulta` podía escribir en el padrón.
--
-- 2) UPDATE SIN `WITH CHECK`
--    `ciudadanos_coordinador_update` y `ciudadanos_coord_update_municipio`
--    tenían with_check = null. En un UPDATE, USING decide QUÉ FILAS puedes
--    tocar; WITH CHECK decide CÓMO PUEDEN QUEDAR. Sin él, un coordinador de
--    Manzanillo podía cambiarle el municipio a un ciudadano suyo (sacándolo de
--    su propio alcance) o incluso cambiarle el licencia_id y moverlo a OTRA
--    licencia — una fuga multi-tenant por la puerta de atrás.
--
-- CRITERIO: los roles que SÍ capturan en campo son capturista, jefe_seccion,
-- coordinador, admin y super_admin. `consulta` es solo lectura y `repr_casilla`
-- conserva su política propia (ya filtra por rol).
--
-- ⚠️ STAGING COMPARTIDO: correr coordinado. Avisar a José (cambia RLS).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. INSERT: exigir rol de captura, no solo licencia ────────────────────
DROP POLICY IF EXISTS ciudadanos_insert ON public.ciudadanos;
CREATE POLICY ciudadanos_insert ON public.ciudadanos
  FOR INSERT
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['capturista','jefe_seccion','coordinador','admin','super_admin'])
  );

DROP POLICY IF EXISTS ciudadanos_capturista_insert ON public.ciudadanos;
CREATE POLICY ciudadanos_capturista_insert ON public.ciudadanos
  FOR INSERT
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['capturista','jefe_seccion','coordinador','admin','super_admin'])
  );

-- (ciudadanos_repr_insert se deja como está: ya exige rol = 'repr_casilla'.)

-- ── 2. UPDATE: añadir WITH CHECK para que la fila no se salga del alcance ──
-- admin / super_admin: pueden editar dentro de su licencia y deben DEJARLA
-- dentro de su licencia (impide mover un ciudadano a otro tenant).
DROP POLICY IF EXISTS ciudadanos_coordinador_update ON public.ciudadanos;
CREATE POLICY ciudadanos_coordinador_update ON public.ciudadanos
  FOR UPDATE
  USING (
    get_mi_rol() = ANY (ARRAY['super_admin','admin'])
    AND licencia_id = get_mi_licencia()
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()
  );

-- coordinador municipal: solo su municipio, y la fila debe SEGUIR en su
-- municipio después del UPDATE (antes podía reasignarla a otro municipio y
-- perderla de vista para siempre).
DROP POLICY IF EXISTS ciudadanos_coord_update_municipio ON public.ciudadanos;
CREATE POLICY ciudadanos_coord_update_municipio ON public.ciudadanos
  FOR UPDATE
  USING (
    get_mi_rol() = 'coordinador'
    AND licencia_id = get_mi_licencia()
    AND municipio   = get_mi_municipio()
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND municipio = get_mi_municipio()
  );

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
--
--   -- Ninguna política de INSERT debe quedar sin filtro de rol:
--   SELECT policyname, cmd, with_check FROM pg_policies
--    WHERE tablename='ciudadanos' AND cmd='INSERT';
--     → las 3 deben mencionar get_mi_rol()
--
--   -- Ningún UPDATE debe quedar con with_check nulo:
--   SELECT policyname, cmd, with_check FROM pg_policies
--    WHERE tablename='ciudadanos' AND cmd='UPDATE';
--     → ambas deben tener with_check
--
-- PRUEBAS FUNCIONALES (requieren sesión real de cada rol):
--   a) Con rol `consulta`: intentar INSERT en ciudadanos → debe RECHAZARSE.
--      (Antes pasaba.) Leer sigue funcionando.
--   b) Con rol `capturista`: capturar un ciudadano → debe SEGUIR funcionando.
--   c) Con `coordinador` de un municipio: editar un ciudadano suyo y tratar de
--      cambiarle el municipio a otro → debe RECHAZARSE.
--   d) Con `admin`: editar un ciudadano y tratar de cambiarle el licencia_id
--      → debe RECHAZARSE.
-- ⚠️ Correr (b) antes de dar por buena la migración: es el flujo de campo y
--    no debe romperse.
-- ═══════════════════════════════════════════════════════════════════════════
