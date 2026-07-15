-- ============================================================
--  PRUEBA DE FUGA MULTI-TENANT  ·  SIE Colima 2027  ·  T6
--  Objetivo: DEMOSTRAR que las políticas RLS por licencia_id
--  aíslan de verdad: un usuario de la licencia B no ve NI UN
--  registro de la licencia A (la del cliente real), y viceversa.
--
--  Es SOLO LECTURA sobre los datos reales: crea una 2a licencia
--  de PRUEBA con datos ficticios, verifica el aislamiento en
--  ambos sentidos, y al final HACE ROLLBACK de todo lo creado.
--  No deja rastro en staging. Correr COMPLETO de una sola vez.
--
--  Cómo leerlo: cada bloque "VERIFICACIÓN" imprime un veredicto.
--  Todos deben decir "OK AISLADO". Si alguno dice "FUGA", hay
--  una política mal escrita y NO se puede vender hasta corregir.
-- ============================================================

BEGIN;  -- todo dentro de una transacción que revertimos al final

-- ── IDs de prueba (licencia B, ficticia) ───────────────────
--   Licencia A = la real del cliente: a1b2c3d4-0001-0000-0000-000000000001
--   Licencia B = de prueba, aislada:  b2b2b2b2-0002-0000-0000-000000000002
DO $$
DECLARE
  LIC_A uuid := 'a1b2c3d4-0001-0000-0000-000000000001';
  LIC_B uuid := 'b2b2b2b2-0002-0000-0000-000000000002';
  USER_B uuid := 'b2b2b2b2-0002-0000-0000-0000000000b2';  -- usuario de la lic B
  n_a int;
  n_b int;
BEGIN
  -- 1. Crear la licencia B (si la tabla licencias existe con esas columnas)
  --    Se usa un INSERT tolerante: solo columnas mínimas.
  BEGIN
    INSERT INTO public.licencias (id, nombre)
    VALUES (LIC_B, 'PRUEBA AISLAMIENTO - BORRAR')
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN undefined_column OR undefined_table THEN
    RAISE NOTICE 'Tabla licencias con esquema distinto — continúo igual';
  END;

  -- 2. Crear un usuario de la licencia B (rol admin de su propia licencia)
  INSERT INTO public.usuarios (id, email, rol, licencia_id, municipio)
  VALUES (USER_B, 'prueba_aislamiento_b@test.local', 'admin', LIC_B, NULL)
  ON CONFLICT (id) DO NOTHING;

  -- 3. Meter 3 ciudadanos ficticios en la licencia B
  INSERT INTO public.ciudadanos (nombre, sexo, edad, municipio, seccion_electoral,
                                 compromiso, licencia_id, capturista_id)
  VALUES
    ('PRUEBA B Uno',  'HOMBRE', 30, 'COLIMA', 999, 3, LIC_B, USER_B),
    ('PRUEBA B Dos',  'MUJER',  40, 'COLIMA', 999, 2, LIC_B, USER_B),
    ('PRUEBA B Tres', 'HOMBRE', 50, 'COLIMA', 999, 1, LIC_B, USER_B);

  SELECT COUNT(*) INTO n_a FROM public.ciudadanos WHERE licencia_id = LIC_A;
  SELECT COUNT(*) INTO n_b FROM public.ciudadanos WHERE licencia_id = LIC_B;
  RAISE NOTICE 'Datos base: Licencia A = % ciudadanos, Licencia B = % ciudadanos', n_a, n_b;
END $$;


-- ============================================================
--  VERIFICACIÓN 1 — Usuario de la licencia B ve SOLO lo suyo
--  Simulamos su JWT y consultamos ciudadanos CON RLS activo.
-- ============================================================
SET LOCAL role = authenticated;
SET LOCAL request.jwt.claim.sub = 'b2b2b2b2-0002-0000-0000-0000000000b2';  -- USER_B

