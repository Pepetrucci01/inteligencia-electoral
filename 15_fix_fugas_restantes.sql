-- ============================================================
--  FIX FUGAS MULTI-TENANT restantes · T6 · 15 jul 2026 · v2 conservador
--
--  Patrón de la fuga: (get_mi_rol()='super_admin') OR (licencia_id = get_mi_licencia())
--  El super_admin escapaba el filtro de licencia.
--
--  ENFOQUE CONSERVADOR: la política vieja, por su OR, permitia leer a
--  CUALQUIER rol de la licencia (el 2o termino no filtra rol). Para NO
--  cambiar ese comportamiento (y evitar romper accesos), el fix solo
--  ELIMINA el escape del super_admin: ahora TODOS -incluido super_admin-
--  quedan sujetos a licencia_id = get_mi_licencia().
-- ============================================================

-- 1. casillas_select
DROP POLICY IF EXISTS casillas_select ON public.casillas;
CREATE POLICY casillas_select ON public.casillas
  FOR SELECT
  USING ( licencia_id = get_mi_licencia() );

-- 2. encuestas_select
DROP POLICY IF EXISTS encuestas_select ON public.encuestas;
CREATE POLICY encuestas_select ON public.encuestas
  FOR SELECT
  USING ( licencia_id = get_mi_licencia() );

-- 3. reportes_casilla_select
DROP POLICY IF EXISTS reportes_casilla_select ON public.reportes_casilla_eleccion;
CREATE POLICY reportes_casilla_select ON public.reportes_casilla_eleccion
  FOR SELECT
  USING ( licencia_id = get_mi_licencia() );

-- 4. respuestas_select (esta SI filtraba rol; se conserva la lista y se
--    mete al super_admin bajo el filtro de licencia)
DROP POLICY IF EXISTS respuestas_select ON public.respuestas_encuesta;
CREATE POLICY respuestas_select ON public.respuestas_encuesta
  FOR SELECT
  USING (
    get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador'])
    AND licencia_id = get_mi_licencia()
  );

-- 5. secciones_admin_select
--    DECISIÓN (15 jul): secciones_electorales NO es catálogo compartido.
--    Tiene meta_seccion, semaforo y responsable_id POR LICENCIA (la 138
--    de un cliente tiene meta 2200; otro cliente tendría la suya). Es tabla
--    operativa de campaña → se FILTRA por licencia, igual que las demás.
--    (super_admin ya no escapa el filtro.)
DROP POLICY IF EXISTS secciones_admin_select ON public.secciones_electorales;
CREATE POLICY secciones_admin_select ON public.secciones_electorales
  FOR SELECT
  USING ( licencia_id = get_mi_licencia() );
