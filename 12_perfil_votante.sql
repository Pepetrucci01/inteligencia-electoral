-- ============================================================
--  RPCs — Perfil del votante  ·  SIE Colima 2027
--  Alimentan la pestaña "Perfil del votante" de Reportes.
--  El frontend (modulo_reportes.html · cargarPerfil) llama DOS:
--    get_perfil_demografico() -> array de grupos por rango de edad
--    get_perfil_resumen()     -> KPIs de encabezado (sexo/edad/grupo mayor)
--
--  Mismo patrón de seguridad que get_war_room_kpis / get_capturistas_stats:
--    SECURITY DEFINER + alcance por rol/municipio/licencia vía auth.uid().
--
--  Definiciones (consistentes con get_war_room_kpis):
--    seguro = compromiso >= 3   ·   riesgo = es_riesgo   ·   apoyo = es_apoyo
--
--  Alcance por rol:
--    super_admin / admin                -> todo el estado
--    coordinador con municipio IS NULL  -> todo el estado (General)
--    coordinador con municipio asignado -> solo su municipio
--    otros roles                        -> acceso denegado
-- ============================================================


-- ── Helper interno: resuelve alcance del usuario que llama ──
-- (se repite la lógica inline en cada RPC para no depender de otra función;
--  si mañana se centraliza, se cambia en un solo lugar.)


-- ============================================================
--  1. get_perfil_demografico() -> grupos por rango de edad
--     columnas que consume el front: grupo, total, seguro, riesgo, apoyo
-- ============================================================
-- DROP previo: si existe una version anterior con otro tipo de retorno,
-- CREATE OR REPLACE no puede cambiar las columnas OUT (error 42P13).
DROP FUNCTION IF EXISTS public.get_perfil_demografico();

CREATE OR REPLACE FUNCTION public.get_perfil_demografico()
RETURNS TABLE (
  grupo   text,
  total   bigint,
  seguro  bigint,
  riesgo  bigint,
  apoyo   bigint
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
    SELECT c.edad, c.compromiso, c.es_riesgo, c.es_apoyo
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
      -- orden estable de los rangos (para que no salgan alfabéticos)
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
      b.compromiso, b.es_riesgo, b.es_apoyo
    FROM base b
  )
  SELECT
    cl.grupo_edad::text                              AS grupo,
    COUNT(*)                                          AS total,
    COUNT(*) FILTER (WHERE cl.compromiso >= 3)        AS seguro,
    COUNT(*) FILTER (WHERE cl.es_riesgo)              AS riesgo,
    COUNT(*) FILTER (WHERE cl.es_apoyo)               AS apoyo
  FROM clasificado cl
  GROUP BY cl.grupo_edad, cl.orden
  ORDER BY cl.orden;
END;
$$;

REVOKE ALL ON FUNCTION public.get_perfil_demografico() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_perfil_demografico() TO authenticated;


-- ============================================================
--  2. get_perfil_resumen() -> KPIs de encabezado
--     columnas que consume el front:
--       total, hombres, mujeres, edad_promedio, grupo_mayor, grupo_mayor_n
-- ============================================================
-- DROP previo: ya existia una version con distinto tipo de retorno
-- (por eso el error 42P13 al aplicar). Se elimina antes de recrear.
DROP FUNCTION IF EXISTS public.get_perfil_resumen();

CREATE OR REPLACE FUNCTION public.get_perfil_resumen()
RETURNS TABLE (
  total          bigint,
  hombres        bigint,
  mujeres        bigint,
  edad_promedio  numeric,
  grupo_mayor    text,
  grupo_mayor_n  bigint
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
    SELECT c.edad, c.sexo
    FROM public.ciudadanos c
    WHERE (v_licencia IS NULL OR c.licencia_id = v_licencia)
      AND (v_filtro_mun IS NULL OR c.municipio = v_filtro_mun)
  ),
  -- grupo de edad más numeroso (para "grupo_mayor")
  grupos AS (
    SELECT
      CASE
        WHEN edad IS NULL      THEN 'Sin edad'
        WHEN edad < 18         THEN 'Menores de edad'
        WHEN edad BETWEEN 18 AND 24 THEN '18-24 años'
        WHEN edad BETWEEN 25 AND 34 THEN '25-34 años'
        WHEN edad BETWEEN 35 AND 44 THEN '35-44 años'
        WHEN edad BETWEEN 45 AND 54 THEN '45-54 años'
        WHEN edad BETWEEN 55 AND 64 THEN '55-64 años'
        ELSE '65+ años'
      END AS grupo_edad,
      COUNT(*) AS n
    FROM base
    GROUP BY 1
  ),
  mayor AS (
    SELECT grupo_edad, n
    FROM grupos
    WHERE grupo_edad <> 'Sin edad'
    ORDER BY n DESC
    LIMIT 1
  )
  SELECT
    (SELECT COUNT(*) FROM base)                                    AS total,
    (SELECT COUNT(*) FROM base
       WHERE upper(coalesce(sexo,'')) IN ('M','MASCULINO','H','HOMBRE')) AS hombres,
    (SELECT COUNT(*) FROM base
       WHERE upper(coalesce(sexo,'')) IN ('F','FEMENINO','MUJER'))       AS mujeres,
    (SELECT ROUND(AVG(edad), 1) FROM base WHERE edad IS NOT NULL)  AS edad_promedio,
    (SELECT grupo_edad FROM mayor)                                 AS grupo_mayor,
    (SELECT n          FROM mayor)                                 AS grupo_mayor_n;
END;
$$;

REVOKE ALL ON FUNCTION public.get_perfil_resumen() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_perfil_resumen() TO authenticated;


-- ============================================================
--  PRUEBA
-- ============================================================
-- Desde el SQL Editor auth.uid() es null -> las RPCs lanzan
-- 'Usuario sin perfil'. Es correcto: probar desde el navegador
-- logueado, o simulando el JWT:
--
--   SET request.jwt.claim.sub = '<uuid de un usuario real>';
--   SELECT * FROM public.get_perfil_demografico();
--   SELECT * FROM public.get_perfil_resumen();
--   RESET request.jwt.claim.sub;
--
-- Verificación cruda sin filtro de licencia (dato esperado):
--   SELECT count(*) FROM ciudadanos;                    -- ~14,261
--   SELECT count(*) FILTER (WHERE sexo IS NOT NULL) FROM ciudadanos;
--   SELECT count(*) FILTER (WHERE edad IS NOT NULL)  FROM ciudadanos;
-- ============================================================
