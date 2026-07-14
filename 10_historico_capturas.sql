-- ============================================================================
-- VOTERA — PARTE 10: HISTÓRICO DE CAPTURAS (ritmo real)
-- Proyecto staging: dyirhwwmykskpuvzcafx · 14 jul 2026 · rama desarrollo
--
-- PROBLEMA
--   La pestaña "Avance & ritmo" mostraba datos INVENTADOS:
--     "Promedio diario: 84"  ·  "Mejor semana: 614"  ·  "Peor semana: 421"
--   Y el Resumen Ejecutivo decía "ritmo actual: 574 capturas/semana", también
--   inventado — de él dependían la proyección y la "brecha de ritmo x7.2".
--
--   Se dejaron esos campos en blanco ("sin datos históricos") porque el dato no
--   se estaba calculando. Pero SÍ existe: ciudadanos.created_at guarda cuándo se
--   capturó cada registro. Solo faltaba agregarlo.
--
-- SOLUCIÓN
--   Una RPC que agrupa por semana EN LA BASE. Devuelve unas 50 filas en vez de
--   bajar 14,261 registros al navegador para agruparlos ahí — el patrón que ya
--   nos costó un "Failed to fetch" en offset=8000.
--
-- ⚠️ STAGING COMPARTIDO con la rama desarrollo: correr coordinado.
-- ============================================================================

BEGIN;

-- ── Histórico semanal de capturas ───────────────────────────────────────────
-- Devuelve una fila por semana con el conteo de capturas de esa semana.
-- Respeta RLS: cada licencia ve solo lo suyo (usa get_mi_licencia()).
DROP FUNCTION IF EXISTS get_historico_capturas();
CREATE OR REPLACE FUNCTION get_historico_capturas()
RETURNS TABLE (
  semana        date,      -- lunes de esa semana
  capturas      bigint,    -- registros capturados esa semana
  acumulado     bigint     -- total acumulado hasta el fin de esa semana
)
LANGUAGE sql
STABLE
SECURITY INVOKER          -- respeta la RLS del usuario que llama
AS $$
  WITH por_semana AS (
    SELECT
      date_trunc('week', created_at)::date AS semana,
      count(*)                             AS capturas
    FROM ciudadanos
    WHERE created_at IS NOT NULL
      AND licencia_id = get_mi_licencia()
    GROUP BY 1
  )
  SELECT
    semana,
    capturas,
    sum(capturas) OVER (ORDER BY semana)::bigint AS acumulado
  FROM por_semana
  ORDER BY semana;
$$;

COMMENT ON FUNCTION get_historico_capturas() IS
  'Histórico de capturas agrupado por semana. Alimenta la pestaña Avance & ritmo
   y el ritmo actual del Resumen Ejecutivo. Agrega en la BD para no bajar 14k
   filas al navegador.';

GRANT EXECUTE ON FUNCTION get_historico_capturas() TO authenticated;


