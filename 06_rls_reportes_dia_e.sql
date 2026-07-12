-- ============================================================================
-- VOTERA — PARTE 5 (FINAL): DESBLOQUEAR reportes_casilla_eleccion  [T19]
-- Proyecto staging: dyirhwwmykskpuvzcafx · 10 jul 2026 · rama desarrollo
--
-- ESQUEMA CONFIRMADO (consultado en BD):
--   id bigint · casilla_id uuid · licencia_id uuid
--   presidente/secretario/escrutador_1/escrutador_2 varchar
--   votos_partido int · votos_total int · lista_nominal int
--   abierta bool · cerrada bool
--   hora_apertura time · hora_cierre time
--   incidencias text · foto_acta_url text · capturado_por uuid · created_at
--
-- ✅ TIENE licencia_id (uuid) → el aislamiento por licencia SÍ es posible.
--    No hace falta cambio de esquema.
--
-- ESTADO ACTUAL: RLS activada + 0 políticas = DENY-ALL.
--   Nadie lee ni escribe. Por eso T19 caía al fallback en silencio.
--   La tabla está VACÍA (0 filas), así que no hay riesgo al abrirla.
--
-- ⚠️ STAGING COMPARTIDO con la rama `desarrollo`: correr coordinado.
-- ============================================================================

BEGIN;

-- Lectura: super_admin ve todo; el resto, solo su licencia.
-- El visor (T19) usa este SELECT para pintar la capa Día E en vivo.
DROP POLICY IF EXISTS reportes_casilla_select ON reportes_casilla_eleccion;
CREATE POLICY reportes_casilla_select ON reportes_casilla_eleccion
  FOR SELECT USING (
    get_mi_rol() = 'super_admin' OR licencia_id = get_mi_licencia()
  );

-- INSERT: el representante de casilla reporta desde el campo el Día E.
-- Roles de campo + mando, siempre dentro de su propia licencia.
DROP POLICY IF EXISTS reportes_casilla_insert ON reportes_casilla_eleccion;
CREATE POLICY reportes_casilla_insert ON reportes_casilla_eleccion
  FOR INSERT WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador',
                                  'capturista','jefe_seccion'])
    -- La casilla reportada debe pertenecer a la MISMA licencia.
    -- (impide reportar sobre casillas de otro cliente)
    AND EXISTS (
      SELECT 1 FROM casillas c
      WHERE c.id = reportes_casilla_eleccion.casilla_id
        AND c.licencia_id = get_mi_licencia()
    )
  );

-- UPDATE: corregir el reporte durante la jornada (abrir, sumar votos, cerrar).
DROP POLICY IF EXISTS reportes_casilla_update ON reportes_casilla_eleccion;
CREATE POLICY reportes_casilla_update ON reportes_casilla_eleccion
  FOR UPDATE
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador',
                                  'capturista','jefe_seccion'])
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()   -- no se puede "mover" a otra licencia
  );

-- DELETE: solo mando. Un reporte del Día E no se borra a la ligera.
DROP POLICY IF EXISTS reportes_casilla_delete ON reportes_casilla_eleccion;
CREATE POLICY reportes_casilla_delete ON reportes_casilla_eleccion
  FOR DELETE USING (
    get_mi_rol() = ANY (ARRAY['super_admin','admin'])
    AND licencia_id = get_mi_licencia()
  );

COMMIT;


-- ============================================================================
--  auditoria_accesos — NO se toca por ahora
--
--  Diagnóstico: NINGÚN trigger escribe en ella (los 7 triggers del sistema son
--  updated_at + asignar_responsable). Es un vestigio sin uso activo, así que
--  su deny-all no está rompiendo nada. Decidir con José si se usa o se borra.
--  Si se va a usar, avisar: necesita políticas (y confirmar si tiene licencia_id).
-- ============================================================================


-- ============================================================================
-- VERIFICACIÓN (correr después del COMMIT)
-- ============================================================================

-- 1) Ya no debe quedar ninguna tabla con RLS y 0 políticas
--    (salvo auditoria_accesos, que dejamos a propósito).
-- SELECT c.relname, count(p.policyname) AS n_politicas
-- FROM pg_class c
-- JOIN pg_namespace n ON n.oid = c.relnamespace
-- LEFT JOIN pg_policies p ON p.tablename = c.relname AND p.schemaname = 'public'
-- WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity = true
-- GROUP BY c.relname
-- HAVING count(p.policyname) = 0;
-- Esperado: solo auditoria_accesos.

-- 2) T19 ya puede leer (logueado como admin/coordinador, NO super_admin):
-- SELECT count(*) FROM reportes_casilla_eleccion;
-- Esperado: 0 (tabla vacía) — pero SIN error. Antes daba deny-all.

-- 3) Prueba de fuga (como admin/coordinador):
-- SELECT count(DISTINCT licencia_id) FROM reportes_casilla_eleccion;
-- Esperado: 0 o 1. Más de 1 → FUGA.
