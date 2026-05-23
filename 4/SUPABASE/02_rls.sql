-- ══════════════════════════════════════════════════════════════════════
--  INTELIGENCIA ELECTORAL — Row Level Security (RLS)
--  Archivo: 02_rls.sql
--  Ejecutar SEGUNDO, después de 01_schema.sql
--
--  Lógica de acceso:
--  superadmin  → ve TODO, sin restricción de licencia
--  admin       → ve solo su licencia
--  coordinador → ve su municipio dentro de su licencia
--  capturista  → ve solo sus secciones asignadas
-- ══════════════════════════════════════════════════════════════════════

-- ── Helper: obtener el rol del usuario actual ──
-- Esta función lee el rol desde la tabla usuarios
CREATE OR REPLACE FUNCTION get_mi_rol()
RETURNS TEXT AS $$
    SELECT rol FROM usuarios WHERE id = auth.uid()
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- ── Helper: obtener la licencia del usuario actual ──
CREATE OR REPLACE FUNCTION get_mi_licencia()
RETURNS UUID AS $$
    SELECT licencia_id FROM usuarios WHERE id = auth.uid()
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- ── Helper: obtener el municipio del usuario actual ──
CREATE OR REPLACE FUNCTION get_mi_municipio()
RETURNS TEXT AS $$
    SELECT municipio FROM usuarios WHERE id = auth.uid()
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- ── Helper: obtener sección base del capturista ──
CREATE OR REPLACE FUNCTION get_mi_seccion()
RETURNS INTEGER AS $$
    SELECT seccion_base FROM usuarios WHERE id = auth.uid()
$$ LANGUAGE SQL SECURITY DEFINER STABLE;

-- ══════════════════════════════════════════════════════════════════════
--  HABILITAR RLS EN TODAS LAS TABLAS
-- ══════════════════════════════════════════════════════════════════════
ALTER TABLE licencias               ENABLE ROW LEVEL SECURITY;
ALTER TABLE candidaturas            ENABLE ROW LEVEL SECURITY;
ALTER TABLE municipios              ENABLE ROW LEVEL SECURITY;
ALTER TABLE distritos               ENABLE ROW LEVEL SECURITY;
ALTER TABLE distritos_municipios    ENABLE ROW LEVEL SECURITY;
ALTER TABLE secciones_electorales   ENABLE ROW LEVEL SECURITY;
ALTER TABLE usuarios                ENABLE ROW LEVEL SECURITY;
ALTER TABLE ciudadanos              ENABLE ROW LEVEL SECURITY;
ALTER TABLE ciudadanos_candidaturas ENABLE ROW LEVEL SECURITY;
ALTER TABLE casillas                ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_log               ENABLE ROW LEVEL SECURITY;
ALTER TABLE configuracion_sistema   ENABLE ROW LEVEL SECURITY;

-- ══════════════════════════════════════════════════════════════════════
--  POLÍTICAS: licencias
-- ══════════════════════════════════════════════════════════════════════
-- superadmin ve todas
CREATE POLICY "licencias_superadmin_select"
    ON licencias FOR SELECT
    USING (get_mi_rol() = 'superadmin');

-- admin ve solo la suya
CREATE POLICY "licencias_admin_select"
    ON licencias FOR SELECT
    USING (
        get_mi_rol() IN ('admin','coordinador','capturista')
        AND id = get_mi_licencia()
    );

-- solo superadmin puede crear/editar licencias
CREATE POLICY "licencias_superadmin_all"
    ON licencias FOR ALL
    USING (get_mi_rol() = 'superadmin')
    WITH CHECK (get_mi_rol() = 'superadmin');

-- ══════════════════════════════════════════════════════════════════════
--  POLÍTICAS: candidaturas
-- ══════════════════════════════════════════════════════════════════════
CREATE POLICY "candidaturas_select"
    ON candidaturas FOR SELECT
    USING (
        get_mi_rol() = 'superadmin'
        OR licencia_id = get_mi_licencia()
    );

CREATE POLICY "candidaturas_insert_admin"
    ON candidaturas FOR INSERT
    WITH CHECK (
        get_mi_rol() IN ('superadmin','admin')
        AND licencia_id = get_mi_licencia()
    );

CREATE POLICY "candidaturas_update_admin"
    ON candidaturas FOR UPDATE
    USING (
        get_mi_rol() IN ('superadmin','admin')
        AND licencia_id = get_mi_licencia()
    );

-- ══════════════════════════════════════════════════════════════════════
--  POLÍTICAS: municipios
-- ══════════════════════════════════════════════════════════════════════
CREATE POLICY "municipios_select"
    ON municipios FOR SELECT
    USING (
        get_mi_rol() = 'superadmin'
        OR licencia_id = get_mi_licencia()
    );

CREATE POLICY "municipios_write_admin"
    ON municipios FOR ALL
    USING (
        get_mi_rol() IN ('superadmin','admin')
        AND licencia_id = get_mi_licencia()
    )
    WITH CHECK (
        get_mi_rol() IN ('superadmin','admin')
    );

