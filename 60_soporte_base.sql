-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 60: BASE DEL MODULO DE SOPORTE TECNICO
-- Proyecto staging: dyirhwwmykskpuvzcafx · rama desarrollo
--
-- QUE RESUELVE
--   Los 9 roles de cualquier licencia levantan un ticket desde el hub.
--   El ticket queda ABIERTO hasta que soporte lo resuelva, con hilo de
--   conversacion, adjuntos y estados. La mesa de soporte (MEFT) los ve
--   TODOS, de todas las licencias y estados, desde una consola aparte.
--
-- DECISION DE DISENO: el staff de soporte NO es un rol de `usuarios`
--   `usuarios.rol` describe que hace alguien DENTRO de una licencia, y todo
--   el modelo asume que cada usuario pertenece a una (get_mi_licencia() es
--   la base de casi todas las politicas). Un agente de soporte no pertenece
--   a ninguna: pertenece a MEFT. Meterlo en `usuarios` obligaria a darle una
--   licencia falsa o a dejar licencia_id en NULL — y un permiso que se
--   otorga porque un campo esta vacio es un permiso que se otorga por
--   accidente. Es exactamente la forma de `ciudadanos_coord_general_select`
--   (rol='coordinador' AND get_mi_municipio() IS NULL), la puerta trasera
--   que encontramos el 11 ago.
--   Por eso: tabla `soporte_staff` + helper es_soporte(), y politicas que
--   dicen explicitamente "o es tuyo, o eres soporte".
--
-- EFECTO SECUNDARIO DESEADO: como el agente no tiene fila en `usuarios`,
--   get_mi_rol() le devuelve NULL y NO PUEDE ENTRAR AL HUB DEL CLIENTE.
--   La promesa de "soporte nunca ve el padron" no depende de que la RLS
--   este bien escrita: es estructural. El agente literalmente no tiene rol
--   con el cual leer `ciudadanos`.
--
-- ⚠️ STAGING COMPARTIDO: avisar a Jose. Todo ADITIVO (tablas y funciones
--    nuevas, no se toca nada existente). Reversible con DROP.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. STAFF DE SOPORTE
-- ───────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.soporte_staff (
  usuario_id  uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre      text NOT NULL,
  nivel       text NOT NULL DEFAULT 'agente'
              CHECK (nivel IN ('agente','supervisor')),
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.soporte_staff IS
  'Personal de MEFT que atiende tickets. NO son usuarios de una licencia: '
  'no tienen fila en public.usuarios y por eso no pueden entrar al hub del cliente.';

-- Helper con la misma forma que la familia get_mi_*: SECURITY DEFINER y
-- search_path fijo, para que la consulta no quede sujeta a la RLS de la
-- propia tabla (el problema que el SQL 36 corrigio en alertas).
CREATE OR REPLACE FUNCTION public.es_soporte()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.soporte_staff s
    WHERE s.usuario_id = auth.uid() AND s.activo
  );
$$;

CREATE OR REPLACE FUNCTION public.es_soporte_supervisor()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.soporte_staff s
    WHERE s.usuario_id = auth.uid() AND s.activo AND s.nivel = 'supervisor'
  );
$$;

-- ───────────────────────────────────────────────────────────────────────────
-- 2. TICKETS
-- ───────────────────────────────────────────────────────────────────────────
CREATE SEQUENCE IF NOT EXISTS public.ticket_folio_seq;

