-- ============================================================================
-- VOTERA — PARTE 7: EL GRANT QUE FALTABA  [T19]
-- Proyecto staging: dyirhwwmykskpuvzcafx · 10 jul 2026 · rama desarrollo
--
-- CAUSA RAÍZ CONFIRMADA (PostgREST lo dijo textual):
--   403 Forbidden · code 42501
--   "permission denied for table reportes_casilla_eleccion"
--   hint: "GRANT SELECT ON public.reportes_casilla_eleccion TO authenticated;"
--
-- EN POSTGRES HAY DOS CAPAS DE PERMISOS. Hay que pasar LAS DOS:
--   1) GRANT  → ¿el rol puede TOCAR la tabla?      ← ESTO FALTABA
--   2) RLS    → de las filas, ¿cuáles VE?          ← esto ya lo hicimos (06)
--
--   Sin el GRANT, Postgres corta en la primera puerta y ni siquiera evalúa
--   las políticas RLS. Por eso el 06 no cambió nada.
--
-- Ya estaba documentado en ESTRUCTURA_MAESTRA: "las tablas creadas vía SQL
-- necesitan GRANT explícito al rol authenticated". Se nos pasó.
-- ============================================================================

BEGIN;

-- ── El GRANT que faltaba (T19) ──────────────────────────────────────────────
-- SELECT: el visor lee el estado de las casillas en vivo.
-- INSERT/UPDATE: el panel de captura del Día E reporta desde el campo.
-- (RLS sigue filtrando por licencia_id: el GRANT abre la puerta, la RLS
--  decide qué filas se ven. Las dos capas trabajan juntas.)
GRANT SELECT, INSERT, UPDATE ON public.reportes_casilla_eleccion TO authenticated;

-- La tabla usa id bigint (probablemente con secuencia). Sin esto, el INSERT
-- del panel de captura fallaría al generar el id.
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;


-- ── Revisar las tablas de T21: ¿tienen GRANT? ───────────────────────────────
-- Las creó esquema_modulo_encuestas.sql vía SQL → mismo riesgo.
-- Idempotente: si ya lo tienen, no pasa nada.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.encuestas           TO authenticated;
GRANT SELECT, INSERT                 ON public.respuestas_encuesta TO authenticated;
-- (respuestas: sin UPDATE/DELETE — una entrevista levantada no se edita,
--  igual que decidimos en las políticas RLS del 02.)

-- La vista del cruce también necesita GRANT.
GRANT SELECT ON public.v_territorio_vs_opinion TO authenticated;

COMMIT;


-- ============================================================================
-- AUDITORÍA: ¿qué otras tablas están sin GRANT?
-- Correr esto para cazar el mismo bug en el resto del sistema ANTES de que
-- muerda en producción. Si alguna tabla con datos vivos aparece sin
-- privilegios para 'authenticated', es una bomba de tiempo.
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
  AND c.relkind IN ('r','v')       -- tablas y vistas
GROUP BY c.relname
ORDER BY (COALESCE(string_agg(p.privilege_type, ''), '') = '') DESC,  -- las sin grant primero
         c.relname;
-- Revisar las que digan "⚠️ SIN GRANT": si tienen datos que la app consume,
-- necesitan su GRANT igual que reportes_casilla_eleccion.


-- ============================================================================
-- VERIFICACIÓN (recargar el visor después del COMMIT)
-- ============================================================================
-- En la consola del navegador debe desaparecer el 401/403 de T19, y verse:
--   ⚠️ T19 Día E: arreglo vacío  ← NORMAL: la tabla tiene 0 filas.
-- Eso significa que ya LEE bien; simplemente no hay reportes cargados aún.
-- La capa Día E seguirá simulando hasta que el panel de captura la alimente.
