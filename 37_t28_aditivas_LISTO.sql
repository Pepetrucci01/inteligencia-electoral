-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 37 (LISTO PARA CORRER) · TAREA 28 · aditivas T3, T4, T7, T9
-- Proyecto staging: dyirhwwmykskpuvzcafx · 27 jul 2026 · rama desarrollo
--
-- CÓMO CORRERLO: por PASOS numerados, de arriba a abajo. Los PASOS marcados
-- [DIAGNÓSTICO] solo LEEN — córrelos y mira el resultado. Los marcados
-- [APLICAR] hacen el cambio. Donde un APLICAR depende de lo que viste, lo dice.
--
-- Estado ya confirmado el 27 jul:
--   • T9: capturista@test.com existe, rol capturista, 0 capturas → BORRADO ACTIVO.
--   • T7: migración activa (aditiva pura, sin riesgo).
--   • T3 y T4: diagnóstico primero; su APLICAR queda listo para descomentar.
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- PASO 1 · TAREA 9 — BORRAR usuario residual capturista@test.com  [APLICAR]
-- Ya confirmado: 0 capturas. Se borra en orden hijas → auth.users.
-- ═══════════════════════════════════════════════════════════════════════════
DELETE FROM public.usuarios WHERE id = (SELECT id FROM auth.users WHERE email='capturista@test.com');
DELETE FROM auth.identities WHERE user_id = (SELECT id FROM auth.users WHERE email='capturista@test.com');
DELETE FROM auth.users      WHERE email = 'capturista@test.com';

-- PASO 1-verificación [DIAGNÓSTICO] — debe devolver 0 filas.
SELECT COUNT(*) AS quedan
FROM auth.users WHERE email = 'capturista@test.com';


-- ═══════════════════════════════════════════════════════════════════════════
-- PASO 2 · TAREA 7 — Columna fecha_apertura_captura en licencias  [APLICAR]
-- Aditiva pura, segura. Define desde cuándo el representante puede practicar.
-- ═══════════════════════════════════════════════════════════════════════════
ALTER TABLE public.licencias
  ADD COLUMN IF NOT EXISTS fecha_apertura_captura date;

-- PASO 2-verificación [DIAGNÓSTICO] — debe listar la columna, y de paso
-- confirmar que existe fecha_eleccion (la necesita el simulacro T8 después).
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'licencias'
  AND column_name IN ('fecha_apertura_captura','fecha_eleccion')
ORDER BY column_name;


-- ═══════════════════════════════════════════════════════════════════════════
-- PASO 3 · TAREA 3 — Columnas de alcance territorial en usuarios [DIAGNÓSTICO]
-- Prerrequisito de la RLS territorial (T5). R6: si municipio/seccion vienen
-- null, la policy no filtra y un coordinador municipal ve el estado completo.
-- ═══════════════════════════════════════════════════════════════════════════

-- 3.1 ¿existen las columnas y de qué tipo?
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'usuarios' AND column_name IN ('municipio','seccion')
ORDER BY column_name;

-- 3.2 ¿cuántos usuarios de cada rol NO tienen su dato de alcance?
-- (Estos conteos se le REPORTAN a José. Si hay >0, poblar antes de T5.)
SELECT rol,
       COUNT(*)                                  AS total,
       COUNT(*) FILTER (WHERE municipio IS NULL) AS sin_municipio,
       COUNT(*) FILTER (WHERE seccion   IS NULL) AS sin_seccion
FROM public.usuarios
WHERE rol IN ('coordinador','coordinador_estatal','jefe_seccion','repr_casilla')
GROUP BY rol
ORDER BY rol;

-- 3.3 [APLICAR SOLO si 3.1 muestra que FALTA alguna columna] — descomentar:
-- ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS municipio text;
-- ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS seccion   text;


-- ═══════════════════════════════════════════════════════════════════════════
-- PASO 4 · TAREA 4 — Índice único anti-duplicados en ciudadanos [DIAGNÓSTICO]
-- El activista ya no verifica si el ciudadano existe → la defensa se mueve al
-- servidor: único por (clave_elector, licencia_id), parcial para no chocar con
-- registros rápidos sin clave.
-- ═══════════════════════════════════════════════════════════════════════════

-- 4.1 ¿hay duplicados que impedirían crear el índice?
-- Si devuelve 0 filas → sigue con 4.2. Si devuelve filas → limpiar con José antes.
SELECT clave_elector, licencia_id, COUNT(*) AS copias
FROM public.ciudadanos
WHERE clave_elector IS NOT NULL
GROUP BY clave_elector, licencia_id
HAVING COUNT(*) > 1
ORDER BY copias DESC;

-- 4.2 [APLICAR SOLO si 4.1 devolvió 0 filas] — descomentar:
-- CREATE UNIQUE INDEX IF NOT EXISTS ux_ciudadanos_clave_licencia
--   ON public.ciudadanos (clave_elector, licencia_id)
--   WHERE clave_elector IS NOT NULL;

-- NOTA (frontend, no SQL): al violar el índice PostgREST devuelve 409/23505.
-- modulo_captura debe traducirlo a «Este ciudadano ya fue registrado por otro
-- activista» SIN revelar por quién. Se hace al conectar la captura.


-- ═══════════════════════════════════════════════════════════════════════════
-- RESUMEN AL TERMINAR
--   PASO 1 (T9): borrado — listo.
--   PASO 2 (T7): columna añadida — listo.
--   PASO 3 (T3): reportar a José los conteos de 3.2; aplicar 3.3 solo si faltan columnas.
--   PASO 4 (T4): si 4.1 = 0 filas, aplicar 4.2; si no, limpiar duplicados primero.
--
-- IMPORTANTE para la T5 (después): la policy del capturista usa
-- capturista_id = auth.uid(), NO created_by (esa columna no existe).
-- ═══════════════════════════════════════════════════════════════════════════
