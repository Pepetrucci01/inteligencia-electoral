-- ============================================================
--  AUDITORÍA DE ACCESOS · T · 15 jul 2026
--  DECISIÓN: en un sistema que maneja preferencia política (dato
--  personal SENSIBLE bajo LFPDPPP), la trazabilidad de accesos NO
--  es opcional. La tabla auditoria_accesos existía como cascarón
--  (RLS on, 0 políticas, 0 triggers). Se implementa de verdad.
--
--  Alcance v1: registrar operaciones de ESCRITURA sobre ciudadanos
--  (INSERT/UPDATE/DELETE) — quién, qué acción, cuándo, y detalle.
--  No registramos SELECT (sería demasiado volumen y Postgres no
--  dispara triggers en SELECT); para lecturas masivas/exportaciones
--  se auditará desde la capa de aplicación en una fase posterior.
--
--  La tabla es append-only: nadie edita ni borra registros de
--  auditoría (ni siquiera super_admin). Solo el sistema escribe
--  (vía trigger SECURITY DEFINER) y se puede leer para revisión.
-- ============================================================

-- ── 1. Función de trigger: registra la operación ───────────
CREATE OR REPLACE FUNCTION public.fn_auditar_ciudadanos()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_detalle jsonb;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_detalle := jsonb_build_object(
      'tabla', 'ciudadanos',
      'ciudadano_id', OLD.id,
      'curp', OLD.curp,
      'municipio', OLD.municipio,
      'licencia_id', OLD.licencia_id
    );
  ELSE
    v_detalle := jsonb_build_object(
      'tabla', 'ciudadanos',
      'ciudadano_id', NEW.id,
      'curp', NEW.curp,
      'municipio', NEW.municipio,
      'licencia_id', NEW.licencia_id
    );
  END IF;

  INSERT INTO public.auditoria_accesos (user_id, accion, detalle)
  VALUES (
    COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'),
    'ciudadanos.' || lower(TG_OP),   -- ciudadanos.insert / .update / .delete
    v_detalle
  );

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

-- ── 2. Triggers en ciudadanos ──────────────────────────────
DROP TRIGGER IF EXISTS trg_auditar_ciudadanos_ins ON public.ciudadanos;
CREATE TRIGGER trg_auditar_ciudadanos_ins
  AFTER INSERT ON public.ciudadanos
  FOR EACH ROW EXECUTE FUNCTION public.fn_auditar_ciudadanos();

DROP TRIGGER IF EXISTS trg_auditar_ciudadanos_upd ON public.ciudadanos;
CREATE TRIGGER trg_auditar_ciudadanos_upd
  AFTER UPDATE ON public.ciudadanos
  FOR EACH ROW EXECUTE FUNCTION public.fn_auditar_ciudadanos();

DROP TRIGGER IF EXISTS trg_auditar_ciudadanos_del ON public.ciudadanos;
CREATE TRIGGER trg_auditar_ciudadanos_del
  AFTER DELETE ON public.ciudadanos
  FOR EACH ROW EXECUTE FUNCTION public.fn_auditar_ciudadanos();

-- ── 3. Permisos y RLS: append-only auditable ───────────────
-- El trigger es SECURITY DEFINER, así que escribe aunque el usuario
-- no tenga INSERT directo. Damos SELECT a authenticated (para revisión
-- por admins) pero NADIE tiene UPDATE/DELETE: la auditoría es inmutable.
GRANT SELECT ON public.auditoria_accesos TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.auditoria_accesos FROM authenticated;

-- Política de lectura: super_admin/admin ven la auditoría de SU licencia.
-- (Los registros no llevan licencia_id propio; se filtra por el detalle.)
DROP POLICY IF EXISTS auditoria_select ON public.auditoria_accesos;
CREATE POLICY auditoria_select ON public.auditoria_accesos
  FOR SELECT
  USING (
    get_mi_rol() = ANY (ARRAY['super_admin','admin'])
    AND (detalle ->> 'licencia_id')::uuid = get_mi_licencia()
  );

-- ============================================================
--  VERIFICACIÓN
--    -- tras aplicar, capturar/editar un ciudadano y revisar:
--    SELECT user_id, accion, detalle, created_at
--    FROM auditoria_accesos ORDER BY created_at DESC LIMIT 5;
--    -- debe aparecer una fila 'ciudadanos.insert' con el detalle.
-- ============================================================
