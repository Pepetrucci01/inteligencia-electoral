-- ══════════════════════════════════════════════════════════════════════
--  INTELIGENCIA ELECTORAL — Schema Principal
--  Archivo: 01_schema.sql
--  Ejecutar PRIMERO en: Supabase → SQL Editor
--  Orden de ejecución: este archivo completo de arriba a abajo
-- ══════════════════════════════════════════════════════════════════════

-- Habilitar extensiones necesarias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ══════════════════════════════════════════════════════════════════════
--  TABLA 1: licencias
--  Una licencia = un cliente (partido en un estado)
--  Una licencia puede tener N usuarios y N candidaturas
-- ══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS licencias (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clave           TEXT NOT NULL UNIQUE,          -- ej: "COL-2027", "JAL-2027"
    tipo            TEXT NOT NULL                  -- 'distrito' | 'estado' | 'enterprise'
                    CHECK (tipo IN ('distrito','estado','enterprise')),
    estado          TEXT NOT NULL,                 -- nombre del estado: "Colima", "Jalisco"
    municipio       TEXT,                          -- solo si tipo = 'distrito'
    meta_estatal    INTEGER NOT NULL DEFAULT 0,    -- meta total de capturas
    anio_eleccion   INTEGER NOT NULL DEFAULT 2027,
    fecha_eleccion  DATE,                          -- ej: 2027-06-01
    fecha_inicio    DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_vencimiento DATE NOT NULL,
    max_usuarios    INTEGER NOT NULL DEFAULT 10,
    activa          BOOLEAN NOT NULL DEFAULT TRUE,
    notas           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ
);

-- ══════════════════════════════════════════════════════════════════════
--  TABLA 2: candidaturas
--  Cada candidatura es una "carrera electoral" dentro de una licencia
--  Un cliente puede tener: gobernador + diputados + presidentes mpal
-- ══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS candidaturas (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    licencia_id     UUID NOT NULL REFERENCES licencias(id) ON DELETE CASCADE,
    codigo          TEXT NOT NULL,                 -- ej: "CAND-001"
    nombre          TEXT NOT NULL,                 -- ej: "Candidato a Gobernador"
    tipo            TEXT NOT NULL                  -- ver CHECK abajo
                    CHECK (tipo IN (
                        'gobernador','senador','dip_federal',
                        'dip_local','presidente','regidor','sindico'
                    )),
    territorio      TEXT NOT NULL,                 -- ej: "Estado de Colima", "Distrito Federal 1"
    meta            INTEGER NOT NULL DEFAULT 0,    -- meta de capturas para esta candidatura
    fecha_eleccion  DATE,
    activa          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ,
    UNIQUE(licencia_id, codigo)
);

-- ══════════════════════════════════════════════════════════════════════
--  TABLA 3: municipios
--  Catálogo geográfico de municipios de la licencia
-- ══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS municipios (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    licencia_id     UUID NOT NULL REFERENCES licencias(id) ON DELETE CASCADE,
    codigo          TEXT NOT NULL,                 -- ej: "VDA", "MAN", "COL"
    nombre          TEXT NOT NULL,                 -- ej: "Villa de Álvarez"
    distrito_federal TEXT,                         -- ej: "DF1", "DF2"
    total_secciones INTEGER NOT NULL DEFAULT 0,
    total_casillas  INTEGER NOT NULL DEFAULT 0,
    votos_2024      INTEGER NOT NULL DEFAULT 0,    -- votos históricos referencia
    ganador_2024    TEXT,                          -- "Partido A", "Partido B"
    pct_ganador_2024 NUMERIC(5,2),                 -- porcentaje
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(licencia_id, codigo)
);

-- ══════════════════════════════════════════════════════════════════════
--  TABLA 4: distritos
--  Distritos electorales (federales y locales)
-- ══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS distritos (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    licencia_id     UUID NOT NULL REFERENCES licencias(id) ON DELETE CASCADE,
    codigo          TEXT NOT NULL,                 -- ej: "DF1", "DL3"
    nombre          TEXT NOT NULL,
    tipo            TEXT NOT NULL CHECK (tipo IN ('federal','local')),
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(licencia_id, codigo)
);

-- Tabla puente: qué municipios pertenecen a qué distrito
CREATE TABLE IF NOT EXISTS distritos_municipios (
    distrito_id     UUID NOT NULL REFERENCES distritos(id) ON DELETE CASCADE,
    municipio_id    UUID NOT NULL REFERENCES municipios(id) ON DELETE CASCADE,
    PRIMARY KEY(distrito_id, municipio_id)
);

