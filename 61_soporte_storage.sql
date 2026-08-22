-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 61: BUCKET DE ADJUNTOS DEL SOPORTE
-- Complementa el SQL 60. Aditivo y reversible.
--
-- POR QUE VA APARTE Y POR QUE IMPORTA
--   El error mas comun con adjuntos es proteger la TABLA y dejar el BUCKET
--   abierto: la fila de ticket_adjuntos queda bien acotada por RLS, pero el
--   archivo en si queda accesible por URL para cualquiera que la tenga.
--   Aqui el archivo hereda exactamente el mismo permiso que su ticket.
--
--   CONVENCION DE RUTA (obligatoria, la politica depende de ella):
--       {ticket_id}/{nombre-archivo}
--   La primera carpeta ES el uuid del ticket. Si el frontend sube con otra
--   forma, la politica lo rechaza — a proposito.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Helper: sacar el ticket_id de la ruta SIN reventar si no es un uuid.
--    Un cast directo dentro de una politica tumbaria la consulta entera
--    ante un nombre de archivo mal formado.
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ticket_id_de_ruta(p_name text)
RETURNS uuid
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  RETURN (split_part(p_name, '/', 1))::uuid;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.puedo_ver_ticket(p_ticket_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tickets t
    WHERE t.id = p_ticket_id
      AND ( t.creado_por = auth.uid()
            OR public.es_soporte()
            OR ( t.licencia_id = public.get_mi_licencia()
                 AND public.get_mi_rol() = ANY (ARRAY['super_admin','admin']) ) )
  );
$$;

CREATE OR REPLACE FUNCTION public.puedo_escribir_ticket(p_ticket_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tickets t
    WHERE t.id = p_ticket_id
      AND (t.creado_por = auth.uid() OR public.es_soporte())
  );
$$;

GRANT EXECUTE ON FUNCTION public.ticket_id_de_ruta(text)   TO authenticated;
GRANT EXECUTE ON FUNCTION public.puedo_ver_ticket(uuid)    TO authenticated;
GRANT EXECUTE ON FUNCTION public.puedo_escribir_ticket(uuid) TO authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 2. El bucket. PRIVADO (public=false): sin esto, cualquiera con la URL
--    entra sin token y las politicas de abajo no sirven de nada.
-- ───────────────────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'ticket-adjuntos', 'ticket-adjuntos', false, 5242880,
  ARRAY['image/png','image/jpeg','image/webp','application/pdf','text/plain']
)
ON CONFLICT (id) DO UPDATE
  SET public             = false,
      file_size_limit    = 5242880,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

COMMIT;

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Politicas sobre storage.objects
--    Si este bloque falla por permisos, hay que crearlas desde el dashboard
--    (Storage → ticket-adjuntos → Policies) con estas mismas condiciones.
-- ───────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS ticket_adj_obj_select ON storage.objects;
CREATE POLICY ticket_adj_obj_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'ticket-adjuntos'
    AND public.puedo_ver_ticket(public.ticket_id_de_ruta(name))
  );

DROP POLICY IF EXISTS ticket_adj_obj_insert ON storage.objects;
CREATE POLICY ticket_adj_obj_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'ticket-adjuntos'
    AND public.puedo_escribir_ticket(public.ticket_id_de_ruta(name))
  );

-- Los adjuntos NO se editan ni se borran: el hilo de un ticket es evidencia.
-- Solo un supervisor de soporte puede retirar un archivo (dato personal
-- subido por error, por ejemplo).
DROP POLICY IF EXISTS ticket_adj_obj_delete ON storage.objects;
CREATE POLICY ticket_adj_obj_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'ticket-adjuntos'
    AND public.es_soporte_supervisor()
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICACION — correr todo junto, es solo lectura
-- ═══════════════════════════════════════════════════════════════════════════
-- SELECT 'tablas' AS q, string_agg(tablename, ', ') AS r
--   FROM pg_tables WHERE schemaname='public'
--    AND tablename IN ('soporte_staff','tickets','ticket_mensajes','ticket_adjuntos')
-- UNION ALL
-- SELECT 'politicas tickets',
--        (SELECT string_agg(policyname||' ['||cmd||']', ' · ')
--           FROM pg_policies WHERE schemaname='public'
--            AND tablename IN ('soporte_staff','tickets','ticket_mensajes','ticket_adjuntos'))
-- UNION ALL
-- SELECT 'bucket',
--        (SELECT id||' · publico='||public::text||' · limite='||file_size_limit::text
--           FROM storage.buckets WHERE id='ticket-adjuntos')
-- UNION ALL
-- SELECT 'politicas storage',
--        (SELECT string_agg(policyname||' ['||cmd||']', ' · ')
--           FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
--            AND policyname LIKE 'ticket_adj%')
-- UNION ALL
-- SELECT 'rpcs',
--        (SELECT string_agg(p.proname, ', ' ORDER BY p.proname)
--           FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
--          WHERE n.nspname='public'
--            AND p.proname IN ('es_soporte','es_soporte_supervisor','crear_ticket',
--                'agregar_mensaje_ticket','reabrir_ticket','cambiar_estado_ticket',
--                'puedo_ver_ticket','puedo_escribir_ticket','ticket_id_de_ruta'));
--
-- PRUEBA DE HUMO (crea un ticket real como el usuario actual; el folio que
-- devuelva es el primero de la secuencia):
--   SELECT public.crear_ticket(
--     'Prueba del modulo de soporte',
--     'Ticket de prueba generado desde el SQL Editor para validar el flujo.',
--     'otro', 'baja',
--     '{"origen":"sql_editor","build":"20260727s"}'::jsonb);
--
-- REVERSIBLE:
--   DROP POLICY ticket_adj_obj_select ON storage.objects;
--   DROP POLICY ticket_adj_obj_insert ON storage.objects;
--   DROP POLICY ticket_adj_obj_delete ON storage.objects;
--   DELETE FROM storage.buckets WHERE id='ticket-adjuntos';
-- ═══════════════════════════════════════════════════════════════════════════
