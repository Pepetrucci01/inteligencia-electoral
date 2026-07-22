-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 30: CENTRO DE LLAMADAS (CALL CENTER)
-- Proyecto staging: dyirhwwmykskpuvzcafx · 21 jul 2026 · rama desarrollo
--
-- Crea el esquema que consume modulo_callcenter.html (maqueta de José con
-- 15 marcadores [SWAP LUIS]). Nombres tomados LITERALMENTE de esos marcadores:
--   campanas_llamadas · cola_llamadas · v_productividad_callcenter ·
--   v_auditoria_callcenter
-- (La plantilla 27 hablaba de "cola_callcenter"; el módulo usa cola_llamadas.
--  Este archivo SUSTITUYE y activa lo que el 27 dejó comentado.)
--
-- ── DISEÑO DE LA COLA: reserva temporal (lease) ────────────────────────────
-- Práctica estándar de call center. Ni cola fija por operador (se congela el
-- trabajo del que falta) ni cola común pura (dos operadores llaman al mismo
-- contacto). El operador pide "siguiente" y el sistema le RESERVA el registro
-- por unos minutos:
--   ▸ mientras está reservado, nadie más lo ve
--   ▸ si lo trabaja, pasa a 'completada'
--   ▸ si abandona o se le cae la sesión, la reserva EXPIRA y el contacto
--     vuelve solo a la cola para otro operador
-- La función siguiente_llamada() usa FOR UPDATE SKIP LOCKED — el patrón de
-- Postgres para colas concurrentes: dos operadores nunca reciben la misma
-- fila aunque pidan en el mismo milisegundo.
--
-- ── CUMPLIMIENTO ──────────────────────────────────────────────────────────
-- ▸ consent: un contacto sin consentimiento NO entra a la cola (filtro en la
--   función de reparto, no solo en la UI).
-- ▸ Las respuestas de campañas tipo 'encuesta' (CATI) se guardan ANÓNIMAS en
--   las tablas del módulo de Encuestas — sin ciudadano_id y sin cola_id — tal
--   como marcó José. Este archivo NO las toca.
-- ▸ La carga externa de contactos NO escribe en `ciudadanos`: la cola es una
--   tabla aparte y el padrón no se contamina con listas compradas/externas.
--
-- ⚠️ STAGING COMPARTIDO: correr coordinado.
-- ⚠️ Cambio de esquema + RLS de un rol nuevo → avisar a José (coordinación).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ══ 1. CAMPAÑAS ═══════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.campanas_llamadas (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  licencia_id   uuid NOT NULL,
  nombre        text NOT NULL,
  -- identificacion | encuesta (CATI) | movilizacion
  tipo          text NOT NULL DEFAULT 'identificacion'
                CHECK (tipo IN ('identificacion','encuesta','movilizacion')),
  estado        text NOT NULL DEFAULT 'activa'
                CHECK (estado IN ('activa','pausada','cerrada')),
  guion         text,
  -- Si tipo='encuesta', apunta a la encuesta del módulo de Encuestas cuyas
  -- preguntas se leen en el guion. Las respuestas se guardan ANÓNIMAS allá.
  encuesta_id   uuid,
  creado_por    uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,
  creado_en     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_camp_llam_lic
  ON public.campanas_llamadas (licencia_id, estado);

COMMENT ON TABLE public.campanas_llamadas IS
  'Campañas del centro de llamadas. tipo=encuesta son estudios CATI cuyas
   respuestas se guardan anónimas en el módulo de Encuestas.';


-- ══ 2. COLA DE LLAMADAS ═══════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.cola_llamadas (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campana_id     uuid NOT NULL REFERENCES public.campanas_llamadas(id) ON DELETE CASCADE,
  licencia_id    uuid NOT NULL,

  -- ── Contacto ──
  nombre         text,
  telefono       text NOT NULL,
  seccion        text,
  municipio      text,
  -- Consentimiento para ser contactado. Sin esto NO se reparte (cumplimiento).
  consent        boolean NOT NULL DEFAULT false,
  -- 'padron' = salió de ciudadanos · 'externo' = carga masiva desde Excel.
  -- Enlace opcional al padrón; NULL si es contacto externo.
  origen         text NOT NULL DEFAULT 'padron'
                 CHECK (origen IN ('padron','externo')),
  ciudadano_id   uuid,

  -- ── Estado de la cola ──
  estado         text NOT NULL DEFAULT 'pendiente'
                 CHECK (estado IN ('pendiente','reservada','completada','descartada')),
  operador_id    uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,
  -- Vencimiento de la reserva: si pasa esta hora sin completarse, el registro
  -- vuelve solo a la cola (lo libera siguiente_llamada / liberar_reservas).
  reservado_hasta timestamptz,

  -- ── Resultado de la llamada ──
  disposicion    text CHECK (disposicion IN
                   ('contactado','comprometido','no_contesto','buzon',
                    'numero_equivocado','rechazo','no_llamar')),
  notas          text,
  intentos       int NOT NULL DEFAULT 0,
  reintento_programado timestamptz,
  hora_inicio    timestamptz,
  hora_fin       timestamptz,
  duracion_segundos int,
  fecha_llamada  timestamptz,

  -- ── Verificación de calidad (supervisión) ──
  verificado             boolean NOT NULL DEFAULT false,
  verificado_por         uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,
  resultado_verificacion text,

  creado_en      timestamptz NOT NULL DEFAULT now()
);

-- Índice del reparto: la consulta caliente de siguiente_llamada().
CREATE INDEX IF NOT EXISTS idx_cola_reparto
  ON public.cola_llamadas (licencia_id, campana_id, estado, reintento_programado)
  WHERE estado IN ('pendiente','reservada');

CREATE INDEX IF NOT EXISTS idx_cola_operador
  ON public.cola_llamadas (operador_id, estado);

-- Evita cargar dos veces el mismo teléfono en una campaña (dedupe de la
-- carga masiva a nivel base, no solo en la UI).
CREATE UNIQUE INDEX IF NOT EXISTS idx_cola_tel_unico
  ON public.cola_llamadas (campana_id, telefono);

COMMENT ON TABLE public.cola_llamadas IS
  'Cola de contactos del call center. Reparto por reserva temporal
   (estado=reservada + reservado_hasta); las reservas vencidas se reciclan
   solas. NO es el padrón: los contactos externos viven aquí, no en ciudadanos.';


-- ══ 3. REPARTO: "dame el siguiente" con reserva atómica ═══════════════════
-- Devuelve UNA fila y la deja reservada para el operador que llama.
-- FOR UPDATE SKIP LOCKED = dos operadores concurrentes nunca reciben la misma.
DROP FUNCTION IF EXISTS public.siguiente_llamada(uuid, int);
CREATE OR REPLACE FUNCTION public.siguiente_llamada(
  p_campana_id uuid,
  p_minutos    int DEFAULT 15      -- duración de la reserva
)
RETURNS SETOF public.cola_llamadas
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol      text;
  v_licencia uuid;
BEGIN
  SELECT u.rol, u.licencia_id INTO v_rol, v_licencia
  FROM public.usuarios u WHERE u.id = auth.uid() LIMIT 1;

  IF v_rol IS NULL THEN
    RAISE EXCEPTION 'Usuario sin perfil o no autenticado';
  END IF;
  IF v_rol NOT IN ('operador_cc','coordinador','admin','super_admin') THEN
    RAISE EXCEPTION 'Rol % no autorizado para tomar llamadas', v_rol;
  END IF;

  RETURN QUERY
  WITH siguiente AS (
    SELECT c.id
    FROM public.cola_llamadas c
    JOIN public.campanas_llamadas k ON k.id = c.campana_id
    WHERE c.campana_id  = p_campana_id
      AND c.licencia_id = v_licencia
      AND k.estado      = 'activa'          -- no repartir de campañas pausadas
      AND c.consent     = true              -- cumplimiento: sin consent no se llama
      AND c.disposicion IS DISTINCT FROM 'no_llamar'
      AND (
            c.estado = 'pendiente'
            -- recicla reservas vencidas (operador que abandonó)
        OR (c.estado = 'reservada' AND c.reservado_hasta < now())
      )
      -- respeta el reintento programado
      AND (c.reintento_programado IS NULL OR c.reintento_programado <= now())
    ORDER BY c.intentos ASC, c.creado_en ASC   -- primero los menos intentados
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.cola_llamadas c
     SET estado          = 'reservada',
         operador_id     = auth.uid(),
         reservado_hasta = now() + make_interval(mins => p_minutos)
    FROM siguiente s
   WHERE c.id = s.id
  RETURNING c.*;
END;
$$;

REVOKE ALL ON FUNCTION public.siguiente_llamada(uuid,int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.siguiente_llamada(uuid,int) TO authenticated;

COMMENT ON FUNCTION public.siguiente_llamada(uuid,int) IS
  'Entrega el siguiente contacto de la campaña y lo reserva para quien llama.
   Recicla reservas vencidas, respeta consent, reintentos y campaña activa.';


-- ══ 4. VISTAS DE MANDO ════════════════════════════════════════════════════
-- Productividad por operador (la consume el tab de supervisión).
CREATE OR REPLACE VIEW public.v_productividad_callcenter AS
SELECT
  c.licencia_id,
  c.operador_id,
  u.nombre                                                          AS operador,
  count(*) FILTER (WHERE c.estado = 'completada')                   AS llamadas,
  count(*) FILTER (WHERE c.disposicion = 'contactado')              AS contactados,
  count(*) FILTER (WHERE c.disposicion = 'comprometido')            AS comprometidos,
  count(*) FILTER (WHERE c.disposicion IN ('no_contesto','buzon'))  AS sin_respuesta,
  round(avg(c.duracion_segundos) FILTER (WHERE c.duracion_segundos > 0))::int
                                                                    AS duracion_promedio
FROM public.cola_llamadas c
LEFT JOIN public.usuarios u ON u.id = c.operador_id
WHERE c.operador_id IS NOT NULL
GROUP BY c.licencia_id, c.operador_id, u.nombre;

COMMENT ON VIEW public.v_productividad_callcenter IS
  'Productividad por operador. Hereda la RLS de cola_llamadas (security_invoker).';

-- Auditoría: llamadas completadas, de la más reciente hacia atrás.
CREATE OR REPLACE VIEW public.v_auditoria_callcenter AS
SELECT
  c.licencia_id,
  c.id,
  c.campana_id,
  k.nombre        AS campana,
  c.nombre        AS contacto,
  c.telefono,
  c.municipio,
  c.seccion,
  c.operador_id,
  u.nombre        AS operador,
  c.disposicion,
  c.notas,
  c.duracion_segundos,
  c.fecha_llamada,
  c.verificado,
  c.resultado_verificacion
FROM public.cola_llamadas c
JOIN public.campanas_llamadas k ON k.id = c.campana_id
LEFT JOIN public.usuarios u     ON u.id = c.operador_id
WHERE c.estado = 'completada';

COMMENT ON VIEW public.v_auditoria_callcenter IS
  'Bitácora de llamadas completadas para supervisión y verificación de calidad.';

-- security_invoker: las vistas aplican la RLS del usuario que consulta,
-- no la del dueño. Sin esto, una vista sería un agujero en el aislamiento
-- por licencia. (Postgres 15+.)
ALTER VIEW public.v_productividad_callcenter SET (security_invoker = true);
ALTER VIEW public.v_auditoria_callcenter     SET (security_invoker = true);


-- ══ 5. RLS ════════════════════════════════════════════════════════════════
-- Activa lo que 27_rls_operador_cc.sql dejó de plantilla, con los nombres
-- reales. Principio del instructivo de Fase 4:
--   operador_cc solo ve/escribe SU cola, siempre dentro de SU licencia.
ALTER TABLE public.campanas_llamadas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cola_llamadas     ENABLE ROW LEVEL SECURITY;

-- ── Campañas ──
-- Todos los roles del call center LEEN las campañas de su licencia
-- (el operador necesita el guion); solo el mando las crea/edita.
DROP POLICY IF EXISTS camp_llam_select ON public.campanas_llamadas;
CREATE POLICY camp_llam_select ON public.campanas_llamadas
  FOR SELECT USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['operador_cc','coordinador','admin','super_admin'])
  );

DROP POLICY IF EXISTS camp_llam_mando ON public.campanas_llamadas;
CREATE POLICY camp_llam_mando ON public.campanas_llamadas
  FOR ALL
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['coordinador','admin','super_admin'])
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['coordinador','admin','super_admin'])
  );

