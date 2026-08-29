-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — PARTE 64: EL SEGUNDO FACTOR SE EXIGE EN LA BASE
--
-- ⚠️⚠️  ORDEN DE APLICACION — LEER ANTES DE CORRER  ⚠️⚠️
--   1. Habilitar MFA (TOTP) en el dashboard de Supabase.
--   2. Desplegar la consola nueva y ENROLAR el segundo factor con
--      soporte@votera.mx (la consola muestra el QR sola la primera vez).
--   3. HASTA ENTONCES correr este archivo.
--   Si se corre ANTES de enrolar, la cuenta de soporte queda fuera: no habria
--   token con aal2 y es_soporte() devolveria false para todo.
--   Si eso pasa, el rescate esta al final del archivo.
--
-- POR QUE EN LA BASE Y NO SOLO EN LA CONSOLA
--   Una validacion que vive en el navegador no protege nada: cualquiera con
--   la contraseña puede llamar la API de PostgREST directamente con un token
--   normal y saltarse las pantallas. La consola es la comodidad; ESTO es la
--   seguridad. Sin aal2, la RLS no devuelve ni un ticket.
--
-- QUE ES aal2
--   GoTrue mete en el JWT la claim `aal` (authenticator assurance level).
--   Un login con solo contraseña da 'aal1'; tras verificar el TOTP, el token
--   nuevo trae 'aal2'. La base lo lee de auth.jwt().
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Helper SIN exigir aal2. Existe por una razon concreta: la consola
--    necesita distinguir "esta cuenta no es del equipo" de "es del equipo
--    pero aun no ha verificado el codigo". Con una sola funcion, los dos
--    casos darian false y el mensaje de error mentiria.
--    NO usar en politicas RLS: no aporta seguridad, solo diagnostico.
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.es_staff_registrado()
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

-- ───────────────────────────────────────────────────────────────────────────
-- 2. La de verdad: staff activo Y segundo factor verificado en ESTA sesion.
--    Es la que usan todas las politicas de tickets, mensajes y adjuntos, y
--    tambien las funciones puedo_ver_ticket / puedo_escribir_ticket.
-- ───────────────────────────────────────────────────────────────────────────
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
         )
     AND COALESCE(auth.jwt() ->> 'aal', 'aal1') = 'aal2';
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
         )
     AND COALESCE(auth.jwt() ->> 'aal', 'aal1') = 'aal2';
$$;

GRANT EXECUTE ON FUNCTION public.es_staff_registrado() TO authenticated;

COMMIT;

-- ═══════════════════════════════════════════════════════════════════════════
-- VERIFICACION
--   Desde el SQL Editor (sin sesion) es_soporte() debe dar FALSE — correcto,
--   ahi no hay JWT. La prueba real es entrar a la consola:
--     · con el codigo verificado  → se ve la bandeja
--     · sin verificar             → no se ve un solo ticket
--
--   Estado del enrolamiento del staff:
--     SELECT au.email, s.nombre, s.nivel, s.activo,
--            (SELECT count(*) FROM auth.mfa_factors f
--              WHERE f.user_id = s.usuario_id AND f.status = 'verified') AS factores
--       FROM public.soporte_staff s
--       JOIN auth.users au ON au.id = s.usuario_id;
--   Si `factores` = 0, esa persona NO podra entrar tras aplicar este archivo.
--
-- RESCATE si alguien queda fuera (revierte la exigencia de aal2):
--   CREATE OR REPLACE FUNCTION public.es_soporte()
--   RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
--   AS $$ SELECT EXISTS (SELECT 1 FROM public.soporte_staff s
--                         WHERE s.usuario_id = auth.uid() AND s.activo); $$;
--   (y lo mismo para es_soporte_supervisor, quitando la condicion del aal)
-- ═══════════════════════════════════════════════════════════════════════════
