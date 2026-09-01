-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — 67: importar_carga_maestra PARAMETRIZADA (v2)
-- Proyecto staging: dyirhwwmykskpuvzcafx
-- Migracion aplicada: pepe_20260831_importar_carga_maestra_parametrizada
--
-- ⚠ SUPERA a 45_carga_maestra_import.sql y 45b_fix_importar_funcion.sql.
--   Esos archivos traen la v1 con la licencia y los totales de Colima QUEMADOS.
--   Si alguien los vuelve a correr, la funcion deja de servir para cualquier
--   otro estado o licencia. Este es el archivo VIGENTE.
--
-- LO QUE CAMBIO Y POR QUE
--
--   v1                                   v2
--   ─────────────────────────────────    ───────────────────────────────────────
--   v_lic := 'a1b2c3d4-...' (fija)       licencia del usuario que importa
--   valida contra 1033 / 208748 / 500    valida que la BASE quede == ARCHIVO
--   UPDATE secciones_electorales_colima  solo si licencias.estado = 'Colima'
--   sin idempotencia                     lo que no viene se marca activo=false
--   —                                    rechaza casilla_completa duplicada
--   —                                    guardia: archivo parcial (>25%) aborta
--   —                                    alinea licencias.meta_estatal y
--                                        configuracion_sistema.sistema_meta
--
-- FORMATO DE ENTRADA (p_filas): array JSON, un objeto por casilla, con llaves
--   casilla_completa, numero_seccion, numero_casilla, tipo_letra (B/C/E/S),
--   municipio, lista_nominal, meta_proyectada, meta_real, estructura_real,
--   lat, lng, lugar, direccion
--
-- RESPUESTA: {ok, licencia_id, estado, casillas, meta_proyectada,
--             estructura_real, filas_procesadas, desactivadas}
--
-- PRUEBA (desde el modulo Carga Maestra, logueado como super_admin o admin;
-- desde el SQL Editor NO: auth.uid() es NULL y truena "No autorizado")
--   1. Cargar el archivo dorado de Colima completo
--      -> casillas=1033, meta_proyectada=208754, desactivadas=0
--   2. Volverlo a cargar: mismo resultado (idempotente)
--   3. Cargar un archivo con solo un municipio: debe ABORTAR por ">25%"
--
-- PENDIENTE ESTRUCTURAL: secciones_electorales_colima no tiene licencia_id.
-- Para un segundo estado hace falta una tabla de secciones por licencia o una
-- columna licencia_id + estado. Hasta entonces la funcion solo actualiza
-- secciones para Colima.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.importar_carga_maestra(p_filas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_lic        uuid;
  v_rol        text;
  v_estado     text;
  v_fila       jsonb;
  v_tipo       text;
  v_n          integer := 0;
  v_ids        text[];
  -- esperado (archivo)
  e_total      integer;
  e_meta       numeric;
  e_estruct    numeric;
  -- obtenido (base)
  b_total      integer;
  b_meta       numeric;
  b_estruct    numeric;
  v_activas_antes integer;
  v_desactivadas  integer := 0;
BEGIN
  -- 0. Autorizacion y licencia del que importa
  SELECT rol, licencia_id INTO v_rol, v_lic FROM public.usuarios WHERE id = auth.uid();
  IF v_rol IS NULL OR v_rol <> ALL (ARRAY['super_admin','admin']) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin o admin pueden importar la carga maestra.';
  END IF;
  IF v_lic IS NULL THEN
    RAISE EXCEPTION 'El usuario que importa no tiene licencia asignada.';
  END IF;
  SELECT estado INTO v_estado FROM public.licencias WHERE id = v_lic;

  IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array' THEN
    RAISE EXCEPTION 'p_filas debe ser un array JSON.';
  END IF;

  -- 1. Totales ESPERADOS, calculados del archivo (no quemados)
  SELECT COUNT(*),
         SUM(round(NULLIF(f->>'meta_proyectada','')::numeric)),
         SUM(NULLIF(f->>'estructura_real','')::numeric),
         array_agg(f->>'casilla_completa')
    INTO e_total, e_meta, e_estruct, v_ids
  FROM jsonb_array_elements(p_filas) f
  WHERE NULLIF(f->>'casilla_completa','') IS NOT NULL;

  IF COALESCE(e_total,0) = 0 THEN
    RAISE EXCEPTION 'El archivo no trae ninguna fila con casilla_completa.';
  END IF;
  IF (SELECT COUNT(*) FROM unnest(v_ids)) <> (SELECT COUNT(DISTINCT x) FROM unnest(v_ids) x) THEN
    RAISE EXCEPTION 'El archivo trae casilla_completa duplicada. Corrige el archivo antes de cargar.';
  END IF;

  -- Guardia contra archivo parcial: cuantas activas actuales NO vienen en el archivo
  SELECT COUNT(*) INTO v_activas_antes
  FROM public.casillas WHERE licencia_id = v_lic AND activo;
  SELECT COUNT(*) INTO v_desactivadas
  FROM public.casillas
  WHERE licencia_id = v_lic AND activo AND NOT (casilla_completa = ANY(v_ids));
  IF v_activas_antes > 0 AND v_desactivadas > v_activas_antes * 0.25 THEN
    RAISE EXCEPTION 'El archivo dejaria fuera % de % casillas activas (>25%%). Parece un archivo parcial. ROLLBACK.',
      v_desactivadas, v_activas_antes;
  END IF;

  -- 2. UPSERT fila por fila
  FOR v_fila IN SELECT * FROM jsonb_array_elements(p_filas)
  LOOP
    CONTINUE WHEN NULLIF(v_fila->>'casilla_completa','') IS NULL;

    v_tipo := CASE upper(trim(v_fila->>'tipo_letra'))
                WHEN 'B' THEN 'basica'
                WHEN 'C' THEN 'contigua'
                WHEN 'E' THEN 'extraordinaria'
                WHEN 'S' THEN 'especial'
                ELSE NULL
              END;
    IF v_tipo IS NULL THEN
      RAISE EXCEPTION 'TIPO_CASILLA no mapeable: "%" en casilla %',
        v_fila->>'tipo_letra', v_fila->>'casilla_completa';
    END IF;

    INSERT INTO public.casillas (
      licencia_id, casilla_completa, numero_seccion, numero_casilla,
      tipo_casilla, municipio, lista_nominal,
      meta_proyectada, meta_real, estructura_real, lat, lng, lugar, direccion, activo
    ) VALUES (
      v_lic,
      v_fila->>'casilla_completa',
      (v_fila->>'numero_seccion')::integer,
      (v_fila->>'numero_casilla')::integer,
      v_tipo,
      v_fila->>'municipio',
      NULLIF(v_fila->>'lista_nominal','')::integer,
      round(NULLIF(v_fila->>'meta_proyectada','')::numeric)::integer,
      round(NULLIF(v_fila->>'meta_real','')::numeric)::integer,
      NULLIF(v_fila->>'estructura_real','')::numeric,
      NULLIF(v_fila->>'lat','')::numeric,
      NULLIF(v_fila->>'lng','')::numeric,
      v_fila->>'lugar',
      v_fila->>'direccion',
      true
    )
    ON CONFLICT (licencia_id, casilla_completa) WHERE casilla_completa IS NOT NULL
    DO UPDATE SET
      numero_seccion  = EXCLUDED.numero_seccion,
      numero_casilla  = EXCLUDED.numero_casilla,
      tipo_casilla    = EXCLUDED.tipo_casilla,
      municipio       = EXCLUDED.municipio,
      lista_nominal   = EXCLUDED.lista_nominal,
      meta_proyectada = EXCLUDED.meta_proyectada,
      meta_real       = EXCLUDED.meta_real,
      estructura_real = EXCLUDED.estructura_real,
      lat             = EXCLUDED.lat,
      lng             = EXCLUDED.lng,
      lugar           = EXCLUDED.lugar,
      direccion       = EXCLUDED.direccion,
      activo          = true,
      updated_at      = now();

    v_n := v_n + 1;
  END LOOP;

  -- 3. Idempotencia: lo que no vino en el archivo se desactiva (no se borra)
  UPDATE public.casillas
     SET activo = false, updated_at = now()
   WHERE licencia_id = v_lic AND activo AND NOT (casilla_completa = ANY(v_ids));
  GET DIAGNOSTICS v_desactivadas = ROW_COUNT;

  -- 4. Metas seccionales — SOLO para Colima (la tabla no tiene licencia_id)
  IF upper(COALESCE(v_estado,'')) = 'COLIMA' THEN
    UPDATE public.secciones_electorales_colima s
       SET meta_proyectada = agg.mp, meta_real = agg.mr, lista_nominal = agg.ln
      FROM (
        SELECT numero_seccion, SUM(meta_proyectada) AS mp, SUM(meta_real) AS mr, SUM(lista_nominal) AS ln
        FROM public.casillas
        WHERE licencia_id = v_lic AND activo
        GROUP BY numero_seccion
      ) agg
     WHERE s.seccion = agg.numero_seccion;
  END IF;

  -- 5. Validacion de cierre: la base debe quedar IGUAL al archivo
  SELECT COUNT(*), SUM(meta_proyectada), SUM(estructura_real)
    INTO b_total, b_meta, b_estruct
  FROM public.casillas
  WHERE licencia_id = v_lic AND activo;

  IF b_total <> e_total THEN
    RAISE EXCEPTION 'Validacion FALLO: % casillas activas en base vs % en archivo. ROLLBACK.', b_total, e_total;
  END IF;
  IF b_meta <> e_meta THEN
    RAISE EXCEPTION 'Validacion FALLO: SUM meta_proyectada base=% vs archivo=%. ROLLBACK.', b_meta, e_meta;
  END IF;
  IF abs(COALESCE(b_estruct,0) - COALESCE(e_estruct,0)) > 0.01 THEN
    RAISE EXCEPTION 'Validacion FALLO: SUM estructura_real base=% vs archivo=%. ROLLBACK.', b_estruct, e_estruct;
  END IF;

  -- 6. La licencia refleja lo cargado: una sola cifra de meta en todo el sistema
  UPDATE public.licencias
     SET meta_estatal = b_meta::integer, updated_at = now()
   WHERE id = v_lic;
  UPDATE public.configuracion_sistema
     SET sistema_meta = b_meta::integer, updated_at = now()
   WHERE licencia_id = v_lic;

  -- 7. Auditoria
  BEGIN
    INSERT INTO public.audit_log
      (licencia_id, usuario_id, usuario_nombre, accion, tabla, detalle, created_at)
    VALUES (
      v_lic, auth.uid(),
      (SELECT nombre FROM public.usuarios WHERE id = auth.uid()),
      'import_carga_maestra', 'casillas',
      jsonb_build_object('casillas', b_total, 'meta', b_meta, 'estructura', b_estruct,
                         'filas_procesadas', v_n, 'desactivadas', v_desactivadas,
                         'estado', v_estado),
      now()
    );
  EXCEPTION WHEN undefined_table OR undefined_column THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'licencia_id', v_lic,
    'estado', v_estado,
    'casillas', b_total,
    'meta_proyectada', b_meta,
    'estructura_real', b_estruct,
    'filas_procesadas', v_n,
    'desactivadas', v_desactivadas
  );
END;
$function$;
