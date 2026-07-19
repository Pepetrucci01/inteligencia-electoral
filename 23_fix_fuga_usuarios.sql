-- ═══════════════════════════════════════════════════════════════════════════
-- 23_fix_fuga_usuarios.sql · 18 jul 2026
-- FUGA MULTI-TENANT en `usuarios` (hallada revisando pg_policies para la
-- validación de José 16-17 jul; mismo patrón que las 7 fugas de T6).
--
-- Problema: la política "Service role full access" está definida con
--   roles = {public}, cmd = ALL, qual = true
-- Como las políticas RLS son permisivas (OR), CUALQUIER usuario autenticado
-- de CUALQUIER licencia puede leer/actualizar/borrar TODOS los usuarios de
-- TODAS las licencias. La versión correcta ya existe (usuarios_service_role
-- con auth.role() = 'service_role'), así que la de `true` sobra.
--
-- ⚠️ Se sustituye en el MISMO script por una política de administración por
-- licencia, porque el panel de admin muy probablemente dependía de la fuga
-- para editar usuarios ajenos (la única UPDATE legítima era
-- usuarios_update_propio = solo el propio perfil).
--
-- REVISAR CON JOSÉ ANTES DE APLICAR (cambio de schema/permisos).
-- Después de aplicar: probar en staging que el panel admin puede seguir
-- creando/editando/desactivando usuarios con super_admin y con admin.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Eliminar la política con qual=true (la fuga)
DROP POLICY IF EXISTS "Service role full access" ON public.usuarios;

-- 2. Administración de usuarios por licencia:
--    super_admin → todos los usuarios (es MEFT)
--    admin       → solo usuarios de SU licencia, y NUNCA filas con rol
--                  super_admin (ni tocarlas ni crearlas ni promover a nadie:
--                  sin este candado, un admin podría escalar privilegios
--                  asignando rol='super_admin' y ver TODAS las licencias).
CREATE POLICY usuarios_admin_manage ON public.usuarios
  FOR ALL
  USING (
        get_mi_rol() = 'super_admin'
     OR (get_mi_rol() = 'admin'
         AND licencia_id = get_mi_licencia()
         AND rol IS DISTINCT FROM 'super_admin')
  )
  WITH CHECK (
        get_mi_rol() = 'super_admin'
     OR (get_mi_rol() = 'admin'
         AND licencia_id = get_mi_licencia()
         AND rol IS DISTINCT FROM 'super_admin')
  );

-- ─────────────────────────────────────────────────────────────────────────
-- Verificación (patrón 13_prueba_fuga_multitenant):
-- a) Como usuario de la licencia B (p.ej. capturista), correr desde el cliente:
--      GET /rest/v1/usuarios?select=id,email  → NO debe devolver usuarios de A.
-- b) Como admin de la licencia A: debe seguir viendo/editando SOLO usuarios A.
-- c) Como super_admin: todo igual que antes.
-- d) Como admin de A: intentar UPDATE usuarios SET rol='super_admin' sobre un
--    usuario de su licencia → debe RECHAZARSE (candado anti-escalación).
-- e) SELECT tablename, policyname, cmd, qual FROM pg_policies
--      WHERE tablename = 'usuarios';
--    → ya no debe aparecer ninguna política con qual = true.
-- ─────────────────────────────────────────────────────────────────────────
