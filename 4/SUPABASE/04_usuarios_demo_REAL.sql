-- ══════════════════════════════════════════════════════════════════════
--  INTELIGENCIA ELECTORAL — Usuarios Demo
--  Archivo: 04_usuarios_demo.sql
--  Ejecutar CUARTO
--
--  PRE-REQUISITO: Crear primero los usuarios en Supabase Auth:
--  Panel de Supabase → Authentication → Users → "Add user"
--
--  Usuarios a crear en Auth (email + password):
--  ┌─────────────────────────┬────────────────┬─────────────────────────────────────┐
--  │ Email                   │ Password       │ UUID a copiar para este script      │
--  ├─────────────────────────┼────────────────┼─────────────────────────────────────┤
--  │ admin@sistema.mx        │ Admin2027!     │ (copiar el UUID que genera Supabase) │
--  │ candidato@demo.mx       │ Demo2027!      │ (copiar el UUID que genera Supabase) │
--  │ coord.a@demo.mx         │ Coord2027!     │ (copiar el UUID que genera Supabase) │
--  │ coord.b@demo.mx         │ Coord2027!     │ (copiar el UUID que genera Supabase) │
--  │ cap017@demo.mx          │ Cap2027!       │ (copiar el UUID que genera Supabase) │
--  │ cap018@demo.mx          │ Cap2027!       │ (copiar el UUID que genera Supabase) │
--  └─────────────────────────┴────────────────┴─────────────────────────────────────┘
--
--  Después de crearlos, reemplazar los UUIDs de abajo con los reales
--  o ejecutar este script con los UUIDs placeholder primero y actualizarlos.
-- ══════════════════════════════════════════════════════════════════════

-- ── INSTRUCCIONES PARA EL DESARROLLADOR ──────────────────────────────
-- 1. Ir a Supabase → Authentication → Users
-- 2. Crear cada usuario con "Add user" (email + password)
-- 3. Copiar el UUID auto-generado por Supabase para cada uno
-- 4. Reemplazar los UUIDs placeholder de abajo con los reales
-- 5. Ejecutar este script
-- ─────────────────────────────────────────────────────────────────────

-- REEMPLAZAR ESTOS UUIDs con los que genera Supabase Auth:
-- (estos son solo ejemplos — Supabase genera UUIDs distintos)
DO $$
DECLARE
    v_lic     UUID := 'a1b2c3d4-0001-0000-0000-000000000001';
    -- Reemplazar cada uno con el UUID real de Supabase Auth:
    v_super   UUID := '0cdb0073-6ecf-481a-ab3f-2bccdb59efc4'; -- admin@sistema.mx ✅
    v_admin   UUID := '105287ad-1725-44ab-8447-dbab4b55050e'; -- candidato@demo.mx
    v_cord_a  UUID := '528cb07a-363d-4d77-8eeb-462bbbfd32c6'; -- coord.a@demo.mx
    v_cord_b  UUID := 'aeba6e17-79fc-428c-bc7f-a608239e3338'; -- coord.b@demo.mx
    v_ldr138  UUID := '9ace9b08-0336-4a1b-858c-50d4742809dd'; -- lider138@demo.mx
    v_cap017  UUID := '2fc4dcf7-5205-49be-87f1-e38908b0d1d6'; -- cap017@demo.mx
    v_cap018  UUID := 'ef6e7f9f-5de4-4d6b-a306-f8b64f91a1d8'; -- cap018@demo.mx
BEGIN

    INSERT INTO usuarios (
        id, licencia_id, codigo, nombre, email, rol,
        municipio, seccion_base, meta_individual, activo, status
    ) VALUES
    (
        v_super, v_lic, 'ADM-001', 'Super Administrador', 'admin@sistema.mx',
        'superadmin', NULL, NULL, 0, TRUE, 'activo'
    ),
    (
        v_admin, v_lic, 'ADM-DEMO', 'Administrador Demo', 'candidato@demo.mx',
        'admin', NULL, NULL, 0, TRUE, 'activo'
    ),
    (
        v_cord_a, v_lic, 'CORD-A', 'Coordinador Ciudad A', 'coord.a@demo.mx',
        'coordinador', 'Ciudad A', NULL, 0, TRUE, 'activo'
    ),
    (
        v_cord_b, v_lic, 'CORD-B', 'Coordinador Ciudad B', 'coord.b@demo.mx',
        'coordinador', 'Ciudad B', NULL, 0, TRUE, 'activo'
    ),
    (
        v_ldr138, v_lic, 'LDR-138', 'Líder Sección 138', 'lider138@demo.mx',
        'lider_seccion', 'Ciudad C', 138, 0, TRUE, 'activo'
    ),
    (
        v_cap017, v_lic, 'CAP-017', 'Capturista 017', 'cap017@demo.mx',
        'capturista', 'Ciudad C', 138, 50, TRUE, 'activo'
    ),
    (
        v_cap018, v_lic, 'CAP-018', 'Capturista 018', 'cap018@demo.mx',
        'capturista', 'Ciudad C', 139, 50, TRUE, 'activo'
    )
    ON CONFLICT (id) DO UPDATE SET
        nombre = EXCLUDED.nombre,
        rol    = EXCLUDED.rol,
        status = EXCLUDED.status;

    -- Asignar responsables a secciones (sección 138 → CAP-017, sección 139 → CAP-018)
    UPDATE secciones_electorales
    SET responsable_id = v_cap017
    WHERE licencia_id = v_lic AND numero_seccion IN (138, 140, 141);

    UPDATE secciones_electorales
    SET responsable_id = v_cap018
    WHERE licencia_id = v_lic AND numero_seccion IN (139);

    RAISE NOTICE 'Usuarios demo insertados correctamente.';
