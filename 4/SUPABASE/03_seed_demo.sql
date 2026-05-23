-- ══════════════════════════════════════════════════════════════════════
--  INTELIGENCIA ELECTORAL — Datos Demo (Seed)
--  Archivo: 03_seed_demo.sql
--  Ejecutar TERCERO, después de 02_rls.sql
--
--  IMPORTANTE: Este seed usa datos GENÉRICOS (Partido A, Cliente A)
--  para que el sistema sea demostrable a cualquier partido.
--  Los datos numéricos están basados en los mocks del sistema.
--
--  NOTA SOBRE USUARIOS:
--  Los usuarios de auth.users los crea Supabase Auth.
--  Este script usa UUIDs fijos para los datos demo.
--  El desarrollador deberá crear los usuarios en el panel de Auth
--  con los mismos UUIDs o ajustar los FKs.
-- ══════════════════════════════════════════════════════════════════════

-- ── UUIDs fijos para demo (no cambiar — los módulos los referencian) ──
-- Licencia demo:       'lic-demo-0000-0000-000000000001'
-- Superadmin:          'usr-super-0000-0000-000000000001'
-- Admin (candidato):   'usr-admin-0000-0000-000000000001'
-- Coordinador MZL:     'usr-cord-0000-0000-000000000001'
-- Coordinador COL:     'usr-cord-0000-0000-000000000002'
-- Capturista 017:      'usr-cap-0000-0000-000000000017'
-- Candidatura GBR:     'cand-gbr-0000-0000-000000000001'

-- ══════════════════════════════════════════════════════════════════════
--  1. LICENCIA DEMO
-- ══════════════════════════════════════════════════════════════════════
INSERT INTO licencias (
    id, clave, tipo, estado, meta_estatal, anio_eleccion,
    fecha_eleccion, fecha_inicio, fecha_vencimiento, max_usuarios, activa, notas
) VALUES (
    'a1b2c3d4-0001-0000-0000-000000000001',
    'DEMO-2027',
    'estado',
    'Estado Demo',
    197297,
    2027,
    '2027-06-01',
    '2026-01-01',
    '2027-07-31',
    50,
    TRUE,
    'Licencia de demostración — datos genéricos para presentaciones'
) ON CONFLICT (clave) DO NOTHING;

-- ══════════════════════════════════════════════════════════════════════
--  2. CANDIDATURAS DEMO
--  Basadas en CANDIDATURAS array de modulo_admin.html
-- ══════════════════════════════════════════════════════════════════════
INSERT INTO candidaturas (id, licencia_id, codigo, nombre, tipo, territorio, meta, activa) VALUES
    ('a1b2c3d4-0001-0000-0000-000000000101', 'a1b2c3d4-0001-0000-0000-000000000001',
     'CAND-001', 'Candidato a Gobernador',           'gobernador',   'Estado Demo',         197297, TRUE),
    ('a1b2c3d4-0001-0000-0000-000000000102', 'a1b2c3d4-0001-0000-0000-000000000001',
     'CAND-002', 'Candidato a Senador',               'senador',      'Estado Demo',         197297, TRUE),
    ('a1b2c3d4-0001-0000-0000-000000000103', 'a1b2c3d4-0001-0000-0000-000000000001',
     'CAND-003', 'Diputado Federal Dist. 1',          'dip_federal',  'Distrito Federal 1',   98648, TRUE),
    ('a1b2c3d4-0001-0000-0000-000000000104', 'a1b2c3d4-0001-0000-0000-000000000001',
     'CAND-004', 'Diputado Federal Dist. 2',          'dip_federal',  'Distrito Federal 2',   98649, TRUE),
    ('a1b2c3d4-0001-0000-0000-000000000105', 'a1b2c3d4-0001-0000-0000-000000000001',
     'CAND-005', 'Diputado Local Dist. 1',            'dip_local',    'Distrito Local 1',     18200, TRUE),
    ('a1b2c3d4-0001-0000-0000-000000000106', 'a1b2c3d4-0001-0000-0000-000000000001',
     'CAND-006', 'Diputado Local Dist. 4',            'dip_local',    'Distrito Local 4',     22400, TRUE),
    ('a1b2c3d4-0001-0000-0000-000000000107', 'a1b2c3d4-0001-0000-0000-000000000001',
     'CAND-007', 'Presidente Municipal — Ciudad A',   'presidente',   'Ciudad A',             48030, TRUE),
    ('a1b2c3d4-0001-0000-0000-000000000108', 'a1b2c3d4-0001-0000-0000-000000000001',
     'CAND-008', 'Presidente Municipal — Ciudad B',   'presidente',   'Ciudad B',             51442, TRUE),
    ('a1b2c3d4-0001-0000-0000-000000000109', 'a1b2c3d4-0001-0000-0000-000000000001',
     'CAND-009', 'Presidente Municipal — Ciudad C',   'presidente',   'Ciudad C',             34952, TRUE),
    ('a1b2c3d4-0001-0000-0000-000000000110', 'a1b2c3d4-0001-0000-0000-000000000001',
     'CAND-010', 'Presidente Municipal — Ciudad D',   'presidente',   'Ciudad D',             29211, TRUE)
