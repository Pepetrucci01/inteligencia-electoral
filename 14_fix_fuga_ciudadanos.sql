-- ============================================================
--  FIX FUGA MULTI-TENANT · ciudadanos · T6 · 15 jul 2026
--
--  HALLAZGO (prueba de fuga 13_prueba_fuga_multitenant):
--  Dos políticas de 'ciudadanos' daban a super_admin (y en DELETE
--  también a admin) acceso SIN filtro de licencia_id → un
--  super_admin de la licencia A veía Y podía borrar ciudadanos de
--  CUALQUIER otra licencia. Fuga confirmada: VERIF 2 daba ve_de_B=3.
--
--  Las RPC (get_war_room_kpis, etc.) NO tenían la fuga porque son
--  SECURITY DEFINER y filtran por v_licencia en código. La fuga era
--  solo en consulta DIRECTA a la tabla vía RLS.
--
--  DECISIÓN DE DISEÑO: el super_admin ve/gestiona todo dentro de su
--  PROPIA licencia, no de todas. Correcto para multi-tenant.
--
--  Verificado: tras el fix, VERIF 2 = OK AISLADO (ve_total=14262,
--  ve_de_B=0) y el super_admin SIGUE viendo sus 14,262.
-- ============================================================

-- 1. SELECT: super_admin y admin, ambos acotados a su licencia
DROP POLICY IF EXISTS ciudadanos_admin_select ON public.ciudadanos;
CREATE POLICY ciudadanos_admin_select ON public.ciudadanos
  FOR SELECT
  USING (
    get_mi_rol() = ANY (ARRAY['super_admin','admin'])
    AND licencia_id = get_mi_licencia()
  );

-- 2. DELETE: super_admin y admin, acotados a su licencia
--    (esta era la más peligrosa: permitía BORRAR de otra licencia)
DROP POLICY IF EXISTS ciudadanos_delete ON public.ciudadanos;
CREATE POLICY ciudadanos_delete ON public.ciudadanos
  FOR DELETE
  USING (
    get_mi_rol() = ANY (ARRAY['super_admin','admin'])
    AND licencia_id = get_mi_licencia()
  );

-- ============================================================
--  NOTA: revisar el mismo patrón en encuestas, respuestas_encuesta,
--  alertas, reportes_casilla_eleccion (chequeo en curso).
-- ============================================================
