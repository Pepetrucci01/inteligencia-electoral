-- ============================================================================
-- VOTERA — PARTE 11: AVANCE POR SECCIÓN (pestaña "Calidad del padrón")
-- Proyecto staging: dyirhwwmykskpuvzcafx · 14 jul 2026 · rama desarrollo
--
-- PROBLEMA
--   La pestaña mostraba SEC_DATA: un arreglo horneado con secciones inventadas
--   ({sec:1, municipio:'Colima', cap:12, meta:180, dificultad:'FACIL'}...).
--   Ninguna de esas cifras venía de la base.
--
--   Además, el KPI "219 secciones críticas" del Resumen Ejecutivo dependía de
--   ese arreglo falso.
--
-- SOLUCIÓN
--   Una RPC que cruza los ciudadanos capturados (por seccion_electoral) contra
--   las metas reales de secciones_electorales_colima. Agrega EN LA BASE: ~388
--   filas en vez de bajar 14,261 registros al navegador.
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS get_avance_secciones();
CREATE OR REPLACE FUNCTION get_avance_secciones()
RETURNS TABLE (
  seccion          integer,
  municipio        text,
  distrito_federal integer,
  distrito_local   integer,
  meta             integer,
  capturados       bigint,
  avance_pct       numeric,
  lista_nominal    integer,
  dificultad       text
)
LANGUAGE sql
STABLE
SECURITY INVOKER          -- respeta la RLS del usuario que llama
AS $$
  WITH capturas AS (
    SELECT
      seccion_electoral::integer AS seccion,
      count(*)                   AS capturados
    FROM ciudadanos
    WHERE licencia_id = get_mi_licencia()
      AND seccion_electoral IS NOT NULL
    GROUP BY 1
  )
  SELECT
    s.seccion,
    s.municipio,
    s.distrito_federal,
    s.distrito_local,
    COALESCE(s.meta_real, s.meta_proyectada::integer, 0)  AS meta,
    COALESCE(c.capturados, 0)                             AS capturados,
    CASE
      WHEN COALESCE(s.meta_real, s.meta_proyectada::integer, 0) > 0
      THEN round(COALESCE(c.capturados,0)::numeric
                 / COALESCE(s.meta_real, s.meta_proyectada::integer) * 100, 1)
      ELSE 0
    END                                                   AS avance_pct,
    s.lista_nominal,
    -- La "dificultad" del arreglo viejo estaba inventada. Ahora se DERIVA del
    -- dato real: la afluencia histórica de esa sección (estatus_afluencia).
    COALESCE(s.estatus_afluencia, 'SIN DATO')             AS dificultad
  FROM secciones_electorales_colima s
  LEFT JOIN capturas c ON c.seccion = s.seccion
  ORDER BY s.seccion;
$$;

COMMENT ON FUNCTION get_avance_secciones() IS
  'Avance por sección: cruza capturas reales contra metas de
   secciones_electorales_colima. Reemplaza el arreglo SEC_DATA horneado.';

GRANT EXECUTE ON FUNCTION get_avance_secciones() TO authenticated;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (desde la app, NO desde el SQL Editor)
--
-- ⚠️ En el SQL Editor NO hay sesión: auth.uid() es null, get_mi_licencia()
--    devuelve null, y la función filtra por una licencia inexistente → 0 filas.
--    Eso NO es un error. Probarla desde el navegador.
--
-- Para verificar el dato crudo sin el filtro de licencia:
--
-- SELECT count(*) FROM secciones_electorales_colima;   -- esperado: 388
--
-- SELECT count(*) FILTER (WHERE avance < 5) AS criticas
-- FROM (
--   SELECT s.seccion,
--          CASE WHEN COALESCE(s.meta_real, s.meta_proyectada::integer,0) > 0
--               THEN COALESCE(c.n,0)::numeric / COALESCE(s.meta_real, s.meta_proyectada::integer) * 100
--               ELSE 0 END AS avance
--   FROM secciones_electorales_colima s
--   LEFT JOIN (SELECT seccion_electoral::integer AS sec, count(*) n
--              FROM ciudadanos GROUP BY 1) c ON c.sec = s.seccion
-- ) t;
--   → Este es el número REAL de "secciones críticas" (el panel decía 219 horneado).
-- ============================================================================
