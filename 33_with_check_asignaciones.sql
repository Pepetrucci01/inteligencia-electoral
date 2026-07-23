-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 33: `WITH CHECK` EN asig_repr_update
-- Proyecto staging: dyirhwwmykskpuvzcafx · 22 jul 2026 · rama desarrollo
--
-- Cierra la ÚLTIMA tabla del pendiente que dejó anotado
-- 14_fix_fuga_ciudadanos.sql. Estado revisado de `asignaciones_representante`:
--
--   ✔ asig_repr_insert ... filtra por licencia y rol (super_admin/admin/
--                          coordinador) · OK
--   ✔ asig_repr_delete ... filtra por licencia y rol (super_admin/admin) · OK
--   ✔ asig_repr_select ... licencia + (es la propia OR es rol de mando) · OK
--   ✘ asig_repr_update ... with_check = NULL
--
-- HALLAZGO: mismo patrón ya corregido en ciudadanos (SQL 31) y alertas
-- (SQL 32). El `qual` acota bien QUÉ FILAS puede tocar el mando, pero sin
-- `WITH CHECK` no se controla CÓMO QUEDAN: un coordinador podía editar una
-- asignación de su licencia y cambiarle el licencia_id, moviéndola a otro
-- tenant. Menos grave que los casos anteriores porque el INSERT ya estaba
-- acotado a roles de mando (no a cualquier rol autenticado), pero cerrarlo
-- deja las tres tablas consistentes.
--
-- ⚠️ STAGING COMPARTIDO: correr coordinado. Avisar a José (cambia RLS).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DROP POLICY IF EXISTS asig_repr_update ON public.asignaciones_representante;

CREATE POLICY asig_repr_update ON public.asignaciones_representante
  FOR UPDATE
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador'])
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()
  );

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
--
--   SELECT policyname, cmd, with_check FROM pg_policies
--    WHERE tablename='asignaciones_representante' AND cmd='UPDATE';
--     → asig_repr_update debe tener with_check = (licencia_id = get_mi_licencia())
--
-- PRUEBAS FUNCIONALES:
--   a) Con `coordinador`: reasignar un representante dentro de su licencia
--      → debe SEGUIR funcionando.
--   b) Con cualquier rol: intentar cambiar el licencia_id de una asignación
--      → debe RECHAZARSE.
--
-- ── ESTADO GLOBAL TRAS SQL 31/32/33 ────────────────────────────────────────
-- Queda cerrado el pendiente de 14_fix_fuga_ciudadanos.sql. Las tablas con
-- escrituras sensibles (ciudadanos, alertas, asignaciones_representante, encuestas,
-- respuestas_encuesta, reportes_casilla_eleccion) ya filtran por rol en
-- INSERT y tienen WITH CHECK en UPDATE, así que ninguna fila puede salirse
-- de su licencia (ni de su municipio/sección donde aplica) por la vía de un
-- UPDATE.
-- ═══════════════════════════════════════════════════════════════════════════
