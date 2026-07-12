-- ============================================================================
-- VOTERA — PARTE 8: GRANTS FALTANTES (hallados en la auditoría del 07)
-- Proyecto staging: dyirhwwmykskpuvzcafx · 10 jul 2026 · rama desarrollo
--
-- La auditoría de GRANTs destapó el MISMO bug de reportes_casilla_eleccion en
-- otras tablas: tienen políticas RLS, pero les falta el GRANT. Postgres corta
-- en la primera puerta y las políticas nunca se evalúan.
--
--   distritos             → REFERENCES, TRIGGER, TRUNCATE   ← sin SELECT
--   distritos_municipios  → REFERENCES, TRIGGER, TRUNCATE   ← sin SELECT
--
-- Nota: en 01_reparar_politicas_muertas.sql YA reparamos las políticas RLS de
-- ambas (estaban muertas por el rol 'superadmin' inexistente). Pero seguían
-- inalcanzables por falta de GRANT. Este script cierra el círculo.
-- ============================================================================

BEGIN;

-- ── Catálogos geográficos: lectura para cualquier autenticado ───────────────
-- La RLS ya filtra por licencia_id; el GRANT solo abre la puerta.
GRANT SELECT ON public.distritos            TO authenticated;
GRANT SELECT ON public.distritos_municipios TO authenticated;

COMMIT;


-- ============================================================================
--  auditoria_accesos — NO se toca (decisión deliberada)
--
--  Estado: sin GRANT (SELECT/INSERT), sin políticas RLS, y NINGÚN trigger
--  escribe en ella. Es un vestigio muerto: no está rompiendo nada porque
--  nadie la usa.
--
--  DECIDIR CON JOSÉ: ¿se usa o se borra?
--    · Si se va a usar → necesita GRANT + políticas (y confirmar licencia_id).
--    · Si no           → DROP TABLE y quitarla del esquema.
--  Dejarla en este limbo es deuda técnica: parece que audita, pero no audita.
-- ============================================================================


-- ============================================================================
--  audit_log — CORRECTO como está, no tocar
--
--  Tiene INSERT pero NO SELECT para 'authenticated'. Esto es intencional y
--  correcto: un log se ESCRIBE desde la app, pero no se LEE desde ella.
--  La lectura de auditoría se hace con service_role, fuera del frontend.
--  (Su política audit_select existe para cuando se consulte con privilegios.)
-- ============================================================================


-- ============================================================================
-- VERIFICACIÓN: no debe quedar ninguna tabla EN USO sin SELECT
-- ============================================================================
SELECT c.relname AS tabla,
       COALESCE(
         string_agg(DISTINCT p.privilege_type, ', ' ORDER BY p.privilege_type),
         '⚠️ SIN GRANT'
       ) AS privilegios_authenticated
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN information_schema.role_table_grants p
       ON p.table_name = c.relname
      AND p.table_schema = 'public'
      AND p.grantee = 'authenticated'
WHERE n.nspname = 'public'
  AND c.relkind IN ('r','v')
GROUP BY c.relname
HAVING NOT (COALESCE(string_agg(DISTINCT p.privilege_type, ','), '') LIKE '%SELECT%')
ORDER BY c.relname;
--
-- ESPERADO tras este script: solo 2 filas —
--   audit_log          (correcto: es de solo escritura)
--   auditoria_accesos  (vestigio: decidir con José)
--
-- Cualquier OTRA tabla que aparezca aquí y que la app consulte,
-- está fallando en silencio. Darle su GRANT SELECT.
