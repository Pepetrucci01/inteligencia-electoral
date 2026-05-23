-- ══════════════════════════════════════════════════════════════════════
--  INTELIGENCIA ELECTORAL — Vistas y Funciones del Frontend
--  Archivo: 05_vistas_funciones.sql
--  Ejecutar QUINTO
--
--  Estas vistas pre-calculan los agregados que cada módulo necesita.
--  El frontend llama a la vista en lugar de hacer JOINs complejos.
-- ══════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════
--  VISTA 1: war_room_municipios
--  Usada por: war_room_electoral_colima.html → array MUNS
--  Reemplaza el cálculo manual de cap, meta, secs, cas por municipio
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW war_room_municipios AS
SELECT
    m.id,
    m.licencia_id,
    m.codigo,
    m.nombre,
    m.distrito_federal,
    m.total_secciones                               AS secs,
    m.total_casillas                                AS cas,
    m.votos_2024                                    AS v24,
    m.ganador_2024                                  AS g24,
    m.pct_ganador_2024                              AS p24,
    -- Meta total del municipio (suma de metas de sus secciones)
    COALESCE(SUM(se.meta_seccion), 0)               AS meta,
    -- Capturas actuales (ciudadanos registrados en esas secciones)
    COUNT(DISTINCT ci.id)                           AS cap,
    -- Porcentaje de avance
    CASE
        WHEN SUM(se.meta_seccion) > 0
        THEN ROUND(COUNT(DISTINCT ci.id)::NUMERIC / SUM(se.meta_seccion) * 100, 1)
        ELSE 0
    END                                             AS pct_avance,
    -- Desglose por nivel de compromiso
    COUNT(DISTINCT ci.id) FILTER (WHERE ci.compromiso = 4)  AS moviliza,
    COUNT(DISTINCT ci.id) FILTER (WHERE ci.compromiso = 3)  AS seg_vota,
    COUNT(DISTINCT ci.id) FILTER (WHERE ci.compromiso = 2)  AS simpatiza,
    COUNT(DISTINCT ci.id) FILTER (WHERE ci.compromiso = 1)  AS contacto,
    -- Validados vs duplicados
    COUNT(DISTINCT ci.id) FILTER (WHERE ci.validado = TRUE)  AS validados,
    COUNT(DISTINCT ci.id) FILTER (WHERE ci.duplicado = TRUE) AS duplicados,
    COUNT(DISTINCT ci.id) FILTER (WHERE ci.es_riesgo = TRUE) AS en_riesgo
FROM municipios m
LEFT JOIN secciones_electorales se ON se.municipio_id = m.id
LEFT JOIN ciudadanos ci ON ci.seccion_electoral = se.numero_seccion
    AND ci.licencia_id = m.licencia_id
GROUP BY m.id, m.licencia_id, m.codigo, m.nombre, m.distrito_federal,
         m.total_secciones, m.total_casillas, m.votos_2024, m.ganador_2024, m.pct_ganador_2024;

-- ══════════════════════════════════════════════════════════════════════
--  VISTA 2: war_room_secciones
--  Usada por: war_room (telemetría por sección) y mapa territorial
--  Reemplaza el objeto SECS del war_room
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW war_room_secciones AS
SELECT
    se.id,
    se.licencia_id,
    se.numero_seccion                               AS s,
    se.municipio_nombre                             AS m,
    se.meta_seccion                                 AS mt,
    se.total_nominilla                              AS nm,
    se.dificultad                                   AS d,
    se.semaforo                                     AS sem,
    se.ganador_2024                                 AS g,
    se.pos_x                                        AS x,
    se.pos_y                                        AS y,
    se.responsable_id,
    u.nombre                                        AS responsable_nombre,
    u.codigo                                        AS responsable_codigo,
    -- Capturas en esta sección
    COUNT(DISTINCT ci.id)                           AS c,
    -- Porcentaje
    CASE
        WHEN se.meta_seccion > 0
        THEN ROUND(COUNT(DISTINCT ci.id)::NUMERIC / se.meta_seccion * 100, 1)
        ELSE 0
    END                                             AS p,
    -- Prometidos (compromiso >= 3)
    COUNT(DISTINCT ci.id) FILTER (WHERE ci.compromiso >= 3) AS pr
FROM secciones_electorales se
LEFT JOIN usuarios u ON u.id = se.responsable_id
LEFT JOIN ciudadanos ci ON ci.seccion_electoral = se.numero_seccion
    AND ci.licencia_id = se.licencia_id
