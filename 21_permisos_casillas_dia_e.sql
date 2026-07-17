-- ============================================================
--  PERMISOS casillas para Día E · 16 jul 2026
--
--  Problema detectado al conectar el Día E:
--  1. La política UPDATE (casillas_representante_update) solo dejaba actualizar
--     a super_admin/admin/coordinador o al representante YA asignado en la fila.
--     Un repr_casilla instalando su casilla (con representante_id aún null) era
--     RECHAZADO → no podía instalar su propia casilla el día E.
--  2. NO existía política de INSERT en casillas → el UPSERT no podía CREAR
--     casillas nuevas (las del reseccionamiento de marzo 2027 que José mencionó).
--
--  Solución: usar la asignación por sección (asignaciones_representante /
--  get_mis_secciones) para autorizar tanto UPDATE como INSERT al repr_casilla
--  sobre casillas de SU sección. Roles de mando conservan acceso amplio.
-- ============================================================

-- ── 1. UPDATE: permitir al repr_casilla sobre casillas de su sección ───────
DROP POLICY IF EXISTS casillas_representante_update ON public.casillas;
CREATE POLICY casillas_representante_update ON public.casillas
  FOR UPDATE
  USING (
    licencia_id = get_mi_licencia()
    AND (
      get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador'])
      OR representante_id = auth.uid()
      OR numero_seccion IN (SELECT numero_seccion FROM public.get_mis_secciones())
    )
  );

-- ── 2. INSERT: faltaba. El UPSERT del Día E crea casillas nuevas. ──────────
--   Autorizado a mando + repr_casilla sobre su sección asignada, siempre en su
--   licencia. (Los roles de mando pueden crear cualquier casilla de su licencia.)
DROP POLICY IF EXISTS casillas_insert ON public.casillas;
CREATE POLICY casillas_insert ON public.casillas
  FOR INSERT
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND (
      get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador'])
      OR (
        get_mi_rol() = 'repr_casilla'
        AND numero_seccion IN (SELECT numero_seccion FROM public.get_mis_secciones())
      )
    )
  );

GRANT INSERT, UPDATE ON public.casillas TO authenticated;

-- ============================================================
--  VERIFICACIÓN (simular un repr_casilla con sección asignada):
--    1. Asignarle una sección en asignaciones_representante.
--    2. SET LOCAL role=authenticated; set_config sub = <uuid repr>.
--    3. Intentar UPDATE/INSERT de una casilla de esa sección → debe permitir.
--    4. Intentar sobre una sección NO asignada → debe rechazar.
-- ============================================================
