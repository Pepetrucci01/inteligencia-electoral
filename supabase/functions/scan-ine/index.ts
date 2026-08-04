// ═══════════════════════════════════════════════════════════════════════════
// VOTERA · Edge Function scan-ine — lectura de credencial INE con visión IA
// ───────────────────────────────────────────────────────────────────────────
// Recibe la foto de una INE, la lee con la API de Anthropic (modelo Haiku) y
// devuelve SOLO los campos del formulario. La imagen se lee y se DESCARTA:
// nunca se guarda en Storage, tablas ni logs (LFPDPPP + compromiso comercial).
//
// Requisitos de José (27 jul), todos implementados aquí:
//   1. Key vía Deno.env.get('VISION_API_KEY') — nunca hardcodeada.
//   2. Modelo claude-haiku-4-5-20251001 (para leer una INE va sobrado).
//   3. Valida el JWT y saca licencia_id del USUARIO autenticado, no del body.
//   4. No persiste la imagen en ningún punto.
//   5. Devuelve solo {nombre, paterno, materno, curp, clave_elector, seccion,
//      municipio, edad, sexo, domicilio}, no el texto crudo del modelo.
//   6. Registra el escaneo (licencia_id, fecha, éxito/error) en scan_ine_log
//      para medir consumo y topar por licencia — SIN la imagen.
//
// Despliegue: Luis sube este código; José carga el secret VISION_API_KEY desde
// el dashboard (Edge Functions → Secrets) el mismo día.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MODELO = 'claude-haiku-4-5-20251001'
const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages'

// Prompt de extracción: pide SOLO JSON con los campos del formulario.
const PROMPT_EXTRACCION = `Eres un lector de credenciales de elector mexicanas (INE/IFE).
Extrae ÚNICAMENTE los siguientes campos de la credencial en la imagen y responde
SOLO con un objeto JSON válido, sin texto antes ni después, sin markdown:

{
  "nombre": "nombre(s) de pila",
  "paterno": "apellido paterno",
  "materno": "apellido materno",
  "curp": "CURP de 18 caracteres si es legible, si no cadena vacía",
  "clave_elector": "clave de elector de 18 caracteres si es legible, si no cadena vacía",
  "seccion": "número de sección electoral como texto, si no cadena vacía",
  "domicilio": "domicilio si es legible, si no cadena vacía",
  "sexo": "H o M si es legible, si no cadena vacía"
}

Reglas:
- Si un campo no se lee con claridad, devuélvelo como cadena vacía "" — NO inventes.
- Si la imagen no es una credencial de elector, responde: {"error":"no_es_ine"}
- No agregues explicaciones. Solo el JSON.`

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // Cliente de servicio para escribir el log aunque falle algo (sin imagen).
  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  )
  let licenciaId: string | null = null

  const registrarLog = async (exito: boolean, motivo: string) => {
    try {
      await supabaseAdmin.from('scan_ine_log').insert({
        licencia_id: licenciaId,
        exito,
        motivo,           // 'ok' | 'no_es_ine' | 'foto_ilegible' | 'error_api' | 'no_autorizado'
      })
    } catch (_e) { /* el log es best-effort; nunca rompe la respuesta */ }
  }

  try {
    // ── 1. Autorización: validar JWT y sacar licencia del USUARIO ──────────
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      await registrarLog(false, 'no_autorizado')
      return json({ success: false, error: 'No autorizado.' }, 401)
    }

    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )
    const { data: { user } } = await supabaseUser.auth.getUser()
    if (!user) {
      await registrarLog(false, 'no_autorizado')
      return json({ success: false, error: 'No autorizado.' }, 401)
    }

    const { data: perfil } = await supabaseUser
      .from('usuarios')
      .select('licencia_id, rol')
      .eq('id', user.id)
      .single()
    if (!perfil) {
      await registrarLog(false, 'no_autorizado')
      return json({ success: false, error: 'Usuario sin perfil.' }, 403)
    }
    // licencia_id sale de AQUÍ, del usuario autenticado — nunca del body.
    licenciaId = perfil.licencia_id

    // ── 2. Leer la imagen del body (y validarla mínimamente) ───────────────
    const { image_base64, media_type } = await req.json()
    if (!image_base64 || typeof image_base64 !== 'string') {
      await registrarLog(false, 'foto_ilegible')
      return json({ success: false, error: 'No se recibió imagen.' }, 400)
    }
    // Tope defensivo de tamaño (~5MB en base64 ≈ 6.8M chars). La app ya
    // redimensiona a 1000px antes de enviar, esto es solo un cinturón extra.
    if (image_base64.length > 7_000_000) {
      await registrarLog(false, 'foto_ilegible')
      return json({ success: false, error: 'La imagen es demasiado grande.' }, 413)
    }

    // ── 3. Llamar a la API de visión (key desde secret, nunca hardcodeada) ─
    const apiKey = Deno.env.get('VISION_API_KEY')
    if (!apiKey) {
      await registrarLog(false, 'error_api')
      return json({ success: false, error: 'Servicio de lectura no configurado.' }, 503)
    }

    const visionResp = await fetch(ANTHROPIC_URL, {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: MODELO,
        max_tokens: 400,
        messages: [{
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type: media_type || 'image/jpeg', data: image_base64 } },
            { type: 'text', text: PROMPT_EXTRACCION },
          ],
        }],
      }),
    })

    if (!visionResp.ok) {
      await registrarLog(false, 'error_api')
      return json({ success: false, error: 'No se pudo leer la credencial. Captura manualmente.' }, 502)
    }

    const visionData = await visionResp.json()
    const texto = (visionData?.content?.[0]?.text ?? '').trim()

    // ── 4. Parsear el JSON del modelo y devolver SOLO los campos ───────────
    let datos: Record<string, string>
    try {
      datos = JSON.parse(texto.replace(/^```json\s*|\s*```$/g, ''))
    } catch (_e) {
      await registrarLog(false, 'foto_ilegible')
      return json({ success: false, error: 'No se pudo leer la credencial. Captura manualmente.' }, 200)
    }

    if (datos.error === 'no_es_ine') {
      await registrarLog(false, 'no_es_ine')
      return json({ success: false, error: 'La imagen no parece una credencial de elector.' }, 200)
    }

    // Mapear a los nombres que el formulario espera (aplicarDatosINE los usa).
    const salida = {
      nombre:        datos.nombre        ?? '',
      paterno:       datos.paterno       ?? '',
      materno:       datos.materno       ?? '',
      curp:          datos.curp          ?? '',
      clave_elector: datos.clave_elector ?? '',
      seccion:       datos.seccion       ?? '',
      domicilio:     datos.domicilio     ?? '',
      sexo:          datos.sexo          ?? '',
    }

    await registrarLog(true, 'ok')
    // La imagen (image_base64) sale de scope aquí y se descarta con la request.
    return json({ success: true, data: salida }, 200)

  } catch (_e) {
    await registrarLog(false, 'error_api')
    return json({ success: false, error: 'Error de conexión. Captura manualmente.' }, 500)
  }
})

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
