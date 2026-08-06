-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 43: TAREA 28 · T5 (cierre) — coordinador_estatal en las
-- políticas RLS restantes
-- Proyecto staging: dyirhwwmykskpuvzcafx · 6 ago 2026 · rama desarrollo
--
-- Completa la T5: añade coordinador_estatal a las políticas que hoy listan
-- 'coordinador' por ARRAY. Regla de la matriz del Excel: mismo acceso que el
-- coordinador (los mismos módulos/tablas), la diferencia es solo el ALCANCE
-- territorial — y ese ya lo dan las 5 funciones (SQL aplicado antes) y las
-- columnas usuarios.municipio/seccion. En estas tablas (casillas, alertas,
-- encuestas, call center, asignaciones, reportes) la policy NO filtra por
-- municipio, así que basta ampliar el ARRAY de roles.
--
-- Cada política se recrea desde su DEFINICIÓN VIGENTE (verificada una por una
-- contra el archivo donde vive su última versión — cuando una policy existe en
-- dos archivos, manda el de número mayor porque su DROP+CREATE reemplaza).
--
-- ⚠️ Avisar a José por WhatsApp antes de aplicar. apply_migration nombrada.
--    Requiere el rol ya válido en el constraint (SQL 41 · T1) — ya aplicado.
--    Solo AMPLÍA acceso a un rol nuevo; no quita nada a nadie.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ═══ reportes_casilla_eleccion — versión vigente en 24_rls_repr_casilla.sql ═══
-- (el 24 es posterior al 06; su INSERT/UPDATE añadió repr_casilla + jefe_seccion)
DROP POLICY IF EXISTS reportes_casilla_insert ON reportes_casilla_eleccion;
CREATE POLICY reportes_casilla_insert ON reportes_casilla_eleccion
  FOR INSERT
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador','coordinador_estatal',
                                  'jefe_seccion','repr_casilla'])
  );

DROP POLICY IF EXISTS reportes_casilla_update ON reportes_casilla_eleccion;
CREATE POLICY reportes_casilla_update ON reportes_casilla_eleccion
  FOR UPDATE
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador','coordinador_estatal',
                                  'jefe_seccion','repr_casilla'])
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador','coordinador_estatal',
                                  'jefe_seccion','repr_casilla'])
  );

-- ═══ respuestas_encuesta — 15_fix_fugas_restantes.sql (SELECT) + 25 (INSERT) ══
DROP POLICY IF EXISTS respuestas_select ON public.respuestas_encuesta;
CREATE POLICY respuestas_select ON public.respuestas_encuesta
  FOR SELECT
  USING (
    get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador','coordinador_estatal'])
    AND licencia_id = get_mi_licencia()
  );

DROP POLICY IF EXISTS respuestas_insert ON respuestas_encuesta;
CREATE POLICY respuestas_insert ON respuestas_encuesta
  FOR INSERT
  WITH CHECK (
    get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador','coordinador_estatal'])
    AND licencia_id = get_mi_licencia()
  );

-- ═══ asignaciones_representante — versión vigente: 33 (update) + 19 (resto) ═══
DROP POLICY IF EXISTS asig_repr_select ON public.asignaciones_representante;
CREATE POLICY asig_repr_select ON public.asignaciones_representante
  FOR SELECT
  USING (
    licencia_id = get_mi_licencia()
    AND ( usuario_id = auth.uid()
          OR get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador','coordinador_estatal']) )
  );

DROP POLICY IF EXISTS asig_repr_insert ON public.asignaciones_representante;
CREATE POLICY asig_repr_insert ON public.asignaciones_representante
  FOR INSERT
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador','coordinador_estatal'])
  );

DROP POLICY IF EXISTS asig_repr_update ON public.asignaciones_representante;
CREATE POLICY asig_repr_update ON public.asignaciones_representante
  FOR UPDATE
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador','coordinador_estatal'])
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador','coordinador_estatal'])
  );

DROP POLICY IF EXISTS asig_repr_delete ON public.asignaciones_representante;
CREATE POLICY asig_repr_delete ON public.asignaciones_representante
  FOR DELETE
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador','coordinador_estatal'])
  );