-- ══════════════════════════════════════════════════════════════════════
--  TABLA 5: secciones_electorales
--  Sección electoral = unidad mínima del padrón INE
--  Es el objeto central del mapa territorial
-- ══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS secciones_electorales (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    licencia_id     UUID NOT NULL REFERENCES licencias(id) ON DELETE CASCADE,
    municipio_id    UUID REFERENCES municipios(id),
    numero_seccion  INTEGER NOT NULL,              -- número oficial INE
    municipio_nombre TEXT NOT NULL,
    estado_nombre   TEXT NOT NULL,
    -- Datos electorales
    total_nominilla INTEGER NOT NULL DEFAULT 0,    -- lista nominal (nm en el mapa)
    meta_seccion    INTEGER NOT NULL DEFAULT 0,    -- meta de capturas calculada
    meta_original   INTEGER NOT NULL DEFAULT 0,    -- meta antes de ajuste afluencia
    dificultad      TEXT CHECK (dificultad IN ('FACIL','MEDIO','DIFICIL')),
    semaforo        TEXT CHECK (semaforo IN ('ALTO','MEDIO','BAJO')),
    ganador_2024    TEXT,
    -- Posición en el canvas del mapa (porcentaje 0-1)
    pos_x           NUMERIC(5,4),
    pos_y           NUMERIC(5,4),
    -- Responsable territorial asignado (FK a usuarios — se llena después)
    responsable_id  UUID,                          -- FK → usuarios.id (se agrega después)
    activa          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(licencia_id, numero_seccion)
);

-- ══════════════════════════════════════════════════════════════════════
--  TABLA 6: usuarios
--  Extiende auth.users de Supabase con datos del sistema
--  IMPORTANTE: auth.users es manejado por Supabase Auth automáticamente
-- ══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS usuarios (
    id              UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    licencia_id     UUID NOT NULL REFERENCES licencias(id),
    codigo          TEXT NOT NULL,                 -- ej: "CAP-017", "CORD-MZL"
    nombre          TEXT NOT NULL,
    email           TEXT NOT NULL,
    rol             TEXT NOT NULL
                    CHECK (rol IN ('superadmin','admin','coordinador','lider_seccion','capturista')),
    municipio       TEXT,                          -- municipio asignado
    seccion_base    INTEGER,                       -- sección base (capturistas)
    candidatura_id  UUID REFERENCES candidaturas(id), -- candidatura por defecto
    meta_individual INTEGER NOT NULL DEFAULT 50,   -- meta personal de capturas
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    status          TEXT NOT NULL DEFAULT 'activo'
                    CHECK (status IN ('activo','pendiente','bloqueado')),
    ultimo_acceso   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ,
    UNIQUE(licencia_id, codigo)
);

-- Ahora sí podemos agregar la FK de secciones a usuarios
ALTER TABLE secciones_electorales
    ADD CONSTRAINT fk_seccion_responsable
    FOREIGN KEY (responsable_id) REFERENCES usuarios(id);

-- ══════════════════════════════════════════════════════════════════════
--  TABLA 7: ciudadanos
--  Registro central de personas capturadas
--  Es la tabla de mayor volumen — puede llegar a 200k+ por licencia
-- ══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS ciudadanos (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    licencia_id         UUID NOT NULL REFERENCES licencias(id),
    -- Datos personales
    nombre              TEXT NOT NULL,
    edad                INTEGER,
    sexo                TEXT CHECK (sexo IN ('HOMBRE','MUJER','OTRO')),
    telefono            TEXT,
    curp                TEXT,
    -- Ubicación electoral
    seccion_electoral   INTEGER NOT NULL,
    municipio           TEXT NOT NULL,
    -- Asignación (regla de negocio crítica)
    responsable_id      UUID REFERENCES usuarios(id),  -- responsable de SU sección
    capturista_id       UUID REFERENCES usuarios(id),  -- quien capturó (solo auditoría)
    -- Nivel de compromiso
    -- 1=Contacto, 2=Simpatiza, 3=Seguro vota, 4=Moviliza
    compromiso          INTEGER NOT NULL DEFAULT 1
                        CHECK (compromiso BETWEEN 1 AND 4),
    -- Características
    es_influencia       BOOLEAN NOT NULL DEFAULT FALSE,  -- moviliza a otros
    es_apoyo            BOOLEAN NOT NULL DEFAULT FALSE,  -- apoya logísticamente
    es_riesgo           BOOLEAN NOT NULL DEFAULT FALSE,  -- puede votar en contra
    -- Canal de captación
    origen              TEXT CHECK (origen IN (
                            'Casa por casa','Referido','Digital',
                            'Evento','Otro'
                        )),
    -- Validación
    validado            BOOLEAN NOT NULL DEFAULT FALSE,
    duplicado           BOOLEAN NOT NULL DEFAULT FALSE,
    -- Sincronización PWA offline
    sync_status         TEXT NOT NULL DEFAULT 'synced'
                        CHECK (sync_status IN ('pending','synced','conflict')),
    -- Timestamps
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ,
    -- Un ciudadano puede estar en varias candidaturas (ver tabla pivot)
    notas               TEXT
);

