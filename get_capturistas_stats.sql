-- ============================================================
--  RPC — get_capturistas_stats()  ·  SIE Colima 2027
--  Estadísticas de desempeño por capturista, calculadas en la
--  base (sin paginar 14K+ filas al navegador, sin traer PII de
--  ciudadanos). Mismo patrón que get_war_room_kpis.
--
--  Alcance por rol:
--    super_admin / admin                  -> todo el estado
--    coordinador con municipio IS NULL    -> todo el estado (General)
--    coordinador con municipio asignado   -> solo su municipio
--    otros roles                          -> acceso denegado
--
--  Devuelve un JSON con:
--    capturistas[]  -> un objeto por capturista REAL (con nombre)
--    sin_asignar    -> agregado de registros con capturista_id NULL
--                      (pendientes de asignación, mostrados aparte)
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_capturistas_stats()
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
  META_CAP      constant integer := 50;   -- meta de capturas por capturista
BEGIN
  -- ── 1. Identificar al usuario que llama ────────────────────
  SELECT rol, municipio, licencia_id
    INTO v_rol, v_municipio, v_licencia
  FROM public.usuarios
  WHERE id = auth.uid()
  LIMIT 1;

  IF v_rol IS NULL THEN
    RAISE EXCEPTION 'Usuario sin perfil o no autenticado';
  END IF;

  -- ── 2. Alcance territorial ─────────────────────────────────
  v_es_estatal :=
        v_rol IN ('super_admin','admin')
     OR (v_rol = 'coordinador' AND v_municipio IS NULL);

  IF v_es_estatal THEN
    v_filtro_mun := NULL;
  ELSIF v_rol = 'coordinador' THEN
    v_filtro_mun := v_municipio;
  ELSE
    RAISE EXCEPTION 'Rol % no autorizado para panel de capturistas', v_rol;
  END IF;

  -- ── 3. Calcular stats por capturista ───────────────────────
  WITH base AS (
    SELECT *
    FROM public.ciudadanos c
    WHERE (v_licencia IS NULL OR c.licencia_id = v_licencia)
      AND (v_filtro_mun IS NULL OR c.municipio = v_filtro_mun)
  ),
  -- Solo registros CON capturista asignado, agrupados
  por_cap AS (
    SELECT
      b.capturista_id,
      COUNT(*)                                   AS total,
      COUNT(*) FILTER (WHERE b.compromiso >= 2)  AS validados,
      COUNT(*) FILTER (WHERE b.compromiso >= 3)  AS seguros,
      COUNT(*) FILTER (WHERE b.es_riesgo)        AS riesgo_alto,
      COUNT(*) FILTER (WHERE b.duplicado)        AS duplicados,
      MAX(b.created_at)                          AS ultima_captura,
      -- municipio "principal" del capturista (el más frecuente)
      MODE() WITHIN GROUP (ORDER BY b.municipio) AS municipio
    FROM base b
    WHERE b.capturista_id IS NOT NULL
    GROUP BY b.capturista_id
  ),
  -- Enriquecer con el nombre del capturista desde usuarios
  con_nombre AS (
    SELECT
      pc.*,
      COALESCE(
        NULLIF(TRIM(u.nombre), ''),
        'Capturista ' || LEFT(pc.capturista_id::text, 8)
      ) AS nombre
    FROM por_cap pc
    LEFT JOIN public.usuarios u ON u.id = pc.capturista_id
  ),
  -- Construir array de capturistas con métricas calculadas
  cap_array AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'id',           capturista_id,
        'nombre',       nombre,
        'municipio',    COALESCE(municipio, '—'),
        'total',        total,
        'meta',         META_CAP,
        'faltantes',    GREATEST(0, META_CAP - total),
        'validados',    validados,
        'seguros',      seguros,
        'riesgo_alto',  riesgo_alto,
        'duplicados',   duplicados,
        'pct_meta',     ROUND((total::numeric    / META_CAP) * 100, 1),
        'pct_val',      CASE WHEN total > 0 THEN ROUND((validados::numeric / total) * 100, 1) ELSE 0 END,
        'pct_seg',      CASE WHEN total > 0 THEN ROUND((seguros::numeric   / total) * 100, 1) ELSE 0 END,
        'score',        CASE WHEN total > 0
                          THEN ROUND( ((validados::numeric/total)*50 + (seguros::numeric/total)*50), 1)
                          ELSE 0 END,
        'ultima',       ultima_captura
      )
      ORDER BY total DESC
    ) AS data
    FROM con_nombre
  ),
  -- Agregado de los SIN asignar (capturista_id NULL)
  sin_asignar AS (
    SELECT
      COUNT(*)                                  AS total,
      COUNT(*) FILTER (WHERE compromiso >= 2)   AS validados,
      COUNT(*) FILTER (WHERE compromiso >= 3)   AS seguros,
      COUNT(*) FILTER (WHERE es_riesgo)         AS riesgo_alto
    FROM base
    WHERE capturista_id IS NULL
  )
  SELECT jsonb_build_object(
    'capturistas',  COALESCE(ca.data, '[]'::jsonb),
    'num_capturistas', (SELECT COUNT(*) FROM con_nombre),
    'sin_asignar',  jsonb_build_object(
                      'total',       sa.total,
                      'validados',   sa.validados,
                      'seguros',     sa.seguros,
                      'riesgo_alto', sa.riesgo_alto
                    ),
    'alcance',      CASE WHEN v_es_estatal THEN 'estatal'
                       ELSE 'municipio:' || v_filtro_mun END,
    'generado',     now()
  )
  INTO v_resultado
  FROM cap_array ca, sin_asignar sa;

  RETURN v_resultado;
END;
$$;

REVOKE ALL ON FUNCTION public.get_capturistas_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_capturistas_stats() TO authenticated;

-- ============================================================
--  PRUEBA (simular coord.b General)
-- ============================================================
-- SET request.jwt.claim.sub = '2fc4dcf7-5205-49be-87f1-e38908b0d1d6';
-- SELECT public.get_capturistas_stats();
-- RESET request.jwt.claim.sub;
-- ============================================================
