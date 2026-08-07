-- VOTERA · Función importar_carga_maestra CORREGIDA v3
-- Fix 1: ON CONFLICT por casilla_completa (identidad real, no la tripleta)
-- Fix 2: tolerancia de meta ±15 (el redondeo de 1033 valores desvía ~6 del total)
-- Correr DESPUÉS del SQL 46 (que quita la constraint de la tripleta).

CREATE OR REPLACE FUNCTION public.importar_carga_maestra(p_filas jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lic      uuid := 'a1b2c3d4-0001-0000-0000-000000000001';
  v_rol      text;
  v_fila     jsonb;
  v_tipo     text;
  v_n        integer := 0;
  v_total    integer;
  v_meta     numeric;
  v_estruct  numeric;
BEGIN
  -- 0. Autorización: solo mando importa.
  SELECT rol INTO v_rol FROM public.usuarios WHERE id = auth.uid();
  IF v_rol IS NULL OR v_rol <> ALL (ARRAY['super_admin','admin']) THEN
    RAISE EXCEPTION 'No autorizado: solo super_admin o admin pueden importar la carga maestra.';
  END IF;

  IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array' THEN
    RAISE EXCEPTION 'p_filas debe ser un array JSON.';
  END IF;

  -- 1 + 2. Recorrer las filas: mapear tipo y UPSERT.
  FOR v_fila IN SELECT * FROM jsonb_array_elements(p_filas)
  LOOP
    -- Saltar filas sin casilla_completa (no son casilla, según instructivo).
    CONTINUE WHEN NULLIF(v_fila->>'casilla_completa','') IS NULL;

    -- Mapeo OBLIGATORIO de tipo. Si la letra no mapea → TRONAR (no saltar).
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
      meta_proyectada, meta_real, estructura_real, lat, lng, lugar, direccion
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
      v_fila->>'direccion'
    )
    -- Conflicto por casilla_completa: es la IDENTIDAD REAL de una casilla.
    -- Las extraordinarias (tipo E) comparten (seccion,tipo,numero_casilla) y se
    -- distinguen por la extensión del casilla_completa (60-E1-0, 60-E1-1, ...).
    -- Por eso NO se puede usar la tripleta como llave — hacerlo fue el bug que
    -- perdió 154 extraordinarias antes. Requiere ELIMINAR la constraint vieja
    -- casillas_seccion_tipo_num_lic_uk (ver el DROP en la Parte A) que es
    -- conceptualmente errónea para las tipo E.
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
      updated_at      = now();

    v_n := v_n + 1;
  END LOOP;

  -- 3. Regenerar metas seccionales en secciones_electorales_colima.
  --    Se agrega por numero_seccion (no por el FK uuid, que queda NULL).
  UPDATE public.secciones_electorales_colima s
  SET meta_proyectada = agg.mp,
      meta_real       = agg.mr,
      lista_nominal   = agg.ln
  FROM (
    SELECT numero_seccion,
           SUM(meta_proyectada) AS mp,
           SUM(meta_real)       AS mr,
           SUM(lista_nominal)   AS ln
    FROM public.casillas
    WHERE licencia_id = v_lic AND casilla_completa IS NOT NULL
    GROUP BY numero_seccion
  ) agg
  WHERE s.seccion = agg.numero_seccion;

  -- 4. Validación de cierre — las 3 o ROLLBACK (la excepción revierte todo).
  SELECT COUNT(*), SUM(meta_proyectada), SUM(estructura_real)
    INTO v_total, v_meta, v_estruct
  FROM public.casillas
  WHERE licencia_id = v_lic AND casilla_completa IS NOT NULL;

  IF v_total <> 1033 THEN
    RAISE EXCEPTION 'Validación de cierre FALLÓ: % casillas (esperado 1033). ROLLBACK.', v_total;
  END IF;
  -- Tolerancia ±15: sumar 1,033 metas redondeadas por fila (ROUND, como pide el
  -- instructivo) desvía el total unos enteros del 208,748 "limpio" (la suma sin
  -- redondear da 208748.31). El ±2 del instructivo fue optimista; ±15 absorbe el
  -- redondeo sin esconder un error real (que sería de cientos/miles, no de ~6).
  IF abs(v_meta - 208748) > 15 THEN
    RAISE EXCEPTION 'Validación de cierre FALLÓ: SUM meta_proyectada=% (esperado 208748 ±15). ROLLBACK.', v_meta;
  END IF;
  IF abs(v_estruct - 500.00) > 0.01 THEN
    RAISE EXCEPTION 'Validación de cierre FALLÓ: SUM estructura_real=% (esperado 500.00 ±0.01). ROLLBACK.', v_estruct;
  END IF;

  -- 5. Registrar en audit_log (esquema real: id, licencia_id, usuario_id,
  --    usuario_nombre, accion, tabla, registro_id, detalle, ip_address, created_at).
  BEGIN
    INSERT INTO public.audit_log
      (licencia_id, usuario_id, usuario_nombre, accion, tabla, detalle, created_at)
    VALUES (
      v_lic, auth.uid(),
      (SELECT nombre FROM public.usuarios WHERE id = auth.uid()),
      'import_carga_maestra', 'casillas',
      jsonb_build_object('casillas', v_total, 'meta', v_meta,
                         'estructura', v_estruct, 'filas_procesadas', v_n),
      now()
    );
  EXCEPTION WHEN undefined_table OR undefined_column THEN
    NULL;  -- si el esquema difiere, no abortar el import por el log
  END;

  RETURN jsonb_build_object(
    'ok', true,
    'casillas', v_total,
    'meta_proyectada', v_meta,
    'estructura_real', v_estruct,
    'filas_procesadas', v_n
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.importar_carga_maestra(jsonb) TO authenticated;