-- ══════════════════════════════════════════════════════════════════════
--  POLÍTICAS: distritos y distritos_municipios
-- ══════════════════════════════════════════════════════════════════════
CREATE POLICY "distritos_select"
    ON distritos FOR SELECT
    USING (
        get_mi_rol() = 'superadmin'
        OR licencia_id = get_mi_licencia()
    );

CREATE POLICY "distritos_municipios_select"
    ON distritos_municipios FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM distritos d
            WHERE d.id = distrito_id
            AND (get_mi_rol() = 'superadmin' OR d.licencia_id = get_mi_licencia())
        )
    );

-- ══════════════════════════════════════════════════════════════════════
--  POLÍTICAS: secciones_electorales
-- ══════════════════════════════════════════════════════════════════════
-- superadmin y admin ven todas las secciones de su licencia
CREATE POLICY "secciones_admin_select"
    ON secciones_electorales FOR SELECT
    USING (
        get_mi_rol() = 'superadmin'
        OR (
            get_mi_rol() = 'admin'
            AND licencia_id = get_mi_licencia()
        )
    );

-- coordinador ve secciones de su municipio
CREATE POLICY "secciones_coordinador_select"
    ON secciones_electorales FOR SELECT
    USING (
        get_mi_rol() = 'coordinador'
        AND licencia_id = get_mi_licencia()
        AND municipio_nombre = get_mi_municipio()
    );

-- lider_seccion ve solo su sección
CREATE POLICY "secciones_lider_select"
    ON secciones_electorales FOR SELECT
    USING (
        get_mi_rol() = 'lider_seccion'
        AND licencia_id = get_mi_licencia()
        AND numero_seccion = get_mi_seccion()
    );

-- capturista ve todas las secciones de su municipio (necesita ver otras secciones para capturar)
CREATE POLICY "secciones_capturista_select"
    ON secciones_electorales FOR SELECT
    USING (
        get_mi_rol() = 'capturista'
        AND licencia_id = get_mi_licencia()
        AND municipio_nombre = (
            SELECT municipio FROM usuarios WHERE id = auth.uid()
        )
    );

-- solo admin+ puede modificar secciones
CREATE POLICY "secciones_admin_write"
    ON secciones_electorales FOR ALL
    USING (
        get_mi_rol() IN ('superadmin','admin')
        AND licencia_id = get_mi_licencia()
    )
    WITH CHECK (get_mi_rol() IN ('superadmin','admin'));

-- ══════════════════════════════════════════════════════════════════════
--  POLÍTICAS: usuarios
-- ══════════════════════════════════════════════════════════════════════
-- superadmin ve todos
CREATE POLICY "usuarios_superadmin_select"
    ON usuarios FOR SELECT
    USING (get_mi_rol() = 'superadmin');

-- admin ve usuarios de su licencia
CREATE POLICY "usuarios_admin_select"
    ON usuarios FOR SELECT
    USING (
        get_mi_rol() = 'admin'
        AND licencia_id = get_mi_licencia()
    );

-- coordinador ve capturistas de su municipio
CREATE POLICY "usuarios_coordinador_select"
    ON usuarios FOR SELECT
    USING (
        get_mi_rol() = 'coordinador'
        AND licencia_id = get_mi_licencia()
        AND (municipio = get_mi_municipio() OR id = auth.uid())
    );

-- lider_seccion ve los capturistas asignados a su sección
CREATE POLICY "usuarios_lider_select"
    ON usuarios FOR SELECT
    USING (
        get_mi_rol() = 'lider_seccion'
        AND licencia_id = get_mi_licencia()
        AND (seccion_base = get_mi_seccion() OR id = auth.uid())
    );

-- capturista solo se ve a sí mismo
CREATE POLICY "usuarios_self_select"
    ON usuarios FOR SELECT
    USING (id = auth.uid());

-- admin puede crear/editar usuarios de su licencia
CREATE POLICY "usuarios_admin_write"
    ON usuarios FOR INSERT
    WITH CHECK (
        get_mi_rol() IN ('superadmin','admin')
        AND licencia_id = get_mi_licencia()
    );

CREATE POLICY "usuarios_admin_update"
    ON usuarios FOR UPDATE
    USING (
        get_mi_rol() IN ('superadmin','admin')
        AND licencia_id = get_mi_licencia()
    );

-- cualquier usuario puede actualizar su propio perfil (último acceso)
CREATE POLICY "usuarios_self_update"
    ON usuarios FOR UPDATE
    USING (id = auth.uid());

-- ══════════════════════════════════════════════════════════════════════
--  POLÍTICAS: ciudadanos
--  Tabla de mayor volumen — RLS crítico para performance
-- ══════════════════════════════════════════════════════════════════════

-- superadmin y admin ven todos los ciudadanos de su licencia
CREATE POLICY "ciudadanos_admin_select"
    ON ciudadanos FOR SELECT
    USING (
        get_mi_rol() = 'superadmin'
        OR (
            get_mi_rol() = 'admin'
            AND licencia_id = get_mi_licencia()
        )
    );

