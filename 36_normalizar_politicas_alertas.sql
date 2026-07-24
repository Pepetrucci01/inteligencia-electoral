-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 36: NORMALIZAR LAS POLÍTICAS DE `alertas`
-- Proyecto staging: dyirhwwmykskpuvzcafx · 23 jul 2026 · rama desarrollo
--
-- Higiene detectada al revisar pg_policies (22 jul): `alertas_insert` y
-- `alertas_select` son de las POCAS políticas del proyecto que resuelven la
-- licencia y el rol con SUBCONSULTAS CRUDAS a `usuarios`:
--
--     licencia_id = (SELECT u.licencia_id FROM usuarios u WHERE u.id = auth.uid())
--
-- en vez de las funciones canónicas get_mi_licencia() / get_mi_rol() que usa
-- todo lo demás. Vienen de T17_alertas_tabla_rls.sql, anterior a que esas
-- funciones se estandarizaran.
--
-- POR QUÉ IMPORTA (no es solo estética):
--   ▸ get_mi_licencia() y get_mi_rol() son SECURITY DEFINER con search_path
--     fijado (28_hardening_search_path.sql). Una subconsulta cruda a
--     `usuarios` se evalúa con los permisos del invocador y queda sujeta a la
--     RLS de esa tabla, lo que puede dar resultados distintos o recursión.
--   ▸ Además se evalúan DOS veces por fila en alertas_insert (una para la
--     licencia y otra para el rol); las funciones son STABLE y el planner las
--     puede cachear por sentencia.
--   ▸ Y si algún día cambia cómo se deriva la licencia de un usuario, hoy
--     habría que tocar dos sitios en vez de uno.
--
-- Este script SOLO cambia la FORMA de expresar la condición, no QUIÉN puede
-- qué: los permisos resultantes son idénticos a los actuales.
--
-- (alertas_update ya quedó normalizada en 32_endurecer_alertas_update.sql,
--  que la separó en alertas_update_mando y alertas_update_destinatario.)
--
-- ⚠️ STAGING COMPARTIDO: correr coordinado.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── INSERT: solo roles de mando, dentro de su licencia ────────────────────
DROP POLICY IF EXISTS alertas_insert ON public.alertas;
CREATE POLICY alertas_insert ON public.alertas
  FOR INSERT
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador'])
  );

-- ── SELECT: cualquier usuario autenticado de la misma licencia ────────────
DROP POLICY IF EXISTS alertas_select ON public.alertas;
CREATE POLICY alertas_select ON public.alertas
  FOR SELECT
  USING (
    licencia_id = get_mi_licencia()
  );

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
--
--   SELECT policyname, cmd, qual, with_check FROM pg_policies
--    WHERE tablename='alertas' ORDER BY cmd, policyname;
--     → las 4 políticas (alertas_insert, alertas_select,
--       alertas_update_mando, alertas_update_destinatario) deben usar
--       get_mi_licencia() / get_mi_rol(), sin subconsultas a `usuarios`
--
-- PRUEBAS FUNCIONALES (los permisos NO cambian, así que todo debe seguir igual):
--   a) Con `coordinador`: enviar una alerta a una sección → debe funcionar.
--   b) Con `capturista`: recibir esa alerta en su panel → debe verla.
--   c) Con `capturista`: intentar CREAR una alerta → debe seguir rechazándose.
-- ═══════════════════════════════════════════════════════════════════════════