-- ── Cola: operador ──
-- Lee SOLO lo que tiene reservado/trabajado él mismo.
DROP POLICY IF EXISTS cola_operador_select ON public.cola_llamadas;
CREATE POLICY cola_operador_select ON public.cola_llamadas
  FOR SELECT USING (
    get_mi_rol()  = 'operador_cc'
    AND operador_id = auth.uid()
    AND licencia_id = get_mi_licencia()
  );

-- Escribe SOLO la disposición de su propia llamada, y NO puede reasignarse
-- registros de otro (WITH CHECK obliga a que siga siendo suyo).
DROP POLICY IF EXISTS cola_operador_update ON public.cola_llamadas;
CREATE POLICY cola_operador_update ON public.cola_llamadas
  FOR UPDATE
  USING (
    get_mi_rol()  = 'operador_cc'
    AND operador_id = auth.uid()
    AND licencia_id = get_mi_licencia()
  )
  WITH CHECK (
    operador_id = auth.uid()
    AND licencia_id = get_mi_licencia()
  );

-- ── Cola: mando ──
-- Gestiona toda la cola de SU licencia (cargar contactos, verificar calidad).
DROP POLICY IF EXISTS cola_mando_all ON public.cola_llamadas;
CREATE POLICY cola_mando_all ON public.cola_llamadas
  FOR ALL
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['coordinador','admin','super_admin'])
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['coordinador','admin','super_admin'])
  );

