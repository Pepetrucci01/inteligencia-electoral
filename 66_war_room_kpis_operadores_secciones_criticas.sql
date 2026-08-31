-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — 66: operadores, secciones y criticas en get_war_room_kpis
-- Proyecto staging: dyirhwwmykskpuvzcafx
--
-- El hub traia tres tarjetas quemadas en el HTML: 60 operadores, 392 secciones
-- y 219 criticas. Los valores reales son 17 / 388 / 218 a nivel estatal.
-- El 60 no correspondia a nada: hay 20 usuarios en total, 17 de estructura.
--
-- Se agregan tres llaves al jsonb, con el mismo filtro territorial que el resto:
--   operadores → usuarios activos con rol de estructura de campo
--   secciones  → secciones con casilla activa
--   criticas   → secciones con avance por debajo del 5%% de su meta
--
-- Nota tecnica: las casillas se agrupan por seccion ANTES de unir con los
-- capturados. Si se une primero, el conteo se multiplica por el numero de
-- casillas de la seccion (ese error daba 139 criticas en vez de 218).
--
-- ESTE ES EL ARCHIVO VIGENTE de get_war_room_kpis.
--
--   ⚠ VERSION VIGENTE AL 31/08/2026. Este archivo ya NO trae la meta quemada.
--
--   Historial del dia:
--     · La meta estaba como constante META_ESTATAL := 197297 dentro de la
--       funcion. Nunca leia la base, por eso ningun UPDATE a
--       licencias.meta_estatal cambiaba el War Room.
--     · El filtro de municipio se aplicaba a los ciudadanos pero no a la meta:
--       un coordinador veia su total municipal contra la meta estatal.
--     · (v_licencia IS NULL OR ...) abria TODAS las licencias en una funcion
--       SECURITY DEFINER, que se salta el RLS.
--
--   Ahora: meta derivada de SUM(casillas.meta_proyectada) con filtro
--   territorial, candado de licencia, y las llaves meta_fuente, operadores,
--   secciones y criticas en el jsonb.
--
--   Valores de referencia (staging, 31/08/2026):
--     super_admin       meta 208754  total 14275  operadores 17  secciones 388  criticas 218
--     coord.a@demo.mx   meta  48664  total  3571  operadores 14  secciones  97  criticas  50
--
--   Migraciones aplicadas:
--     pepe_20260831_alinear_meta_208754_y_fecha_eleccion
--     pepe_20260831_war_room_kpis_operadores_secciones_criticas
--     pepe_20260831_restaurar_war_room_kpis_cuerpo_completo
--
--   Los tres archivos (49, 65, 66 y get_war_room_kpis) llevan el MISMO cuerpo.
--   Correr cualquiera de ellos es seguro. Cambios futuros: editar el 66 y
--   replicar en los otros.
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
  v_filtro_mun  text;
  v_resultado   jsonb;
  v_meta        integer;
  v_meta_fuente text;
  v_operadores  integer;
  v_secciones   integer;
  v_criticas    integer;
