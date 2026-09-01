-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — 69: carga masiva de ESTRUCTURA (capturistas / coordinadores / repr)
-- Proyecto staging: dyirhwwmykskpuvzcafx
-- Migracion aplicada: pepe_20260831_columnas_estructura_telefono_meta_individual
--
-- PIEZAS (las tres ya estan desplegadas en staging):
--
--   1. Columnas aditivas (este archivo):
--        usuarios.telefono                        text, nullable
--        asignaciones_seccion.meta_individual     integer, nullable
--        indice usuarios_email_lower_idx
--
--   2. Edge Function  importar-estructura   (verify_jwt=false, auth manual
--      igual que crear-usuario). Recibe {filas:[...]} de hasta 60 y por cada
--      fila: busca por email -> crea cuenta Auth + crear_usuario_sistema (RPC de
--      Luis) o actualiza -> asignaciones_seccion / asignaciones_representante.
--      La licencia SIEMPRE es la del usuario que llama. Devuelve la contrasena
--      temporal de los creados UNA sola vez.
--      Codigo: supabase/functions/importar-estructura/index.ts
--
--   3. importador_carga.html, pestana 2 "Estructura": lee CAPTURISTAS y
--      ESTRUCTURA de la Carga Maestra, valida (correos unicos, seccion, suma de
--      metas vs get_estado_carga_maestra) y manda lotes de 50 a la Edge
--      Function. Ofrece CSV de credenciales y de errores.
--
-- PENDIENTE RELACIONADO: get_capturistas_stats usa META_CAP := 50 quemado.
-- Debe leer asignaciones_seccion.meta_individual.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.usuarios
  ADD COLUMN IF NOT EXISTS telefono text;

ALTER TABLE public.asignaciones_seccion
  ADD COLUMN IF NOT EXISTS meta_individual integer;

COMMENT ON COLUMN public.asignaciones_seccion.meta_individual IS
  'Meta de simpatizantes asignada a este usuario en esta seccion (Carga Maestra, reparto exacto de la meta seccional).';

CREATE INDEX IF NOT EXISTS usuarios_email_lower_idx ON public.usuarios (lower(email));
