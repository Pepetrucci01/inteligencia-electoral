-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — 68: get_estado_carga_maestra()
-- Proyecto staging: dyirhwwmykskpuvzcafx
-- Migracion aplicada: pepe_20260831_get_estado_carga_maestra
--
-- Totales actuales de la carga maestra para la licencia del usuario que llama.
-- La usa importador_carga.html en la revision previa: en vez de comparar el
-- archivo contra 1033 / 208748 / 500 quemados, lo compara contra lo que hay
-- HOY en la base y avisa cuanto cambiaria. Solo super_admin / admin.
--
-- Respuesta: {licencia_id, estado, casillas, meta_proyectada, estructura_real,
--             ultima_carga}
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

  RETURN jsonb_build_object(
    'licencia_id', v_lic, 'estado', v_estado,
    'casillas', v_n, 'meta_proyectada', v_meta, 'estructura_real', v_estruct,
    'ultima_carga', v_ultima
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_estado_carga_maestra() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_estado_carga_maestra() TO authenticated;
