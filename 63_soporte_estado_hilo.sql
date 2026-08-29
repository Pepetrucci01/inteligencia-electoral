-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 63: EL ESTADO SIGUE AL HILO
-- Complementa el SQL 60. Solo reemplaza el cuerpo de agregar_mensaje_ticket.
--
-- QUE ESTABA MAL
--   Soporte respondia un ticket y este se quedaba en 'nuevo' hasta que
--   alguien se acordara de moverlo a mano. Efecto: la bandeja mostraba como
--   NUEVO algo ya contestado, y el KPI de nuevos mentia. Una cola que miente
--   deja de leerse a las dos semanas.
--
--   Ya existia la regla espejo (si el CLIENTE responde un ticket en
--   'esperando_cliente', vuelve a 'en_proceso'); faltaba la de soporte.
--
-- REGLA NUEVA
--   Respuesta PUBLICA de soporte sobre un ticket en 'nuevo' o 'reabierto'
--   → pasa solo a 'en_proceso', y si nadie lo tenia asignado, se asigna a
--     quien contesto.
--   Las notas INTERNAS no mueven el estado a proposito: escribirse a uno
--   mismo no es atender al cliente.
--   Tampoco se toca 'esperando_cliente' ni 'resuelto': ahi el estado lo puso
--   alguien deliberadamente y el automatismo no debe pisarlo.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

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

  -- ── El estado sigue al hilo ──────────────────────────────────────────
  IF v_tipo = 'cliente' AND v_t.estado = 'esperando_cliente' THEN
    -- El cliente contesto: vuelve a la cola del equipo.
    UPDATE public.tickets SET estado = 'en_proceso' WHERE id = p_ticket_id;

  ELSIF v_tipo = 'soporte'
        AND NOT COALESCE(p_interno,false)          -- las notas internas no cuentan
        AND v_t.estado IN ('nuevo','reabierto') THEN
    -- Primera respuesta publica: deja de ser "nuevo" y queda a nombre de
    -- quien contesto, si nadie lo tenia.
    UPDATE public.tickets
       SET estado     = 'en_proceso',
           asignado_a = COALESCE(asignado_a, auth.uid())
     WHERE id = p_ticket_id;
  END IF;

  RETURN jsonb_build_object('id', v_msg_id, 'autor_tipo', v_tipo);
END;
$$;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- REGULARIZAR LO YA EXISTENTE
-- Los tickets que soporte ya contesto pero siguen marcados como 'nuevo'
-- (el VOT-2026-000002 entre ellos). Correr UNA vez:
--
--   UPDATE public.tickets t
--      SET estado = 'en_proceso'
--    WHERE t.estado = 'nuevo'
--      AND EXISTS (SELECT 1 FROM public.ticket_mensajes m
--                   WHERE m.ticket_id = t.id
--                     AND m.autor_tipo = 'soporte' AND NOT m.interno);
--
-- VERIFICAR:
--   SELECT folio, estado, prioridad, prioridad_soporte,
--          (SELECT count(*) FROM public.ticket_mensajes m
--            WHERE m.ticket_id = t.id AND m.autor_tipo='soporte' AND NOT m.interno) AS resp_publicas
--     FROM public.tickets t ORDER BY created_at;
-- ═══════════════════════════════════════════════════════════════════════════
