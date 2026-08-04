-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 38: TABLA asignaciones_seccion (mapa de responsables real)
-- Proyecto staging: dyirhwwmykskpuvzcafx · 4 ago 2026 · rama desarrollo
--
-- Responde la pregunta 2 de José. Hoy el "mapa de responsables" de
-- modulo_captura está HORNEADO (sección → CAP-XXX inventado) y el jefe_seccion
-- ve todo porque no hay tabla contra la cual filtrar. Esta tabla puente lo
-- resuelve y ADEMÁS cierra esa fuga de RLS.
--
-- "Responsable" en VOTERA son DOS cosas (aclaración de José):
--   · jefe_seccion  = responsable territorial. UNO por sección.
--   · capturista    = quien captura. VARIOS por sección; uno puede cubrir varias.
--
-- NO confundir con `asignaciones_representante` (SQL 19), que es OTRA cosa:
-- esa asigna al REPRESENTANTE DE CASILLA a su sección para el Día E. Esta es
-- para la operación de campaña (jefes y capturistas). Coexisten a propósito.
--
-- DIFERENCIA de diseño clave: esta tabla lleva HISTORIAL (activo + fecha_fin).
-- Reasignar NO borra el renglón — se marca activo=false y se crea uno nuevo.
-- José lo necesita para auditar quién capturó bajo el mando de quién.
--
-- ⚠️ Avisar a José por WhatsApp antes de aplicar. Aditivo: sin drops, sin
--    renames. Meter con apply_migration nombrada.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── Tabla ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.asignaciones_seccion (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  licencia_id       uuid NOT NULL REFERENCES public.licencias(id) ON DELETE CASCADE,
  numero_seccion    integer NOT NULL,
  usuario_id        uuid NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
  tipo_asignacion   text NOT NULL CHECK (tipo_asignacion IN ('jefe_seccion','capturista')),
  activo            boolean NOT NULL DEFAULT true,
  fecha_inicio      date,
  fecha_fin         date,
  created_at        timestamptz NOT NULL DEFAULT now()
);

-- ── Constraint: UN solo jefe_seccion ACTIVO por sección por licencia ────────
-- (Capturistas activos, los que sean → por eso el índice parcial solo cubre
--  jefe_seccion. Un índice único parcial es la forma correcta de decir
--  "único bajo esta condición".)
CREATE UNIQUE INDEX IF NOT EXISTS ux_asig_seccion_jefe_activo
  ON public.asignaciones_seccion (licencia_id, numero_seccion)
  WHERE tipo_asignacion = 'jefe_seccion' AND activo = true;

-- ── Índices de acceso (los que pidió José) ─────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_asig_seccion_lic_sec
  ON public.asignaciones_seccion (licencia_id, numero_seccion);
CREATE INDEX IF NOT EXISTS idx_asig_seccion_lic_usr
  ON public.asignaciones_seccion (licencia_id, usuario_id);

-- ── Restricción única PARCIAL sobre filas ACTIVAS ──────────────────────────
-- Garantiza a nivel de BD que no haya dos asignaciones ACTIVAS idénticas
-- (misma persona, sección, tipo) — el historial (activo=false) puede repetir
-- esa tripleta cuantas veces haga falta. Es la red de seguridad de integridad:
-- aunque alguien inserte directo saltándose la función asignar_seccion(), la BD
-- impide el duplicado activo. Es el patrón estándar de tablas de asignación con
-- historial (slowly changing dimension tipo 2).
CREATE UNIQUE INDEX IF NOT EXISTS ux_asig_seccion_activa
  ON public.asignaciones_seccion (licencia_id, numero_seccion, usuario_id, tipo_asignacion)
  WHERE activo = true;

-- ── GRANT (sin esto, 403 antes de evaluar RLS) ─────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON public.asignaciones_seccion TO authenticated;

-- ── RLS ────────────────────────────────────────────────────────────────────
ALTER TABLE public.asignaciones_seccion ENABLE ROW LEVEL SECURITY;