-- ── Resumen del ritmo (lo que el frontend necesita de un vistazo) ───────────
-- ⚠️ DROP necesario: CREATE OR REPLACE no puede cambiar el tipo de retorno de
-- una funcion que ya existe (error 42P13). Al añadir pct_semana_pico y
-- es_carga_masiva cambiaron las columnas devueltas, asi que hay que recrearla.
DROP FUNCTION IF EXISTS get_ritmo_capturas();
CREATE OR REPLACE FUNCTION get_ritmo_capturas()
RETURNS TABLE (
  total              bigint,   -- total capturado
  semanas_activas    bigint,   -- semanas con al menos una captura
  promedio_semanal   numeric,  -- ritmo promedio
  mejor_semana       bigint,   -- pico
  mejor_semana_fecha date,
  peor_semana        bigint,   -- valle (solo semanas activas)
  peor_semana_fecha  date,
  ultima_semana      bigint,   -- capturas de la semana en curso
  promedio_diario    numeric,  -- promedio_semanal / 7
  pct_semana_pico    numeric,  -- % del total que cayó en la semana más grande
  es_carga_masiva    boolean   -- true si una semana concentra >80% (no es ritmo real)
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH por_semana AS (
    SELECT
      date_trunc('week', created_at)::date AS semana,
      count(*)                             AS capturas
    FROM ciudadanos
    WHERE created_at IS NOT NULL
      AND licencia_id = get_mi_licencia()
    GROUP BY 1
  ),
  agg AS (
    SELECT
      sum(capturas)                        AS total,
      count(*)                             AS semanas_activas,
      round(avg(capturas), 1)              AS promedio_semanal,
      max(capturas)                        AS mejor_semana,
      min(capturas)                        AS peor_semana,
      -- ⚠️ DETECCIÓN DE CARGA MASIVA
      -- No basta contar semanas activas: en Colima hay 4 semanas con datos, pero
      -- UNA sola concentra el 99.96% (14,256 de 14,261 el 25-may). Las otras 3
      -- son capturas sueltas de prueba.
      -- Si una semana concentra >80% del total, NO es ritmo de campo: es una
      -- importación por Excel. Promediar eso daría "3,565/semana", un número
      -- correcto y completamente engañoso.
      round(max(capturas)::numeric / NULLIF(sum(capturas),0) * 100, 1) AS pct_semana_pico
    FROM por_semana
  )
  SELECT
    a.total,
    a.semanas_activas,
    a.promedio_semanal,
    a.mejor_semana,
    (SELECT semana FROM por_semana WHERE capturas = a.mejor_semana ORDER BY semana DESC LIMIT 1),
    a.peor_semana,
    (SELECT semana FROM por_semana WHERE capturas = a.peor_semana ORDER BY semana DESC LIMIT 1),
    COALESCE((SELECT capturas FROM por_semana
              WHERE semana = date_trunc('week', now())::date), 0),
    round(a.promedio_semanal / 7.0, 1),
    a.pct_semana_pico,
    (a.pct_semana_pico > 80)   -- carga masiva: una semana se lleva casi todo
  FROM agg a;
$$;

COMMENT ON FUNCTION get_ritmo_capturas() IS
  'Resumen del ritmo de captura: promedio, mejor/peor semana, promedio diario.
   Reemplaza las cifras inventadas (84/día, mejor 614, peor 421).';

GRANT EXECUTE ON FUNCTION get_ritmo_capturas() TO authenticated;

COMMIT;


-- ============================================================================
-- VERIFICACIÓN (correr como admin o coordinador, NO como super_admin)
-- ============================================================================

-- 1. El histórico: una fila por semana.
-- SELECT * FROM get_historico_capturas();
--    Esperado: ~N filas, y el `acumulado` de la última debe ser 14,261.

-- 2. El resumen del ritmo:
-- SELECT * FROM get_ritmo_capturas();
--    Esperado: total = 14,261 · promedio_semanal y promedio_diario reales.
--
--    ⚠️ OJO con la interpretación: si los 14,261 se cargaron de golpe en una
--    importación masiva (carga inicial por Excel), TODOS caerán en la misma
--    semana y el "ritmo" será engañoso — no refleja captura en campo, sino una
--    importación. Revisar la distribución antes de confiar en el promedio:
--
-- SELECT semana, capturas FROM get_historico_capturas() ORDER BY capturas DESC LIMIT 5;
--    Si una sola semana concentra casi todo → fue carga masiva, no ritmo real.
-- ============================================================================


-- ============================================================================
-- PARTE 10b: PERFIL DEMOGRÁFICO (pestaña "Perfil del votante")
--
-- La pestaña mostraba datos INVENTADOS: "5,007 hombres / 4,993 mujeres",
-- "edad promedio 47", y una tabla por grupo de edad cuyos totales sumaban
-- exactamente 10,000 (el mismo número falso de los KPIs).
-- Los datos SÍ existen: ciudadanos.sexo y ciudadanos.edad.
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS get_perfil_demografico();
CREATE OR REPLACE FUNCTION get_perfil_demografico()
RETURNS TABLE (
  grupo        text,
  total        bigint,
  seguro       bigint,   -- compromiso >= 3
  riesgo       bigint,
  apoyo        bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  SELECT
    CASE
      WHEN edad IS NULL      THEN 'Sin dato'
      WHEN edad < 18         THEN 'Menor de 18'
      WHEN edad BETWEEN 18 AND 29 THEN '18-29 años'
      WHEN edad BETWEEN 30 AND 39 THEN '30-39 años'
      WHEN edad BETWEEN 40 AND 49 THEN '40-49 años'
      WHEN edad BETWEEN 50 AND 59 THEN '50-59 años'
      WHEN edad BETWEEN 60 AND 69 THEN '60-69 años'
      ELSE '70+ años'
    END                                              AS grupo,
    count(*)                                         AS total,
    count(*) FILTER (WHERE compromiso >= 3)          AS seguro,
    count(*) FILTER (WHERE es_riesgo IS TRUE)        AS riesgo,
    count(*) FILTER (WHERE es_apoyo  IS TRUE)        AS apoyo
  FROM ciudadanos
  WHERE licencia_id = get_mi_licencia()
  GROUP BY 1
  ORDER BY 1;
$$;

GRANT EXECUTE ON FUNCTION get_perfil_demografico() TO authenticated;


DROP FUNCTION IF EXISTS get_perfil_resumen();
CREATE OR REPLACE FUNCTION get_perfil_resumen()
RETURNS TABLE (
  total          bigint,
  hombres        bigint,
  mujeres        bigint,
  otro           bigint,
  edad_promedio  numeric,
  grupo_mayor    text,
  grupo_mayor_n  bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
AS $$
  WITH base AS (
    SELECT * FROM ciudadanos WHERE licencia_id = get_mi_licencia()
  ),
  grupos AS (
    SELECT grupo, total FROM get_perfil_demografico()
    WHERE grupo NOT IN ('Sin dato')
    ORDER BY total DESC LIMIT 1
  )
  SELECT
    (SELECT count(*) FROM base),
    (SELECT count(*) FROM base WHERE upper(sexo) IN ('M','MASCULINO','HOMBRE')),
    (SELECT count(*) FROM base WHERE upper(sexo) IN ('F','FEMENINO','MUJER')),
    (SELECT count(*) FROM base WHERE sexo IS NULL
        OR upper(sexo) NOT IN ('M','MASCULINO','HOMBRE','F','FEMENINO','MUJER')),
    (SELECT round(avg(edad), 0) FROM base WHERE edad IS NOT NULL AND edad BETWEEN 1 AND 120),
    (SELECT grupo FROM grupos),
    (SELECT total FROM grupos);
$$;

GRANT EXECUTE ON FUNCTION get_perfil_resumen() TO authenticated;

COMMIT;

-- Verificación:
-- SELECT * FROM get_perfil_resumen();
--   Esperado: total = 14,261 (NO 10,000). hombres + mujeres + otro = total.
-- SELECT * FROM get_perfil_demografico();
--   Esperado: la suma de `total` = 14,261.