BEGIN
  SELECT rol, municipio, licencia_id
    INTO v_rol, v_municipio, v_licencia
  FROM public.usuarios WHERE id = auth.uid() LIMIT 1;

  IF v_rol IS NULL THEN
    RAISE EXCEPTION 'Usuario sin perfil o no autenticado';
  END IF;

  IF v_licencia IS NULL THEN
    RAISE EXCEPTION 'Usuario % sin licencia asignada: acceso denegado al War Room', v_rol;
  END IF;

  v_es_estatal :=
        v_rol IN ('super_admin','admin','coordinador_estatal','consulta')
     OR (v_rol = 'coordinador' AND v_municipio IS NULL);

  IF v_es_estatal THEN
    v_filtro_mun := NULL;
  ELSIF v_rol = 'coordinador' THEN
    v_filtro_mun := v_municipio;
  ELSE
    RAISE EXCEPTION 'Rol % no autorizado para War Room', v_rol;
  END IF;

  SELECT COALESCE(SUM(k.meta_proyectada), 0) INTO v_meta
  FROM public.casillas k
  WHERE k.licencia_id = v_licencia AND k.activo
    AND (v_filtro_mun IS NULL OR k.municipio = v_filtro_mun);

  v_meta_fuente := 'casillas';

  IF COALESCE(v_meta, 0) = 0 THEN
    SELECT l.meta_estatal INTO v_meta FROM public.licencias l WHERE l.id = v_licencia;
    v_meta        := COALESCE(v_meta, 0);
    v_meta_fuente := CASE WHEN v_meta > 0 THEN 'licencia' ELSE 'sin_meta' END;
  END IF;

  SELECT COUNT(*) INTO v_operadores
  FROM public.usuarios u
  WHERE u.licencia_id = v_licencia AND u.activo
    AND u.rol IN ('coordinador_estatal','coordinador','jefe_seccion',
                  'capturista','operador_cc','repr_casilla')
    AND (v_filtro_mun IS NULL OR u.municipio = v_filtro_mun);

  WITH sec AS (
    SELECT k.numero_seccion AS s, SUM(k.meta_proyectada) AS meta
    FROM public.casillas k
    WHERE k.licencia_id = v_licencia AND k.activo
      AND (v_filtro_mun IS NULL OR k.municipio = v_filtro_mun)
    GROUP BY k.numero_seccion
  ),
  cap AS (
    SELECT c.seccion_electoral AS s, COUNT(*) AS n
    FROM public.ciudadanos c
    WHERE c.licencia_id = v_licencia
      AND (v_filtro_mun IS NULL OR c.municipio = v_filtro_mun)
      AND c.seccion_electoral IS NOT NULL
    GROUP BY c.seccion_electoral
  )
  SELECT COUNT(*),
         COUNT(*) FILTER (WHERE sec.meta > 0
                            AND COALESCE(cap.n,0)::numeric / sec.meta < 0.05)
    INTO v_secciones, v_criticas
  FROM sec LEFT JOIN cap ON cap.s = sec.s;

  WITH base AS (
    SELECT * FROM public.ciudadanos c
    WHERE c.licencia_id = v_licencia
      AND (v_filtro_mun IS NULL OR c.municipio = v_filtro_mun)
  ),
  totales AS (
    SELECT COUNT(*) AS total,
      COUNT(*) FILTER (WHERE compromiso >= 3) AS seguro,
      COUNT(*) FILTER (WHERE es_apoyo)        AS apoyos,
      COUNT(*) FILTER (WHERE es_influencia)   AS influencia,
      COUNT(*) FILTER (WHERE es_riesgo)       AS riesgo,
      COUNT(*) FILTER (WHERE validado)        AS validados,
      COUNT(*) FILTER (WHERE compromiso = 2)  AS atencion,
      COUNT(*) FILTER (WHERE duplicado)       AS depurar,
      COUNT(DISTINCT capturista_id) FILTER (WHERE capturista_id IS NOT NULL) AS capturistas
    FROM base
  ),
  mun_agg AS (
    SELECT COALESCE(municipio,'(sin municipio)') AS municipio,
      COUNT(*) AS total,
      COUNT(*) FILTER (WHERE compromiso >= 3) AS seguro,
      COUNT(*) FILTER (WHERE es_apoyo)        AS apoyos,
      COUNT(*) FILTER (WHERE es_influencia)   AS influencia,
      COUNT(*) FILTER (WHERE es_riesgo)       AS riesgo,
      COUNT(*) FILTER (WHERE validado)        AS validados,
      COUNT(*) FILTER (WHERE compromiso = 2)  AS atencion,
      COUNT(*) FILTER (WHERE duplicado)       AS depurar
    FROM base GROUP BY COALESCE(municipio,'(sin municipio)')
  ),
  por_municipio AS (
    SELECT jsonb_object_agg(municipio, jsonb_build_object(
      'total',total,'seguro',seguro,'apoyos',apoyos,'influencia',influencia,
      'riesgo',riesgo,'validados',validados,'atencion',atencion,'depurar',depurar)) AS data
    FROM mun_agg
  ),
  por_seccion AS (
    SELECT jsonb_object_agg(seccion::text, n) AS data
    FROM (SELECT seccion_electoral AS seccion, COUNT(*) AS n FROM base
          WHERE seccion_electoral IS NOT NULL GROUP BY seccion_electoral) s
  )
  SELECT jsonb_build_object(
    'meta', v_meta, 'meta_fuente', v_meta_fuente, 'total', t.total,
    'pct_avance', CASE WHEN v_meta > 0
                       THEN ROUND((t.total::numeric / v_meta) * 100, 2) ELSE 0 END,
    'seguro',t.seguro,'apoyos',t.apoyos,'influencia',t.influencia,'riesgo',t.riesgo,
    'validados',t.validados,'atencion',t.atencion,'depurar',t.depurar,
    'capturistas',t.capturistas,
    'operadores', v_operadores,
    'secciones',  v_secciones,
    'criticas',   v_criticas,
    'por_municipio', COALESCE(pm.data,'{}'::jsonb),
    'por_seccion',   COALESCE(ps.data,'{}'::jsonb),
    'alcance', CASE WHEN v_es_estatal THEN 'estatal' ELSE 'municipio:'||v_filtro_mun END,
    'generado', now()
  ) INTO v_resultado
  FROM totales t, por_municipio pm, por_seccion ps;

  RETURN v_resultado;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_war_room_kpis() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_war_room_kpis() TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICACION (desde el frontend logueado, NO desde el SQL Editor:
--   ahi corre como service_role y auth.uid() no se comporta igual)
--
--   const base='https://dyirhwwmykskpuvzcafx.supabase.co';
--   const r=await(await supaFetch(base+'/rest/v1/rpc/get_war_room_kpis',
--     {method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})).json();
--   console.log(r.meta, r.total, r.pct_avance, r.alcance, r.meta_fuente,
--               r.operadores, r.secciones, r.criticas);
-- ═══════════════════════════════════════════════════════════════════════════