-- ══════════════════════════════════════════════════════════════════════
--  TABLA 8: ciudadanos_candidaturas  (tabla pivot)
--  Un ciudadano puede tener DIFERENTE nivel de compromiso
--  según la candidatura. Esta es la tabla que maneja eso.
-- ══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS ciudadanos_candidaturas (
    ciudadano_id    UUID NOT NULL REFERENCES ciudadanos(id) ON DELETE CASCADE,
    candidatura_id  UUID NOT NULL REFERENCES candidaturas(id) ON DELETE CASCADE,
    compromiso      INTEGER NOT NULL DEFAULT 1 CHECK (compromiso BETWEEN 1 AND 4),
    voto_confirmado BOOLEAN NOT NULL DEFAULT FALSE,  -- día de elección
    hora_voto       TIMESTAMPTZ,                     -- cuándo votó
    notas           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ,
    PRIMARY KEY(ciudadano_id, candidatura_id)
);

-- ══════════════════════════════════════════════════════════════════════
--  TABLA 9: casillas
--  Casillas electorales por sección
--  Se usan en War Room y Módulo Día de Elección
-- ══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS casillas (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    licencia_id     UUID NOT NULL REFERENCES licencias(id),
    seccion_id      UUID REFERENCES secciones_electorales(id),
    numero_seccion  INTEGER NOT NULL,
    numero_casilla  INTEGER NOT NULL,
    tipo            TEXT CHECK (tipo IN ('Básica','Contigua','Especial','Extraordinaria')),
    municipio       TEXT NOT NULL,
    colonia         TEXT,
    calle           TEXT,
    lugar           TEXT,                          -- ej: "Escuela primaria"
    representante_id UUID REFERENCES usuarios(id),
    -- Estado el día de elección
    estatus         TEXT NOT NULL DEFAULT 'sinreporte'
                    CHECK (estatus IN ('sinreporte','abierta','incidencia','cerrada')),
    hora_apertura   TIMESTAMPTZ,
    hora_cierre     TIMESTAMPTZ,
    votos_favor     INTEGER,
    votos_contra    INTEGER,
    votos_nulos     INTEGER,
    incidencia_desc TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ,
    UNIQUE(licencia_id, numero_seccion, numero_casilla)
);

