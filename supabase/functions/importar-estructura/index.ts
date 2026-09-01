// importar-estructura — carga masiva de estructura (VOTERA)
// ─────────────────────────────────────────────────────────────────────────────
// Version en lote de crear-usuario (Luis). Recibe hasta 60 filas por llamada y
// por cada una:
//   1. Busca el usuario por email (public.usuarios, lower(email)).
//   2. Si no existe: crea la cuenta en Auth con contrasena temporal y llama a
//      crear_usuario_sistema (la RPC de Luis) para la fila de usuarios.
//      Si existe: actualiza nombre/rol/municipio/seccion/telefono. NO toca su
//      contrasena. Si pertenece a OTRA licencia, se rechaza la fila.
//   3. Segun el tipo:
//        capturista / jefe_seccion -> asignaciones_seccion (desactiva las
//                                    anteriores, inserta la nueva con meta)
//        repr_casilla              -> asignaciones_representante
//        coordinador               -> solo usuarios (rol + municipio)
//   4. Devuelve el resultado fila por fila. La contrasena temporal viaja SOLO
//      en esta respuesta, una vez; el frontend la ofrece para descargar.
//
// La licencia SIEMPRE es la del usuario que llama (nunca viene en el payload).
// Auth manual (verify_jwt=false) igual que crear-usuario: el gateway rechaza
// el preflight OPTIONS si verify_jwt esta activo.
// Desplegado en staging el 31/08/2026 (version 1).
// ─────────────────────────────────────────────────────────────────────────────
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

const ROLES_OK = new Set(['capturista', 'jefe_seccion', 'coordinador', 'repr_casilla', 'operador_cc'])
const MAX_FILAS = 60

