-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 46: FIX de fondo del Importador — la constraint de la tripleta
-- rompe las extraordinarias (causa histórica de la pérdida de 154 casillas)
-- Proyecto staging: dyirhwwmykskpuvzcafx · 6 ago 2026 · rama desarrollo
--
-- HALLAZGO: la constraint casillas_seccion_tipo_num_lic_uk sobre
--   (numero_seccion, tipo_casilla, numero_casilla, licencia_id)
-- es INCORRECTA para las casillas extraordinarias (tipo E). Varias E comparten
-- esa tripleta y se distinguen por la EXTENSIÓN del casilla_completa:
--   60-E1-0, 60-E1-1, 60-E1-2 ... 60-E1-7  (8 casillas, misma tripleta)
-- El Excel trae 25 tripletas repetidas, todas tipo E. Esta constraint es la que
-- rechazaba esas casillas → por eso el sistema tenía 939 en vez de 1,033.
--
-- La identidad REAL de una casilla es casilla_completa, no la tripleta. El fix:
--   1. (Diagnóstico) confirmar que no hay casilla_completa duplicados hoy.
--   2. Eliminar la constraint vieja de la tripleta.
--   3. La constraint ux_casillas_completa_licencia (ya creada en SQL 45) queda
--      como la llave única correcta, y el UPSERT del import resuelve por ella.
--
-- ⚠️ Avisar a José. apply_migration. El ROLLBACK del import ya probó que la base
--    sigue intacta con las 938 originales — esto no borra datos, solo corrige
--    una constraint mal diseñada.
-- ═══════════════════════════════════════════════════════════════════════════


-- ── PASO 1 · DIAGNÓSTICO (correr y leer antes del PASO 2) ──────────────────

-- 1.1 ¿Hay casilla_completa duplicados hoy? (debe dar 0 filas para poder crear
--     la constraint única sin problema — ya confirmamos que sí es 0)
SELECT casilla_completa, COUNT(*)
FROM public.casillas
WHERE licencia_id = 'a1b2c3d4-0001-0000-0000-000000000001'
GROUP BY casilla_completa HAVING COUNT(*) > 1;

-- 1.2 Confirmar el nombre y definición de la constraint de la tripleta:
SELECT con.conname, pg_get_constraintdef(con.oid)
FROM pg_constraint con JOIN pg_class rel ON rel.oid = con.conrelid
WHERE rel.relname = 'casillas' AND con.contype = 'u';
--   Debe aparecer casillas_seccion_tipo_num_lic_uk y ux_casillas_completa_licencia.

-- 1.3 ¿Algo referencia la constraint vieja como FK? (no debería)
SELECT conname, conrelid::regclass
FROM pg_constraint
WHERE confrelid = 'public.casillas'::regclass AND contype = 'f';


-- ── PASO 2 · FIX — correr tras confirmar que 1.1 da 0 filas ─────────────────
-- Elimina la constraint de la tripleta (incorrecta para extraordinarias).
-- Es un UNIQUE constraint, se quita con DROP CONSTRAINT.

BEGIN;

ALTER TABLE public.casillas
  DROP CONSTRAINT IF EXISTS casillas_seccion_tipo_num_lic_uk;

-- Asegurar que la constraint correcta existe (por si el SQL 45 no se aplicó o
-- se aplicó parcialmente). Es idempotente.
CREATE UNIQUE INDEX IF NOT EXISTS ux_casillas_completa_licencia
  ON public.casillas (licencia_id, casilla_completa)
  WHERE casilla_completa IS NOT NULL;

COMMIT;

-- ── PASO 3 · Reaplicar la función (ya corregida a ON CONFLICT casilla_completa)
-- Correr el archivo 45b_fix_importar_funcion.sql (o la Parte C del SQL 45), que
-- ya trae el ON CONFLICT (licencia_id, casilla_completa). Con la constraint de
-- la tripleta ya eliminada, el import de las extraordinarias entra limpio.

-- ── VERIFICACIÓN ────────────────────────────────────────────────────────────
--   SELECT conname FROM pg_constraint WHERE conrelid='public.casillas'::regclass AND contype='u';
--     → ya NO debe aparecer casillas_seccion_tipo_num_lic_uk
--   Después, reintentar el import desde el módulo Carga Maestra.
--   Debe cerrar en 1,033 casillas (las 938 + las 95 extraordinarias que faltaban).
-- ═══════════════════════════════════════════════════════════════════════════
