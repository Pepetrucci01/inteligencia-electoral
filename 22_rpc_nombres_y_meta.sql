-- ═══════════════════════════════════════════════════════════════════════════
-- 22_rpc_nombres_y_meta.sql · 18 jul 2026
-- Validación de José 16-17 jul — familia de bugs "UUID en vez de nombre"
-- (bugs 8 y 11) + META SECCIÓN "—" del panel líder (bugs 9-10).
--
-- 1) get_nombres_usuarios(uuid[]) — RPC genérica para que CUALQUIER módulo
--    traduzca ids de usuario a nombres sin depender del RLS de `usuarios`
--    (el capturista/jefe_seccion normalmente no puede leer usuarios ajenos).
--    Seguridad: solo devuelve usuarios de la MISMA licencia del solicitante
--    (super_admin ve todas). Solo expone id + nombre — nada sensible.
--
-- 2) get_meta_seccion(int) — meta_proyectada del catálogo
--    secciones_electorales_colima, a prueba de RLS/grants del rol.
--
-- Aplicar en el SQL Editor de Supabase y versionar en git.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- 1. get_nombres_usuarios
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_nombres_usuarios(p_ids uuid[])
RETURNS TABLE (id uuid, nombre text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_rol      text;
  v_licencia uuid;
BEGIN
  SELECT u.rol, u.licencia_id
    INTO v_rol, v_licencia
  FROM public.usuarios u
  WHERE u.id = auth.uid()
  LIMIT 1;

  IF v_rol IS NULL THEN
    RAISE EXCEPTION 'Usuario sin perfil o no autenticado';
  END IF;

  RETURN QUERY
  SELECT u.id,
         COALESCE(NULLIF(TRIM(u.nombre), ''),
                  'Usuario ' || LEFT(u.id::text, 8)) AS nombre
  FROM public.usuarios u
  WHERE u.id = ANY(p_ids)
    AND (v_rol = 'super_admin' OR u.licencia_id = v_licencia);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_nombres_usuarios(uuid[]) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- 2. get_meta_seccion
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_meta_seccion(p_seccion integer)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_meta numeric;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  SELECT s.meta_proyectada
    INTO v_meta
  FROM public.secciones_electorales_colima s
  WHERE s.seccion = p_seccion
  LIMIT 1;

  RETURN COALESCE(v_meta, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_meta_seccion(integer) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- Verificación rápida (correr como super_admin en el SQL Editor):
--   SELECT * FROM get_nombres_usuarios(ARRAY(SELECT id FROM usuarios LIMIT 5));
--   SELECT get_meta_seccion(138);
-- ─────────────────────────────────────────────────────────────────────────
