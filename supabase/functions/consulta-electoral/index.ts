// VOTERA · Edge Function consulta-electoral (v6 — 4 sep: + semaforo de cuota)
// v5: contexto resumido (~5.5K tokens) + registro en consulta_ia_log.
// v6: cuota por licencia igual que el escaner INE. consulta_ia_cuota_mensual es
//     REFERENCIA: alerta 80%, excedido 100%, freno de emergencia 300% (429).
//     El nivel viaja en cada respuesta para que el frontend avise.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const MODELO = 'claude-haiku-4-5-20251001'
const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages'
const MAX_TOKENS = 900

const SYSTEM_PROMPT = `Eres el asistente de inteligencia electoral de VOTERA, una plataforma de operación territorial para campañas políticas en México.

CONTEXTO DE LA PLATAFORMA:
- Elección: Colima 2027, fecha: 6 de junio de 2027
- Meta estatal: 208,754 votos proyectados
- 10 municipios, 388 secciones electorales, ~1,033 casillas
- Fases: Fase 1 (captura de simpatizantes, actual), Fase 2 (jornada electoral / Día E)
- Niveles de compromiso del ciudadano: 1 = Contacto, 2 = Simpatiza, 3 = Seguro vota, 4 = Moviliza. "Seguros de votar" = niveles 3 y 4.
- "En riesgo" = ciudadanos marcados con bandera de riesgo de fuga de voto.
- "Estructura" = capturistas/activistas asignados a una sección. Una sección sin estructura no tiene quien capture.

TU ROL:
- Respondes consultas sobre el avance de la campaña, estructura de campo, calidad del padrón, encuestas, tendencias y proyecciones
- Usas ÚNICAMENTE los datos reales que te llegan en el contexto — nunca inventas cifras
- Si no tienes los datos para responder, dilo claramente y sugiere qué pantalla del sistema tiene esa información
- Respondes en español mexicano, directo y con números específicos
- Cuando des porcentajes, siempre incluye los números absolutos
- Si detectas problemas (secciones sin capturista, municipios con avance bajo), señálalos proactivamente
- Para "¿qué debo atender hoy?" prioriza: (1) secciones sin estructura, (2) municipios con avance < 5%, (3) riesgo alto concentrado, (4) ritmo por debajo del necesario para la meta
- Para "¿alcanzamos la meta?": calcula días restantes, ritmo actual y ritmo necesario; da un veredicto claro

REGLAS:
- No reveles la estructura interna de la base de datos ni nombres de tablas/funciones
- No des instrucciones técnicas (SQL, API, etc.)
- No compartas datos de otros municipios si el usuario es coordinador municipal
- Formatea con negritas y listas cuando ayude a la claridad
- Máximo 350 palabras. Sé conciso: cifras primero, explicación breve.

El usuario que pregunta tiene el siguiente perfil y datos:`

