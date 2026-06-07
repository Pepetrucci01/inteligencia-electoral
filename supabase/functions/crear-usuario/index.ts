import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('No autorizado')

    // Cliente con token del usuario
    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } }
    )

    // Verificar rol
    const { data: { user } } = await supabaseUser.auth.getUser()
    if (!user) throw new Error('No autorizado')

    const { data: perfil } = await supabaseUser
      .from('usuarios')
      .select('rol, licencia_id')
      .eq('id', user.id)
      .single()

    if (!perfil || !['super_admin', 'admin'].includes(perfil.rol)) {
      throw new Error('Sin permisos para crear usuarios')
    }

    const { nombre, email, password, rol, municipio, seccion } = await req.json()
    if (!nombre || !email || !password) throw new Error('Nombre, email y contraseña son obligatorios')

    // Cliente admin
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // 1. Crear en Auth
    const { data: newUser, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    })
    if (authError) throw authError

    // 2. Insertar via función SECURITY DEFINER
    const { error: dbError } = await supabaseAdmin.rpc('crear_usuario_sistema', {
      p_id:          newUser.user.id,
      p_email:       email,
      p_nombre:      nombre,
      p_rol:         rol || 'capturista',
      p_municipio:   municipio || null,
      p_seccion:     seccion ? String(seccion) : null,
      p_licencia_id: perfil.licencia_id,
    })
    if (dbError) throw dbError

    return new Response(
      JSON.stringify({ ok: true, id: newUser.user.id }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (err) {
    console.error('Error:', err.message)
    return new Response(
      JSON.stringify({ ok: false, error: err.message }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