-- coordinador ve ciudadanos de su municipio
CREATE POLICY "ciudadanos_coordinador_select"
    ON ciudadanos FOR SELECT
    USING (
        get_mi_rol() = 'coordinador'
        AND licencia_id = get_mi_licencia()
        AND municipio = get_mi_municipio()
    );

-- lider_seccion ve solo ciudadanos de SU sección
CREATE POLICY "ciudadanos_lider_select"
    ON ciudadanos FOR SELECT
    USING (
        get_mi_rol() = 'lider_seccion'
        AND licencia_id = get_mi_licencia()
        AND seccion_electoral = get_mi_seccion()
    );

-- capturista ve ciudadanos cuyo responsable es él O que él capturó
CREATE POLICY "ciudadanos_capturista_select"
    ON ciudadanos FOR SELECT
    USING (
        get_mi_rol() = 'capturista'
        AND licencia_id = get_mi_licencia()
        AND (
            responsable_id = auth.uid()
            OR capturista_id = auth.uid()
        )
    );

-- capturista puede insertar ciudadanos en su licencia
-- La asignación de responsable_id se hace en el servidor (Edge Function o trigger)
CREATE POLICY "ciudadanos_capturista_insert"
    ON ciudadanos FOR INSERT
    WITH CHECK (
        get_mi_rol() IN ('superadmin','admin','coordinador','capturista')
        AND licencia_id = get_mi_licencia()
    );

-- coordinador y admin pueden editar ciudadanos de su ámbito
CREATE POLICY "ciudadanos_coordinador_update"
    ON ciudadanos FOR UPDATE
    USING (
        get_mi_rol() IN ('superadmin','admin')
        AND licencia_id = get_mi_licencia()
    );

CREATE POLICY "ciudadanos_coord_update_municipio"
    ON ciudadanos FOR UPDATE
    USING (
        get_mi_rol() = 'coordinador'
        AND licencia_id = get_mi_licencia()
        AND municipio = get_mi_municipio()
    );

-- ══════════════════════════════════════════════════════════════════════
--  POLÍTICAS: ciudadanos_candidaturas
-- ══════════════════════════════════════════════════════════════════════
CREATE POLICY "cc_select"
    ON ciudadanos_candidaturas FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM ciudadanos c
            WHERE c.id = ciudadano_id
            AND (
                get_mi_rol() = 'superadmin'
                OR c.licencia_id = get_mi_licencia()
            )
        )
    );

CREATE POLICY "cc_insert"
    ON ciudadanos_candidaturas FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM ciudadanos c
            WHERE c.id = ciudadano_id
            AND c.licencia_id = get_mi_licencia()
        )
        AND EXISTS (
            SELECT 1 FROM candidaturas ca
            WHERE ca.id = candidatura_id
            AND ca.licencia_id = get_mi_licencia()
        )
    );

CREATE POLICY "cc_update"
    ON ciudadanos_candidaturas FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM ciudadanos c
            WHERE c.id = ciudadano_id
            AND (
                get_mi_rol() = 'superadmin'
                OR c.licencia_id = get_mi_licencia()
            )
        )
    );

-- ══════════════════════════════════════════════════════════════════════
--  POLÍTICAS: casillas
-- ══════════════════════════════════════════════════════════════════════
CREATE POLICY "casillas_select"
    ON casillas FOR SELECT
    USING (
        get_mi_rol() = 'superadmin'
        OR licencia_id = get_mi_licencia()
    );

-- representante de casilla puede actualizar su casilla
CREATE POLICY "casillas_representante_update"
    ON casillas FOR UPDATE
    USING (
        licencia_id = get_mi_licencia()
        AND (
            get_mi_rol() IN ('superadmin','admin','coordinador')
            OR representante_id = auth.uid()
        )
    );

-- ══════════════════════════════════════════════════════════════════════
--  POLÍTICAS: audit_log
-- ══════════════════════════════════════════════════════════════════════
-- solo superadmin y admin pueden leer el audit log
CREATE POLICY "audit_select"
    ON audit_log FOR SELECT
    USING (
        get_mi_rol() = 'superadmin'
        OR (
            get_mi_rol() = 'admin'
            AND licencia_id = get_mi_licencia()
        )
    );

-- cualquier rol autenticado puede insertar en audit_log (acciones propias)
CREATE POLICY "audit_insert"
    ON audit_log FOR INSERT
    WITH CHECK (auth.uid() IS NOT NULL);

-- ══════════════════════════════════════════════════════════════════════
--  POLÍTICAS: configuracion_sistema
-- ══════════════════════════════════════════════════════════════════════
CREATE POLICY "config_select"
    ON configuracion_sistema FOR SELECT
    USING (
        get_mi_rol() = 'superadmin'
        OR licencia_id = get_mi_licencia()
    );

CREATE POLICY "config_write"
    ON configuracion_sistema FOR ALL
    USING (
        get_mi_rol() IN ('superadmin','admin')
        AND licencia_id = get_mi_licencia()
    )
    WITH CHECK (get_mi_rol() IN ('superadmin','admin'));

-- ══════════════════════════════════════════════════════════════════════
--  FIN DE RLS
--  Continuar con: 03_seed_demo.sql
-- ══════════════════════════════════════════════════════════════════════