COMMIT;

-- ══ 6. GRANTS DE TABLA (imprescindibles para PostgREST) ══════════════════
-- La RLS decide QUÉ FILAS ve cada quien, pero Postgres primero exige permiso
-- sobre la TABLA. Sin estos GRANT, PostgREST devuelve 403 antes siquiera de
-- evaluar las políticas. (Las tablas viejas del proyecto ya los tenían; las
-- nuevas hay que otorgarlos explícitamente.)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.campanas_llamadas TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cola_llamadas     TO authenticated;
GRANT SELECT ON public.v_productividad_callcenter TO authenticated;
GRANT SELECT ON public.v_auditoria_callcenter     TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN (correr desde la app o con una sesión real; en el SQL Editor
-- auth.uid() es NULL y las funciones con guard fallan por diseño).
--
--   -- estructura creada:
--   SELECT table_name FROM information_schema.tables
--    WHERE table_name IN ('campanas_llamadas','cola_llamadas');
--
--   -- RLS activa y políticas puestas:
--   SELECT tablename, policyname, cmd FROM pg_policies
--    WHERE tablename IN ('campanas_llamadas','cola_llamadas');
--
--   -- las vistas deben ser security_invoker (aislamiento por licencia):
--   SELECT relname, reloptions FROM pg_class
--    WHERE relname IN ('v_productividad_callcenter','v_auditoria_callcenter');
--
--   -- reparto (con sesión de operador_cc):
--   SELECT * FROM siguiente_llamada('<campana_id>');
--     → devuelve 1 fila, ya con estado='reservada' y operador_id = el que llama
--     → llamarla dos veces seguidas debe dar CONTACTOS DISTINTOS
-- ═══════════════════════════════════════════════════════════════════════════
