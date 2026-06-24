-- ============================================================
--  RPC — get_avance_por_seccion()  ·  SIE Colima 2027
--  Devuelve el conteo de ciudadanos agrupado por sección, para
--  colorear el mapa del visor. Reemplaza la paginación de 14K+
--  filas (que provocaba 500 Internal Server Error por timeout)
--  con UNA agregación en la base.
--
--  Respeta licencia y alcance por rol, igual que los otros RPC.
--  Devuelve: { "138": 311, "139": 234, ... }  (seccion -> conteo)
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_avance_por_seccion()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol         text;
  v_municipio   text;
  v_licencia    uuid;
  v_es_estatal  boolean;
  v_filtro_mun  text;
  v_resultado   jsonb;
BEGIN
  SELECT rol, municipio, licencia_id
    INTO v_rol, v_municipio, v_licencia
  FROM public.usuarios
  WHERE id = auth.uid()
  LIMIT 1;

  IF v_rol IS NULL THEN
    RAISE EXCEPTION 'Usuario sin perfil o no autenticado';
  END IF;

  v_es_estatal :=
        v_rol IN ('super_admin','admin')
     OR (v_rol = 'coordinador' AND v_municipio IS NULL);

  IF v_es_estatal THEN
    v_filtro_mun := NULL;
  ELSIF v_rol = 'coordinador' THEN
    v_filtro_mun := v_municipio;
  ELSE
    -- jefe_seccion / capturista: también pueden ver el mapa, acotado
    -- a su licencia (sin filtro de municipio extra). Si se quisiera
    -- acotar más, se añadiría aquí.
    v_filtro_mun := NULL;
  END IF;

  SELECT COALESCE(jsonb_object_agg(seccion::text, n), '{}'::jsonb)
    INTO v_resultado
  FROM (
    SELECT seccion_electoral AS seccion, COUNT(*) AS n
    FROM public.ciudadanos c
    WHERE (v_licencia IS NULL OR c.licencia_id = v_licencia)
      AND (v_filtro_mun IS NULL OR c.municipio = v_filtro_mun)
      AND c.seccion_electoral IS NOT NULL
    GROUP BY seccion_electoral
  ) sub;

  RETURN v_resultado;
END;
$$;

REVOKE ALL ON FUNCTION public.get_avance_por_seccion() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_avance_por_seccion() TO authenticated;

-- ============================================================
--  PRUEBA
-- ============================================================
-- SET request.jwt.claim.sub = '2fc4dcf7-5205-49be-87f1-e38908b0d1d6';
-- SELECT public.get_avance_por_seccion();
-- RESET request.jwt.claim.sub;
-- ============================================================
