-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 45: Importador de Carga Maestra (CARGA-01) — base + función
-- Proyecto staging: dyirhwwmykskpuvzcafx · 6 ago 2026 · rama desarrollo
--
-- Construye el motor del importador: la restricción para el UPSERT, las 3
-- correcciones de base, y la función transaccional que hace toda la carga.
-- El frontend (pantalla que lee el Excel con SheetJS) solo convierte a JSON y
-- llama a importar_carga_maestra(). Toda la lógica crítica vive AQUÍ, en una
-- transacción real: si la validación de cierre falla, RAISE EXCEPTION revierte
-- TODO — nunca queda una carga a medias.
--
-- ⚠️ Avisar a José por WhatsApp antes de aplicar. apply_migration nombrada.
--    Las correcciones 2 y 3 (meta 208748) van SINCRONIZADAS con el commit de
--    frontend de Pepe (theme.js sistemaMeta:208748) — acordar el momento.
--
-- Verificado contra la base (SQL 44): casillas ya tiene todas las columnas;
-- falta la constraint de casilla_completa; licencia se filtra por
-- clave='DEMO-2027'; metas seccionales van en secciones_electorales_colima
-- (columna 'seccion', integer). El FK seccion_id (uuid → secciones_electorales,
-- 18 filas) NO se puebla: su tabla no tiene las secciones de Colima y el tipo
-- no empata; se deja NULL (como hoy) hasta que Pepe defina el modelo.
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- PARTE A · Restricción única para el UPSERT por casilla_completa
-- ───────────────────────────────────────────────────────────────────────────
-- El UPSERT necesita una constraint sobre (licencia_id, casilla_completa).
-- Parcial (WHERE casilla_completa IS NOT NULL) para no chocar con las filas
-- viejas del Día E que puedan no tener ese valor.
CREATE UNIQUE INDEX IF NOT EXISTS ux_casillas_completa_licencia
  ON public.casillas (licencia_id, casilla_completa)
  WHERE casilla_completa IS NOT NULL;


-- ═══════════════════════════════════════════════════════════════════════════
-- PARTE B · Las 3 correcciones de base (aditivas)
-- ───────────────────────────────────────────────────────────────────────────
-- Corrección 1: eliminar el registro basura (fila con casilla_completa NULL en
-- una sección que no existe). Cubre también la vieja "fila de prueba Día E".
DELETE FROM public.casillas
WHERE casilla_completa IS NULL AND numero_seccion = 145;

-- Corrección 2: meta de la licencia (hoy 197297 → 208748).
-- ⚠️ SINCRONIZAR con el commit de frontend de Pepe.
UPDATE public.licencias
SET meta_estatal = 208748
WHERE clave = 'DEMO-2027';

-- Corrección 3: meta del sistema (hoy 208717 → 208748).
-- ⚠️ SINCRONIZAR con el commit de frontend de Pepe.
UPDATE public.configuracion_sistema
SET sistema_meta = 208748;


-- ═══════════════════════════════════════════════════════════════════════════
-- PARTE C · La función transaccional del import
-- ───────────────────────────────────────────────────────────────────────────
-- Recibe un jsonb array con las 1,033 filas ya mapeadas por el frontend:
--   [{ "numero_seccion":2, "numero_casilla":1, "tipo_letra":"B",
--      "casilla_completa":"2-B1-0", "municipio":"COLIMA", "lista_nominal":123,
--      "meta_proyectada":201, "meta_real":195, "estructura_real":0.48,
--      "lat":19.26, "lng":-103.71, "lugar":"...", "direccion":"..." }, ... ]
--
-- Hace, TODO en una transacción (la función ya es atómica):
--   1. Mapea tipo_letra → tipo_casilla (truena si una letra no mapea).
--   2. UPSERT por (licencia_id, casilla_completa).
--   3. Regenera metas seccionales en secciones_electorales_colima.
--   4. Valida el cierre (1033 / 208748 / 500.00); si falla, RAISE → ROLLBACK.
--   5. Registra en audit_log.
-- Devuelve un jsonb con el resumen para que el frontend lo muestre.
--
-- SECURITY DEFINER + control de rol: solo super_admin/admin importan.
-- ═══════════════════════════════════════════════════════════════════════════
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
  IF abs(v_meta - 208748) > 2 THEN
    RAISE EXCEPTION 'Validación de cierre FALLÓ: SUM meta_proyectada=% (esperado 208748 ±2). ROLLBACK.', v_meta;
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

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN tras aplicar:
--   SELECT indexname FROM pg_indexes WHERE tablename='casillas' AND indexname='ux_casillas_completa_licencia';
--   SELECT meta_estatal FROM licencias WHERE clave='DEMO-2027';        -- 208748
--   SELECT sistema_meta FROM configuracion_sistema;                    -- 208748
--   SELECT proname FROM pg_proc WHERE proname='importar_carga_maestra';
--
-- El import en sí se dispara desde el frontend (llama a la función por RPC con
-- las 1,033 filas en JSON). Al terminar, la función devuelve el resumen o
-- lanza la excepción de cierre (y revierte todo).
--
-- NOTA audit_log: el paso 5 usa el esquema REAL confirmado (id, licencia_id,
-- usuario_id, usuario_nombre, accion, tabla, registro_id, detalle, ip_address,
-- created_at). El registro del import queda con accion='import_carga_maestra',
-- tabla='casillas' y el resumen en detalle. ip_address queda NULL (no la tiene
-- la función; si se quiere, se pasa desde el frontend como parámetro extra).
-- ═══════════════════════════════════════════════════════════════════════════
