-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 32: ENDURECER `alertas_update`
-- Proyecto staging: dyirhwwmykskpuvzcafx · 22 jul 2026 · rama desarrollo
--
-- Cierra el pendiente que dejó anotado 14_fix_fuga_ciudadanos.sql
-- ("revisar el mismo patrón en encuestas, respuestas_encuesta, alertas,
--  reportes_casilla_eleccion"). Revisadas las cuatro contra pg_policies:
--
--   ✔ encuestas .................. INSERT/UPDATE/DELETE filtran por rol · OK
--   ✔ respuestas_encuesta ........ INSERT filtra por rol y exige que la
--                                  encuesta esté 'activa' con EXISTS · OK
--   ✔ reportes_casilla_eleccion .. INSERT/UPDATE filtran por rol y validan
--                                  con EXISTS que la casilla sea de la
--                                  licencia · OK (el mejor diseño de las 4)
--   ✘ alertas .................... alertas_update con DOS problemas
--
-- HALLAZGO en `alertas_update`:
--   qual = (licencia_id = licencia del usuario) · with_check = NULL
--
--   1) SIN FILTRO DE ROL: cualquier rol autenticado de la licencia podía
--      modificar CUALQUIER alerta — no solo marcar la suya como leída, sino
--      editar el MENSAJE de una alerta ajena o marcar como leídas las de
--      otras secciones. El INSERT sí estaba bien acotado (super_admin, admin,
--      coordinador); el UPDATE quedó abierto.
--   2) with_check NULO: mismo patrón que ciudadanos (SQL 31) — se podía
--      cambiar el licencia_id de una alerta y sacarla a otra licencia.
--
-- DISEÑO CORRECTO (separa las dos operaciones que hoy estaban mezcladas):
--   ▸ El MANDO (super_admin/admin/coordinador) gestiona alertas: puede
--     editarlas dentro de su licencia.
--   ▸ El DESTINATARIO solo puede MARCARLA COMO LEÍDA. Las alertas se dirigen
--     por sección (el frontend consulta `?seccion=eq.X&leida=eq.false`), así
--     que el capturista/líder solo toca las de SU sección y la fila debe
--     seguir en su sección y licencia después del UPDATE.
--
--   Nota: RLS no distingue QUÉ COLUMNA se modifica, así que la política del
--   destinatario no puede impedir por sí sola que cambie el texto del
--   mensaje; lo que sí garantiza es que solo alcance alertas de SU sección y
--   que no pueda sacarlas de su ámbito. Para blindar columna por columna
--   haría falta un trigger — se deja anotado como mejora, no es urgente
--   porque el frontend solo envía {leida, leida_at}.
--
-- ⚠️ STAGING COMPARTIDO: correr coordinado. Avisar a José (cambia RLS).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DROP POLICY IF EXISTS alertas_update ON public.alertas;

-- 1. Mando: gestiona las alertas de su licencia y debe dejarlas ahí.
CREATE POLICY alertas_update_mando ON public.alertas
  FOR UPDATE
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador'])
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()
  );

-- 2. Destinatario: solo alertas de SU sección, y deben seguir en su sección.
--    Cubre el flujo real de marcarAlertaLeida() en panel_capturista_personal.
CREATE POLICY alertas_update_destinatario ON public.alertas
  FOR UPDATE
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['capturista','jefe_seccion'])
    AND seccion = get_mi_seccion()
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND seccion = get_mi_seccion()
  );

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
--
--   SELECT policyname, cmd, qual, with_check FROM pg_policies
--    WHERE tablename='alertas' ORDER BY cmd, policyname;
--     → alertas_update ya no existe; en su lugar alertas_update_mando y
--       alertas_update_destinatario, ambas con with_check NO nulo
--
-- PRUEBAS FUNCIONALES (requieren sesión real de cada rol):
--   a) Con `capturista`: abrir su panel, recibir una alerta de su sección y
--      pulsar "✓ Entendido" → debe SEGUIR funcionando (flujo de campo).
--   b) Con `capturista`: intentar marcar como leída una alerta de OTRA
--      sección → debe RECHAZARSE (antes pasaba).
--   c) Con `coordinador`: editar una alerta de su licencia → debe funcionar.
--   d) Cualquier rol: intentar cambiar el licencia_id de una alerta → debe
--      RECHAZARSE.
-- ⚠️ Correr (a) antes de dar por buena la migración.
--
-- MEJORA FUTURA (no urgente): trigger que impida al destinatario modificar
-- cualquier columna que no sea `leida`/`leida_at`. Hoy el frontend solo envía
-- esas dos, pero RLS por sí sola no lo garantiza.
-- ═══════════════════════════════════════════════════════════════════════════
