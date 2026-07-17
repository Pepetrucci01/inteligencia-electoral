-- ============================================================
--  LIMPIEZA DE DUPLICADOS EN casillas + CONSTRAINT UNIQUE
--  Día E · 16 jul 2026  ·  ⚠️ REQUIERE OK DE JOSÉ ANTES DE APLICAR
--
--  Hallazgo: casillas tiene duplicados por error de carga (la
--  importación del 30-may corrió varias veces). Copias idénticas
--  campo por campo y mismo created_at al microsegundo.
--    básicas: 12 dup · contiguas: 0 · especiales: 83 dup (de 154)
--
--  Este script:
--    1. Conserva UNA fila por (numero_seccion, tipo_casilla,
--       numero_casilla, licencia_id) y borra las copias.
--    2. Prioriza conservar la fila "más útil": la que ya tenga
--       estatus instalado / representante / registrado_por, para no
--       perder trabajo si alguna casilla ya se tocó. Entre iguales,
--       la más antigua (created_at asc).
--    3. Crea el constraint UNIQUE que el UPSERT del Día E necesita.
--
--  Envuelto en transacción: revisa los conteos antes del COMMIT.
-- ============================================================

BEGIN;

-- ── Diagnóstico previo (para comparar antes/después) ───────
--   Cuántas filas hay ahora
SELECT 'ANTES' AS momento, tipo_casilla, COUNT(*) AS filas
FROM public.casillas GROUP BY tipo_casilla ORDER BY tipo_casilla;

-- ── 1. Borrar duplicados conservando la fila más útil ──────
--   Ranking por grupo: primero las que tienen datos de instalación
--   o representante (para no perder trabajo), luego la más antigua.
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY numero_seccion, tipo_casilla, numero_casilla, licencia_id
      ORDER BY
        (estatus_casilla IS DISTINCT FROM 'no_instalada') DESC,  -- instaladas primero
        (registrado_por IS NOT NULL) DESC,                        -- con representante
        (presidente_casilla IS NOT NULL) DESC,                    -- con datos capturados
        created_at ASC                                            -- desempate: la más antigua
    ) AS rn
  FROM public.casillas
)
DELETE FROM public.casillas
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

-- ── 2. Verificar que ya no quedan duplicados ───────────────
SELECT 'duplicados restantes (debe ser 0)' AS chequeo, COUNT(*) AS grupos_dup
FROM (
  SELECT 1
  FROM public.casillas
  GROUP BY numero_seccion, tipo_casilla, numero_casilla, licencia_id
  HAVING COUNT(*) > 1
) s;

-- ── 3. Conteo después ──────────────────────────────────────
SELECT 'DESPUES' AS momento, tipo_casilla, COUNT(*) AS filas
FROM public.casillas GROUP BY tipo_casilla ORDER BY tipo_casilla;

-- ── 4. Crear el constraint UNIQUE que el UPSERT necesita ────
--   (solo se ejecuta si ya no hay duplicados; si los hubiera, esto
--    falla y hay que revisar antes del COMMIT.)
ALTER TABLE public.casillas
  ADD CONSTRAINT casillas_seccion_tipo_num_lic_uk
  UNIQUE (numero_seccion, tipo_casilla, numero_casilla, licencia_id);

-- ============================================================
--  Si los conteos DESPUES cuadran (especiales ~71, básicas ~388)
--  y "duplicados restantes" = 0 y el constraint se creó sin error:
--    → COMMIT;
--  Si algo se ve raro:
--    → ROLLBACK;  (no se pierde nada)
-- ============================================================
ROLLBACK;  -- cambiar a COMMIT tras revisar los resultados y con OK de José.