ON CONFLICT (licencia_id, codigo) DO NOTHING;

-- ══════════════════════════════════════════════════════════════════════
--  3. MUNICIPIOS DEMO
--  Basados en MUNS array de war_room_electoral_colima.html
--  Nombres genéricos para demo partido-neutral
-- ══════════════════════════════════════════════════════════════════════
INSERT INTO municipios (
    id, licencia_id, codigo, nombre, distrito_federal,
    total_secciones, total_casillas, votos_2024, ganador_2024, pct_ganador_2024
) VALUES
    ('a1b2c3d4-0001-0000-0000-000000000201', 'a1b2c3d4-0001-0000-0000-000000000001',
     'MUN-A', 'Ciudad A', 'DF2', 99, 203, 5180, 'Partido A', 45.4),
    ('a1b2c3d4-0001-0000-0000-000000000202', 'a1b2c3d4-0001-0000-0000-000000000001',
     'MUN-B', 'Ciudad B', 'DF2', 79, 316, 8420, 'Partido A', 47.9),
    ('a1b2c3d4-0001-0000-0000-000000000203', 'a1b2c3d4-0001-0000-0000-000000000001',
     'MUN-C', 'Ciudad C', 'DF1', 70, 169, 5220, 'Partido A', 47.0),
    ('a1b2c3d4-0001-0000-0000-000000000204', 'a1b2c3d4-0001-0000-0000-000000000001',
     'MUN-D', 'Ciudad D', 'DF2', 62, 220, 6820, 'Partido A', 61.7),
    ('a1b2c3d4-0001-0000-0000-000000000205', 'a1b2c3d4-0001-0000-0000-000000000001',
     'MUN-E', 'Ciudad E', 'DF1', 32, 47,  2310, 'Partido A', 50.4),
    ('a1b2c3d4-0001-0000-0000-000000000206', 'a1b2c3d4-0001-0000-0000-000000000001',
     'MUN-F', 'Ciudad F', 'DF1', 22, 34,  1640, 'Partido A', 47.7),
    ('a1b2c3d4-0001-0000-0000-000000000207', 'a1b2c3d4-0001-0000-0000-000000000001',
     'MUN-G', 'Ciudad G', 'DF2', 21, 16,  2030, 'Partido A', 60.4),
    ('a1b2c3d4-0001-0000-0000-000000000208', 'a1b2c3d4-0001-0000-0000-000000000001',
     'MUN-H', 'Ciudad H', 'DF1', 23, 29,  1820, 'Partido B', 52.7),
    ('a1b2c3d4-0001-0000-0000-000000000209', 'a1b2c3d4-0001-0000-0000-000000000001',
     'MUN-I', 'Ciudad I', 'DF2', 14, 15,  1440, 'Partido A', 64.1),
    ('a1b2c3d4-0001-0000-0000-000000000210', 'a1b2c3d4-0001-0000-0000-000000000001',
     'MUN-J', 'Ciudad J', 'DF2', 12, 11,  1280, 'Partido A', 61.4)
ON CONFLICT (licencia_id, codigo) DO NOTHING;

-- ══════════════════════════════════════════════════════════════════════
--  4. DISTRITOS DEMO
-- ══════════════════════════════════════════════════════════════════════
INSERT INTO distritos (id, licencia_id, codigo, nombre, tipo) VALUES
    ('a1b2c3d4-0001-0000-0000-000000000301', 'a1b2c3d4-0001-0000-0000-000000000001',
     'DF1', 'Distrito Federal 1', 'federal'),
    ('a1b2c3d4-0001-0000-0000-000000000302', 'a1b2c3d4-0001-0000-0000-000000000001',
     'DF2', 'Distrito Federal 2', 'federal'),
    ('a1b2c3d4-0001-0000-0000-000000000303', 'a1b2c3d4-0001-0000-0000-000000000001',
     'DL1', 'Distrito Local 1', 'local'),
    ('a1b2c3d4-0001-0000-0000-000000000304', 'a1b2c3d4-0001-0000-0000-000000000001',
     'DL2', 'Distrito Local 2', 'local'),
    ('a1b2c3d4-0001-0000-0000-000000000305', 'a1b2c3d4-0001-0000-0000-000000000001',
     'DL3', 'Distrito Local 3', 'local'),
    ('a1b2c3d4-0001-0000-0000-000000000306', 'a1b2c3d4-0001-0000-0000-000000000001',
     'DL4', 'Distrito Local 4', 'local')
ON CONFLICT (licencia_id, codigo) DO NOTHING;

