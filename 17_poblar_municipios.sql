-- ============================================================
--  POBLAR CATÁLOGO municipios · T8 · 15 jul 2026
--  ⚠️ REQUIERE VALIDACIÓN DE JOSÉ antes de aplicar (catálogo maestro).
--
--  Hallazgo: la tabla municipios tenía 10 placeholders "Ciudad A-J"
--  (codigo MUN-A..MUN-J) que nunca se poblaron con los municipios
--  reales de Colima. Los ciudadanos SÍ usan los nombres reales en
--  texto, pero el catálogo no los reflejaba → municipio_id en
--  encuestas iba null y el cruce territorial no funcionaba (PEND #6).
--
--  Este script actualiza los nombres de placeholder a los 10 reales.
--  NO cambia ids (se conservan los UUID existentes, ya referenciados).
--  Solo actualiza nombre y codigo. Los datos electorales (votos_2024,
--  ganador_2024, distrito_federal) quedan para que José los complete
--  con el dato oficial — este script NO los inventa.
--
--  El match con ciudadanos.municipio es por nombre en MAYÚSCULAS
--  (así se guardan). Se usa el mismo formato exacto que ya existe
--  en ciudadanos para que el cruce funcione sin normalización.
-- ============================================================

BEGIN;  -- revisar los resultados del SELECT final antes de COMMIT

-- Mapeo determinista: placeholder alfabético → municipio real alfabético.
-- (Ambas listas ordenadas; A→ARMERÍA, B→COLIMA, etc.)
UPDATE public.municipios SET nombre = 'ARMERÍA',          codigo = 'ARM' WHERE codigo = 'MUN-A';
UPDATE public.municipios SET nombre = 'COLIMA',           codigo = 'COL' WHERE codigo = 'MUN-B';
UPDATE public.municipios SET nombre = 'COMALA',           codigo = 'COM' WHERE codigo = 'MUN-C';
UPDATE public.municipios SET nombre = 'COQUIMATLÁN',      codigo = 'COQ' WHERE codigo = 'MUN-D';
UPDATE public.municipios SET nombre = 'CUAUHTÉMOC',       codigo = 'CUA' WHERE codigo = 'MUN-E';
UPDATE public.municipios SET nombre = 'IXTLAHUACÁN',      codigo = 'IXT' WHERE codigo = 'MUN-F';
UPDATE public.municipios SET nombre = 'MANZANILLO',       codigo = 'MAN' WHERE codigo = 'MUN-G';
UPDATE public.municipios SET nombre = 'MINATITLÁN',       codigo = 'MIN' WHERE codigo = 'MUN-H';
UPDATE public.municipios SET nombre = 'TECOMÁN',          codigo = 'TEC' WHERE codigo = 'MUN-I';
UPDATE public.municipios SET nombre = 'VILLA DE ALVAREZ', codigo = 'VDA' WHERE codigo = 'MUN-J';

-- Verificar: todos los nombres del catálogo deben coincidir con los
-- que usan los ciudadanos (0 huérfanos en ambos sentidos).
SELECT
  'municipios sin match en ciudadanos' AS chequeo,
  string_agg(m.nombre, ', ') AS lista
FROM municipios m
WHERE m.nombre NOT IN (SELECT DISTINCT municipio FROM ciudadanos WHERE municipio IS NOT NULL)
UNION ALL
SELECT
  'municipios de ciudadanos sin catálogo',
  string_agg(DISTINCT c.municipio, ', ')
FROM ciudadanos c
WHERE c.municipio IS NOT NULL
  AND c.municipio NOT IN (SELECT nombre FROM municipios);

-- Si ambas listas salen NULL/vacías → match perfecto, hacer COMMIT.
-- Si sale algún nombre → revisar acentos/mayúsculas antes de COMMIT.
ROLLBACK;  -- cambiar a COMMIT cuando el chequeo salga limpio y José apruebe.