-- ═══ casillas — 21_permisos_casillas_dia_e.sql ══════════════════════════════
-- INSERT y UPDATE: mando + repr_casilla en su sección. coordinador_estatal va
-- junto al mando (ve/gestiona toda la licencia). Se conserva la rama de
-- repr_casilla tal cual (el OR con su sección).
-- Patrón REAL del SQL 21: la sección se compara con
--   numero_seccion IN (SELECT numero_seccion FROM public.get_mis_secciones())
-- (get_mis_secciones() devuelve integer, sin choque de tipos). NO existe un
-- get_mi_seccion() escalar. El UPDATE conserva además representante_id=auth.uid().
DROP POLICY IF EXISTS casillas_insert ON public.casillas;
CREATE POLICY casillas_insert ON public.casillas
  FOR INSERT
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND (
      get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador','coordinador_estatal'])
      OR (
        get_mi_rol() = 'repr_casilla'
        AND numero_seccion IN (SELECT numero_seccion FROM public.get_mis_secciones())
      )
    )
  );

DROP POLICY IF EXISTS casillas_representante_update ON public.casillas;
CREATE POLICY casillas_representante_update ON public.casillas
  FOR UPDATE
  USING (
    licencia_id = get_mi_licencia()
    AND (
      get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador','coordinador_estatal'])
      OR representante_id = auth.uid()
      OR numero_seccion IN (SELECT numero_seccion FROM public.get_mis_secciones())
    )
  );

-- ═══ campanas_llamadas — 30_callcenter_schema.sql ═══════════════════════════
DROP POLICY IF EXISTS camp_llam_select ON public.campanas_llamadas;
CREATE POLICY camp_llam_select ON public.campanas_llamadas
  FOR SELECT
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['operador_cc','coordinador','coordinador_estatal','admin','super_admin'])
  );

DROP POLICY IF EXISTS camp_llam_mando ON public.campanas_llamadas;
CREATE POLICY camp_llam_mando ON public.campanas_llamadas
  FOR ALL
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['coordinador','coordinador_estatal','admin','super_admin'])
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['coordinador','coordinador_estatal','admin','super_admin'])
  );

-- ═══ cola_llamadas — 30_callcenter_schema.sql (política de mando) ════════════
DROP POLICY IF EXISTS cola_mando_all ON public.cola_llamadas;
CREATE POLICY cola_mando_all ON public.cola_llamadas
  FOR ALL
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['coordinador','coordinador_estatal','admin','super_admin'])
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['coordinador','coordinador_estatal','admin','super_admin'])
  );

-- ═══ alertas — INSERT (36) + UPDATE mando (32) ══════════════════════════════
DROP POLICY IF EXISTS alertas_insert ON public.alertas;
CREATE POLICY alertas_insert ON public.alertas
  FOR INSERT
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador','coordinador_estatal'])
  );

DROP POLICY IF EXISTS alertas_update_mando ON public.alertas;
CREATE POLICY alertas_update_mando ON public.alertas
  FOR UPDATE
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador','coordinador_estatal'])
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador','coordinador_estatal'])
  );

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- OJO — políticas que NO se tocaron aquí y por qué:
--   · 06_rls_reportes_dia_e reportes_casilla_select/delete: el SELECT ya es
--     amplio por licencia; el 24 rehízo INSERT/UPDATE que son los que importan.
--   · 15_fix_fugas casillas_select/encuestas_select/secciones_select: son
--     SELECT abiertos por licencia (no listan coordinador como restricción).
--   · 25 el trigger alertas y 35/36 de columnas: no filtran por rol coordinador.
--   · cola_operador_select/update (30): son del operador_cc por su reserva, no
--     de coordinador — no aplica el rol estatal ahí.
--   · La normalización de alertas_select (36) usa solo get_mi_licencia(), sin
--     lista de roles → cualquier autenticado de la licencia lee; no hay que tocar.
--
-- VERIFICACIÓN:
--   SELECT tablename, policyname FROM pg_policies
--    WHERE schemaname='public'
--      AND (qual LIKE '%coordinador_estatal%' OR with_check LIKE '%coordinador_estatal%')
--    ORDER BY tablename, policyname;
--   → deben aparecer todas las de arriba + las de ciudadanos (SQL 40).
--
-- PRUEBA FUNCIONAL con el usuario demo coordinador_estatal:
--   · Ve casillas, alertas, encuestas, campañas de TODA la licencia.
--   · Puede crear una alerta, gestionar campañas de call center.
--   · Sigue SIN entrar a Administración / Meta / Panel Ejec.→Resumen.
-- ═══════════════════════════════════════════════════════════════════════════
