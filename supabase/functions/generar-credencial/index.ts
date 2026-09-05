// generar-credencial — repone la contrasena de un miembro de la estructura
// ─────────────────────────────────────────────────────────────────────────────
// PROBLEMA QUE RESUELVE
// Al cargar la estructura se generan contrasenas temporales que se muestran UNA
// sola vez. Repartir 510 obligaba a manejar un CSV con todas ellas, y si alguien
// perdia la suya habia que volver a Pepe. Ahora cada coordinador repone la
// contrasena de SU gente desde el sistema: no hay archivos con contrasenas
// dando vueltas y nadie depende de nadie.
//
// QUIEN PUEDE SOBRE QUIEN
//   super_admin / admin / coordinador_estatal -> cualquiera de su licencia
//   coordinador                               -> solo su municipio
//   jefe_seccion                              -> solo capturistas de sus secciones
//   resto                                     -> nadie
// Nunca sobre super_admin ni admin: un coordinador no puede tomar la cuenta del
// candidato. Y nadie puede regenerar la suya propia por esta via (para eso esta
// el cambio de contrasena normal).
//
// La contrasena viaja en la respuesta UNA vez y no se guarda en ningun lado.
// En credenciales_log queda solo el registro de que se genero, para saber a
// quien ya se le entrego su acceso.
// ─────────────────────────────────────────────────────────────────────────────
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

const MAX_LOTE = 60

function passwordTemporal(): string {
  // 10 caracteres sin ambiguos (0/O, 1/l): se dictan por telefono sin errores.
  const abc = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789'
  const b = new Uint8Array(10); crypto.getRandomValues(b)
  return Array.from(b, x => abc[x % abc.length]).join('')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ ok: false, error: 'No autorizado' }, 401)

    const url = Deno.env.get('SUPABASE_URL') ?? ''
    const userClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } })
    const { data: { user } } = await userClient.auth.getUser()
    if (!user) return json({ ok: false, error: 'No autorizado' }, 401)

    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '')

    // Perfil de quien pide
    const { data: yo } = await admin.from('usuarios')
      .select('id, rol, municipio, licencia_id, nombre').eq('id', user.id).single()
    if (!yo) return json({ ok: false, error: 'Usuario sin perfil' }, 403)
    if (!yo.licencia_id) return json({ ok: false, error: 'Usuario sin licencia' }, 403)

    const ROLES_QUE_PUEDEN = ['super_admin', 'admin', 'coordinador_estatal', 'coordinador', 'jefe_seccion']
    if (!ROLES_QUE_PUEDEN.includes(yo.rol))
      return json({ ok: false, error: 'Tu rol no puede generar credenciales' }, 403)

    const body = await req.json().catch(() => null)
    const ids: string[] = Array.isArray(body?.usuario_ids) ? body.usuario_ids
      : (body?.usuario_id ? [body.usuario_id] : [])
    const motivo = String(body?.motivo ?? 'reenvio').slice(0, 40)
    if (!ids.length) return json({ ok: false, error: 'Falta usuario_id' }, 400)
    if (ids.length > MAX_LOTE) return json({ ok: false, error: `Maximo ${MAX_LOTE} por llamada` }, 400)

    // Secciones a cargo, solo si hace falta
    let seccionesJefe: string[] = []
    if (yo.rol === 'jefe_seccion') {
      const { data: asig } = await admin.from('asignaciones_seccion')
        .select('numero_seccion')
        .eq('usuario_id', yo.id).eq('activo', true).eq('licencia_id', yo.licencia_id)
      seccionesJefe = (asig ?? []).map((a: any) => String(a.numero_seccion))
      if (!seccionesJefe.length && yo.seccion) seccionesJefe = [String(yo.seccion)]
    }

    const esEstatal = ['super_admin', 'admin', 'coordinador_estatal'].includes(yo.rol)
    const norm = (s: unknown) =>
      String(s ?? '').toUpperCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim()

    const resultados: any[] = []
    for (const id of ids) {
      const r: any = { usuario_id: id, ok: false, password: null, error: null, nombre: null }
      try {
        const { data: obj } = await admin.from('usuarios')
          .select('id, nombre, email, rol, municipio, seccion, licencia_id, activo')
          .eq('id', id).maybeSingle()

        if (!obj) throw new Error('La persona no existe')
        if (obj.licencia_id !== yo.licencia_id) throw new Error('Pertenece a otra licencia')
        if (obj.id === yo.id) throw new Error('Para tu propia contrasena usa el cambio desde tu perfil')
        if (['super_admin', 'admin'].includes(obj.rol))
          throw new Error('No se pueden reponer credenciales de administradores')
        if (obj.activo === false) throw new Error('La persona esta dada de baja')

        // Alcance territorial
        if (!esEstatal) {
          if (yo.rol === 'coordinador') {
            if (norm(obj.municipio) !== norm(yo.municipio))
              throw new Error('Solo puedes generar credenciales de tu municipio')
          } else if (yo.rol === 'jefe_seccion') {
            const { data: asigObj } = await admin.from('asignaciones_seccion')
              .select('numero_seccion')
              .eq('usuario_id', obj.id).eq('activo', true).eq('licencia_id', yo.licencia_id)
            const secsObj = (asigObj ?? []).map((a: any) => String(a.numero_seccion))
            if (obj.seccion) secsObj.push(String(obj.seccion))
            if (!secsObj.some(s => seccionesJefe.includes(s)))
              throw new Error('Solo puedes generar credenciales de tus secciones')
          }
        }

        const password = passwordTemporal()
        const { error: ePwd } = await admin.auth.admin.updateUserById(obj.id, { password })
        if (ePwd) throw ePwd

        await admin.from('credenciales_log').insert({
          licencia_id: yo.licencia_id,
          usuario_id: obj.id,
          generada_por: yo.id,
          motivo,
        })

        r.ok = true; r.password = password; r.nombre = obj.nombre; r.email = obj.email
        r.municipio = obj.municipio; r.seccion = obj.seccion
      } catch (e: any) {
        r.error = e?.message ?? String(e)
      }
      resultados.push(r)
    }

    const okN = resultados.filter(x => x.ok).length
    await admin.from('audit_log').insert({
      licencia_id: yo.licencia_id, usuario_id: yo.id, usuario_nombre: yo.nombre,
      accion: 'generar_credencial', tabla: 'usuarios',
      detalle: { solicitadas: ids.length, generadas: okN, motivo },
    }).then(() => {}, () => {})

    return json({ ok: true, generadas: okN, resultados })
  } catch (err: any) {
    console.error('generar-credencial:', err?.message ?? err)
    return json({ ok: false, error: err?.message ?? String(err) }, 500)
  }
})