-- ══════════════════════════════════════════════════════════════════════
--  TABLA 10: audit_log
--  Registro de todas las acciones importantes del sistema
--  Se usa en modulo_admin.html → pestaña "Auditoría"
-- ══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS audit_log (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    licencia_id     UUID REFERENCES licencias(id),
    usuario_id      UUID REFERENCES usuarios(id),
    usuario_nombre  TEXT,                          -- desnormalizado por si se borra el usuario
    accion          TEXT NOT NULL,                 -- ej: "CREAR_CIUDADANO", "EDITAR_USUARIO"
    tabla           TEXT,                          -- tabla afectada
    registro_id     UUID,                          -- id del registro afectado
    detalle         JSONB,                         -- datos antes/después
    ip_address      TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ══════════════════════════════════════════════════════════════════════
--  TABLA 11: configuracion_sistema
--  Guarda el tema y configuración por licencia
--  Reemplaza el localStorage del theme.js para persistencia real
-- ══════════════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS configuracion_sistema (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    licencia_id     UUID NOT NULL REFERENCES licencias(id) UNIQUE,
    -- Identidad visual (espeja DEFAULT_THEME de theme.js)
    partido_nombre  TEXT NOT NULL DEFAULT 'Inteligencia Electoral',
    partido_slogan  TEXT NOT NULL DEFAULT 'Sistema de control territorial',
    logo_url        TEXT,
    logo_inicial    TEXT NOT NULL DEFAULT 'IE',
    -- Paleta de colores
    color_primario      TEXT NOT NULL DEFAULT '#3b82f6',
    color_secundario    TEXT NOT NULL DEFAULT '#06b6d4',
    color_alerta        TEXT NOT NULL DEFAULT '#ef4444',
    color_exito         TEXT NOT NULL DEFAULT '#22c55e',
    color_advertencia   TEXT NOT NULL DEFAULT '#f59e0b',
    -- Fondos
    bg_base         TEXT NOT NULL DEFAULT '#0a0e1a',
    bg_panel        TEXT NOT NULL DEFAULT '#0f1526',
    bg_card         TEXT NOT NULL DEFAULT '#141b2e',
    bg_card2        TEXT NOT NULL DEFAULT '#1a2238',
    -- Datos operativos
    sistema_estado  TEXT NOT NULL DEFAULT 'Estado',
    sistema_meta    INTEGER NOT NULL DEFAULT 0,
    sistema_anio    INTEGER NOT NULL DEFAULT 2027,
    fecha_eleccion  DATE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ
);

-- ══════════════════════════════════════════════════════════════════════
--  ÍNDICES  (mejoran velocidad de las consultas más comunes)
-- ══════════════════════════════════════════════════════════════════════

-- ciudadanos: consultas por sección, municipio, candidatura, responsable
CREATE INDEX IF NOT EXISTS idx_ciudadanos_licencia       ON ciudadanos(licencia_id);
CREATE INDEX IF NOT EXISTS idx_ciudadanos_seccion        ON ciudadanos(seccion_electoral);
CREATE INDEX IF NOT EXISTS idx_ciudadanos_municipio      ON ciudadanos(municipio);
CREATE INDEX IF NOT EXISTS idx_ciudadanos_responsable    ON ciudadanos(responsable_id);
CREATE INDEX IF NOT EXISTS idx_ciudadanos_capturista     ON ciudadanos(capturista_id);
CREATE INDEX IF NOT EXISTS idx_ciudadanos_compromiso     ON ciudadanos(compromiso);
CREATE INDEX IF NOT EXISTS idx_ciudadanos_sync           ON ciudadanos(sync_status) WHERE sync_status = 'pending';

-- ciudadanos_candidaturas: consultas por candidatura (war room y reportes)
CREATE INDEX IF NOT EXISTS idx_cc_candidatura            ON ciudadanos_candidaturas(candidatura_id);
CREATE INDEX IF NOT EXISTS idx_cc_ciudadano              ON ciudadanos_candidaturas(ciudadano_id);

-- usuarios: consultas por licencia y rol
CREATE INDEX IF NOT EXISTS idx_usuarios_licencia         ON usuarios(licencia_id);
CREATE INDEX IF NOT EXISTS idx_usuarios_rol              ON usuarios(rol);

-- secciones: consultas por municipio y responsable
CREATE INDEX IF NOT EXISTS idx_secciones_licencia        ON secciones_electorales(licencia_id);
CREATE INDEX IF NOT EXISTS idx_secciones_municipio       ON secciones_electorales(municipio_nombre);
CREATE INDEX IF NOT EXISTS idx_secciones_numero          ON secciones_electorales(numero_seccion);

-- audit_log: consultas recientes por licencia
CREATE INDEX IF NOT EXISTS idx_audit_licencia            ON audit_log(licencia_id);
CREATE INDEX IF NOT EXISTS idx_audit_created             ON audit_log(created_at DESC);

-- casillas: consultas por sección
CREATE INDEX IF NOT EXISTS idx_casillas_seccion          ON casillas(numero_seccion);
CREATE INDEX IF NOT EXISTS idx_casillas_licencia         ON casillas(licencia_id);

-- ══════════════════════════════════════════════════════════════════════
--  TRIGGER: updated_at automático
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_licencias_updated
    BEFORE UPDATE ON licencias
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_candidaturas_updated
    BEFORE UPDATE ON candidaturas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_usuarios_updated
    BEFORE UPDATE ON usuarios
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_ciudadanos_updated
    BEFORE UPDATE ON ciudadanos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_ciudadanos_cands_updated
    BEFORE UPDATE ON ciudadanos_candidaturas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_casillas_updated
    BEFORE UPDATE ON casillas
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_config_updated
    BEFORE UPDATE ON configuracion_sistema
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ══════════════════════════════════════════════════════════════════════
--  FIN DEL SCHEMA
--  Continuar con: 02_rls.sql
-- ══════════════════════════════════════════════════════════════════════
