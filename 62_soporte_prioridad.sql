-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 62: PRIORIDAD DE SOPORTE + ALTA DE AGENTES
-- Complementa los SQL 60 y 61. Aditivo y reversible.
--
-- POR QUE DOS PRIORIDADES
--   `prioridad` es lo que DECLARA el cliente al levantar el ticket. Es un
--   dato util —dice cuanto le duele— pero no sirve para ordenar la cola: en
--   dos semanas todo estara marcado como urgente, porque para quien reporta
--   siempre lo es.
--   `prioridad_soporte` es la que ASIGNA el equipo despues de leerlo. Esa es
--   la que ordena la bandeja y la que alimenta cualquier SLA.
--   Se guardan las DOS a proposito: la distancia entre lo que el cliente
--   siente y lo que el equipo evalua es informacion por si misma (un cliente
--   cuyos "criticos" siempre resultan menores necesita capacitacion, no
--   soporte; uno cuyos "medios" resultan criticos necesita atencion urgente).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.tickets
  ADD COLUMN IF NOT EXISTS prioridad_soporte text
  CHECK (prioridad_soporte IS NULL
         OR prioridad_soporte IN ('baja','media','alta','critica'));

COMMENT ON COLUMN public.tickets.prioridad       IS 'La que declaro el CLIENTE. No usar para ordenar la cola.';
COMMENT ON COLUMN public.tickets.prioridad_soporte IS 'La que asigno SOPORTE tras leer el ticket. NULL = aun sin clasificar.';

-- Orden de la bandeja: primero lo sin clasificar (hay que verlo), luego por
-- prioridad real, luego lo mas viejo. Un indice parcial basta porque la
-- bandeja nunca lista los cerrados.
CREATE INDEX IF NOT EXISTS ix_tickets_cola
  ON public.tickets (prioridad_soporte, created_at)
  WHERE estado <> 'cerrado';

-- ───────────────────────────────────────────────────────────────────────────
-- RPC: clasificar. Solo soporte, y deja rastro en el hilo como nota INTERNA
-- (el cliente no tiene por que enterarse de que le bajaron la prioridad).
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.clasificar_ticket(
  p_ticket_id uuid,
  p_prioridad text,
  p_categoria text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_ant text; v_nueva_cat text;
BEGIN
  IF NOT public.es_soporte() THEN
    RAISE EXCEPTION 'Solo soporte clasifica tickets.' USING ERRCODE = '42501';
  END IF;
  IF p_prioridad NOT IN ('baja','media','alta','critica') THEN
    RAISE EXCEPTION 'Prioridad invalida: %', p_prioridad;
  END IF;

  SELECT prioridad_soporte INTO v_ant FROM public.tickets WHERE id = p_ticket_id;

  UPDATE public.tickets
     SET prioridad_soporte = p_prioridad,
         categoria = COALESCE(p_categoria, categoria)
   WHERE id = p_ticket_id
  RETURNING categoria INTO v_nueva_cat;

  IF v_nueva_cat IS NULL THEN
    RAISE EXCEPTION 'Ticket no encontrado.';
  END IF;

  PERFORM public.agregar_mensaje_ticket(
    p_ticket_id,
    'Clasificado como ' || p_prioridad ||
      COALESCE(' (antes ' || v_ant || ')', ' (primera clasificacion)'),
    true);   -- interno: el cliente no lo ve

  RETURN jsonb_build_object('id', p_ticket_id, 'prioridad_soporte', p_prioridad);
END;
$$;

GRANT EXECUTE ON FUNCTION public.clasificar_ticket(uuid,text,text) TO authenticated;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- ALTA DE AGENTES  —  por SQL a proposito: seran 2 o 3 personas y una
-- pantalla de administracion para eso es trabajo que no se usa.
--
-- ⚠️ EN PRODUCCION el staff de soporte debe tener CUENTAS PROPIAS, sin fila
--    en public.usuarios. Esa es justamente la garantia estructural: sin rol
--    de licencia, get_mi_rol() da NULL y no pueden entrar al hub del cliente
--    ni leer el padron.
--    Para PROBAR en staging es aceptable usar tu propia cuenta (quedarias en
--    las dos tablas y podrias entrar a ambos lados), pero NO se debe replicar
--    cuando haya clientes reales.
--
-- Cambia el correo y descomenta:
--
-- INSERT INTO public.soporte_staff (usuario_id, nombre, nivel)
-- SELECT id, 'Luis', 'supervisor' FROM auth.users WHERE email = 'TU_CORREO_AQUI'
-- ON CONFLICT (usuario_id) DO UPDATE
--   SET nombre = EXCLUDED.nombre, nivel = EXCLUDED.nivel, activo = true;
--
-- Verificar:
--   SELECT s.nombre, s.nivel, s.activo, au.email
--     FROM public.soporte_staff s JOIN auth.users au ON au.id = s.usuario_id;
--
-- REVERSIBLE:
--   DROP FUNCTION public.clasificar_ticket(uuid,text,text);
--   DROP INDEX public.ix_tickets_cola;
--   ALTER TABLE public.tickets DROP COLUMN prioridad_soporte;
-- ═══════════════════════════════════════════════════════════════════════════