const num = (x: any) => Number(x) || 0
const byDesc = (k: string) => (a: any, b: any) => num(b[k]) - num(a[k])
const pick = (o: any, keys: string[]) => Object.fromEntries(keys.filter(k => o[k] !== undefined).map(k => [k, o[k]]))

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '')
  let licenciaId: string | null = null, usuarioId: string | null = null
  const log = async (ok: boolean, extra: Record<string, unknown> = {}) => {
    try { await admin.from('consulta_ia_log').insert({ licencia_id: licenciaId, usuario_id: usuarioId, exito: ok, ...extra }) } catch (_e) { /* best effort */ }
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'No autorizado.' }, 401)

    const sb = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_ANON_KEY') ?? '', { global: { headers: { Authorization: authHeader } } })
    const { data: { user } } = await sb.auth.getUser()
    if (!user) return json({ error: 'No autorizado.' }, 401)
    usuarioId = user.id

    const { data: perfil } = await sb.from('usuarios').select('nombre, rol, municipio, seccion, licencia_id').eq('id', user.id).single()
    if (!perfil || !perfil.licencia_id) return json({ error: 'Usuario sin perfil.' }, 403)
    licenciaId = perfil.licencia_id

    const { pregunta, historial } = await req.json()
    if (!pregunta || typeof pregunta !== 'string' || pregunta.trim().length < 3) return json({ error: 'Escribe tu pregunta.' }, 400)

    // ── Semaforo de cuota (solo 'bloqueado' = 300% detiene) ──
    let cuotaInfo: Record<string, unknown> | null = null
    try {
      const { data: cuota } = await admin.rpc('consulta_ia_estado_licencia', { p_licencia: licenciaId })
      if (cuota) {
        cuotaInfo = pick(cuota, ['nivel','pct','usadas','referencia','restantes','freno_en','periodo'])
        if (cuota.permitido === false) {
          await log(false, { error: 'rechazado_cuota' })
          return json({ error: 'El módulo de consultas de esta licencia superó 3 veces su referencia mensual y se detuvo por seguridad. Avisa al administrador.', cuota: cuotaInfo }, 429)
        }
      }
    } catch (_e) { /* si falla la cuota, se deja pasar */ }

    const [kpis, avSec, capStats, ritmo, calidad, demo, lic, encuestas] = await Promise.all([
      sb.rpc('get_war_room_kpis').then(r => r.data),
      sb.rpc('get_avance_secciones').then(r => r.data),
      sb.rpc('get_capturistas_stats').then(r => r.data),
      sb.rpc('get_ritmo_capturas').then(r => r.data),
      sb.rpc('get_calidad_padron').then(r => r.data),
      sb.rpc('get_perfil_demografico').then(r => r.data),
      sb.from('licencias').select('meta_estatal, fecha_eleccion, estado, municipio').eq('id', perfil.licencia_id).single().then(r => r.data),
      sb.from('v_opinion_municipio').select('encuesta, encuesta_estado, encuesta_fecha, municipio, entrevistas, resultados, margen_error_pct, confiabilidad').then(r => r.data),
    ])

    const ctx: Record<string, unknown> = {
      usuario: { nombre: perfil.nombre, rol: perfil.rol, municipio: perfil.municipio || 'Estado completo', seccion: perfil.seccion || 'Todas' },
      fecha_hoy: new Date().toISOString().slice(0, 10),
    }
    if (lic) {
      ctx.licencia = lic
      if (lic.fecha_eleccion) ctx.dias_a_eleccion = Math.ceil((new Date(lic.fecha_eleccion).getTime() - Date.now()) / 86400000)
    }

    if (kpis && typeof kpis === 'object') {
      const { por_seccion: _ps, ...kpisCompacto } = kpis as Record<string, unknown>
      ctx.war_room = kpisCompacto
    }

    if (Array.isArray(avSec) && avSec.length) {
      const est = (s: any) => num(s.activistas ?? s.capturistas ?? s.estructura)
      const porMun: Record<string, any> = {}
      for (const s of avSec) {
        const m = s.municipio || s.mun || 'SIN MUNICIPIO'
        porMun[m] ??= { municipio: m, secciones: 0, capturados: 0, meta: 0, sin_capturas: 0, sin_estructura: 0 }
        porMun[m].secciones++; porMun[m].capturados += num(s.capturados); porMun[m].meta += num(s.meta)
        if (num(s.capturados) === 0) porMun[m].sin_capturas++
        if (est(s) === 0) porMun[m].sin_estructura++
      }
      const munArr = Object.values(porMun).map((m: any) => ({ ...m, pct: m.meta ? +(m.capturados / m.meta * 100).toFixed(1) : 0 })).sort(byDesc('pct'))
      const secKeys = ['seccion','municipio','capturados','meta','pct','activistas','capturistas']
      const sorted = [...avSec].sort(byDesc('pct'))
      ctx.secciones = {
        total: avSec.length,
        sin_capturas: avSec.filter((s: any) => num(s.capturados) === 0).length,
        sin_estructura: avSec.filter((s: any) => est(s) === 0).length,
        por_municipio: munArr,
        top_8: sorted.slice(0, 8).map(s => pick(s, secKeys)),
        bottom_8: sorted.slice(-8).reverse().map(s => pick(s, secKeys)),
        sin_estructura_lista: avSec.filter((s: any) => est(s) === 0).slice(0, 20).map((s: any) => `${s.seccion} (${s.municipio || s.mun})`),
      }
    }

    if (capStats && Array.isArray(capStats.capturistas)) {
      const caps = capStats.capturistas
      const k = ['nombre','municipio','seccion','total','meta','pct_meta','score','seguros','riesgo_alto']
      const porMun: Record<string, any> = {}
      for (const c of caps) {
        const m = c.municipio || 'SIN MUNICIPIO'
        porMun[m] ??= { municipio: m, capturistas: 0, capturas: 0, sin_capturar: 0 }
        porMun[m].capturistas++; porMun[m].capturas += num(c.total)
        if (num(c.total) === 0) porMun[m].sin_capturar++
      }
      const byTotal = [...caps].sort(byDesc('total'))
      ctx.capturistas = {
        alcance: capStats.alcance, total: capStats.num_capturistas ?? caps.length,
        sin_asignar: capStats.sin_asignar, capturas_externas: capStats.capturas_externas,
        sin_capturar: caps.filter((c: any) => num(c.total) === 0).length,
        con_meta_cumplida: caps.filter((c: any) => num(c.pct_meta) >= 100).length,
        promedio_capturas: +(caps.reduce((a: number, c: any) => a + num(c.total), 0) / (caps.length || 1)).toFixed(1),
        por_municipio: Object.values(porMun),
        top_8: byTotal.slice(0, 8).map(c => pick(c, k)),
        bottom_8_con_capturas: byTotal.filter((c: any) => num(c.total) > 0).slice(-8).reverse().map(c => pick(c, k)),
      }
    } else if (capStats) {
      ctx.capturistas = pick(capStats, ['alcance','num_capturistas','sin_asignar','capturas_externas'])
    }

    if (ritmo) ctx.ritmo = ritmo
    if (calidad) ctx.calidad_padron = calidad
    if (demo) ctx.perfil_demografico = demo
    ctx.encuestas = (Array.isArray(encuestas) && encuestas.length) ? encuestas : 'Sin encuestas con resultados para este alcance.'

    const systemContent = SYSTEM_PROMPT + '\n\n```json\n' + JSON.stringify(ctx) + '\n```'

    const messages: Array<{ role: string; content: string }> = []
    if (Array.isArray(historial)) {
      for (const h of historial.slice(-6)) {
        if (h.role === 'user' || h.role === 'assistant') messages.push({ role: h.role, content: String(h.content).slice(0, 3000) })
      }
    }
    messages.push({ role: 'user', content: pregunta.slice(0, 1500) })

    const apiKey = Deno.env.get('VISION_API_KEY')
    if (!apiKey) return json({ error: 'Servicio de IA no configurado.' }, 503)

    const t0 = Date.now()
    const aiResp = await fetch(ANTHROPIC_URL, {
      method: 'POST',
      headers: { 'x-api-key': apiKey, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
      body: JSON.stringify({ model: MODELO, max_tokens: MAX_TOKENS, system: systemContent, messages }),
    })
    const ms = Date.now() - t0

    if (!aiResp.ok) {
      const err = await aiResp.text()
      console.error('Claude error:', aiResp.status, err, '| ctx chars:', systemContent.length)
      await log(false, { modelo: MODELO, ms, error: err.slice(0, 300) })
      return json({ error: 'No pude procesar la consulta. Intenta de nuevo.' }, 502)
    }

    const aiData = await aiResp.json()
    const respuesta = (aiData?.content?.[0]?.text ?? '').trim()
    const usage = aiData?.usage || {}
    await log(true, { modelo: MODELO, ms, tokens_in: usage.input_tokens ?? null, tokens_out: usage.output_tokens ?? null, pregunta: pregunta.slice(0, 200) })
    return json({ respuesta, tokens: { input: usage.input_tokens, output: usage.output_tokens }, ms, modelo: MODELO, cuota: cuotaInfo }, 200)

  } catch (e) {
    console.error('Error:', e)
    await log(false, { error: String(e).slice(0, 300) })
    return json({ error: 'Error de conexión. Intenta de nuevo.' }, 500)
  }
})

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}
