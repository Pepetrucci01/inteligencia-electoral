-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 39: base aditiva para el escáner INE (scan-ine)
-- Proyecto staging: dyirhwwmykskpuvzcafx · 4 ago 2026 · rama desarrollo
--
-- Las dos piezas de base que pidió José para el escáner:
--   1. scan_ine_log — registro de escaneos (SIN la imagen) para medir consumo
--      y poder topar por licencia. La escribe la Edge Function con service_role.
--   2. licencias.vision_key_ref — puerta para ENTERPRISE (key por cliente).
--      Vacía = key maestra; con valor = referencia a la key del cliente. NO se
--      usa aún. Si algún día se guardan keys, van en Supabase Vault, NUNCA en
--      columna plana — esta columna solo guardaría una REFERENCIA, no la key.
--
-- ⚠️ Avisar a José por WhatsApp antes de aplicar. Aditivo puro. apply_migration.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. Tabla de log de escaneos ────────────────────────────────────────────
-- NO guarda la imagen ni datos personales: solo licencia, fecha y resultado.
CREATE TABLE IF NOT EXISTS public.scan_ine_log (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  licencia_id  uuid REFERENCES public.licencias(id) ON DELETE SET NULL,
  exito        boolean NOT NULL,
  motivo       text,          -- 'ok' | 'no_es_ine' | 'foto_ilegible' | 'error_api' | 'no_autorizado'
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Índice para los reportes de consumo por licencia y periodo.
CREATE INDEX IF NOT EXISTS idx_scan_ine_log_lic_fecha
  ON public.scan_ine_log (licencia_id, created_at);

-- RLS: la Edge Function escribe con service_role (que se salta RLS), así que
-- aquí solo definimos la LECTURA para el panel. Mando ve el consumo de su
-- licencia; super_admin ve todo. Nadie escribe desde el cliente.
ALTER TABLE public.scan_ine_log ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.scan_ine_log TO authenticated;

DROP POLICY IF EXISTS scan_ine_log_select ON public.scan_ine_log;
CREATE POLICY scan_ine_log_select ON public.scan_ine_log
  FOR SELECT USING (
    get_mi_rol() = 'super_admin'
    OR (
      licencia_id = get_mi_licencia()
      AND get_mi_rol() = ANY (ARRAY['admin','coordinador_estatal','coordinador'])
    )
  );
-- (Sin políticas de INSERT/UPDATE/DELETE: solo la Edge Function escribe, y lo
--  hace con service_role que no pasa por RLS. El cliente no puede escribir.)


-- ── 2. Columna vision_key_ref en licencias (ENTERPRISE, futura) ────────────
ALTER TABLE public.licencias
  ADD COLUMN IF NOT EXISTS vision_key_ref text;

COMMENT ON COLUMN public.licencias.vision_key_ref IS
  'ENTERPRISE (no usada aún): referencia a la key de visión propia del cliente. '
  'Vacía = key maestra de VOTERA. Si se usa, apunta a un secreto en Supabase Vault, '
  'NUNCA contiene la key en texto plano.';

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
--   SELECT tablename FROM pg_tables WHERE tablename='scan_ine_log';
--   SELECT policyname FROM pg_policies WHERE tablename='scan_ine_log';
--     → scan_ine_log_select
--   SELECT column_name FROM information_schema.columns
--    WHERE table_name='licencias' AND column_name='vision_key_ref';
--
-- La Edge Function scan-ine inserta aquí con SUPABASE_SERVICE_ROLE_KEY, así que
-- funciona aunque el usuario no tenga permiso de escritura (correcto: el log es
-- del sistema, no del usuario).
-- REVERSIBLE: DROP TABLE public.scan_ine_log; ALTER TABLE licencias DROP COLUMN vision_key_ref;
-- ═══════════════════════════════════════════════════════════════════════════
