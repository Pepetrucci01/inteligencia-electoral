-- ============================================================
--  ASIGNACIONES DE REPRESENTANTE · Día E · 16 jul 2026
--  Decisión de José: el representante se asigna a una SECCIÓN
--  (no a una casilla). El día E, el sistema filtra las casillas
--  por la sección asignada y le muestra las disponibles.
--
--  Tabla pivote (no un campo en usuarios) para soportar que un
--  representante cubra >1 sección si hiciera falta, y para llevar
--  histórico de asignaciones sin tocar el registro del usuario.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.asignaciones_representante (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id      uuid NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
  licencia_id     uuid NOT NULL REFERENCES public.licencias(id),
  numero_seccion  integer NOT NULL,
  activa          boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  -- Un representante no se asigna dos veces a la misma sección en la misma licencia
  UNIQUE (usuario_id, licencia_id, numero_seccion)
);

CREATE INDEX IF NOT EXISTS idx_asig_repr_usuario  ON public.asignaciones_representante(usuario_id);
CREATE INDEX IF NOT EXISTS idx_asig_repr_seccion  ON public.asignaciones_representante(numero_seccion);
CREATE INDEX IF NOT EXISTS idx_asig_repr_licencia ON public.asignaciones_representante(licencia_id);

-- ── RLS ────────────────────────────────────────────────────
ALTER TABLE public.asignaciones_representante ENABLE ROW LEVEL SECURITY;

-- El representante ve SUS propias asignaciones; admin/coordinador ven las de su licencia.
DROP POLICY IF EXISTS asig_repr_select ON public.asignaciones_representante;
CREATE POLICY asig_repr_select ON public.asignaciones_representante
  FOR SELECT
  USING (
    licencia_id = get_mi_licencia()
    AND (
      usuario_id = auth.uid()
      OR get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador'])
    )
  );

-- Solo admin/coordinador/super_admin asignan (dentro de su licencia).
DROP POLICY IF EXISTS asig_repr_insert ON public.asignaciones_representante;
CREATE POLICY asig_repr_insert ON public.asignaciones_representante
  FOR INSERT
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador'])
  );

DROP POLICY IF EXISTS asig_repr_update ON public.asignaciones_representante;
CREATE POLICY asig_repr_update ON public.asignaciones_representante
  FOR UPDATE
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador'])
  );

DROP POLICY IF EXISTS asig_repr_delete ON public.asignaciones_representante;
CREATE POLICY asig_repr_delete ON public.asignaciones_representante
  FOR DELETE
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin'])
  );

GRANT SELECT ON public.asignaciones_representante TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.asignaciones_representante TO authenticated;

-- ── Helper: secciones asignadas al usuario actual ──────────
-- Devuelve las secciones activas del representante que llama.
-- Útil para que el día E filtre las casillas por sección.
CREATE OR REPLACE FUNCTION public.get_mis_secciones()
RETURNS TABLE(numero_seccion integer)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT numero_seccion
  FROM public.asignaciones_representante
  WHERE usuario_id = auth.uid()
    AND activa = true;
$$;

REVOKE ALL ON FUNCTION public.get_mis_secciones() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_mis_secciones() TO authenticated;

-- ============================================================
--  VERIFICACIÓN / uso
--  -- asignar (como admin): 
--  INSERT INTO asignaciones_representante (usuario_id, licencia_id, numero_seccion)
--  VALUES ('<uuid_repr>', '<uuid_licencia>', 138);
--
--  -- el representante consulta sus secciones:
--  SELECT * FROM get_mis_secciones();
-- ============================================================
