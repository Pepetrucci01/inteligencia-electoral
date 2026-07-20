-- ═══════════════════════════════════════════════════════════════════════════
-- 25_rls_encuestas_respuestas.sql · 18 jul 2026
-- Instructivo de Roles Fase 4 (José) — Tarea 1 (parte encuestas). Prioridad ALTA.
--
-- respuestas_insert permite hoy a jefe_seccion y capturista insertar respuestas
-- de encuesta. Según el modelo de roles, SOLO super_admin, admin y coordinador
-- tienen acceso al módulo de Encuestas. Se quitan jefe_seccion y capturista.
--
-- Cuerpo tomado del estado REAL en Supabase (pg_policies 18 jul); se conserva
-- intacta la validación de licencia y de encuesta activa de la misma licencia.
--
-- ⚠️ REVISAR CON JOSÉ ANTES DE APLICAR (cambio de RLS).
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS respuestas_insert ON respuestas_encuesta;
CREATE POLICY respuestas_insert ON respuestas_encuesta
  FOR INSERT WITH CHECK (
    get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador'])
    AND licencia_id = get_mi_licencia()
    AND EXISTS (
      SELECT 1 FROM encuestas e
      WHERE e.id = respuestas_encuesta.encuesta_id
        AND e.licencia_id = get_mi_licencia()
        AND e.estado = 'activa'
    )
  );

-- ─────────────────────────────────────────────────────────────────────────
-- Verificación:
--   SELECT policyname, cmd, with_check FROM pg_policies
--    WHERE tablename='respuestas_encuesta' AND cmd='INSERT';
--   -- El array debe ser solo super_admin/admin/coordinador.
-- Prueba funcional: como capturista (cap017@demo.mx) o jefe_seccion
--   (lider138@demo.mx), intentar insertar una respuesta → RECHAZADO.
--   Como coordinador (coord.a@demo.mx) sobre encuesta activa de su licencia → OK.
-- ─────────────────────────────────────────────────────────────────────────
