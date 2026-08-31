-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — 49: permitir al rol 'consulta' leer get_war_room_kpis
-- Proyecto staging: dyirhwwmykskpuvzcafx
--
-- ⚠ ACTUALIZADO 31/08/2026 — ESTE ARCHIVO YA NO TRAE LA META QUEMADA.
--
--   La versión original de este archivo declaraba META_ESTATAL constant
--   integer := 197297 dentro de la función. Si se volvía a correr, revertía
--   la meta a esa cifra y rompía el War Room otra vez.
--
--   El cuerpo de abajo es ahora el del archivo 65_war_room_meta_derivada.sql,
--   que es la versión VIGENTE. Correr este archivo ya es seguro: deja la
--   función igual que el 65.
--
--   Cualquier cambio futuro a get_war_room_kpis se hace en el 65 y se replica
--   aquí, no al revés.
--
-- Lo que aportó originalmente el 49 y se conserva:
--   'consulta' cuenta como alcance ESTATAL (observador global de solo lectura).
--   Antes caía en el RAISE 'Rol no autorizado' → HTTP 400 → el panel de inicio
--   del rol consulta no cargaba KPIs.
-- ═══════════════════════════════════════════════════════════════════════════

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
  v_meta        integer;          -- [A] antes era: META_ESTATAL constant := 197297
  v_meta_fuente text;
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

  -- ── 1b. [C] Candado de aislamiento multi-tenant ────────────
  --    SECURITY DEFINER se salta el RLS. Sin licencia no hay a qué acotar,
  --    así que se deniega en vez de abrir todas las licencias.
  IF v_licencia IS NULL THEN
    RAISE EXCEPTION 'Usuario % sin licencia asignada: acceso denegado al War Room', v_rol;
  END IF;

  -- ── 2. Decidir alcance territorial según rol ───────────────
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

  -- ── 2b. [A][B] META DERIVADA, con el MISMO filtro territorial ──
  --    Fuente de verdad: suma de casillas.meta_proyectada activas.
  --    Referencia canónica del archivo dorado: 208,748.31 (CONFIGURACIÓN D4).
  --    La suma de enteros da 208,754 — los 6 de diferencia son el redondeo por
  --    casilla, y ya están contemplados en la tolerancia ±15 de
  --    importar_carga_maestra.
  SELECT COALESCE(SUM(k.meta_proyectada), 0)
    INTO v_meta
  FROM public.casillas k
  WHERE k.licencia_id = v_licencia
    AND k.activo
    AND (v_filtro_mun IS NULL OR k.municipio = v_filtro_mun);

  v_meta_fuente := 'casillas';

  -- Respaldo: si no hay casillas cargadas, cae a la cifra de la licencia.
  IF COALESCE(v_meta, 0) = 0 THEN
    SELECT l.meta_estatal INTO v_meta
    FROM public.licencias l
    WHERE l.id = v_licencia;

    v_meta        := COALESCE(v_meta, 0);
    v_meta_fuente := CASE WHEN v_meta > 0 THEN 'licencia' ELSE 'sin_meta' END;
  END IF;

  -- ── 3. Calcular todos los KPIs en una sola pasada ──────────
  WITH base AS (
    SELECT *
    FROM public.ciudadanos c
    WHERE c.licencia_id = v_licencia              -- [C] sin la fuga del OR NULL
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
    'meta',          v_meta,
    'meta_fuente',   v_meta_fuente,          -- casillas | licencia | sin_meta
    'total',         t.total,
    'pct_avance',    CASE WHEN v_meta > 0    -- [A] guarda contra división entre cero
                          THEN ROUND( (t.total::numeric / v_meta) * 100, 2)
                          ELSE 0 END,
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

-- ── Permisos (venían del archivo get_war_room_kpis, el SQL 49 los omitía) ──
REVOKE ALL ON FUNCTION public.get_war_room_kpis() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_war_room_kpis() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN RÁPIDA (desde el frontend, logueado — NO desde el SQL Editor)
--   super_admin      -> meta 208754,  alcance 'estatal'
--   coord.a@demo.mx  -> meta  48664,  alcance 'municipio:COLIMA'
--   consulta@demo.mx -> meta 208754,  alcance 'estatal', sin HTTP 400
-- ═══════════════════════════════════════════════════════════════════════════
