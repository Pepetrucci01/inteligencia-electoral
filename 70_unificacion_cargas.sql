-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — 70: unificacion de las cargas por Excel en un solo modulo
-- Proyecto staging: dyirhwwmykskpuvzcafx
-- Migracion aplicada: pepe_20260901_get_estado_carga_maestra_con_catalogos
--
-- ANTES: las cargas estaban repartidas en tres archivos.
--   importador_carga.html         casillas + metas
--   configurador_meta_estados     calculadora de meta + carga de ciudadanos
--   configurador_maestro.html     demo vieja, huerfana (ningun boton la abria)
--   (estructura y representantes: no existian)
--
-- AHORA: todo entra por importador_carga.html, cuatro pestanas:
--   1 Metas          -> importar_carga_maestra (archivo 67)
--   2 Estructura     -> Edge Function importar-estructura (archivo 69)
--   3 Representantes -> misma Edge Function, rol repr_casilla
--   4 Ciudadanos     -> POST /rest/v1/ciudadanos por lotes de 200
--
-- get_estado_carga_maestra v2 ahora devuelve tambien:
--   municipios[]      catalogo real de la licencia (antes: lista quemada de
--                     Colima en el configurador)
--   secciones[]       para validar ciudadanos y representantes contra la
--                     carga maestra
--   ciudadanos        conteo actual del padron
--   estructura_alta   personas de estructura ya dadas de alta
--
-- CORRECCION DE DATOS PERSONALES: la carga de ciudadanos del configurador NO
-- enviaba 'consentimiento' (columna NOT NULL). El modulo unificado exige marcar
-- una casilla de consentimiento LFPDPPP y guarda consentimiento + fecha.
--
-- PARA DESECHAR (ya no los usa nadie):
--   configurador_maestro.html          huerfano
--   configurador_meta_estados.html     su carga de ciudadanos vive ahora en el
--                                      importador. Si se conserva la
--                                      calculadora, restringirla a super_admin:
--                                      muestra en pantalla los factores de
--                                      afluencia (0.88 / 0.98 / 1.08) y la meta
--                                      por capturista, que son metodologia
--                                      propietaria.
--   Quitar del hub el modulo "Configurador de meta" al retirarlo.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_estado_carga_maestra()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lic uuid; v_rol text; v_estado text;
  v_n integer; v_meta numeric; v_estruct numeric; v_ultima timestamptz;
  v_muns jsonb; v_secs jsonb; v_ciud integer; v_estructura integer;
BEGIN
  SELECT rol, licencia_id INTO v_rol, v_lic FROM public.usuarios WHERE id = auth.uid();
  IF v_rol IS NULL OR v_rol <> ALL (ARRAY['super_admin','admin']) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;
  IF v_lic IS NULL THEN
    RAISE EXCEPTION 'Usuario sin licencia asignada';
  END IF;
  SELECT estado INTO v_estado FROM public.licencias WHERE id = v_lic;

  SELECT COUNT(*), COALESCE(SUM(meta_proyectada),0), COALESCE(SUM(estructura_real),0), MAX(updated_at)
    INTO v_n, v_meta, v_estruct, v_ultima
  FROM public.casillas WHERE licencia_id = v_lic AND activo;

  SELECT COALESCE(jsonb_agg(DISTINCT municipio), '[]'::jsonb) INTO v_muns
  FROM public.casillas WHERE licencia_id = v_lic AND activo AND municipio IS NOT NULL;

  SELECT COALESCE(jsonb_agg(DISTINCT numero_seccion), '[]'::jsonb) INTO v_secs
  FROM public.casillas WHERE licencia_id = v_lic AND activo;

  SELECT COUNT(*) INTO v_ciud FROM public.ciudadanos WHERE licencia_id = v_lic;

  SELECT COUNT(*) INTO v_estructura
  FROM public.usuarios
  WHERE licencia_id = v_lic AND activo
    AND rol IN ('coordinador_estatal','coordinador','jefe_seccion','capturista','operador_cc','repr_casilla');

  RETURN jsonb_build_object(
    'licencia_id', v_lic, 'estado', v_estado,
    'casillas', v_n, 'meta_proyectada', v_meta, 'estructura_real', v_estruct,
    'ultima_carga', v_ultima,
    'municipios', v_muns, 'secciones', v_secs,
    'ciudadanos', v_ciud, 'estructura_alta', v_estructura
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_estado_carga_maestra() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_estado_carga_maestra() TO authenticated;
