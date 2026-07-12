-- ============================================================
-- VOTERA — Módulo de Encuestas: esquema de base de datos
-- Proyecto Supabase staging: dyirhwwmykskpuvzcafx
-- ⚠ IMPORTANTE: el staging es compartido con la rama `desarrollo`
--   de Luis. Ejecutar en un momento coordinado — el cambio de
--   esquema afecta ambas ramas de inmediato.
-- ⚠ RLS: las políticas quedan DESACTIVADAS aquí. La activación
--   la hace Luis dentro de Fase 4 con el mismo patrón de
--   licencia_id del resto de las tablas.
-- ============================================================

-- ── 1. Licencias: módulos habilitados (modelo "Solo Encuestas") ──
-- Default: sistema completo. Para una licencia solo-encuestas:
--   UPDATE licencias SET modulos_habilitados = ARRAY['encuestas']
--   WHERE id = '...';
ALTER TABLE licencias
  ADD COLUMN IF NOT EXISTS modulos_habilitados text[]
  NOT NULL DEFAULT ARRAY['completo'];

COMMENT ON COLUMN licencias.modulos_habilitados IS
  'Módulos que la licencia habilita. ''completo'' = todo VOTERA. Valores: completo, encuestas.';

-- ── 2. Encuestas (definición de cada estudio) ────────────────────
CREATE TABLE IF NOT EXISTS encuestas (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  licencia_id   uuid NOT NULL REFERENCES licencias(id),
  nombre        text NOT NULL,
  descripcion   text,
  estado        text NOT NULL DEFAULT 'borrador'
                CHECK (estado IN ('borrador','activa','cerrada')),
  fecha_inicio  date,
  fecha_fin     date,
  -- Cuestionario como arreglo JSON. Cada pregunta:
  -- { "clave":"intencion", "texto":"Si hoy fueran las elecciones...",
  --   "tipo":"opcion_unica", "opciones":["Candidato A","Indeciso",
  --   "Ninguno","Prefiere no responder"], "obligatoria":false }
  -- Claves ESTÁNDAR reservadas para el cruce Territorio vs Opinión:
  --   conocimiento, imagen, intencion, firmeza, tema, aprobacion
  preguntas     jsonb NOT NULL DEFAULT '[]'::jsonb,
  -- Metodología del estudio (validez estadística + requisito INE si
  -- los resultados se publican). Ejemplo:
  -- { "modo":"Vivienda", "diseno":"Estratificado",
  --   "n":2850, "dist":"Proporcional" }
  metodologia   jsonb NOT NULL DEFAULT '{}'::jsonb,
  creado_por    uuid,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_encuestas_licencia
  ON encuestas (licencia_id);

-- ── 3. Respuestas (una fila por entrevista levantada) ────────────
-- ANÓNIMAS POR DISEÑO: sin nombre, teléfono ni FK a ciudadanos.
CREATE TABLE IF NOT EXISTS respuestas_encuesta (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  encuesta_id   uuid NOT NULL REFERENCES encuestas(id) ON DELETE CASCADE,
  licencia_id   uuid NOT NULL REFERENCES licencias(id),
  -- Georreferencia territorial (mismas claves que el resto del sistema)
  municipio_id  integer,
  seccion_id    integer,
  -- Quién levantó la entrevista (usuario del sistema, rol capturista)
  usuario_id    uuid,
  -- Demografía opcional del encuestado (NUNCA identificable)
  rango_edad    text CHECK (rango_edad IS NULL OR rango_edad IN
                ('18-25','26-35','36-45','46-55','56-65','66+')),
  genero        text CHECK (genero IS NULL OR genero IN
                ('M','F','Otro','No responde')),
  -- Respuestas con claves estándar, p. ej.:
  -- { "conocimiento":"Sí", "imagen":"Buena",
  --   "intencion":"Candidato A", "firmeza":"Definitiva",
  --   "tema":"Seguridad", "aprobacion":"Aprueba" }
  respuestas    jsonb NOT NULL DEFAULT '{}'::jsonb,
  levantada_en  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_resp_enc_encuesta
  ON respuestas_encuesta (encuesta_id);
CREATE INDEX IF NOT EXISTS idx_resp_enc_licencia_seccion
  ON respuestas_encuesta (licencia_id, seccion_id);
-- Índice para el cruce por intención de voto
CREATE INDEX IF NOT EXISTS idx_resp_enc_intencion
  ON respuestas_encuesta ((respuestas->>'intencion'));

-- ── 4. Vista del cruce Territorio vs Opinión (por sección) ───────
-- Combina avance de estructura (ciudadanos comprometidos) con
-- intención de voto medida en encuestas. El semáforo se calcula
-- en el frontend; la vista solo entrega los agregados.
-- NOTA: ajustar nombres de columnas de `ciudadanos` si difieren
-- en staging (verificar antes de ejecutar).
CREATE OR REPLACE VIEW v_territorio_vs_opinion AS
SELECT
  r.licencia_id,
  r.seccion_id,
  r.municipio_id,
  count(*)                                            AS entrevistas,
  count(*) FILTER (WHERE r.respuestas->>'intencion' NOT IN
    ('Indeciso','Ninguno','Prefiere no responder')
    AND r.respuestas->>'intencion' IS NOT NULL)       AS con_preferencia,
  count(*) FILTER (WHERE r.respuestas->>'intencion' = 'Indeciso')
                                                      AS indecisos,
  count(*) FILTER (WHERE r.respuestas->>'firmeza' = 'Definitiva')
                                                      AS voto_firme
FROM respuestas_encuesta r
GROUP BY r.licencia_id, r.seccion_id, r.municipio_id;

-- ============================================================
-- PENDIENTE PARA LUIS (Fase 4, rama desarrollo):
--   ALTER TABLE encuestas ENABLE ROW LEVEL SECURITY;
--   ALTER TABLE respuestas_encuesta ENABLE ROW LEVEL SECURITY;
--   + políticas por licencia_id con el patrón existente
--   + INSERT de respuestas restringido a roles de campo de la
--     misma licencia
-- ============================================================
