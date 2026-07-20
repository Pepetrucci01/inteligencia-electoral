-- ═══════════════════════════════════════════════════════════════════════════
-- 26_rls_consulta_select.sql · 18 jul 2026
-- Instructivo de Roles Fase 4 (José) — Tarea 5A: rol "consulta" (solo lectura)
-- en las tablas que alimentan War Room, Reportes y Visor.
--
-- Análisis del estado REAL (pg_policies 18 jul) — qué necesita consulta:
--   · configuracion_sistema, candidaturas, distritos, municipios
--       → SELECT ya es (super_admin OR licencia_id = get_mi_licencia())
--         ⇒ consulta YA lee. No se toca.
--   · casillas → SELECT es (licencia_id = get_mi_licencia())
--         ⇒ consulta YA lee. No se toca.
--   · secciones_electorales / _colima → tienen política con qual = true
--         ⇒ consulta YA lee. No se toca.
--   · ciudadanos → TODAS las _select filtran por rol concreto (admin,
--         capturista, coordinador, jefe_seccion). Consulta NO aparece ⇒ ÚNICO
--         hueco. Se agrega una política ADITIVA (permisiva, se suma con OR),
--         sin tocar las existentes → no altera el aislamiento de ningún otro rol.
--
-- Patrón deliberadamente inverso a la fuga del SQL 23: aquí SUMAMOS acceso de
-- forma acotada (rol exacto + licencia), no abrimos con qual=true.
--
-- ⚠️ REVISAR CON JOSÉ ANTES DE APLICAR (cambio de RLS).
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS ciudadanos_consulta_select ON ciudadanos;
CREATE POLICY ciudadanos_consulta_select ON ciudadanos
  FOR SELECT USING (
    get_mi_rol() = 'consulta'
    AND licencia_id = get_mi_licencia()
  );

-- ─────────────────────────────────────────────────────────────────────────
-- Verificación:
--   SELECT policyname, cmd, qual FROM pg_policies
--    WHERE tablename='ciudadanos' AND cmd='SELECT'
--      AND policyname='ciudadanos_consulta_select';
-- Prueba funcional (consulta@demo.mx):
--   · GET /rest/v1/ciudadanos?select=id → devuelve los de SU licencia (no vacío).
--   · Desde otra licencia, consulta NO ve estos ciudadanos (aislamiento intacto).
--   · Escritura sigue bloqueada: no hay política INSERT/UPDATE/DELETE para
--     consulta (el frontend además oculta los controles — Tarea 5B, ya hecha).
-- NOTA: si a futuro se agregan tablas nuevas al War Room/Visor, revisar si su
--   SELECT ya cubre "licencia_id = get_mi_licencia()" (cubre a consulta) o si
--   filtra por rol (entonces requiere una política aditiva como esta).
-- ─────────────────────────────────────────────────────────────────────────
