-- ═══════════════════════════════════════════════════════════════════════════
-- VOTERA — 47: resetear contraseñas de las cuentas demo a una clave conocida
-- Proyecto staging: dyirhwwmykskpuvzcafx
--
-- Las cuentas representante/operador/consulta se crearon el 16-jul con claves
-- que no conocemos, por eso el login da 400 (credenciales incorrectas). Este
-- SQL las resetea a una clave conocida para poder probar los roles. Incluye
-- también coord.estatal por si acaso. bcrypt vía crypt()+gen_salt('bf').
--
-- Clave nueva para las 4: Demo2027!
-- ═══════════════════════════════════════════════════════════════════════════

UPDATE auth.users
SET encrypted_password = crypt('Demo2027!', gen_salt('bf')),
    updated_at = now()
WHERE email IN (
  'coord.estatal@demo.mx',
  'representante@demo.mx',
  'operador@demo.mx',
  'consulta@demo.mx'
);

-- Verificación: las 4 filas afectadas
SELECT email, updated_at
FROM auth.users
WHERE email IN ('coord.estatal@demo.mx','representante@demo.mx','operador@demo.mx','consulta@demo.mx')
ORDER BY email;

-- ═══════════════════════════════════════════════════════════════════════════
-- Tras correr esto, las 4 cuentas entran con:  Demo2027!
--   coord.estatal@demo.mx  / Demo2027!
--   representante@demo.mx   / Demo2027!
--   operador@demo.mx        / Demo2027!
--   consulta@demo.mx        / Demo2027!
-- ═══════════════════════════════════════════════════════════════════════════
