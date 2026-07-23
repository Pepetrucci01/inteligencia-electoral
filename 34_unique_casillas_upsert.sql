-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 34: RESTRICCIÓN ÚNICA EN `casillas` (la que el upsert del Día E necesita)
-- Proyecto staging: dyirhwwmykskpuvzcafx · 22 jul 2026 · rama desarrollo
--
-- ⚠️ HALLAZGO GRAVE (auditoría de concurrencia, 22 jul):
--
-- modulo_dia_eleccion guarda instalación y cierre con:
--     .upsert([fila], { onConflict: 'numero_seccion,tipo_casilla,numero_casilla,licencia_id' })
--
-- pero pg_constraint muestra que `casillas` SOLO tiene su PRIMARY KEY (id).
-- NO existe la restricción UNIQUE sobre esas cuatro columnas.
--
-- Sin ella, Postgres rechaza el upsert con:
--     "there is no unique or exclusion constraint matching the ON CONFLICT
--      specification"
--
-- CONSECUENCIA: el guardado de instalación y de cierre del Día E ha estado
-- FALLANDO SIEMPRE. Los reportes quedaban solo en localStorage y el War Room
-- nunca veía esas casillas. Pasó inadvertido porque el error se tragaba en
-- silencio (ver el fix del reintento de pendientes, build 20260722d/v60: las
-- banderas de "pendiente" se escribían pero nadie las leía).
--
-- POR QUÉ FALTABA: 20_limpiar_casillas_dup.sql ya creaba esta restricción,
-- pero ese script termina en `ROLLBACK` con la nota "cambiar a COMMIT tras
-- revisar los resultados y con OK de José". Se diseñó en dos pasos y el
-- segundo nunca se dio: la limpieza de duplicados y el constraint quedaron
-- sin aplicar.
--
-- ESTE SCRIPT retoma ese trabajo: primero mide, luego deduplica, luego crea la
-- restricción. Se ejecuta en UNA transacción para poder revisar antes de
-- confirmar — igual de prudente que el original, pero con el COMMIT explícito
-- al final una vez revisados los conteos.
--
-- ⚠️ STAGING COMPARTIDO: correr coordinado con José (toca datos, no solo RLS).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. ¿Cuántos duplicados hay realmente? ──────────────────────────────────
SELECT 'ANTES · duplicados' AS momento,
       COUNT(*) AS grupos_duplicados,
       COALESCE(SUM(copias - 1), 0) AS filas_a_borrar
FROM (
  SELECT COUNT(*) AS copias
  FROM public.casillas
  GROUP BY numero_seccion, tipo_casilla, numero_casilla, licencia_id
  HAVING COUNT(*) > 1
) d;

SELECT 'ANTES · total' AS momento, tipo_casilla, COUNT(*) AS filas
FROM public.casillas GROUP BY tipo_casilla ORDER BY tipo_casilla;

-- ── 2. Deduplicar: conservar la fila MÁS RECIENTE de cada grupo ───────────
-- Criterio: se queda la de id mayor (la última escrita). Si hubiera columna
-- de fecha se preferiría esa, pero id es el desempate disponible y estable.
DELETE FROM public.casillas c
WHERE EXISTS (
  SELECT 1 FROM public.casillas c2
  WHERE c2.numero_seccion = c.numero_seccion
    AND c2.tipo_casilla   IS NOT DISTINCT FROM c.tipo_casilla
    AND c2.numero_casilla IS NOT DISTINCT FROM c.numero_casilla
    AND c2.licencia_id    IS NOT DISTINCT FROM c.licencia_id
    AND c2.id > c.id
);

-- ── 3. Conteo después ──────────────────────────────────────────────────────
SELECT 'DESPUES · total' AS momento, tipo_casilla, COUNT(*) AS filas
FROM public.casillas GROUP BY tipo_casilla ORDER BY tipo_casilla;

SELECT 'DESPUES · duplicados restantes' AS momento, COUNT(*) AS grupos
FROM (
  SELECT 1
  FROM public.casillas
  GROUP BY numero_seccion, tipo_casilla, numero_casilla, licencia_id
  HAVING COUNT(*) > 1
) d;

-- ── 4. Crear la restricción que el UPSERT necesita ────────────────────────
-- Si quedara algún duplicado, esto falla y la transacción entera se revierte
-- (nada se pierde) — hay que revisar antes de reintentar.
ALTER TABLE public.casillas
  ADD CONSTRAINT casillas_seccion_tipo_num_lic_uk
  UNIQUE (numero_seccion, tipo_casilla, numero_casilla, licencia_id);

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
--
--   SELECT conname, pg_get_constraintdef(oid)
--   FROM pg_constraint
--   WHERE conrelid='public.casillas'::regclass AND contype='u';
--     → debe aparecer casillas_seccion_tipo_num_lic_uk con las 4 columnas
--
-- PRUEBA FUNCIONAL (la que de verdad importa):
--   Con un usuario `repr_casilla`, en modulo_dia_eleccion:
--     a) Confirmar instalación → en consola debe salir
--        "✅ Día E: instalación guardada en casillas (upsert)."
--        y NO el error de ON CONFLICT.
--     b) Luego confirmar cierre de la MISMA casilla → debe ACTUALIZAR esa
--        fila, no crear una segunda. Comprobar con:
--          SELECT numero_seccion, tipo_casilla, numero_casilla, estatus,
--                 hora_apertura, hora_cierre
--          FROM casillas WHERE numero_seccion = <la sección de prueba>;
--        → UNA sola fila, con datos de instalación Y de cierre.
--
-- ⚠️ Si el paso (a) sigue fallando, revisar que la fila que envía el módulo
--    traiga las cuatro columnas del conflicto (un NULL en cualquiera de ellas
--    hace que UNIQUE no las considere iguales y se creen filas repetidas).
-- ═══════════════════════════════════════════════════════════════════════════