function passwordTemporal(): string {
  // 10 caracteres sin ambiguos (0/O, 1/l). Se cambia en el primer acceso.
  const abc = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789'
  const b = new Uint8Array(10); crypto.getRandomValues(b)
  return Array.from(b, x => abc[x % abc.length]).join('')
}
const norm = (s: unknown) => String(s ?? '').trim()
const normUpper = (s: unknown) => norm(s).toUpperCase()

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

    const { data: perfil } = await userClient.from('usuarios')
      .select('rol, licencia_id, nombre').eq('id', user.id).single()
    if (!perfil || !['super_admin', 'admin'].includes(perfil.rol))
      return json({ ok: false, error: 'Solo super_admin o admin pueden cargar estructura' }, 403)
    if (!perfil.licencia_id)
      return json({ ok: false, error: 'El usuario que importa no tiene licencia asignada' }, 403)
    const LIC = perfil.licencia_id as string

    const body = await req.json().catch(() => null)
    const filas: any[] = Array.isArray(body?.filas) ? body.filas : []
    if (!filas.length) return json({ ok: false, error: 'filas vacio' }, 400)
    if (filas.length > MAX_FILAS) return json({ ok: false, error: `Maximo ${MAX_FILAS} filas por llamada` }, 400)

    const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '')

    // Secciones validas de la licencia (casillas activas) — una sola consulta
    const { data: secRows } = await admin.from('casillas')
      .select('numero_seccion').eq('licencia_id', LIC).eq('activo', true)
    const SECCIONES = new Set((secRows ?? []).map((r: any) => Number(r.numero_seccion)))

    const hoy = new Date().toISOString().slice(0, 10)
    const resultados: any[] = []
    let creados = 0, actualizados = 0, errores = 0

    for (const f of filas) {
      const email = norm(f.email).toLowerCase()
      const nombre = norm(f.nombre)
      const rol = norm(f.rol || 'capturista')
      const municipio = normUpper(f.municipio) || null
      const seccion = f.seccion != null && f.seccion !== '' ? Number(f.seccion) : null
      const telefono = norm(f.telefono) || null
      const meta = f.meta_individual != null && f.meta_individual !== '' ? Number(f.meta_individual) : null
      const r: any = { email, nombre, rol, seccion, estado: 'error', error: null, password: null }

      try {
        if (!email || !email.includes('@')) throw new Error('email invalido')
        if (!nombre) throw new Error('nombre vacio')
        if (!ROLES_OK.has(rol)) throw new Error(`rol no permitido: ${rol}`)
        const necesitaSeccion = ['capturista', 'jefe_seccion', 'repr_casilla'].includes(rol)
        if (necesitaSeccion) {
          if (seccion == null || Number.isNaN(seccion)) throw new Error('seccion vacia')
          if (!SECCIONES.has(seccion)) throw new Error(`la seccion ${seccion} no existe en la carga maestra de esta licencia`)
        }
        if (rol === 'coordinador' && !municipio) throw new Error('coordinador sin municipio')

        // 1. ¿existe ya?
        const { data: ex } = await admin.from('usuarios')
          .select('id, licencia_id').ilike('email', email).maybeSingle()
        let uid: string

        if (ex) {
          if (ex.licencia_id && ex.licencia_id !== LIC)
            throw new Error('el email pertenece a otra licencia')
          uid = ex.id
          const { error: e2 } = await admin.from('usuarios').update({
            nombre, rol, municipio, seccion: seccion != null ? String(seccion) : null,
            telefono, activo: true, licencia_id: LIC, updated_at: new Date().toISOString(),
          }).eq('id', uid)
          if (e2) throw e2
          r.estado = 'actualizado'; actualizados++
        } else {
          // 2. Crear en Auth + RPC de Luis
          const password = passwordTemporal()
          const { data: nu, error: eAuth } = await admin.auth.admin.createUser({
            email, password, email_confirm: true,
            user_metadata: { nombre, rol, licencia_id: LIC, alta: 'importar-estructura' },
          })
          if (eAuth) throw eAuth
          uid = nu.user.id
          const { error: eRpc } = await admin.rpc('crear_usuario_sistema', {
            p_id: uid, p_email: email, p_nombre: nombre, p_rol: rol,
            p_municipio: municipio, p_seccion: seccion != null ? String(seccion) : null,
            p_licencia_id: LIC,
          })
          if (eRpc) {
            // no dejar la cuenta huerfana en Auth
            await admin.auth.admin.deleteUser(uid).catch(() => {})
            throw eRpc
          }
          if (telefono) await admin.from('usuarios').update({ telefono }).eq('id', uid)
          r.estado = 'creado'; r.password = password; creados++
        }

        // 3. Asignacion territorial
        if (rol === 'capturista' || rol === 'jefe_seccion') {
          await admin.from('asignaciones_seccion')
            .update({ activo: false, fecha_fin: hoy })
            .eq('licencia_id', LIC).eq('usuario_id', uid).eq('activo', true)
          const { error: eA } = await admin.from('asignaciones_seccion').insert({
            licencia_id: LIC, numero_seccion: seccion, usuario_id: uid,
            tipo_asignacion: rol, activo: true, fecha_inicio: hoy, meta_individual: meta,
          })
          if (eA) throw eA
        } else if (rol === 'repr_casilla') {
          await admin.from('asignaciones_representante')
            .update({ activa: false })
            .eq('licencia_id', LIC).eq('usuario_id', uid).eq('activa', true)
          const { error: eR } = await admin.from('asignaciones_representante').insert({
            licencia_id: LIC, numero_seccion: seccion, usuario_id: uid, activa: true,
          })
          if (eR) throw eR
        }
      } catch (e: any) {
        r.estado = 'error'; r.error = e?.message ?? String(e); errores++
      }
      resultados.push(r)
    }

    // Auditoria (best effort)
    await admin.from('audit_log').insert({
      licencia_id: LIC, usuario_id: user.id, usuario_nombre: perfil.nombre,
      accion: 'importar_estructura', tabla: 'usuarios',
      detalle: { filas: filas.length, creados, actualizados, errores },
    }).then(() => {}, () => {})

    return json({ ok: true, licencia_id: LIC, creados, actualizados, errores, resultados })
  } catch (err: any) {
    console.error('importar-estructura:', err?.message ?? err)
    return json({ ok: false, error: err?.message ?? String(err) }, 500)
  }
})
