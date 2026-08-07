-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 40: TAREA 28 · T5 — rama coordinador_estatal en la RLS
-- Proyecto staging: dyirhwwmykskpuvzcafx · 4 ago 2026 · rama desarrollo
--
-- Añade el rol coordinador_estatal a las políticas y funciones de alcance.
-- Regla confirmada por la MATRIZ del Excel de la Tarea 28:
--   "coordinador_estatal y coordinador ven los MISMOS módulos. La diferencia
--    es el alcance de datos, no los permisos."
-- Y la hoja ROLES:
--   coordinador_estatal → alcance "Todo el estado" (SIN filtro territorial)
--   coordinador         → alcance "SOLO SU MUNICIPIO"
--
-- POR TANTO: coordinador_estatal se comporta como admin en ALCANCE (ve toda su
-- licencia, sin filtro de municipio) — NO como el coordinador municipal. En
-- cada lugar va JUNTO A admin, nunca en la rama que filtra por municipio.
--
-- ⚠️ REQUISITO: este SQL asume que el valor 'coordinador_estatal' YA es válido
--    en el CHECK constraint usuarios.rol. Eso es la T1 (DROP+ADD del constraint),
--    que la hace Luis avisando a José antes (staging compartido, no aditivo).
--    Aplicar la T1 ANTES que este 40. Este archivo es idempotente y aditivo en
--    permisos (solo AMPLÍA a un rol nuevo; no quita nada a nadie).
--
-- ⚠️ Avisar a José por WhatsApp antes de aplicar. apply_migration nombrada.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- PARTE 1 · Funciones con lógica territorial (v_es_estatal)
-- ───────────────────────────────────────────────────────────────────────────
-- 3 funciones deciden "ve todo el estado" con el patrón:
--   v_es_estatal := v_rol IN ('super_admin','admin')
--                OR (v_rol = 'coordinador' AND v_municipio IS NULL);
-- coordinador_estatal SIEMPRE ve el estado completo → entra en el IN inicial.
-- (No se puede editar la función con un simple ALTER; hay que CREATE OR REPLACE
--  con el cuerpo completo. Como no tengo aquí el cuerpo íntegro de cada una,
--  este bloque queda como INSTRUCCIÓN PRECISA de qué cambiar, para hacerlo
--  sobre el archivo real de cada función y re-desplegarla.)
--
-- Archivos y línea del patrón a cambiar:
--   · get_avance_por_seccion.sql  (~línea 37)
--   · 12_perfil_votante.sql       (~líneas 66 y 166, dos funciones)
--   · 29_perfil_demografico_sexo.sql (~línea 63)
--
-- CAMBIO EN CADA UNA — de:
--     v_rol IN ('super_admin','admin')
--   a:
--     v_rol IN ('super_admin','admin','coordinador_estatal')
--
-- Con eso coordinador_estatal cae en la rama v_es_estatal=true (v_filtro_mun
-- NULL = sin filtro de municipio), exactamente como admin. El resto del cuerpo
-- de cada función NO cambia. Re-desplegar cada función tras el cambio.


-- ═══════════════════════════════════════════════════════════════════════════
-- PARTE 2 · Políticas RLS que listan roles en un ARRAY
-- ───────────────────────────────────────────────────────────────────────────
-- En cada policy donde el acceso se concede por ARRAY de roles y aparece
-- 'coordinador' con alcance GENERAL (no territorial), coordinador_estatal va
-- junto. Se recrean con DROP+CREATE para dejar el rol dentro.
--
-- NOTA: solo se tocan las políticas donde coordinador tiene acceso de mando
-- general. Las de filtro territorial por municipio (ciudadanos_coord_update_
-- municipio) NO se tocan — ahí coordinador_estatal usa la rama SIN filtro, que
-- ya cubre admin/super_admin y a la que lo agregamos abajo donde aplica.

-- ── ciudadanos: INSERT (SQL 31) — añadir coordinador_estatal a los que capturan
-- (la matriz da EDITAR en Captura a coordinador_estatal) ────────────────────
DROP POLICY IF EXISTS ciudadanos_insert ON public.ciudadanos;
CREATE POLICY ciudadanos_insert ON public.ciudadanos
  FOR INSERT
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['capturista','jefe_seccion','coordinador','coordinador_estatal','admin','super_admin'])
  );