-- SELECT: cada quien ve lo que le toca dentro de su licencia.
--   · capturista  → solo las secciones donde tiene asignación activa
--   · jefe_seccion→ solo sus secciones (donde es jefe)
--   · coordinador y arriba → toda su licencia
-- get_mi_rol() lee usuarios.rol (no el catálogo roles). Se cruza contra la
-- propia tabla con un EXISTS para las filas del mismo usuario.
DROP POLICY IF EXISTS asig_seccion_select ON public.asignaciones_seccion;
CREATE POLICY asig_seccion_select ON public.asignaciones_seccion
  FOR SELECT USING (
    licencia_id = get_mi_licencia()
    AND (
      get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador_estatal','coordinador'])
      OR usuario_id = auth.uid()                       -- ve sus propias asignaciones
      OR (                                              -- jefe: ve las de SUS secciones
        get_mi_rol() = 'jefe_seccion'
        AND numero_seccion IN (
          SELECT a.numero_seccion FROM public.asignaciones_seccion a
          WHERE a.usuario_id = auth.uid()
            AND a.tipo_asignacion = 'jefe_seccion'
            AND a.activo = true
            AND a.licencia_id = get_mi_licencia()
        )
      )
    )
  );

-- INSERT / UPDATE / DELETE: solo mando gestiona asignaciones, dentro de su licencia.
-- (La carga inicial y las reasignaciones las hace el mando; el capturista y el
--  jefe no se auto-asignan.)
DROP POLICY IF EXISTS asig_seccion_insert ON public.asignaciones_seccion;
CREATE POLICY asig_seccion_insert ON public.asignaciones_seccion
  FOR INSERT WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador_estatal','coordinador'])
  );

DROP POLICY IF EXISTS asig_seccion_update ON public.asignaciones_seccion;
CREATE POLICY asig_seccion_update ON public.asignaciones_seccion
  FOR UPDATE
  USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador_estatal','coordinador'])
  )
  WITH CHECK (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador_estatal','coordinador'])
  );

DROP POLICY IF EXISTS asig_seccion_delete ON public.asignaciones_seccion;
CREATE POLICY asig_seccion_delete ON public.asignaciones_seccion
  FOR DELETE USING (
    licencia_id = get_mi_licencia()
    AND get_mi_rol() = ANY (ARRAY['super_admin','admin','coordinador_estatal','coordinador'])
  );

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- FUNCIÓN asignar_seccion — la vía PROFESIONAL para cargar/reasignar
-- ───────────────────────────────────────────────────────────────────────────
-- José pidió UPSERT, pero un upsert que además gestiona historial (desactivar
-- la versión anterior + insertar la nueva) es demasiada lógica para un
-- on_conflict — eso QUIERE ser una función. Este es el patrón estándar para
-- tablas de asignación con historial (slowly changing dimension tipo 2): la
-- lógica vive en el servidor, es atómica, y no depende de las sutilezas de
-- inferencia de conflicto de PostgREST sobre índices parciales.
--
-- Comportamiento (idempotente, seguro para carga masiva y reasignación):
--   · Si YA hay una fila activa idéntica (misma persona/sección/tipo) → no hace
--     nada, devuelve esa fila. Así la carga inicial se puede re-correr sin
--     duplicar (idempotencia = el UPSERT que José quería, hecho bien).
--   · Si hay OTRA persona como jefe_seccion activa en esa sección → la desactiva
--     (activo=false, fecha_fin=hoy) y crea la nueva activa. Historial intacto.
--   · Si no hay conflicto → inserta la nueva activa.
--
-- SECURITY DEFINER + control de rol adentro: solo mando puede asignar. Se
-- valida el rol del LLAMANTE (no se confía en el cliente).
--
-- Params: licencia, sección, usuario a asignar, tipo ('jefe_seccion'|'capturista').
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.asignar_seccion(
  p_licencia   uuid,
  p_seccion    integer,
  p_usuario    uuid,
  p_tipo       text
)
RETURNS public.asignaciones_seccion
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rol   text;
  v_lic   uuid;
  v_fila  public.asignaciones_seccion;