CREATE TABLE IF NOT EXISTS public.tickets (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Folio legible y GLOBAL. El estado va en columna aparte, NO dentro del
  -- folio: si un cliente cambia de plaza, el numero seguiria teniendo sentido.
  folio              text UNIQUE NOT NULL
                     DEFAULT 'VOT-' || to_char(now(), 'YYYY') || '-' ||
                             lpad(nextval('public.ticket_folio_seq')::text, 6, '0'),

  licencia_id        uuid NOT NULL REFERENCES public.licencias(id),

  -- FOTO del origen, no referencia. Si manana se renombra la licencia o
  -- termina el ciclo electoral y se archiva, el historial de soporte sigue
  -- siendo legible. Un JOIN a `licencias` deja tickets huerfanos en dos anos.
  licencia_snapshot  jsonb,
  estado_republica   text,          -- denormalizado para filtrar en la bandeja

  creado_por         uuid NOT NULL REFERENCES auth.users(id),
  creador_nombre     text,
  creador_rol        text,
  creador_municipio  text,
  creador_seccion    text,

  asunto             text NOT NULL CHECK (length(btrim(asunto)) >= 5),
  categoria          text NOT NULL DEFAULT 'otro'
                     CHECK (categoria IN ('acceso','captura','dia_eleccion',
                            'datos','rendimiento','duda','bug','otro')),
  prioridad          text NOT NULL DEFAULT 'media'
                     CHECK (prioridad IN ('baja','media','alta','critica')),

  -- `esperando_cliente` existe para que la metrica no mienta: un ticket
  -- parado porque el cliente no contesta no es tiempo de soporte.
  estado             text NOT NULL DEFAULT 'nuevo'
                     CHECK (estado IN ('nuevo','asignado','en_proceso',
                            'esperando_cliente','resuelto','cerrado','reabierto')),

  asignado_a         uuid REFERENCES auth.users(id),

  -- Diagnostico automatico: build, modulo, user agent, online, errores de
  -- consola. Es lo que convierte "no me deja guardar" en
  -- "capturista v88, offline, RLS 42501 en ciudadanos".
  contexto           jsonb NOT NULL DEFAULT '{}'::jsonb,

  created_at         timestamptz NOT NULL DEFAULT now(),
  actualizado_at     timestamptz NOT NULL DEFAULT now(),
  primera_respuesta_at timestamptz,
  resuelto_at        timestamptz,
  cerrado_at         timestamptz
);