-- ── ciudadanos: UPDATE de alcance estatal — añadir coordinador_estatal junto
-- a admin/super_admin (ve y edita toda la licencia, sin filtro de municipio) ─
DROP POLICY IF EXISTS ciudadanos_estatal_update ON public.ciudadanos;
CREATE POLICY ciudadanos_estatal_update ON public.ciudadanos
  FOR UPDATE
  USING (
    get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador_estatal'])
    AND licencia_id = get_mi_licencia()
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()
  );

-- (La policy ciudadanos_coord_update_municipio del coordinador MUNICIPAL queda
--  intacta: sigue filtrando por get_mi_municipio() solo para 'coordinador'.)

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- PARTE 3 · Las demás políticas que listan 'coordinador' por ARRAY
-- ───────────────────────────────────────────────────────────────────────────
-- Estas están repartidas en varios SQL previos. En TODAS, coordinador_estatal
-- va junto a coordinador (mismo acceso, la matriz dice mismos permisos). Se
-- listan aquí para recrearlas UNA POR UNA contra su definición real (no las
-- reproduzco a ciegas para no debilitar ninguna). Archivos y políticas:
--
--   06_rls_reportes_dia_e.sql   → reportes_dia_e (SELECT/INSERT)  líneas 39, 56
--   15_fix_fugas_restantes.sql  → línea 38
--   19_asignaciones_representante.sql → 3 políticas  líneas 38, 48, 56
--   21_permisos_casillas_dia_e.sql → casillas_insert / casillas_repr_update  24, 39
--   24_rls_repr_casilla.sql     → reportes_casilla  líneas 23, 38
--   25_rls_encuestas_respuestas.sql → línea 18
--   30_callcenter_schema.sql    → 5 políticas  líneas 267,275,279,314,318
--   32_endurecer_alertas_update.sql → alertas_update_mando  línea 55
--   33_with_check_asignaciones.sql → línea 33
--   36_normalizar_politicas_alertas.sql → alertas_insert  línea 43
--
-- REGLA MECÁNICA para cada una: en el ARRAY que hoy dice
--   ...'coordinador'...
-- dejarlo como
--   ...'coordinador','coordinador_estatal'...
-- Nada más. Mismo USING/WITH CHECK, misma tabla. Es ampliar el acceso al rol
-- nuevo con el MISMO alcance que ya tiene el coordinador en esa policy —
-- correcto porque la mayoría de esas tablas (casillas, alertas, encuestas,
-- call center, asignaciones) no filtran por municipio dentro de la policy;
-- el alcance territorial lo dan las funciones de la PARTE 1 y las columnas
-- usuarios.municipio/seccion (R6).
--
-- Se deja como lista de trabajo explícita en vez de un bloque que recree 15
-- políticas a ciegas: la RLS es lo más delicado del sistema y cada policy debe
-- editarse contra su definición real, verificando USING y WITH CHECK. Hacerlas
-- de golpe sin ver cada cuerpo arriesga debilitar alguna.
-- ═══════════════════════════════════════════════════════════════════════════

-- VERIFICACIÓN GENERAL (tras aplicar todo):
--   SELECT policyname, cmd, qual, with_check FROM pg_policies
--    WHERE schemaname='public'
--      AND (qual LIKE '%coordinador_estatal%' OR with_check LIKE '%coordinador_estatal%')
--    ORDER BY tablename, policyname;
--   → deben aparecer todas las políticas ampliadas.
--
-- PRUEBA FUNCIONAL (con el usuario demo coordinador_estatal de la T2):
--   · Debe VER datos de TODA la licencia (todos los municipios), no solo uno.
--   · Debe poder capturar/editar en Captura (EDITAR en la matriz).
--   · NO debe ver Panel Ejecutivo→Resumen/Licencia/Soporte (solo Usuarios).
--   · NO debe entrar a Administración ni Meta/Configurador.
-- ═══════════════════════════════════════════════════════════════════════════
