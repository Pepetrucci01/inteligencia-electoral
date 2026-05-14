# GUÍA DE DESPLIEGUE — INTELIGENCIA ELECTORAL 2027
## Subir a Vercel y tener URL real en 10 minutos

---

## PASO 1 — Descarga todos los archivos del sistema

Descarga estos 8 archivos desde Claude y ponlos todos en una sola carpeta
en tu computadora. Llámala: `inteligencia-electoral`

```
inteligencia-electoral/
├── index.html
├── war_room_electoral_colima.html
├── panel_capturistas.html
├── mapa_secciones_v2.html
├── modulo_captura.html
├── configurador_meta_estados.html
├── modulo_reportes.html
└── modulo_admin.html
```

---

## PASO 2 — Crea una cuenta en Vercel (gratis)

1. Ve a: https://vercel.com
2. Clic en "Sign Up"
3. Regístrate con Google o con tu correo
4. No necesitas tarjeta de crédito

---

## PASO 3 — Sube el proyecto

### OPCIÓN A — Sin instalar nada (más fácil):

1. Ve a: https://vercel.com/new
2. Clic en "Browse" o arrastra tu carpeta `inteligencia-electoral`
3. Vercel detecta automáticamente que son archivos HTML estáticos
4. Clic en "Deploy"
5. Espera 30–60 segundos

### OPCIÓN B — Con GitHub (recomendado para actualizaciones futuras):

1. Instala GitHub Desktop: https://desktop.github.com
2. Crea repositorio nuevo con tu carpeta
3. En Vercel → "Import Git Repository"
4. Conecta tu GitHub y selecciona el repo
5. Deploy automático — cada vez que subas cambios, Vercel actualiza la URL

---

## PASO 4 — Tu URL queda lista

Vercel te da una URL automática como:
```
https://inteligencia-electoral-abc123.vercel.app
```

Esta URL ya funciona en cualquier navegador y celular.
La puedes compartir con cualquier cliente de inmediato.

---

## PASO 5 — Dominio personalizado (opcional, $12 USD/año)

Si quieres una URL profesional como `demo.tuempresa.mx`:

1. Compra el dominio en: https://www.namecheap.com o https://www.godaddy.com
2. En Vercel → tu proyecto → "Domains"
3. Escribe tu dominio y sigue las instrucciones de DNS
4. En 10–30 minutos queda activo con HTTPS incluido

---

## ESTRUCTURA DE URLs POR CLIENTE (cuando tengas varios estados)

Para vender a diferentes partidos/estados, crea un proyecto Vercel por cliente:

```
demo.tuapp.mx              ← Demo genérica para ventas
colima.tuapp.mx            ← Cliente Colima
sonora.tuapp.mx            ← Cliente Sonora
jalisco.tuapp.mx           ← Cliente Jalisco
```

Cada uno es un proyecto Vercel separado con sus propios datos.
Costo: ~$20 USD/mes por dominio principal + $12/año por subdominio.

---

## CHECKLIST ANTES DE ENVIAR AL CLIENTE

- [ ] Los 8 archivos están en la misma carpeta
- [ ] index.html abre correctamente en tu navegador local
- [ ] Todos los módulos cargan desde el hub (prueba cada uno)
- [ ] El mapa, war room y reportes muestran los datos correctos
- [ ] La URL de Vercel funciona desde el celular
- [ ] Cambias el nombre de usuario "Administrador" por el real del cliente
- [ ] El estado activo dice el nombre correcto del estado del cliente

---

## PRÓXIMOS PASOS DESPUÉS DEL DEMO

Una vez que el cliente diga SÍ:

1. **Conectar Supabase** — base de datos real en la nube
   - Crear proyecto en: https://supabase.com
   - Importar el Excel de ciudadanos
   - Conectar el módulo de captura a la BD real

2. **Autenticación real** — login con usuario y contraseña
   - Supabase Auth incluido en el plan gratuito
   - Roles por sección, municipio y estado

3. **Modo offline (PWA)** — para el día de la elección
   - Capturistas que trabajan sin internet
   - Sincronización automática cuando regresa la señal

4. **Tiempo de desarrollo**: 3–4 semanas con un desarrollador
5. **Costo estimado**: $30,000–60,000 MXN una sola vez

---

## SOPORTE TÉCNICO

Si algo falla en el despliegue:
- Documentación Vercel: https://vercel.com/docs
- Soporte Vercel: https://vercel.com/support
- Foro de la comunidad: https://github.com/vercel/vercel/discussions

---

*Sistema de Inteligencia Electoral v1.0 · Generado con Claude*
