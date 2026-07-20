-- ═══════════════════════════════════════════════════════════════════════════
-- 24_rls_repr_casilla.sql · 18 jul 2026
-- Instructivo de Roles Fase 4 (José) — Tarea 1 (parte reportes_casilla) + Tarea 3.
--
-- Fuente versionada: 06_rls_reportes_dia_e.sql. Aquí se REEMPLAZAN las políticas
-- de reportes_casilla_eleccion para el nuevo modelo de roles del Día D:
--   · capturista SALE (ya no participa el Día D).
--   · repr_casilla ENTRA (es quien opera la casilla).
--   · jefe_seccion SE QUEDA (supervisa sus casillas el Día D).
-- Y se agrega el INSERT de repr_casilla sobre ciudadanos (registro de votantes
-- nuevos en vivo).
--
-- ⚠️ REVISAR CON JOSÉ ANTES DE APLICAR (cambio de RLS). Aplicar en SQL Editor y
-- versionar. Requiere que el rol repr_casilla ya exista (José confirma que sí).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Tarea 1 (parte reportes_casilla): swap capturista → repr_casilla ────────
-- INSERT: mando + jefe_seccion + repr_casilla (fuera capturista)
DROP POLICY IF EXISTS reportes_casilla_insert ON reportes_casilla_eleccion;
CREATE POLICY reportes_casilla_insert ON reportes_casilla_eleccion
  FOR INSERT WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador',
                                  'jefe_seccion','repr_casilla'])
    AND EXISTS (
      SELECT 1 FROM casillas c
      WHERE c.id = reportes_casilla_eleccion.casilla_id
        AND c.licencia_id = get_mi_licencia()
    )
  );

-- UPDATE: mismos roles (corregir/abrir/cerrar durante la jornada)
DROP POLICY IF EXISTS reportes_casilla_update ON reportes_casilla_eleccion;
CREATE POLICY reportes_casilla_update ON reportes_casilla_eleccion
  FOR UPDATE
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador',
                                  'jefe_seccion','repr_casilla'])
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()
  );

-- (SELECT y DELETE de reportes_casilla se dejan como están en 06.)

-- ── Tarea 3: repr_casilla puede registrar ciudadanos nuevos el Día D ────────
-- INSERT acotado a su licencia. NO se le da SELECT general sobre ciudadanos:
-- el pase de lista de su casilla debe ir por una RPC/vista filtrada (pendiente),
-- no por acceso directo a la tabla completa (indicación explícita de José).
DROP POLICY IF EXISTS ciudadanos_repr_insert ON ciudadanos;
CREATE POLICY ciudadanos_repr_insert ON ciudadanos
  FOR INSERT WITH CHECK (
    get_mi_rol() = 'repr_casilla'
    AND licencia_id = get_mi_licencia()
  );

-- ─────────────────────────────────────────────────────────────────────────
-- Verificación:
--   SELECT policyname, cmd, with_check FROM pg_policies
--    WHERE tablename='reportes_casilla_eleccion' ORDER BY cmd;
--   -- INSERT/UPDATE deben listar repr_casilla y jefe_seccion, NO capturista.
--   SELECT policyname, cmd FROM pg_policies
--    WHERE tablename='ciudadanos' AND policyname='ciudadanos_repr_insert';
-- Prueba funcional: como repr_casilla (representante@demo.mx) insertar un
--   ciudadano nuevo → OK; intentar SELECT masivo de ciudadanos → sin acceso.
-- ─────────────────────────────────────────────────────────────────────────
