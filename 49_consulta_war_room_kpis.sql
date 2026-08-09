-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — 49: permitir al rol 'consulta' leer get_war_room_kpis
-- Proyecto staging: dyirhwwmykskpuvzcafx
--
-- El rol consulta ve War Room/Mapa/Reportes en SOLO LECTURA (matriz de roles),
-- pero get_war_room_kpis lo mandaba al RAISE 'Rol no autorizado' → HTTP 400 →
-- el panel de inicio del consulta no cargaba KPIs. Fix: tratar 'consulta' como
-- alcance ESTATAL (observador global de solo lectura, ve todo el estado sin
-- filtro territorial). Solo se toca la rama de decisión de alcance; el cálculo
-- de KPIs no cambia. consulta no escribe nada (esto es una función de lectura).
--
-- Es un CREATE OR REPLACE de la función existente con la sola diferencia de
-- añadir 'consulta' a la lista de roles estatales.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_war_room_kpis()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rol         text;
  v_municipio   text;
  v_licencia    uuid;
  v_es_estatal  boolean;
  v_filtro_mun  text;             -- NULL = sin filtro (estatal)
  v_resultado   jsonb;
  META_ESTATAL  constant integer := 197297;
BEGIN
  -- ── 1. Identificar al usuario que llama (vía su token) ──────
  SELECT rol, municipio, licencia_id
    INTO v_rol, v_municipio, v_licencia
  FROM public.usuarios
  WHERE id = auth.uid()
  LIMIT 1;

  IF v_rol IS NULL THEN
    RAISE EXCEPTION 'Usuario sin perfil o no autenticado';
  END IF;

  -- ── 2. Decidir alcance territorial según rol ───────────────
  --    'consulta' se añade como estatal: observador global de solo lectura
  --    (ve todo el estado, no escribe nada — esto es una función de lectura).
  v_es_estatal :=
        v_rol IN ('super_admin','admin','coordinador_estatal','consulta')
     OR (v_rol = 'coordinador' AND v_municipio IS NULL);

  IF v_es_estatal THEN
    v_filtro_mun := NULL;                       -- ve todo el estado
  ELSIF v_rol = 'coordinador' THEN
    v_filtro_mun := v_municipio;                -- solo su municipio
  ELSE
    RAISE EXCEPTION 'Rol % no autorizado para War Room', v_rol;
  END IF;

  -- ── 3. Calcular todos los KPIs en una sola pasada ──────────
  WITH base AS (
    SELECT *
    FROM public.ciudadanos c
    WHERE (v_licencia IS NULL OR c.licencia_id = v_licencia)
      AND (v_filtro_mun IS NULL OR c.municipio = v_filtro_mun)
  ),
  totales AS (
    SELECT
      COUNT(*)                                        AS total,
      COUNT(*) FILTER (WHERE compromiso >= 3)         AS seguro,
      COUNT(*) FILTER (WHERE es_apoyo)                AS apoyos,
      COUNT(*) FILTER (WHERE es_influencia)           AS influencia,
      COUNT(*) FILTER (WHERE es_riesgo)               AS riesgo,
      COUNT(*) FILTER (WHERE validado)                AS validados,
      COUNT(*) FILTER (WHERE compromiso = 2)          AS atencion,
      COUNT(*) FILTER (WHERE duplicado)               AS depurar,
      COUNT(DISTINCT capturista_id)
        FILTER (WHERE capturista_id IS NOT NULL)      AS capturistas
    FROM base
  ),
  mun_agg AS (
    SELECT
      COALESCE(municipio,'(sin municipio)')          AS municipio,
      COUNT(*)                                        AS total,
      COUNT(*) FILTER (WHERE compromiso >= 3)         AS seguro,
      COUNT(*) FILTER (WHERE es_apoyo)                AS apoyos,
      COUNT(*) FILTER (WHERE es_influencia)           AS influencia,
      COUNT(*) FILTER (WHERE es_riesgo)               AS riesgo,
      COUNT(*) FILTER (WHERE validado)                AS validados,
      COUNT(*) FILTER (WHERE compromiso = 2)          AS atencion,
      COUNT(*) FILTER (WHERE duplicado)               AS depurar
    FROM base
    GROUP BY COALESCE(municipio,'(sin municipio)')
  ),
  por_municipio AS (
    SELECT jsonb_object_agg(
             municipio,
             jsonb_build_object(
               'total',     total,
               'seguro',    seguro,
               'apoyos',    apoyos,
               'influencia',influencia,
               'riesgo',    riesgo,
               'validados', validados,
               'atencion',  atencion,
               'depurar',   depurar
             )
           ) AS data
    FROM mun_agg
  ),
  por_seccion AS (
    SELECT jsonb_object_agg(seccion::text, n) AS data
    FROM (
      SELECT seccion_electoral AS seccion, COUNT(*) AS n
      FROM base
      WHERE seccion_electoral IS NOT NULL
      GROUP BY seccion_electoral
    ) s
  )
  SELECT jsonb_build_object(
    'meta',          META_ESTATAL,
    'total',         t.total,
    'pct_avance',    ROUND( (t.total::numeric / META_ESTATAL) * 100, 2),
    'seguro',        t.seguro,
    'apoyos',        t.apoyos,
    'influencia',    t.influencia,
    'riesgo',        t.riesgo,
    'validados',     t.validados,
    'atencion',      t.atencion,
    'depurar',       t.depurar,
    'capturistas',   t.capturistas,
    'por_municipio', COALESCE(pm.data, '{}'::jsonb),
    'por_seccion',   COALESCE(ps.data, '{}'::jsonb),
    'alcance',       CASE WHEN v_es_estatal THEN 'estatal'
                         ELSE 'municipio:' || v_filtro_mun END,
    'generado',      now()
  )
  INTO v_resultado
  FROM totales t, por_municipio pm, por_seccion ps;

  RETURN v_resultado;
END;
$function$;

-- ── VERIFICACIÓN: entrar como consulta@demo.mx y ver que el panel de inicio
--    carga los KPIs (14,275 capturados) sin el error HTTP 400 en consola.
-- ═══════════════════════════════════════════════════════════════════════════