CREATE INDEX IF NOT EXISTS ix_tickets_estado       ON public.tickets(estado);
CREATE INDEX IF NOT EXISTS ix_tickets_licencia     ON public.tickets(licencia_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_tickets_asignado     ON public.tickets(asignado_a) WHERE asignado_a IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_tickets_entidad      ON public.tickets(estado_republica);
CREATE INDEX IF NOT EXISTS ix_tickets_creador      ON public.tickets(creado_por);

-- ───────────────────────────────────────────────────────────────────────────
-- 3. HILO DE CONVERSACION  (inmutable: no se edita ni se borra)
-- ───────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ticket_mensajes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id   uuid NOT NULL REFERENCES public.tickets(id) ON DELETE CASCADE,
  autor_id    uuid NOT NULL REFERENCES auth.users(id),
  autor_nombre text,
  autor_tipo  text NOT NULL CHECK (autor_tipo IN ('cliente','soporte')),
  cuerpo      text NOT NULL CHECK (length(btrim(cuerpo)) > 0),
  -- Nota interna del equipo: el cliente NUNCA la ve.
  interno     boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_tmsg_ticket ON public.ticket_mensajes(ticket_id, created_at);

-- ───────────────────────────────────────────────────────────────────────────
-- 4. ADJUNTOS  (el archivo vive en Storage; aqui solo el registro)
-- ───────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ticket_adjuntos (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id     uuid NOT NULL REFERENCES public.tickets(id) ON DELETE CASCADE,
  mensaje_id    uuid REFERENCES public.ticket_mensajes(id) ON DELETE SET NULL,
  storage_path  text NOT NULL,
  nombre_archivo text NOT NULL,
  mime          text,
  tamano_bytes  bigint CHECK (tamano_bytes IS NULL OR tamano_bytes <= 5242880),
  subido_por    uuid NOT NULL REFERENCES auth.users(id),
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_tadj_ticket ON public.ticket_adjuntos(ticket_id);

-- ───────────────────────────────────────────────────────────────────────────
-- 5. TRIGGERS DE INTEGRIDAD
-- ───────────────────────────────────────────────────────────────────────────

-- actualizado_at + sellos de tiempo derivados del estado
CREATE OR REPLACE FUNCTION public.fn_ticket_sellos()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.actualizado_at := now();
  IF NEW.estado = 'resuelto' AND OLD.estado IS DISTINCT FROM 'resuelto' THEN
    NEW.resuelto_at := now();
  END IF;
  IF NEW.estado = 'cerrado' AND OLD.estado IS DISTINCT FROM 'cerrado' THEN
    NEW.cerrado_at := now();
  END IF;
  IF NEW.estado = 'reabierto' THEN
    NEW.resuelto_at := NULL;
    NEW.cerrado_at  := NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ticket_sellos ON public.tickets;
CREATE TRIGGER trg_ticket_sellos
  BEFORE UPDATE ON public.tickets
  FOR EACH ROW EXECUTE FUNCTION public.fn_ticket_sellos();

-- El cliente no reescribe su ticket: solo agrega mensajes.
-- Mismo principio que trg_alertas_solo_marcar_leida (SQL 35b): la RLS decide
-- QUE FILAS alcanzas, el trigger decide QUE COLUMNAS puedes tocar.
CREATE OR REPLACE FUNCTION public.fn_ticket_columnas()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF public.es_soporte() THEN
    RETURN NEW;                       -- soporte administra el ticket completo
  END IF;
  -- Cliente: unico cambio permitido es reabrir (via RPC reabrir_ticket).
  IF (to_jsonb(NEW) - 'estado' - 'actualizado_at' - 'resuelto_at' - 'cerrado_at')
     IS DISTINCT FROM
     (to_jsonb(OLD) - 'estado' - 'actualizado_at' - 'resuelto_at' - 'cerrado_at')
  THEN
    RAISE EXCEPTION 'Un ticket no se edita: agrega un mensaje al hilo.'
      USING ERRCODE = '42501';
  END IF;
  IF NEW.estado IS DISTINCT FROM OLD.estado
     AND NOT (OLD.estado IN ('resuelto','cerrado') AND NEW.estado = 'reabierto')
  THEN
    RAISE EXCEPTION 'Solo soporte cambia el estado de un ticket (puedes reabrirlo).'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ticket_columnas ON public.tickets;
CREATE TRIGGER trg_ticket_columnas
  BEFORE UPDATE ON public.tickets
  FOR EACH ROW EXECUTE FUNCTION public.fn_ticket_columnas();

-- Primera respuesta de soporte (metrica de SLA)
CREATE OR REPLACE FUNCTION public.fn_ticket_primera_respuesta()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.autor_tipo = 'soporte' AND NOT NEW.interno THEN
    UPDATE public.tickets t
       SET primera_respuesta_at = COALESCE(t.primera_respuesta_at, now())
     WHERE t.id = NEW.ticket_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ticket_primera_respuesta ON public.ticket_mensajes;
CREATE TRIGGER trg_ticket_primera_respuesta
  AFTER INSERT ON public.ticket_mensajes
  FOR EACH ROW EXECUTE FUNCTION public.fn_ticket_primera_respuesta();

-- ───────────────────────────────────────────────────────────────────────────
-- 6. GRANTS
--    Regla del proyecto: tabla + RLS NO basta. PostgREST exige GRANT de
--    TABLA o devuelve 403 ANTES de evaluar las politicas.
-- ───────────────────────────────────────────────────────────────────────────
GRANT SELECT                         ON public.soporte_staff   TO authenticated;
GRANT SELECT, INSERT, UPDATE         ON public.tickets         TO authenticated;
GRANT SELECT, INSERT                 ON public.ticket_mensajes TO authenticated;
GRANT SELECT, INSERT                 ON public.ticket_adjuntos TO authenticated;
GRANT USAGE                          ON SEQUENCE public.ticket_folio_seq TO authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 7. RLS
-- ───────────────────────────────────────────────────────────────────────────
ALTER TABLE public.soporte_staff   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tickets         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_mensajes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_adjuntos ENABLE ROW LEVEL SECURITY;

-- soporte_staff: cada agente se ve a si mismo; el supervisor ve al equipo.
DROP POLICY IF EXISTS soporte_staff_select ON public.soporte_staff;
CREATE POLICY soporte_staff_select ON public.soporte_staff
  FOR SELECT TO authenticated
  USING (usuario_id = auth.uid() OR public.es_soporte_supervisor());

-- tickets: el mio, o los de mi licencia si soy mando, o todos si soy soporte.
DROP POLICY IF EXISTS tickets_select ON public.tickets;
CREATE POLICY tickets_select ON public.tickets
  FOR SELECT TO authenticated
  USING (
    creado_por = auth.uid()
    OR public.es_soporte()
    OR (licencia_id = public.get_mi_licencia()
        AND public.get_mi_rol() = ANY (ARRAY['super_admin','admin']))
  );

DROP POLICY IF EXISTS tickets_insert ON public.tickets;
CREATE POLICY tickets_insert ON public.tickets
  FOR INSERT TO authenticated
  WITH CHECK (
    creado_por = auth.uid()
    AND licencia_id = public.get_mi_licencia()
  );

DROP POLICY IF EXISTS tickets_update ON public.tickets;
CREATE POLICY tickets_update ON public.tickets
  FOR UPDATE TO authenticated
  USING (public.es_soporte() OR creado_por = auth.uid())
  WITH CHECK (public.es_soporte() OR creado_por = auth.uid());

-- mensajes: se ven los del ticket que puedes ver; las notas internas solo soporte.
DROP POLICY IF EXISTS ticket_mensajes_select ON public.ticket_mensajes;
CREATE POLICY ticket_mensajes_select ON public.ticket_mensajes
  FOR SELECT TO authenticated
  USING (
    (NOT interno OR public.es_soporte())
    AND EXISTS (SELECT 1 FROM public.tickets t WHERE t.id = ticket_id)
  );

DROP POLICY IF EXISTS ticket_mensajes_insert ON public.ticket_mensajes;
CREATE POLICY ticket_mensajes_insert ON public.ticket_mensajes
  FOR INSERT TO authenticated
  WITH CHECK (
    autor_id = auth.uid()
    AND (NOT interno OR public.es_soporte())
    AND EXISTS (
      SELECT 1 FROM public.tickets t
      WHERE t.id = ticket_id
        AND (t.creado_por = auth.uid() OR public.es_soporte())
    )
  );

-- adjuntos
DROP POLICY IF EXISTS ticket_adjuntos_select ON public.ticket_adjuntos;
CREATE POLICY ticket_adjuntos_select ON public.ticket_adjuntos
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.tickets t WHERE t.id = ticket_id));

