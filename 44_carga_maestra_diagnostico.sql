-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 44: DIAGNÓSTICO previo al Importador de Carga Maestra (CARGA-01)
-- Proyecto staging: dyirhwwmykskpuvzcafx · 6 ago 2026 · rama desarrollo
--
-- ANTES de construir el importador o tocar nada, hay que ver el esquema REAL.
-- El instructivo asume columnas (casilla_completa, seccion_id, estructura_real,
-- lat, lng, meta_real, lista_nominal) que NO aparecen en el repo — puede que la
-- tabla casillas no las tenga y haya que crearlas (aditivo). También asume
-- filtros ('clave=DEMO') que hay que confirmar. Correr TODO esto y pasarme el
-- resultado; con eso escribo el importador y las correcciones sin inventar.
-- Solo son SELECTs — no modifica nada.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Estructura REAL de la tabla casillas (¿qué columnas existen hoy?)
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'casillas'
ORDER BY ordinal_position;

-- 2. ¿Cuántas casillas hay hoy y cuántas tienen seccion_id en NULL?
--    (el instructivo dice 939 con FK NULL; confirmemos)
SELECT COUNT(*) AS total_casillas,
       COUNT(*) FILTER (WHERE seccion_id IS NULL) AS sin_seccion_id
FROM public.casillas
WHERE licencia_id = 'a1b2c3d4-0001-0000-0000-000000000001';
-- (Si 'seccion_id' no existe como columna, esta query falla — y eso ya nos
--  dice que hay que crear la columna. En ese caso, saltar a la 2b.)

-- 2b. Si la 2 falló por columna inexistente, correr solo el conteo:
-- SELECT COUNT(*) FROM public.casillas
--  WHERE licencia_id = 'a1b2c3d4-0001-0000-0000-000000000001';

-- 3. Estructura de licencias: ¿cómo se llama la columna de meta y cómo filtrar
--    la licencia demo? (el instructivo dice meta_estatal y clave='DEMO')
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'licencias'
  AND (column_name ILIKE '%meta%' OR column_name ILIKE '%clave%'
       OR column_name = 'id' OR column_name ILIKE '%nombre%');

-- 3b. Ver la fila de la licencia demo para saber su valor de meta actual y qué
--     columna la identifica (id ya lo sabemos; ver si hay 'clave' o 'nombre'):
SELECT * FROM public.licencias
WHERE id = 'a1b2c3d4-0001-0000-0000-000000000001';

-- 4. configuracion_sistema: ¿existe la columna sistema_meta? ¿qué valor tiene?
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'configuracion_sistema'
  AND column_name ILIKE '%meta%';

-- 4b. Valor actual (el instructivo dice 208,717):
-- SELECT * FROM public.configuracion_sistema LIMIT 5;

-- 5. La tabla de secciones para poblar el FK: ¿cómo se llama exactamente y qué
--    columnas tiene? El instructivo menciona "secciones_electorales" y
--    "secciones_electorales_colima" — confirmemos cuál es cuál.
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public' AND table_name ILIKE '%seccion%'
ORDER BY table_name;

-- 6. ¿La tabla casillas tiene la restricción única sobre casilla_completa que
--    necesita el UPSERT? (SQL 34 creó una sobre otra tripleta; ver si hay que
--    añadir una sobre (licencia_id, casilla_completa))
SELECT con.conname, pg_get_constraintdef(con.oid) AS definicion
FROM pg_constraint con
JOIN pg_class rel ON rel.oid = con.conrelid
WHERE rel.relname = 'casillas' AND con.contype IN ('u','p');

-- ═══════════════════════════════════════════════════════════════════════════
-- Con estos 6 resultados sé exactamente: qué columnas faltan en casillas
-- (para el ALTER aditivo), cómo filtrar la licencia, el nombre real de la tabla
-- de secciones, y si falta la restricción única para el UPSERT. Entonces
-- construyo el importador y las 3 correcciones sin asumir nada.
-- ═══════════════════════════════════════════════════════════════════════════