END $$;

-- ══════════════════════════════════════════════════════════════════════
--  CIUDADANOS DEMO (10 registros de ejemplo)
--  Basados en CIUDADANOS array de modulo_captura.html
--  IMPORTANTE: Se insertan SIN FK a usuarios para no depender de UUIDs fijos
--  El desarrollador debe actualizarlos con los IDs reales
-- ══════════════════════════════════════════════════════════════════════

-- Este bloque se ejecuta después de que los usuarios estén creados
-- y la tabla secciones tenga responsables asignados

INSERT INTO ciudadanos (
    licencia_id, nombre, edad, sexo, telefono, curp,
    seccion_electoral, municipio,
    compromiso, es_influencia, es_apoyo, es_riesgo,
    origen, validado, duplicado, sync_status
) VALUES
    ('a1b2c3d4-0001-0000-0000-000000000001',
     'Ciudadano Demo 001', 34, 'MUJER', '312-111-0001', NULL,
     138, 'Ciudad C', 3, TRUE,  FALSE, FALSE, 'Casa por casa', TRUE,  FALSE, 'synced'),
    ('a1b2c3d4-0001-0000-0000-000000000001',
     'Ciudadano Demo 002', 52, 'HOMBRE','312-111-0002', NULL,
     138, 'Ciudad C', 4, TRUE,  TRUE,  FALSE, 'Referido',       TRUE,  FALSE, 'synced'),
    ('a1b2c3d4-0001-0000-0000-000000000001',
     'Ciudadano Demo 003', 28, 'MUJER', '312-111-0003', NULL,
     139, 'Ciudad C', 2, FALSE, FALSE, FALSE, 'Digital',        FALSE, FALSE, 'synced'),
    ('a1b2c3d4-0001-0000-0000-000000000001',
     'Ciudadano Demo 004', 45, 'HOMBRE','312-111-0004', NULL,
     138, 'Ciudad C', 3, FALSE, FALSE, TRUE,  'Evento',         TRUE,  FALSE, 'synced'),
    ('a1b2c3d4-0001-0000-0000-000000000001',
     'Ciudadano Demo 005', 31, 'MUJER', '312-111-0005', NULL,
     140, 'Ciudad C', 1, FALSE, TRUE,  FALSE, 'Casa por casa',  FALSE, FALSE, 'synced'),
    ('a1b2c3d4-0001-0000-0000-000000000001',
     'Ciudadano Demo 006', 60, 'HOMBRE','312-111-0006', NULL,
     138, 'Ciudad C', 4, TRUE,  FALSE, FALSE, 'Referido',       TRUE,  FALSE, 'synced'),
    ('a1b2c3d4-0001-0000-0000-000000000001',
     'Ciudadano Demo 007', 22, 'MUJER', '312-111-0007', NULL,
     138, 'Ciudad C', 2, FALSE, FALSE, FALSE, 'Digital',        FALSE, TRUE,  'synced'),
    ('a1b2c3d4-0001-0000-0000-000000000001',
     'Ciudadano Demo 008', 48, 'HOMBRE','312-111-0008', NULL,
     141, 'Ciudad C', 3, FALSE, TRUE,  TRUE,  'Casa por casa',  TRUE,  FALSE, 'synced'),
    ('a1b2c3d4-0001-0000-0000-000000000001',
     'Ciudadano Demo 009', 39, 'MUJER', '312-111-0009', NULL,
     138, 'Ciudad C', 3, TRUE,  FALSE, FALSE, 'Evento',         TRUE,  FALSE, 'synced'),
    ('a1b2c3d4-0001-0000-0000-000000000001',
     'Ciudadano Demo 010', 55, 'HOMBRE','312-111-0010', NULL,
     138, 'Ciudad C', 4, TRUE,  FALSE, FALSE, 'Referido',       TRUE,  FALSE, 'synced')
ON CONFLICT DO NOTHING;

-- Vincular los 10 ciudadanos a la candidatura de gobernador
-- (necesitamos los IDs de los ciudadanos recién insertados)
INSERT INTO ciudadanos_candidaturas (ciudadano_id, candidatura_id, compromiso)
SELECT
    c.id,
    'a1b2c3d4-0001-0000-0000-000000000101', -- CAND-001: Gobernador
    c.compromiso
FROM ciudadanos c
WHERE c.licencia_id = 'a1b2c3d4-0001-0000-0000-000000000001'
AND c.nombre LIKE 'Ciudadano Demo%'
ON CONFLICT (ciudadano_id, candidatura_id) DO NOTHING;

-- ══════════════════════════════════════════════════════════════════════
--  FIN
--  El sistema ya tiene datos demo funcionales para presentaciones.
--  Para producción real: cargar datos via configurador_maestro.html
-- ══════════════════════════════════════════════════════════════════════
