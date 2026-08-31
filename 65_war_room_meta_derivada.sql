-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — 65: War Room KPIs con META DERIVADA (no quemada)
-- Proyecto staging: dyirhwwmykskpuvzcafx
--
-- Parte del SQL 49 (que ya incluía a 'consulta' como alcance estatal) y
-- corrige tres cosas:
--
--   A) META QUEMADA. META_ESTATAL := 197297 era una constante dentro de la
--      función. Nunca leía la base. Por eso ningún UPDATE a licencias.meta_estatal
--      cambiaba nada en el War Room. Ahora la meta se DERIVA de la suma de
--      casillas.meta_proyectada.
--
--   B) DENOMINADOR SIN FILTRO TERRITORIAL. El filtro de municipio se aplicaba a
--      los ciudadanos pero la meta se quedaba estatal. Un coordinador de Comala
--      veía su total municipal dividido entre la meta de TODO el estado, así que
--      su barra de avance no significaba nada. Ahora la meta usa el mismo filtro
--      que la base.
--
--   C) AISLAMIENTO MULTI-TENANT. La condición (v_licencia IS NULL OR
--      c.licencia_id = v_licencia) abría TODAS las licencias cuando el usuario
--      tenía licencia_id en NULL. La función es SECURITY DEFINER, o sea que se
--      salta el RLS: esa línea era el único aislamiento que había. Ahora si no
--      hay licencia, se deniega.
--
-- Se agrega la llave 'meta_fuente' al jsonb para que la UI pueda mostrar un
-- indicador visible cuando la meta viene del respaldo y no de las casillas.
--
-- ✅ APLICADO EN STAGING EL 31/08/2026. Validado antes del swap con la versión
--   _v2 desde el preview: super_admin -> 208754 estatal, coord.a@demo.mx -> 48664
--   municipio:COLIMA, y el total de ciudadanos idéntico en ambas versiones.
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
-- VALIDACIÓN — correr ANTES de hacer el swap
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) La meta esperada por alcance. Estatal debe dar 208,754.
--    Los 10 municipios deben SUMAR exactamente ese estatal.
SELECT COALESCE(municipio,'** ESTATAL **') AS alcance,
       SUM(meta_proyectada)               AS meta_esperada
FROM   public.casillas
WHERE  licencia_id = 'a1b2c3d4-0001-0000-0000-000000000001'
  AND  activo
GROUP  BY ROLLUP(municipio)
ORDER  BY 1;

-- 2) Comparar vieja contra nueva, logueado desde el FRONTEND con cada usuario.
--    El SQL Editor corre como service_role y auth.uid() no se comporta igual,
--    así que esta prueba NO sirve desde el editor.
--
--    super_admin      -> meta 208754, alcance 'estatal'
--    coord.a@demo.mx  -> meta la de COLIMA,           alcance 'municipio:COLIMA'
--    coord.b@demo.mx  -> meta la de VILLA DE ALVAREZ, alcance 'municipio:VILLA DE ALVAREZ'
--    consulta@demo.mx -> meta 208754, alcance 'estatal' (no debe dar HTTP 400)
--
--    En la consola del navegador:
--      await supabase.rpc('get_war_room_kpis')      // vieja
--      await supabase.rpc('get_war_room_kpis')   // nueva
--    Todas las llaves deben ser IDÉNTICAS excepto meta, pct_avance y meta_fuente.

-- 3) Que ningún rol se haya quedado fuera sin querer.
--    Estos siguen dando 'Rol no autorizado': jefe_seccion, capturista,
--    operador_cc, repr_casilla. Si alguno ve algo del War Room en el hub,
--    le va a salir HTTP 400 — revisar contra la matriz de roles.


-- ═══════════════════════════════════════════════════════════════════════════
-- ESTADO: APLICADO — 31/08/2026
-- ═══════════════════════════════════════════════════════════════════════════
--
--  Hecho:
--    ✔ Validado con get_war_room_kpis_v2 antes del swap (frontend, no SQL Editor)
--    ✔ Swap aplicado sobre la función real
--    ✔ get_war_room_kpis_v2 eliminada
--    ✔ 49_consulta_war_room_kpis.sql y get_war_room_kpis.sql actualizados para
--      que no reviertan este cambio si alguien los vuelve a correr
--
--  Resultados de la validación:
--    super_admin       meta 208754  total 14275  pct 6.84  estatal
--    coord.a@demo.mx   meta  48664  total  3571  pct 7.34  municipio:COLIMA
--    El total de ciudadanos NO cambió respecto a la versión anterior.
--
--  PENDIENTE (frontend, no base): theme.js sigue horneando 208,748 y recalcula
--  el porcentaje por su cuenta, así que la barra del hub todavía ignora el
--  'meta' que manda esta RPC. También existe cargarMetaEstatalSupabase() como
--  tercera ruta para la meta, y ie_metas_casilla_horneado.js dice 208,717.
--
--  Este archivo es la versión VIGENTE de get_war_room_kpis. Cualquier cambio
--  futuro se hace aquí y se replica en los otros dos.
-- ═══════════════════════════════════════════════════════════════════════════