GROUP BY se.id, se.licencia_id, se.numero_seccion, se.municipio_nombre,
         se.meta_seccion, se.total_nominilla, se.dificultad, se.semaforo,
         se.ganador_2024, se.pos_x, se.pos_y, se.responsable_id,
         u.nombre, u.codigo;

-- ══════════════════════════════════════════════════════════════════════
--  VISTA 3: panel_capturistas_resumen
--  Usada por: panel_capturistas.html → array DATOS
--  Reemplaza los datos del ranking de capturistas
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW panel_capturistas_resumen AS
SELECT
    u.id,
    u.licencia_id,
    u.codigo                                            AS id_capturista,
    u.nombre                                            AS capturado_por,
    u.municipio,
    u.seccion_base,
    u.meta_individual                                   AS meta,
    u.ultimo_acceso,
    -- Capturas totales
    COUNT(ci.id)                                        AS total,
    -- Faltantes para meta
    GREATEST(u.meta_individual - COUNT(ci.id), 0)       AS faltantes,
    -- Porcentaje de meta
    CASE
        WHEN u.meta_individual > 0
        THEN ROUND(COUNT(ci.id)::NUMERIC / u.meta_individual * 100, 1)
        ELSE 0
    END                                                 AS pct_meta,
    -- Validados
    COUNT(ci.id) FILTER (WHERE ci.validado = TRUE)      AS validados,
    -- Voto seguro (compromiso >= 3)
    COUNT(ci.id) FILTER (WHERE ci.compromiso >= 3)      AS seguros,
    -- Moviliza
    COUNT(ci.id) FILTER (WHERE ci.compromiso = 4)       AS moviliza,
    -- Simpatizantes (comp 2)
    COUNT(ci.id) FILTER (WHERE ci.compromiso = 2)       AS simpatizantes,
    -- Contactos (comp 1)
    COUNT(ci.id) FILTER (WHERE ci.compromiso = 1)       AS contactos,
    -- Alta probabilidad (comp 3+4)
    COUNT(ci.id) FILTER (WHERE ci.compromiso >= 3)      AS alta_prob,
    -- Riesgo
    COUNT(ci.id) FILTER (WHERE ci.es_riesgo = TRUE)     AS riesgo_alto,
    -- Duplicados
    COUNT(ci.id) FILTER (WHERE ci.duplicado = TRUE)     AS duplicados,
    -- Por origen
    COUNT(ci.id) FILTER (WHERE ci.origen = 'Casa por casa') AS casa,
    COUNT(ci.id) FILTER (WHERE ci.origen = 'Referido')      AS referido,
    COUNT(ci.id) FILTER (WHERE ci.origen = 'Evento')         AS evento,
    COUNT(ci.id) FILTER (WHERE ci.origen = 'Digital')        AS digital
FROM usuarios u
LEFT JOIN ciudadanos ci ON ci.capturista_id = u.id
WHERE u.rol IN ('capturista','lider_seccion')
GROUP BY u.id, u.licencia_id, u.codigo, u.nombre, u.municipio,
         u.seccion_base, u.meta_individual, u.ultimo_acceso;

-- ══════════════════════════════════════════════════════════════════════
--  VISTA 4: candidaturas_avance
--  Usada por: modulo_admin.html → sección candidaturas
--             panel_cliente.html → KPIs
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW candidaturas_avance AS
SELECT
    ca.id,
    ca.licencia_id,
    ca.codigo,
    ca.nombre,
    ca.tipo,
    ca.territorio,
    ca.meta,
    ca.activa,
    -- Capturas vinculadas a esta candidatura
    COUNT(DISTINCT cc.ciudadano_id)                         AS caps,
    -- Porcentaje de avance
    CASE
        WHEN ca.meta > 0
        THEN ROUND(COUNT(DISTINCT cc.ciudadano_id)::NUMERIC / ca.meta * 100, 1)
        ELSE 0
    END                                                     AS avance,
    -- Desglose por nivel
    COUNT(cc.ciudadano_id) FILTER (WHERE cc.compromiso = 4) AS moviliza,
    COUNT(cc.ciudadano_id) FILTER (WHERE cc.compromiso = 3) AS seg_vota,
    COUNT(cc.ciudadano_id) FILTER (WHERE cc.compromiso = 2) AS simpatiza,
    COUNT(cc.ciudadano_id) FILTER (WHERE cc.compromiso = 1) AS contacto,
    -- Votos confirmados (día de elección)
    COUNT(cc.ciudadano_id) FILTER (WHERE cc.voto_confirmado = TRUE) AS votos_confirmados
