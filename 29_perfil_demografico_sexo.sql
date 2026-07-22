-- ============================================================
-- VOTERA — PARTE 29: DESGLOSE POR SEXO EN get_perfil_demografico
-- Proyecto staging: dyirhwwmykskpuvzcafx · 20 jul 2026 · rama desarrollo
--
-- TAREA 25.1: la gráfica "Distribución por edad" (pestaña Diagnóstico IA
-- de reportes) debe mostrar cada barra apilada por sexo (hombres/mujeres).
--
-- El RPC get_perfil_demografico() devolvía por grupo de edad:
--   grupo, total, seguro, riesgo, apoyo
-- pero NO el desglose hombres/mujeres, así que el frontend no podía apilar
-- por sexo con dato real. Se añaden dos columnas: hombres, mujeres — con el
-- MISMO patrón COUNT(*) FILTER que ya usa la función, y la MISMA codificación
-- de sexo que get_perfil_resumen (mismo archivo 12_perfil_votante.sql):
--   hombres = upper(sexo) IN ('M','MASCULINO','H','HOMBRE')
--   mujeres = upper(sexo) IN ('F','FEMENINO','MUJER')
-- (hombres + mujeres puede ser < total: registros con sexo NULL o no
--  reconocido no caen en ninguno de los dos — mismo criterio que el resumen.)
--
-- Se conserva TODO lo demás: alcance por rol/municipio/licencia, orden de
-- rangos, seguro/riesgo/apoyo. Solo se AÑADEN columnas.
--
-- ⚠️ STAGING COMPARTIDO con desarrollo: correr coordinado.
-- DROP necesario: CREATE OR REPLACE no puede cambiar las columnas OUT (42P13).
-- ============================================================

BEGIN;

DROP FUNCTION IF EXISTS public.get_perfil_demografico();

CREATE OR REPLACE FUNCTION public.get_perfil_demografico()
RETURNS TABLE (
  grupo    text,
  total    bigint,
  seguro   bigint,
  riesgo   bigint,
  apoyo    bigint,
  hombres  bigint,
  mujeres  bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol        text;
  v_municipio  text;
  v_licencia   uuid;
  v_es_estatal boolean;
  v_filtro_mun text;
BEGIN
  SELECT u.rol, u.municipio, u.licencia_id
    INTO v_rol, v_municipio, v_licencia
  FROM public.usuarios u
  WHERE u.id = auth.uid()
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
    RAISE EXCEPTION 'Rol % no autorizado para perfil del votante', v_rol;
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT c.edad, c.compromiso, c.es_riesgo, c.es_apoyo, c.sexo
    FROM public.ciudadanos c
    WHERE (v_licencia IS NULL OR c.licencia_id = v_licencia)
      AND (v_filtro_mun IS NULL OR c.municipio = v_filtro_mun)
  ),
  clasificado AS (
    SELECT
      CASE
        WHEN b.edad IS NULL      THEN 'Sin edad'
        WHEN b.edad < 18         THEN 'Menores de edad'
        WHEN b.edad BETWEEN 18 AND 24 THEN '18-24 años'
        WHEN b.edad BETWEEN 25 AND 34 THEN '25-34 años'
        WHEN b.edad BETWEEN 35 AND 44 THEN '35-44 años'
        WHEN b.edad BETWEEN 45 AND 54 THEN '45-54 años'
        WHEN b.edad BETWEEN 55 AND 64 THEN '55-64 años'
        ELSE '65+ años'
      END AS grupo_edad,
      CASE
        WHEN b.edad IS NULL      THEN 99
        WHEN b.edad < 18         THEN 0
        WHEN b.edad BETWEEN 18 AND 24 THEN 1
        WHEN b.edad BETWEEN 25 AND 34 THEN 2
        WHEN b.edad BETWEEN 35 AND 44 THEN 3
        WHEN b.edad BETWEEN 45 AND 54 THEN 4
        WHEN b.edad BETWEEN 55 AND 64 THEN 5
        ELSE 6
      END AS orden,
      b.compromiso, b.es_riesgo, b.es_apoyo, b.sexo
    FROM base b
  )
  SELECT
    cl.grupo_edad::text                              AS grupo,
    COUNT(*)                                          AS total,
    COUNT(*) FILTER (WHERE cl.compromiso >= 3)        AS seguro,
    COUNT(*) FILTER (WHERE cl.es_riesgo)              AS riesgo,
    COUNT(*) FILTER (WHERE cl.es_apoyo)               AS apoyo,
    COUNT(*) FILTER (WHERE upper(coalesce(cl.sexo,'')) IN ('M','MASCULINO','H','HOMBRE')) AS hombres,
    COUNT(*) FILTER (WHERE upper(coalesce(cl.sexo,'')) IN ('F','FEMENINO','MUJER'))        AS mujeres
  FROM clasificado cl
  GROUP BY cl.grupo_edad, cl.orden
  ORDER BY cl.orden;
END;
$$;

REVOKE ALL ON FUNCTION public.get_perfil_demografico() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_perfil_demografico() TO authenticated;

COMMIT;

-- ── Verificación ──────────────────────────────────────────
-- SELECT grupo, total, hombres, mujeres, (hombres+mujeres) AS suma_sexo
-- FROM get_perfil_demografico();
--   → por cada grupo: hombres+mujeres ≤ total (la diferencia = sexo NULL/otro)
--   → la suma de todos los 'total' debe coincidir con el padrón de la licencia