BEGIN
  -- 1. Autorización: solo mando de la MISMA licencia asigna.
  SELECT u.rol, u.licencia_id INTO v_rol, v_lic
  FROM public.usuarios u WHERE u.id = auth.uid();

  IF v_rol IS NULL OR v_rol <> ALL (ARRAY['super_admin','admin','coordinador_estatal','coordinador']) THEN
    RAISE EXCEPTION 'No autorizado: solo un rol de mando puede asignar secciones.';
  END IF;
  -- super_admin puede cruzar licencias; el resto solo la suya.
  IF v_rol <> 'super_admin' AND p_licencia <> v_lic THEN
    RAISE EXCEPTION 'No autorizado: fuera de tu licencia.';
  END IF;

  IF p_tipo <> ALL (ARRAY['jefe_seccion','capturista']) THEN
    RAISE EXCEPTION 'tipo_asignacion inválido: %', p_tipo;
  END IF;

  -- 2. ¿Ya existe una fila activa idéntica? → idempotente, devolver esa.
  SELECT * INTO v_fila FROM public.asignaciones_seccion
   WHERE licencia_id = p_licencia AND numero_seccion = p_seccion
     AND usuario_id = p_usuario AND tipo_asignacion = p_tipo AND activo = true
   LIMIT 1;
  IF FOUND THEN
    RETURN v_fila;
  END IF;

  -- 3. Si es jefe_seccion, desactivar al jefe activo ANTERIOR de esa sección
  --    (solo uno permitido). Los capturistas no se desplazan entre sí.
  IF p_tipo = 'jefe_seccion' THEN
    UPDATE public.asignaciones_seccion
       SET activo = false, fecha_fin = CURRENT_DATE
     WHERE licencia_id = p_licencia AND numero_seccion = p_seccion
       AND tipo_asignacion = 'jefe_seccion' AND activo = true;
  END IF;

  -- 4. Insertar la nueva asignación activa.
  INSERT INTO public.asignaciones_seccion
    (licencia_id, numero_seccion, usuario_id, tipo_asignacion, activo, fecha_inicio)
  VALUES (p_licencia, p_seccion, p_usuario, p_tipo, true, CURRENT_DATE)
  RETURNING * INTO v_fila;

  RETURN v_fila;
END;
$$;

GRANT EXECUTE ON FUNCTION public.asignar_seccion(uuid, integer, uuid, text) TO authenticated;

-- Reasignar (quitar a alguien sin poner reemplazo): desactivar es un UPDATE
-- normal cubierto por la RLS de mando; no necesita función aparte.
--   UPDATE asignaciones_seccion SET activo=false, fecha_fin=CURRENT_DATE WHERE id=...;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
--   SELECT tablename FROM pg_tables WHERE tablename='asignaciones_seccion';
--   SELECT policyname, cmd FROM pg_policies WHERE tablename='asignaciones_seccion' ORDER BY cmd;
--     → 4 políticas: asig_seccion_select/insert/update/delete
--   SELECT indexname FROM pg_indexes WHERE tablename='asignaciones_seccion';
--     → ux_asig_seccion_jefe_activo, idx_asig_seccion_lic_sec, idx_asig_seccion_lic_usr, PK
--
-- PRUEBA del constraint de jefe único (debe FALLAR el 2º insert):
--   INSERT ... (lic, 138, userA, 'jefe_seccion', true);   -- ok
--   INSERT ... (lic, 138, userB, 'jefe_seccion', true);   -- ← viola ux_asig_seccion_jefe_activo
--   INSERT ... (lic, 138, userC, 'capturista',  true);    -- ok (capturistas, los que sean)
--
-- CARGA INICIAL: la genera José (archivo con distribución de activistas por
-- sección). Luis la sube llamando la función asignar_seccion() fila por fila
-- (o en lote desde el cliente), NO con upsert crudo: la función es idempotente
-- (re-correrla no duplica), gestiona el historial del jefe automáticamente, y
-- soporta la redistritación INE de marzo 2027 (secciones nuevas se insertan al
-- vuelo). Ejemplo de llamada vía PostgREST:
--   POST /rest/v1/rpc/asignar_seccion
--   body: { p_licencia, p_seccion, p_usuario, p_tipo }
-- El índice parcial ux_asig_seccion_activa queda como red de seguridad de
-- integridad (impide dos activas iguales aunque alguien inserte directo).
--
-- REVERSIBLE: DROP TABLE public.asignaciones_seccion;
-- ═══════════════════════════════════════════════════════════════════════════