FROM candidaturas ca
LEFT JOIN ciudadanos_candidaturas cc ON cc.candidatura_id = ca.id
GROUP BY ca.id, ca.licencia_id, ca.codigo, ca.nombre,
         ca.tipo, ca.territorio, ca.meta, ca.activa;

-- ══════════════════════════════════════════════════════════════════════
--  FUNCIÓN: asignar_responsable_territorial
--  Usada por: modulo_captura.html al insertar un ciudadano
--  Regla de negocio: el ciudadano se asigna al responsable de SU sección
--  NO al capturista que lo registró
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION asignar_responsable_territorial()
RETURNS TRIGGER AS $$
DECLARE
    v_responsable_id UUID;
BEGIN
    -- Buscar el responsable territorial de la sección del ciudadano
    SELECT responsable_id INTO v_responsable_id
    FROM secciones_electorales
    WHERE numero_seccion = NEW.seccion_electoral
    AND licencia_id = NEW.licencia_id
    LIMIT 1;

    -- Asignar el responsable (puede ser NULL si la sección no tiene responsable)
    NEW.responsable_id := v_responsable_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger que se ejecuta automáticamente al insertar un ciudadano
CREATE TRIGGER trg_asignar_responsable
    BEFORE INSERT ON ciudadanos
    FOR EACH ROW
    EXECUTE FUNCTION asignar_responsable_territorial();

-- ══════════════════════════════════════════════════════════════════════
--  FUNCIÓN: registrar_audit
--  Se llama desde el frontend vía RPC para registrar acciones
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION registrar_audit(
    p_licencia_id UUID,
    p_accion TEXT,
    p_tabla TEXT,
    p_registro_id UUID DEFAULT NULL,
    p_detalle JSONB DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO audit_log (
        licencia_id, usuario_id, usuario_nombre,
        accion, tabla, registro_id, detalle
    )
    SELECT
        p_licencia_id,
        auth.uid(),
        u.nombre,
        p_accion,
        p_tabla,
        p_registro_id,
        p_detalle
    FROM usuarios u
    WHERE u.id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ══════════════════════════════════════════════════════════════════════
--  FUNCIÓN: get_war_room_resumen
--  Devuelve KPIs globales para el header del War Room
--  El frontend la llama como: supabase.rpc('get_war_room_resumen', {p_licencia_id: ...})
-- ══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION get_war_room_resumen(p_licencia_id UUID)
RETURNS TABLE (
    total_capturas      BIGINT,
    meta_total          BIGINT,
    pct_avance          NUMERIC,
    voto_seguro         BIGINT,
    moviliza            BIGINT,
    en_riesgo           BIGINT,
    duplicados          BIGINT,
    capturistas_activos BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(DISTINCT ci.id)::BIGINT,
        COALESCE(SUM(DISTINCT se.meta_seccion), 0)::BIGINT,
        CASE WHEN SUM(DISTINCT se.meta_seccion) > 0
             THEN ROUND(COUNT(DISTINCT ci.id)::NUMERIC / SUM(DISTINCT se.meta_seccion) * 100, 1)
             ELSE 0 END,
        COUNT(DISTINCT ci.id) FILTER (WHERE ci.compromiso >= 3)::BIGINT,
        COUNT(DISTINCT ci.id) FILTER (WHERE ci.compromiso = 4)::BIGINT,
        COUNT(DISTINCT ci.id) FILTER (WHERE ci.es_riesgo = TRUE)::BIGINT,
        COUNT(DISTINCT ci.id) FILTER (WHERE ci.duplicado = TRUE)::BIGINT,
        COUNT(DISTINCT u.id) FILTER (WHERE u.ultimo_acceso > NOW() - INTERVAL '24 hours')::BIGINT
    FROM ciudadanos ci
    CROSS JOIN secciones_electorales se
    LEFT JOIN usuarios u ON u.licencia_id = p_licencia_id AND u.rol = 'capturista'
    WHERE ci.licencia_id = p_licencia_id
    AND se.licencia_id = p_licencia_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ══════════════════════════════════════════════════════════════════════
--  FIN
--  Base de datos lista para desarrollo.
--
--  RESUMEN DE LO QUE SE CREÓ:
--  01_schema.sql   → 11 tablas + índices + triggers de updated_at
--  02_rls.sql      → RLS en todas las tablas + helpers de rol
--  03_seed_demo.sql → Datos demo genéricos (licencia, municipios, candidaturas)
--  04_usuarios_demo.sql → Usuarios demo (ejecutar después de crear auth.users)
--  05_vistas_funciones.sql → 4 vistas + 3 funciones para el frontend
-- ══════════════════════════════════════════════════════════════════════
