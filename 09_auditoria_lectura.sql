-- ============================================================================
-- VOTERA — PARTE 9: LECTURA DE AUDITORÍA
-- Proyecto staging: dyirhwwmykskpuvzcafx · 14 jul 2026 · rama desarrollo
--
-- PROBLEMA
--   audit_log tiene INSERT pero NO SELECT para 'authenticated'. Un log que
--   nadie puede leer no sirve de nada: el punto de auditar es poder investigar
--   ("¿quién borró este registro?", "¿quién cambió la meta?"). Sin lectura, es
--   teatro de seguridad.
--
--   Mientras tanto, el panel de Auditoría mostraba datos INVENTADOS: un ataque
--   que nunca ocurrió, con IP falsa ("201.xxx.xxx.12 · 3 intentos fallidos ·
--   IP bloqueada"). Peligroso en ambos sentidos: alguien puede creer que lo
--   están atacando, o confiarse de que no.
--
-- CRITERIO (estándar en sistemas serios)
--   Escritura : cualquier autenticado. Su actividad se registra siempre; nadie
--               puede "no dejar rastro".
--   Lectura   : SOLO super_admin y admin, y cada quien dentro de SU licencia.
--               Un capturista jamás ve el log. El admin del partido A no ve la
--               actividad del partido B.
--   Borrado   : NADIE. Un log alterable no es evidencia. Sin UPDATE, sin DELETE,
--               ni siquiera para el super_admin.
--
-- ⚠️ STAGING COMPARTIDO con la rama desarrollo: correr coordinado.
-- ============================================================================

BEGIN;

-- ── El GRANT que faltaba ────────────────────────────────────────────────────
-- Recordatorio: en Postgres hay DOS puertas. El GRANT abre la tabla; la RLS
-- decide qué filas. Sin GRANT, Postgres corta antes de evaluar la política.
GRANT SELECT ON public.audit_log TO authenticated;

-- (INSERT ya estaba concedido; se deja explícito por claridad)
GRANT INSERT ON public.audit_log TO authenticated;

-- NO se concede UPDATE ni DELETE. A propósito.


-- ── Política de lectura: roles de mando, dentro de su licencia ──────────────
DROP POLICY IF EXISTS audit_select ON audit_log;
CREATE POLICY audit_select ON audit_log
  FOR SELECT USING (
    get_mi_rol() = 'super_admin'
    OR (get_mi_rol() = 'admin' AND licencia_id = get_mi_licencia())
  );

-- ── Escritura: cualquier autenticado deja su rastro ─────────────────────────
DROP POLICY IF EXISTS audit_insert ON audit_log;
CREATE POLICY audit_insert ON audit_log
  FOR INSERT WITH CHECK (
    auth.uid() IS NOT NULL
  );

-- Sin políticas de UPDATE/DELETE: el log es inmutable desde la app.
-- Si alguna vez hay que corregirlo, se hace con service_role y queda constancia.

COMMIT;


-- ============================================================================
-- LO QUE ESTE PANEL **NO** PUEDE MOSTRAR (y por qué)
--
-- Los KPIs "Intentos fallidos", "Alertas de seguridad" y "Sesiones activas"
-- NO viven en tu base de datos. Los intentos de login fallidos ocurren ANTES
-- de que exista una sesión, en la capa de autenticación de Supabase
-- (auth.users / auth.audit_log_entries), a la que la app no tiene acceso.
--
-- Por eso el "3 intentos fallidos · IP 201.xxx.xxx.12" era doblemente falso:
-- ni ocurrió, ni hay dónde guardarlo.
--
-- Si algún día se quieren de verdad, se leen desde la API de administración de
-- Supabase — otro sistema, otras credenciales, otro trabajo. Mientras tanto,
-- se quitan del panel en vez de inventarlos.
-- ============================================================================


-- ============================================================================
-- VERIFICACIÓN (correr después del COMMIT)
-- ============================================================================

-- 1. Logueado como admin/super_admin: debe devolver filas (o 0 si está vacío),
--    pero NUNCA un error de permisos.
-- SELECT count(*) FROM audit_log;

-- 2. Prueba de fuga (como admin, NO como super_admin):
-- SELECT count(DISTINCT licencia_id) FROM audit_log;
--    Esperado: 1 (o 0). Más de 1 → FUGA.

-- 3. Confirmar que el log es inmutable: esto DEBE fallar.
-- DELETE FROM audit_log WHERE id = (SELECT id FROM audit_log LIMIT 1);
--    Esperado: "permission denied" o "no policy". Si BORRA, hay un problema.

-- 4. Confirmar que un capturista NO puede leer:
--    Logueado como capturista, `SELECT count(*) FROM audit_log` debe dar 0 filas.