-- ══════════════════════════════════════════════════════════════════════
--  5. SECCIONES ELECTORALES (muestra representativa)
--  Basadas en SECCIONES array de mapa_secciones_v2.html
--  Solo las primeras ~20 para demo — el cliente carga su Excel completo
-- ══════════════════════════════════════════════════════════════════════
INSERT INTO secciones_electorales (
    licencia_id, municipio_id, numero_seccion, municipio_nombre, estado_nombre,
    total_nominilla, meta_seccion, meta_original, dificultad, semaforo,
    ganador_2024, pos_x, pos_y
) VALUES
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000204',
     101, 'Ciudad D', 'Estado Demo', 4072,  1242, 1613, 'DIFICIL', 'ALTO', 'Partido A', 0.38, 0.72),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000204',
     102, 'Ciudad D', 'Estado Demo', 1135,   387,  503, 'DIFICIL', 'ALTO', 'Partido A', 0.41, 0.68),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000204',
     103, 'Ciudad D', 'Estado Demo', 3355,  1130, 1468, 'DIFICIL', 'ALTO', 'Partido A', 0.43, 0.70),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000204',
     104, 'Ciudad D', 'Estado Demo', 1315,   469,  609, 'MEDIO',   'ALTO', 'Partido A', 0.40, 0.69),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000204',
     105, 'Ciudad D', 'Estado Demo', 9558,  2478, 3218, 'DIFICIL', 'ALTO', 'Partido A', 0.34, 0.76),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000201',
     131, 'Ciudad A', 'Estado Demo',  965,   376,  488, 'MEDIO',   'ALTO', 'Partido A', 0.54, 0.33),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000201',
     132, 'Ciudad A', 'Estado Demo', 1262,   382,  496, 'MEDIO',   'MEDIO','Partido A', 0.58, 0.37),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000201',
     133, 'Ciudad A', 'Estado Demo', 1832,   571,  741, 'MEDIO',   'MEDIO','Partido A', 0.56, 0.24),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000201',
     134, 'Ciudad A', 'Estado Demo', 2317,   768,  997, 'MEDIO',   'MEDIO','Partido A', 0.58, 0.22),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000203',
     138, 'Ciudad C', 'Estado Demo', 7261,  2200, 2857, 'MEDIO',   'MEDIO','Partido A', 0.56, 0.21),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000203',
     139, 'Ciudad C', 'Estado Demo', 3100,   980, 1273, 'MEDIO',   'MEDIO','Partido A', 0.55, 0.22),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000203',
     140, 'Ciudad C', 'Estado Demo', 2850,   853, 1108, 'MEDIO',   'BAJO', 'Partido A', 0.54, 0.23),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000203',
     141, 'Ciudad C', 'Estado Demo', 1943,   604,  784, 'MEDIO',   'BAJO', 'Partido A', 0.57, 0.23),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000202',
     201, 'Ciudad B', 'Estado Demo', 1828,   490,  636, 'MEDIO',   'MEDIO','Partido A', 0.20, 0.52),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000202',
     202, 'Ciudad B', 'Estado Demo', 1734,   657,  853, 'DIFICIL', 'MEDIO','Partido A', 0.17, 0.52),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000202',
     203, 'Ciudad B', 'Estado Demo', 1691,   689,  895, 'MEDIO',   'MEDIO','Partido A', 0.15, 0.54),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000207',
     178, 'Ciudad G', 'Estado Demo', 1241,   263,  342, 'MEDIO',   'ALTO', 'Partido A', 0.22, 0.73),
    ('a1b2c3d4-0001-0000-0000-000000000001', 'a1b2c3d4-0001-0000-0000-000000000207',
     179, 'Ciudad G', 'Estado Demo',  891,   202,  262, 'MEDIO',   'MEDIO','Partido A', 0.21, 0.72)
ON CONFLICT (licencia_id, numero_seccion) DO NOTHING;

-- ══════════════════════════════════════════════════════════════════════
--  6. CONFIGURACIÓN DE SISTEMA DEMO
-- ══════════════════════════════════════════════════════════════════════
INSERT INTO configuracion_sistema (
    licencia_id, partido_nombre, partido_slogan, logo_inicial,
    color_primario, color_secundario,
    sistema_estado, sistema_meta, sistema_anio, fecha_eleccion
) VALUES (
    'a1b2c3d4-0001-0000-0000-000000000001',
    'Inteligencia Electoral',
    'Sistema de control territorial',
    'IE',
    '#3b82f6',
    '#06b6d4',
    'Estado Demo',
    197297,
    2027,
    '2027-06-01'
) ON CONFLICT (licencia_id) DO NOTHING;

-- ══════════════════════════════════════════════════════════════════════
--  NOTA SOBRE USUARIOS:
--  Los usuarios se insertan en auth.users a través del panel de Supabase
--  o mediante la API de Auth. NO se pueden insertar directamente aquí.
--
--  Después de crear los usuarios en Auth, ejecutar 04_usuarios_demo.sql
--  (que asume que ya existen los auth.users correspondientes).
-- ══════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════
--  FIN DEL SEED DEMO
--  Continuar con: 04_usuarios_demo.sql (después de crear auth.users)
-- ══════════════════════════════════════════════════════════════════════
