-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — 68: secciones_ine — secciones electorales MULTI-LICENCIA
-- Proyecto staging: dyirhwwmykskpuvzcafx
-- Migraciones aplicadas (2026-09-25):
--   pepe_20260925_secciones_ine_multi_licencia_estructura
--   pepe_20260925_secciones_ine_multi_licencia_funciones
--
-- QUÉ RESUELVE
--   secciones_electorales_colima no tenía licencia_id, era legible por anon
--   (USING true) y 11 funciones la leían por número de sección a secas.
--   Como los números de sección se repiten entre estados, un usuario o el bot
--   de otro estado obtenía metas/municipios de Colima. Esta migración:
--     1. Renombra la tabla a secciones_ine y le agrega licencia_id (NOT NULL, FK).
--        Backfill de las 388 secciones de Colima a la licencia DEMO-2027.
--     2. UNIQUE (licencia_id, seccion) sustituye a UNIQUE (seccion).
--     3. RLS estricto: SELECT por licencia; escritura solo super_admin/admin de
--        la misma licencia; anon sin ningún permiso.
--     4. Vista de compatibilidad secciones_electorales_colima (security_invoker),
--        filtrada por get_mi_licencia(), para que el frontend que lee ese nombre
--        siga funcionando pero ya filtrado.
--     5. importar_carga_maestra: UPSERT de metas seccionales en secciones_ine para
--        CUALQUIER licencia (antes solo Colima). Al cargar el dorado de un estado,
--        sus secciones se crean solas. Municipio/centroide solo se completan si la
--        sección no los tenía; distritos si el importador los manda.
--     6. Reescritura de 10 funciones para leer secciones_ine filtrando licencia:
--        get_meta_seccion, municipio_de_seccion, jornada_puede_tocar,
--        registrar_voto_sorpresa, get_avance_secciones, get_war_room_territorio,
--        get_avance_bot (Telegram), get_resultados_actas, get_auditoria_datos,
--        importar_contactos_externos. Mensajes con "Colima" quemado → estado de la
--        licencia.
--
-- VERIFICADO con simulación RLS (BEGIN/ROLLBACK):
--   usuario de otra licencia → 0 secciones, municipio_de_seccion(339)=null, meta=0
--   admin Colima            → 388 secciones, VILLA DE ALVAREZ, meta 156
--   anon                    → permiso denegado
--
-- EFECTO EN FRONTEND: el visor/mapa ya NO puede leer secciones sin sesión.
--   Debe cargar autenticado; verá solo las secciones de su licencia.
--
-- Idempotente. El SQL exacto es el aplicado vía MCP; este archivo documenta y
-- permite re-aplicar. Ver cuerpos completos en las funciones del proyecto.
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════ PARTE 1: ESTRUCTURA + RLS + CARGA MAESTRA ═══════════════════════

DO $$
DECLARE v_kind char;
BEGIN
  SELECT c.relkind INTO v_kind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname='secciones_electorales_colima';
  IF to_regclass('public.secciones_ine') IS NULL AND v_kind = 'r' THEN
    ALTER TABLE public.secciones_electorales_colima RENAME TO secciones_ine;
  END IF;
END $$;

ALTER TABLE public.secciones_ine ADD COLUMN IF NOT EXISTS licencia_id uuid;

DO $$
DECLARE v_lic uuid;
BEGIN
  SELECT id INTO v_lic FROM public.licencias WHERE clave = 'DEMO-2027' LIMIT 1;
  IF v_lic IS NULL AND (SELECT count(*) FROM public.licencias) = 1 THEN
    SELECT id INTO v_lic FROM public.licencias LIMIT 1;
  END IF;
  IF v_lic IS NULL THEN
    RAISE EXCEPTION 'No se pudo determinar la licencia para backfill de secciones_ine.';
  END IF;
  UPDATE public.secciones_ine SET licencia_id = v_lic WHERE licencia_id IS NULL;
END $$;

ALTER TABLE public.secciones_ine ALTER COLUMN licencia_id SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'secciones_ine_licencia_fk') THEN
    ALTER TABLE public.secciones_ine
      ADD CONSTRAINT secciones_ine_licencia_fk FOREIGN KEY (licencia_id) REFERENCES public.licencias(id);
  END IF;
END $$;

ALTER TABLE public.secciones_ine DROP CONSTRAINT IF EXISTS secciones_electorales_colima_seccion_key;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'secciones_ine_lic_seccion_key') THEN
    ALTER TABLE public.secciones_ine ADD CONSTRAINT secciones_ine_lic_seccion_key UNIQUE (licencia_id, seccion);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_secciones_ine_lic ON public.secciones_ine (licencia_id);

ALTER TABLE public.secciones_ine ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS secciones_lectura          ON public.secciones_ine;
DROP POLICY IF EXISTS secciones_ine_select       ON public.secciones_ine;
DROP POLICY IF EXISTS secciones_ine_write_admin  ON public.secciones_ine;

CREATE POLICY secciones_ine_select ON public.secciones_ine
  FOR SELECT TO authenticated
  USING (licencia_id = public.get_mi_licencia());

CREATE POLICY secciones_ine_write_admin ON public.secciones_ine
  FOR ALL TO authenticated
  USING      (licencia_id = public.get_mi_licencia() AND public.get_mi_rol() IN ('super_admin','admin'))
  WITH CHECK (licencia_id = public.get_mi_licencia() AND public.get_mi_rol() IN ('super_admin','admin'));

REVOKE ALL ON public.secciones_ine FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.secciones_ine TO authenticated;
GRANT ALL ON public.secciones_ine TO service_role;

DO $$
DECLARE v_kind char;
BEGIN
  SELECT c.relkind INTO v_kind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relname='secciones_electorales_colima';
  IF v_kind = 'v' THEN
    DROP VIEW public.secciones_electorales_colima;
  END IF;
END $$;
CREATE VIEW public.secciones_electorales_colima
  WITH (security_invoker = true) AS
  SELECT * FROM public.secciones_ine WHERE licencia_id = public.get_mi_licencia();
REVOKE ALL ON public.secciones_electorales_colima FROM anon;
GRANT SELECT ON public.secciones_electorales_colima TO authenticated, service_role;

-- importar_carga_maestra y las 10 funciones reescritas: el cuerpo vigente es el
-- que está en la base (pg_get_functiondef). Para re-aplicar desde cero, exportar
-- con:  select pg_get_functiondef(oid) from pg_proc where proname in (...)
-- Cambio en cada una: FROM public.secciones_ine ... AND licencia_id = <licencia del contexto>

NOTIFY pgrst, 'reload schema';