SELECT
  'VERIF 1: usuario B ve solo licencia B' AS prueba,
  COUNT(*)                                             AS filas_visibles,
  COUNT(*) FILTER (WHERE licencia_id = 'a1b2c3d4-0001-0000-0000-000000000001') AS de_licencia_A,
  COUNT(*) FILTER (WHERE licencia_id = 'b2b2b2b2-0002-0000-0000-000000000002') AS de_licencia_B,
  CASE
    WHEN COUNT(*) FILTER (WHERE licencia_id = 'a1b2c3d4-0001-0000-0000-000000000001') = 0
     AND COUNT(*) > 0
    THEN '✅ OK AISLADO — no ve nada de la licencia A'
    WHEN COUNT(*) FILTER (WHERE licencia_id = 'a1b2c3d4-0001-0000-0000-000000000001') > 0
    THEN '🚨 FUGA — el usuario B está viendo ciudadanos de la licencia A'
    ELSE '⚠ REVISAR — no ve ni sus propios datos (RLS quizá demasiado estricta)'
  END AS veredicto
FROM public.ciudadanos;

RESET role;
RESET request.jwt.claim.sub;


-- ============================================================
--  VERIFICACIÓN 2 — Un usuario REAL de la licencia A NO ve
--  los ciudadanos de prueba de la licencia B.
--  Usa admin@sistema.mx (super_admin, licencia A).
-- ============================================================
-- Nota: super_admin ve todo SU estado/licencia A, pero NO debe ver
-- la licencia B. Tomamos su uuid real de la tabla usuarios.
DO $$
DECLARE
  v_admin_a uuid;
BEGIN
  SELECT id INTO v_admin_a FROM public.usuarios
  WHERE email = 'admin@sistema.mx' LIMIT 1;
  RAISE NOTICE 'UUID admin licencia A: %', v_admin_a;
  -- Guardamos en una tabla temporal para el SELECT siguiente
  CREATE TEMP TABLE _t6_admin (uid uuid) ON COMMIT DROP;
  INSERT INTO _t6_admin VALUES (v_admin_a);
END $$;

SET LOCAL role = authenticated;
SELECT set_config('request.jwt.claim.sub', (SELECT uid::text FROM _t6_admin), true);

SELECT
  'VERIF 2: usuario A (admin) NO ve licencia B' AS prueba,
  COUNT(*) FILTER (WHERE licencia_id = 'b2b2b2b2-0002-0000-0000-000000000002') AS ve_de_B,
  CASE
    WHEN COUNT(*) FILTER (WHERE licencia_id = 'b2b2b2b2-0002-0000-0000-000000000002') = 0
    THEN '✅ OK AISLADO — admin A no ve ningún ciudadano de la licencia B'
    ELSE '🚨 FUGA — admin de la licencia A está viendo datos de la licencia B'
  END AS veredicto
FROM public.ciudadanos;

RESET role;
RESET request.jwt.claim.sub;


-- ============================================================
--  VERIFICACIÓN 3 — Las RPC respetan el aislamiento
--  get_war_room_kpis simulando al usuario B: su 'total' debe
--  ser 3 (sus 3 ciudadanos ficticios), NO 14,262.
-- ============================================================
SET LOCAL role = authenticated;
SET LOCAL request.jwt.claim.sub = 'b2b2b2b2-0002-0000-0000-0000000000b2';

SELECT
  'VERIF 3: RPC War Room respeta licencia' AS prueba,
  (public.get_war_room_kpis() ->> 'total')::int AS total_que_ve_B,
  CASE
    WHEN (public.get_war_room_kpis() ->> 'total')::int = 3
    THEN '✅ OK AISLADO — la RPC solo cuenta los 3 de la licencia B'
    WHEN (public.get_war_room_kpis() ->> 'total')::int > 100
    THEN '🚨 FUGA — la RPC le está devolviendo los datos de la licencia A'
    ELSE '⚠ REVISAR — total inesperado'
  END AS veredicto;

RESET role;
RESET request.jwt.claim.sub;


-- ============================================================
--  LIMPIEZA — revertir TODO. No queda rastro en staging.
-- ============================================================
ROLLBACK;

-- ============================================================
--  Si TODOS los veredictos dicen "OK AISLADO":
--    → El aislamiento multi-tenant está DEMOSTRADO. Prerrequisito
--      de venta (EM §4.3) cumplido. Se puede documentar y cerrar T6.
--  Si algún veredicto dice "FUGA":
--    → Copiar el nombre de la prueba y avisar: hay una política RLS
--      que no filtra por licencia_id. NO vender hasta corregir.
-- ============================================================
