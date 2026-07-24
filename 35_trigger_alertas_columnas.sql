-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 35: TRIGGER QUE BLINDA LAS COLUMNAS DE `alertas`
-- Proyecto staging: dyirhwwmykskpuvzcafx · 23 jul 2026 · rama desarrollo
--
-- Cierra la limitación que quedó documentada en 32_endurecer_alertas_update.sql:
--
--   "RLS no distingue QUÉ COLUMNA se modifica, así que la política del
--    destinatario no puede impedir por sí sola que cambie el texto del
--    mensaje; lo que sí garantiza es que solo alcance alertas de SU sección.
--    Para blindar columna por columna haría falta un trigger."
--
-- Este es ese trigger. El destinatario de una alerta (capturista / jefe de
-- sección) solo debe poder MARCARLA COMO LEÍDA. Hoy el frontend únicamente
-- envía {leida, leida_at}, pero eso es una convención del cliente: desde la
-- consola del navegador se podría reescribir el `mensaje` de una alerta del
-- coordinador, o cambiarle el destinatario. La regla tiene que vivir en la BD.
--
-- QUIÉN PUEDE QUÉ, tras este trigger:
--   ▸ super_admin / admin / coordinador → editan la alerta completa (son
--     quienes la emiten; la RLS ya los acota a su licencia).
--   ▸ capturista / jefe_seccion → SOLO pueden cambiar `leida` y `leida_at`.
--     Cualquier otro cambio se rechaza con un mensaje claro.
--
-- Nota: el trigger complementa la RLS, no la sustituye. La RLS decide QUÉ
-- FILAS alcanza cada quien (su sección, su licencia); el trigger decide QUÉ
-- COLUMNAS puede tocar dentro de esas filas.
--
-- ⚠️ STAGING COMPARTIDO: correr coordinado. No cambia datos, solo añade la
--    validación; es reversible con DROP TRIGGER.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.alertas_solo_marcar_leida()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol text;
BEGIN
  SELECT u.rol INTO v_rol FROM public.usuarios u WHERE u.id = auth.uid() LIMIT 1;

  -- El mando puede editar la alerta completa: no aplica restricción.
  IF v_rol IS NULL OR v_rol IN ('super_admin','admin','coordinador') THEN
    RETURN NEW;
  END IF;

  -- Destinatario: todo lo que NO sea leida/leida_at debe quedar intacto.
  IF NEW.id                  IS DISTINCT FROM OLD.id
     OR NEW.licencia_id         IS DISTINCT FROM OLD.licencia_id
     OR NEW.seccion             IS DISTINCT FROM OLD.seccion
     OR NEW.destinatario_nombre IS DISTINCT FROM OLD.destinatario_nombre
     OR NEW.mensaje             IS DISTINCT FROM OLD.mensaje
     OR NEW.enviada_por         IS DISTINCT FROM OLD.enviada_por
     OR NEW.created_at          IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION
      'El destinatario de una alerta solo puede marcarla como leída (leida, leida_at).';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_alertas_solo_marcar_leida ON public.alertas;
CREATE TRIGGER trg_alertas_solo_marcar_leida
  BEFORE UPDATE ON public.alertas
  FOR EACH ROW
  EXECUTE FUNCTION public.alertas_solo_marcar_leida();

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
--
--   SELECT tgname, tgenabled FROM pg_trigger
--    WHERE tgrelid = 'public.alertas'::regclass AND NOT tgisinternal;
--     → trg_alertas_solo_marcar_leida, tgenabled = 'O' (activo)
--
-- PRUEBAS FUNCIONALES:
--   a) Con `capturista`: pulsar "✓ Entendido" en una alerta de su sección
--      → debe SEGUIR funcionando (es el flujo de campo; solo toca leida/leida_at).
--   b) Con `capturista`, desde la consola: intentar un PATCH que cambie
--      `mensaje` → debe RECHAZARSE con el mensaje del trigger.
--   c) Con `coordinador`: editar el mensaje de una alerta suya → debe funcionar.
--
-- ⚠️ Correr (a) antes de dar por buena la migración.
-- REVERSIBLE: DROP TRIGGER trg_alertas_solo_marcar_leida ON public.alertas;
-- ═══════════════════════════════════════════════════════════════════════════
