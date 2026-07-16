-- ============================================================
--  CONSENTIMIENTO D1 · ciudadanos · T7 · 15 jul 2026
--
--  EM §4.3: el consentimiento del ciudadano (aviso de privacidad,
--  derechos ARCO, tratamiento de datos incluida preferencia
--  política) debe quedar PERSISTIDO, no solo validado en el UI.
--  Requisito legal para tratar datos personales de ciudadanos.
--
--  Hoy: el checkbox f-consent se valida en captura pero NO se
--  guarda. Estas columnas cierran ese hueco.
--
--  Aditivo y con default: no rompe filas existentes (los 14,261
--  ciudadanos ya cargados quedan con consentimiento=false, que es
--  correcto — se capturaron por importación, su consentimiento
--  documental vive fuera del sistema).
-- ============================================================

ALTER TABLE public.ciudadanos
  ADD COLUMN IF NOT EXISTS consentimiento        boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS consentimiento_fecha  timestamptz;

-- Comentarios de documentación (aparecen en el esquema)
COMMENT ON COLUMN public.ciudadanos.consentimiento IS
  'true si el capturista confirmó el consentimiento expreso del ciudadano (aviso de privacidad D1). Requisito EM §4.3.';
COMMENT ON COLUMN public.ciudadanos.consentimiento_fecha IS
  'Momento en que se registró el consentimiento (se llena en el INSERT de captura).';

-- ============================================================
--  VERIFICACIÓN
-- ============================================================
-- SELECT column_name, data_type, column_default
-- FROM information_schema.columns
-- WHERE table_schema='public' AND table_name='ciudadanos'
--   AND column_name IN ('consentimiento','consentimiento_fecha');
-- ============================================================