DROP POLICY IF EXISTS ticket_adjuntos_insert ON public.ticket_adjuntos;
CREATE POLICY ticket_adjuntos_insert ON public.ticket_adjuntos
  FOR INSERT TO authenticated
  WITH CHECK (
    subido_por = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.tickets t
      WHERE t.id = ticket_id
        AND (t.creado_por = auth.uid() OR public.es_soporte())
    )
  );

-- ───────────────────────────────────────────────────────────────────────────
-- 8. API — el frontend NUNCA toca las tablas directo, solo estas funciones.
--    Asi, el dia que el almacen se mueva a otro proyecto o a una herramienta
--    externa, se cambia el cuerpo de estas RPC y el modulo ni se entera.
--    Mismo principio que construirDatosCaptura: un solo punto de escritura.
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.crear_ticket(
  p_asunto      text,
  p_descripcion text,
  p_categoria   text DEFAULT 'otro',
  p_prioridad   text DEFAULT 'media',
  p_contexto    jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_u        record;
  v_snap     jsonb;
  v_ticket   public.tickets;
BEGIN
  SELECT u.id, u.nombre, u.rol, u.licencia_id, u.municipio, u.seccion
    INTO v_u
    FROM public.usuarios u
   WHERE u.id = auth.uid();

  IF v_u.id IS NULL THEN
    RAISE EXCEPTION 'Usuario sin perfil: no se puede levantar el ticket.';
  END IF;

  -- Snapshot de la licencia sin conocer sus columnas de antemano, y sin
  -- arrastrar nada sensible.
  SELECT to_jsonb(l) - 'vision_key_ref' INTO v_snap
    FROM public.licencias l WHERE l.id = v_u.licencia_id;

  INSERT INTO public.tickets (
    licencia_id, licencia_snapshot, estado_republica,
    creado_por, creador_nombre, creador_rol, creador_municipio, creador_seccion,
    asunto, categoria, prioridad, contexto
  ) VALUES (
    v_u.licencia_id,
    v_snap,
    COALESCE(v_snap->>'estado', v_snap->>'entidad', v_snap->>'estado_nombre'),
    v_u.id, v_u.nombre, v_u.rol, v_u.municipio, v_u.seccion,
    btrim(p_asunto), p_categoria, p_prioridad,
    COALESCE(p_contexto, '{}'::jsonb)
  )
  RETURNING * INTO v_ticket;

  INSERT INTO public.ticket_mensajes (ticket_id, autor_id, autor_nombre, autor_tipo, cuerpo)
  VALUES (v_ticket.id, v_u.id, v_u.nombre, 'cliente', p_descripcion);

  RETURN jsonb_build_object(
    'id', v_ticket.id, 'folio', v_ticket.folio, 'estado', v_ticket.estado
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.agregar_mensaje_ticket(
  p_ticket_id uuid,
  p_cuerpo    text,
  p_interno   boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_t         public.tickets;
  v_es_sop    boolean := public.es_soporte();
  v_nombre    text;
  v_tipo      text;
  v_msg_id    uuid;
BEGIN
  SELECT * INTO v_t FROM public.tickets WHERE id = p_ticket_id;
  IF v_t.id IS NULL THEN
    RAISE EXCEPTION 'Ticket no encontrado.';
  END IF;

  IF NOT v_es_sop AND v_t.creado_por <> auth.uid() THEN
    RAISE EXCEPTION 'No puedes escribir en este ticket.' USING ERRCODE = '42501';
  END IF;

  IF p_interno AND NOT v_es_sop THEN
    RAISE EXCEPTION 'Solo soporte puede dejar notas internas.' USING ERRCODE = '42501';
  END IF;

  IF v_es_sop THEN
    v_tipo := 'soporte';
    SELECT s.nombre INTO v_nombre FROM public.soporte_staff s WHERE s.usuario_id = auth.uid();
  ELSE
    v_tipo := 'cliente';
    SELECT u.nombre INTO v_nombre FROM public.usuarios u WHERE u.id = auth.uid();
  END IF;

  INSERT INTO public.ticket_mensajes (ticket_id, autor_id, autor_nombre, autor_tipo, cuerpo, interno)
  VALUES (p_ticket_id, auth.uid(), v_nombre, v_tipo, p_cuerpo, COALESCE(p_interno,false))
  RETURNING id INTO v_msg_id;

  -- Si el cliente responde un ticket que estaba esperandolo, vuelve a la cola.
  IF v_tipo = 'cliente' AND v_t.estado = 'esperando_cliente' THEN
    UPDATE public.tickets SET estado = 'en_proceso' WHERE id = p_ticket_id;
  END IF;

  RETURN jsonb_build_object('id', v_msg_id, 'autor_tipo', v_tipo);
END;
$$;

CREATE OR REPLACE FUNCTION public.reabrir_ticket(
  p_ticket_id uuid,
  p_motivo    text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_t public.tickets;
BEGIN
  SELECT * INTO v_t FROM public.tickets WHERE id = p_ticket_id;
  IF v_t.id IS NULL THEN
    RAISE EXCEPTION 'Ticket no encontrado.';
  END IF;
  IF v_t.creado_por <> auth.uid() AND NOT public.es_soporte() THEN
    RAISE EXCEPTION 'No puedes reabrir este ticket.' USING ERRCODE = '42501';
  END IF;
  IF v_t.estado NOT IN ('resuelto','cerrado') THEN
    RAISE EXCEPTION 'Solo se reabre un ticket resuelto o cerrado (esta en %).', v_t.estado;
  END IF;

  UPDATE public.tickets SET estado = 'reabierto' WHERE id = p_ticket_id;
  PERFORM public.agregar_mensaje_ticket(p_ticket_id, 'REABIERTO: ' || p_motivo, false);

  RETURN jsonb_build_object('id', p_ticket_id, 'estado', 'reabierto');
END;
$$;

-- Solo soporte mueve el estado. Nada se cierra solo.
CREATE OR REPLACE FUNCTION public.cambiar_estado_ticket(
  p_ticket_id uuid,
  p_estado    text,
  p_nota      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.es_soporte() THEN
    RAISE EXCEPTION 'Solo soporte cambia el estado de un ticket.' USING ERRCODE = '42501';
  END IF;
  IF p_estado NOT IN ('nuevo','asignado','en_proceso','esperando_cliente',
                      'resuelto','cerrado','reabierto') THEN
    RAISE EXCEPTION 'Estado invalido: %', p_estado;
  END IF;

  UPDATE public.tickets
     SET estado     = p_estado,
         asignado_a = CASE WHEN p_estado = 'asignado' AND asignado_a IS NULL
                           THEN auth.uid() ELSE asignado_a END
   WHERE id = p_ticket_id;

  IF p_nota IS NOT NULL AND btrim(p_nota) <> '' THEN
    PERFORM public.agregar_mensaje_ticket(p_ticket_id, p_nota, false);
  END IF;

  RETURN jsonb_build_object('id', p_ticket_id, 'estado', p_estado);
END;
$$;

GRANT EXECUTE ON FUNCTION public.es_soporte()                                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.es_soporte_supervisor()                        TO authenticated;
GRANT EXECUTE ON FUNCTION public.crear_ticket(text,text,text,text,jsonb)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.agregar_mensaje_ticket(uuid,text,boolean)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.reabrir_ticket(uuid,text)                      TO authenticated;
GRANT EXECUTE ON FUNCTION public.cambiar_estado_ticket(uuid,text,text)          TO authenticated;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICACION (correr despues, es solo lectura)
--
--   SELECT tablename FROM pg_tables
--    WHERE schemaname='public'
--      AND tablename IN ('soporte_staff','tickets','ticket_mensajes','ticket_adjuntos');
--
--   SELECT tablename, policyname, cmd FROM pg_policies
--    WHERE schemaname='public'
--      AND tablename IN ('soporte_staff','tickets','ticket_mensajes','ticket_adjuntos')
--    ORDER BY tablename, cmd;
--
-- ALTA DE UN AGENTE (por SQL a proposito: seran 2 o 3 personas y una pantalla
-- de administracion para eso es trabajo que no se usa):
--   INSERT INTO public.soporte_staff (usuario_id, nombre, nivel)
--   SELECT id, 'Nombre Apellido', 'supervisor' FROM auth.users WHERE email='...';
--
-- PENDIENTE APARTE: bucket de Storage 'ticket-adjuntos' con sus politicas.
-- Se protege la tabla y se deja el bucket abierto: es el error mas comun.
--
-- REVERSIBLE:
--   DROP TABLE public.ticket_adjuntos, public.ticket_mensajes, public.tickets;
--   DROP TABLE public.soporte_staff;
--   DROP SEQUENCE public.ticket_folio_seq;
-- ═══════════════════════════════════════════════════════════════════════════
