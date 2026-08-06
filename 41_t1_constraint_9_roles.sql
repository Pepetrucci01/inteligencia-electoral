-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 41: TAREA 28 · T1 — CHECK constraint de usuarios.rol → 9 roles
-- Proyecto staging: dyirhwwmykskpuvzcafx · 4 ago 2026 · rama desarrollo
--
-- Agrega 'coordinador_estatal' a los valores válidos de usuarios.rol. Es el
-- prerrequisito de TODO lo demás del rol nuevo (T2 usuario, T5 RLS, T6 guards):
-- sin esto, no puede existir un usuario con ese rol.
--
-- ⚠️⚠️ ESTE SQL NO ES ADITIVO — hace DROP + ADD del constraint. Y la tabla
--      usuarios está en el STAGING COMPARTIDO. AVISAR A JOSÉ POR WHATSAPP
--      ANTES DE CORRERLO. Meterlo con apply_migration nombrada.
--
-- ⚠️ El CHECK constraint NO está versionado en el repo — se creó directo en la
--    BD. Por eso el PASO 1 es un DIAGNÓSTICO OBLIGATORIO: hay que ver el nombre
--    y los valores REALES del constraint antes de tocarlo. NO correr el PASO 2
--    hasta haber leído el resultado del PASO 1.
-- ═══════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════
-- PASO 1 · DIAGNÓSTICO OBLIGATORIO — leer antes de tocar nada
-- ═══════════════════════════════════════════════════════════════════════════

-- 1.1 Nombre y definición del/los constraint(s) CHECK sobre usuarios.rol.
-- Anota el conname exacto: lo necesitas en el PASO 2 (puede NO llamarse
-- 'usuarios_rol_check' — a veces Postgres lo nombra distinto).
SELECT con.conname, pg_get_constraintdef(con.oid) AS definicion
FROM pg_constraint con
JOIN pg_class rel ON rel.oid = con.conrelid
JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
WHERE rel.relname = 'usuarios'
  AND nsp.nspname = 'public'
  AND con.contype = 'c'          -- 'c' = CHECK
  AND pg_get_constraintdef(con.oid) ILIKE '%rol%';

-- 1.2 ¿Qué valores de rol existen HOY en la tabla? (para no crear un constraint
-- que rechace filas ya presentes). Todos deben estar en la lista nueva de 9.
SELECT rol, COUNT(*) AS cuantos
FROM public.usuarios
GROUP BY rol
ORDER BY rol;
-- Si aparece algún valor que NO esté en los 9 oficiales (p.ej. 'lider_seccion'
-- o 'superadmin' sin guion), hay que corregir esas filas ANTES del PASO 2, o el
-- ADD CONSTRAINT fallará. Los 9 oficiales:
--   super_admin, admin, coordinador_estatal, coordinador, jefe_seccion,
--   capturista, operador_cc, repr_casilla, consulta


-- ═══════════════════════════════════════════════════════════════════════════
-- PASO 2 · MIGRACIÓN — correr SOLO tras leer el PASO 1
-- ───────────────────────────────────────────────────────────────────────────
-- Sustituye <NOMBRE_REAL_DEL_CONSTRAINT> por el conname que devolvió 1.1.
-- Si 1.1 devolvió VARIOS constraints sobre rol, hacer DROP de cada uno.
-- Todo en una transacción: si algo falla, no queda la tabla sin constraint.
-- ═══════════════════════════════════════════════════════════════════════════

-- BEGIN;
--
-- ALTER TABLE public.usuarios
--   DROP CONSTRAINT <NOMBRE_REAL_DEL_CONSTRAINT>;
--
-- ALTER TABLE public.usuarios
--   ADD CONSTRAINT usuarios_rol_check
--   CHECK (rol IN (
--     'super_admin',
--     'admin',
--     'coordinador_estatal',
--     'coordinador',
--     'jefe_seccion',
--     'capturista',
--     'operador_cc',
--     'repr_casilla',
--     'consulta'
--   ));
--
-- COMMIT;


-- ═══════════════════════════════════════════════════════════════════════════
-- PASO 3 · VERIFICACIÓN
-- ───────────────────────────────────────────────────────────────────────────
-- 3.1 El constraint nuevo debe listar los 9 valores:
--   SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='usuarios_rol_check';
--
-- 3.2 Prueba de que acepta el valor nuevo (en una transacción que se revierte,
--     para no dejar basura):
--   BEGIN;
--     UPDATE public.usuarios SET rol='coordinador_estatal'
--      WHERE id = (SELECT id FROM public.usuarios LIMIT 1);  -- debe PASAR
--   ROLLBACK;
--
-- 3.3 Prueba de que sigue rechazando basura:
--   BEGIN;
--     UPDATE public.usuarios SET rol='rol_inventado'
--      WHERE id = (SELECT id FROM public.usuarios LIMIT 1);  -- debe FALLAR
--   ROLLBACK;
--
-- DESPUÉS DE ESTO: ya se puede crear el usuario demo coordinador_estatal (T2)
-- y aplicar la RLS del rol (SQL 40 + funciones). Este 41 va ANTES que el 40.
-- ═══════════════════════════════════════════════════════════════════════════
