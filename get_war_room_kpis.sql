-- ============================================================
--  C7 — RPC War Room KPIs  ·  SIE Colima 2027
--  Función SECURITY DEFINER: calcula agregados del War Room
--  saltando RLS de forma controlada, pero devolviendo SOLO
--  números (cero filas de ciudadanos = cero PII expuesta).
--
--  Alcance por rol (decidido DENTRO de la función, no confiable
--  desde el frontend):
--    super_admin / admin                  -> todo el estado
--    coordinador con municipio IS NULL    -> todo el estado (Coord. General)
--    coordinador con municipio asignado   -> solo su municipio
--    cualquier otro rol                   -> acceso denegado
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_war_room_kpis()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public          -- evita secuestro de search_path
AS $$
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
  v_es_estatal :=
        v_rol IN ('super_admin','admin')
     OR (v_rol = 'coordinador' AND v_municipio IS NULL);

  IF v_es_estatal THEN
    v_filtro_mun := NULL;                       -- ve todo el estado
  ELSIF v_rol = 'coordinador' THEN
    v_filtro_mun := v_municipio;                -- solo su municipio
  ELSE
    RAISE EXCEPTION 'Rol % no autorizado para War Room', v_rol;
  END IF;

  -- ── 3. Calcular todos los KPIs en una sola pasada ──────────
  --    El filtro de municipio se aplica con (v_filtro_mun IS NULL
  --    OR municipio = v_filtro_mun): si es estatal pasa todo,
  --    si es municipal acota.
  --    Se respeta la licencia del usuario para no mezclar clientes.
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
  -- [v2 15 jul] Desglose COMPLETO por municipio: cada municipio -> objeto con
  -- sus metricas, no solo el conteo. Antes Reportes mostraba val/seg/rie/dup en
  -- CERO porque la RPC solo daba el total estatal desglosado (PENDIENTE #3).
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
$$;

-- ── 4. Permisos: solo usuarios autenticados pueden llamarla ──
REVOKE ALL ON FUNCTION public.get_war_room_kpis() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_war_room_kpis() TO authenticated;

-- ============================================================
--  PRUEBAS (correr como cada usuario para validar alcance)
-- ============================================================
-- Desde el SQL Editor (corre como service_role, ve todo):
--   SELECT public.get_war_room_kpis();
--
-- Para probar el alcance REAL por rol, hazlo desde el frontend
-- logueado con cada usuario, o simula el JWT. El SQL Editor NO
-- respeta auth.uid() igual que un token de usuario.
-- ============================================================
