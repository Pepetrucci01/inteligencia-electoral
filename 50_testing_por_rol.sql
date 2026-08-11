-- =====================================================================
-- 50_testing_por_rol.sql  ·  v2.1  ·  VOTERA / SIE Colima 2027
-- Verificacion automatica de los 9 roles contra la BASE (no el papel).
--
-- COMO SE USA: pegar completo en el SQL Editor de Supabase y ejecutar.
--   Devuelve 2 tablas: un resumen por veredicto y el detalle fila por fila.
--   Cualquier ❌ es un bug real. Los ⚠️ son inconclusos (revisar a mano).
--
-- POR QUE IMPERSONA: en el SQL Editor se corre como `postgres`, que SALTA
--   la RLS. Sin `set local role authenticated` + request.jwt.claims TODO
--   sale en verde falso. Cada prueba fija el sub del usuario demo y
--   vuelve a `reset role` al terminar.
--
-- NO PERSISTE NADA: las pruebas de escritura se auto-revierten con un
--   RAISE '__UNDO__' interno. Es seguro correrlo en staging cuantas veces
--   se quiera, incluso con testers trabajando.
--
-- HISTORIAL
--   v1  (11 ago) primera corrida. Detecto el hueco grave: coordinador_estatal
--       leia 0 de 14,275 ciudadanos (ninguna politica SELECT de `ciudadanos`
--       lo nombraba). Corregido por SQL 54.
--   v2  (11 ago) 3 correcciones de CRITERIO — la v1 pintaba rojos falsos:
--       (1) la lectura de `casillas` abierta a todos es correcta POR DISENO
--           (geografia electoral publica); el acotamiento vive en la
--           ESCRITURA (SQL 21) y ahora se prueba en el bloque C (N2).
--       (2) el INSERT de N1 manda seccion_electoral con casteo
--           (usuarios.seccion es TEXT, ciudadanos.seccion_electoral es INT).
--       (3) get_war_room_kpis: 'Rol no autorizado' es CORRECTO en los roles
--           que no son de War Room; solo es bug en mando + consulta.
--       Anadida verificacion de integridad municipio-vs-seccion en el
--       bloque A (vigila la limpieza del SQL 55).
--   v2.1 (11 ago) N2 usaba estatus='__prueba__' y chocaba con el CHECK
--       casillas_estatus_check antes de poder medir el alcance RLS.
--       Ahora hace `set estatus = estatus`: sigue siendo un UPDATE real
--       (evalua USING y WITH CHECK) pero no viola constraints ni cambia
--       valores.
--
-- LECCION DE FONDO: un RPC en verde NO prueba que la RLS de la tabla este
--   bien. Son dos caminos distintos a los mismos datos y el RPC
--   (SECURITY DEFINER) ENMASCARA el hueco de la tabla. Probar los dos.
-- =====================================================================

drop table if exists _rtest;
create temp table _rtest(
  n int, bloque text, rol text, email text,
  prueba text, resultado text, esperado text, veredicto text
);

do $$
declare
  r record;
  tot_ciu bigint; tot_cas bigint; tot_mun int;
  c_ciu bigint; c_cas bigint; n_mun int; s_mun text;
  f_rol text; f_mun text; f_lic uuid;
  v text; ok boolean; nfilas int; i int := 0; sec_usr int;
  estatales text[] := array['super_admin','admin','coordinador_estatal','consulta'];
  war_room  text[] := array['super_admin','admin','coordinador_estatal','coordinador','consulta'];
begin

  -- ================================================================
  -- A · BASE: cifras de control e integridad de datos
  -- ================================================================
  select count(*) into tot_ciu from public.ciudadanos;
  select count(*) into tot_cas from public.casillas;
  select count(distinct municipio) into tot_mun
    from public.ciudadanos where municipio is not null;

  i:=i+1; insert into _rtest values (i,'A · Base','—','—','Total ciudadanos',
    tot_ciu::text,'14275', case when tot_ciu=14275 then '✅' else '⚠️ revisar' end);

  i:=i+1; insert into _rtest values (i,'A · Base','—','—','Total casillas',
    tot_cas::text,'1033', case when tot_cas=1033 then '✅' else '❌ CARGA-01' end);

  i:=i+1; insert into _rtest values (i,'A · Base','—','—','Municipios distintos',
    tot_mun::text,'10', case when tot_mun=10 then '✅' else '❌ acentos/dedazos' end);

  -- Integridad municipio-vs-seccion contra `casillas` (fuente de verdad
  -- oficial, cargada en CARGA-01). Si esto sube de 0, algo esta volviendo
  -- a escribir el municipio mal (sospecha: se toma de la sesion del
  -- capturista en vez de derivarse de la seccion).
  select count(*) into nfilas
  from public.ciudadanos c
  join (select distinct numero_seccion, municipio from public.casillas) k
    on k.numero_seccion = c.seccion_electoral
  where c.municipio is distinct from k.municipio;

  i:=i+1; insert into _rtest values (i,'A · Base','—','—',
    'Ciudadanos con municipio ≠ al de su seccion',
    nfilas::text,'0', case when nfilas=0 then '✅' else '❌ datos sucios' end);

  -- ================================================================
  -- A · COLUMNAS: sin municipio/seccion poblados la RLS no puede filtrar
  -- (regla R6 de la T28: es prerrequisito del aislamiento territorial)
  -- ================================================================
  for r in
    select u.rol, count(*) tot,
           count(*) filter (where u.municipio is null) sin_mun,
           count(*) filter (where u.seccion  is null) sin_sec
    from public.usuarios u group by u.rol order by u.rol
  loop
    v := format('%s usuarios · sin_municipio=%s · sin_seccion=%s',
                r.tot, r.sin_mun, r.sin_sec);
    if r.rol = 'coordinador' and r.sin_mun > 0 then
      ok := false;                       -- filtra por municipio: obligatorio
    elsif r.rol in ('jefe_seccion','repr_casilla') and r.sin_sec > 0 then
      ok := false;                       -- filtran por seccion: obligatorio
    else
      ok := true;                        -- estatales: NULL es correcto
    end if;
    i:=i+1; insert into _rtest values (i,'A · Columnas', r.rol,'—',
      'Territoriales pobladas', v,'coordinador:mun=0 · jefe/repr:sec=0',
      case when ok then '✅' else '❌ RLS NO PODRA FILTRAR' end);
  end loop;

  -- ================================================================
  -- B · ALCANCE DE LECTURA por rol (impersonando)
  -- ================================================================
  for r in
    select u.id, u.rol, au.email
    from public.usuarios u join auth.users au on au.id = u.id
    where au.email like '%@demo.mx'
    order by array_position(array['super_admin','admin','coordinador_estatal',
             'coordinador','jefe_seccion','capturista','operador_cc',
             'repr_casilla','consulta'], u.rol), au.email
  loop
    begin
      perform set_config('request.jwt.claims',
              json_build_object('sub', r.id::text,'role','authenticated')::text, true);
      execute 'set local role authenticated';

      select count(*) into c_ciu from public.ciudadanos;
      select count(distinct municipio), string_agg(distinct municipio,', ')
        into n_mun, s_mun from public.ciudadanos;
      select count(*) into c_cas from public.casillas;
      begin select public.get_mi_rol()       into f_rol; exception when others then f_rol:='ERR'; end;
      begin select public.get_mi_municipio() into f_mun; exception when others then f_mun:='ERR'; end;
      begin select public.get_mi_licencia()  into f_lic; exception when others then f_lic:=null;  end;

      execute 'reset role';
    exception when others then
      execute 'reset role';
      c_ciu:=-1; n_mun:=-1; s_mun:='ERROR: '||SQLERRM; c_cas:=-1;
      f_rol:='ERR'; f_mun:='ERR';
    end;

    -- ciudadanos: el corazon del aislamiento territorial
    if r.rol = any(estatales) then
      ok := (n_mun = tot_mun); v := 'todos los municipios';
    elsif r.rol in ('coordinador','jefe_seccion') then
      ok := (n_mun = 1);       v := 'exactamente 1 municipio';
    else
      ok := (c_ciu < tot_ciu); v := 'alcance acotado';
    end if;

    i:=i+1; insert into _rtest values (i,'B · Alcance', r.rol, r.email,
      'ciudadanos visibles',
      format('%s de %s · %s municipio(s): %s',
             c_ciu, tot_ciu, n_mun, coalesce(left(s_mun,60),'—')),
      v, case when ok then '✅' else '❌ AISLAMIENTO ROTO' end);

    -- casillas: la LECTURA es abierta por diseno (geografia publica).
    -- El acotamiento real se prueba en el bloque C (N2).
    i:=i+1; insert into _rtest values (i,'B · Alcance', r.rol, r.email,
      'casillas visibles (lectura)',
      format('%s de %s', c_cas, tot_cas),'1033 para todos (por diseno)',
      case when c_cas = tot_cas then '✅' else '⚠️ inesperado' end);

    i:=i+1; insert into _rtest values (i,'B · Funciones', r.rol, r.email,
      'get_mi_rol()', coalesce(f_rol,'NULL'), r.rol,
      case when f_rol = r.rol then '✅' else '❌ DESAJUSTE' end);

    i:=i+1; insert into _rtest values (i,'B · Funciones', r.rol, r.email,
      'get_mi_licencia()', coalesce(f_lic::text,'NULL'),'no NULL',
      case when f_lic is null then '❌' else '✅' end);
  end loop;

  -- ================================================================
  -- C · PRUEBAS NEGATIVAS DE ESCRITURA
  -- Cada bloque intenta escribir y se auto-revierte con RAISE '__UNDO__'.
  -- ================================================================
  for r in
    select u.id, u.rol, au.email, u.municipio, u.seccion
    from public.usuarios u join auth.users au on au.id = u.id
    where au.email like '%@demo.mx'
      and u.rol in ('consulta','coordinador','jefe_seccion','capturista',
                    'operador_cc','repr_casilla','coordinador_estatal')
    order by u.rol, au.email
  loop
    sec_usr := coalesce(nullif(r.seccion::text,'')::int, 138);

    ---------------------------------------------------------------
    -- N1 · INSERT en ciudadanos  (verifica el SQL 31)
    -- consulta y operador_cc DEBEN quedar bloqueados;
    -- los roles de captura DEBEN poder insertar (flujo de campo).
    ---------------------------------------------------------------
    begin
      perform set_config('request.jwt.claims',
              json_build_object('sub', r.id::text,'role','authenticated')::text, true);
      execute 'set local role authenticated';
      insert into public.ciudadanos (nombre, licencia_id, municipio, seccion_electoral)
      values ('__PRUEBA_RLS__', public.get_mi_licencia(),
              coalesce(r.municipio,'COLIMA'), sec_usr);
      raise exception '__UNDO__';
    exception
      when sqlstate '42501' then
        execute 'reset role';
        i:=i+1; insert into _rtest values (i,'C · Escritura', r.rol, r.email,
          'N1 · INSERT ciudadanos','BLOQUEADO',
          case when r.rol in ('consulta','operador_cc')
               then 'DEBE bloquear' else 'debe permitir' end,
          case when r.rol in ('consulta','operador_cc')
               then '✅' else '❌ flujo de campo roto' end);
      when others then
        execute 'reset role';
        if SQLERRM = '__UNDO__' then
          i:=i+1; insert into _rtest values (i,'C · Escritura', r.rol, r.email,
            'N1 · INSERT ciudadanos','PERMITIDO',
            case when r.rol in ('consulta','operador_cc')
                 then 'DEBE bloquear' else 'debe permitir' end,
            case when r.rol in ('consulta','operador_cc')
                 then '❌❌ HUECO GRAVE' else '✅' end);
        else
          i:=i+1; insert into _rtest values (i,'C · Escritura', r.rol, r.email,
            'N1 · INSERT ciudadanos','error: '||left(SQLERRM,70),'—','⚠️ revisar');
        end if;
    end;

    ---------------------------------------------------------------
    -- N2 · UPDATE de casillas de OTRA seccion  (verifica el SQL 21)
    -- Este es el acotamiento REAL del Dia E. `set estatus = estatus`
    -- es un UPDATE que evalua USING y WITH CHECK sin cambiar valores
    -- ni violar el CHECK casillas_estatus_check.
    ---------------------------------------------------------------
    begin
      perform set_config('request.jwt.claims',
              json_build_object('sub', r.id::text,'role','authenticated')::text, true);
      execute 'set local role authenticated';
      update public.casillas set estatus = estatus
       where numero_seccion is distinct from sec_usr;
      get diagnostics nfilas = row_count;
      raise exception '__UNDO__';
    exception
      when sqlstate '42501' then
        execute 'reset role';
        i:=i+1; insert into _rtest values (i,'C · Escritura', r.rol, r.email,
          'N2 · UPDATE casillas de otra seccion','BLOQUEADO','0 filas','✅');
      when others then
        execute 'reset role';
        if SQLERRM = '__UNDO__' then
          i:=i+1; insert into _rtest values (i,'C · Escritura', r.rol, r.email,
            'N2 · UPDATE casillas de otra seccion', nfilas||' filas','0 filas',
            case when nfilas = 0 then '✅'
                 when r.rol in ('coordinador','coordinador_estatal')
                   then 'ℹ️ mando, alcance amplio por diseno'
                 else '❌ HUECO (SQL 21)' end);
        else
          i:=i+1; insert into _rtest values (i,'C · Escritura', r.rol, r.email,
            'N2 · UPDATE casillas de otra seccion','error: '||left(SQLERRM,70),
            '—','⚠️ revisar');
        end if;
    end;

    ---------------------------------------------------------------
    -- N3 · coordinador saca un ciudadano de su municipio
    -- (verifica el WITH CHECK anadido por el SQL 31: sin el, un
    --  coordinador podia mover filas fuera de su alcance o de su licencia)
    ---------------------------------------------------------------
    if r.rol = 'coordinador' then
      begin
        perform set_config('request.jwt.claims',
                json_build_object('sub', r.id::text,'role','authenticated')::text, true);
        execute 'set local role authenticated';
        update public.ciudadanos set municipio = '__OTRO__'
         where ctid in (select ctid from public.ciudadanos limit 1);
        get diagnostics nfilas = row_count;
        raise exception '__UNDO__';
      exception
        when sqlstate '42501' then
          execute 'reset role';
          i:=i+1; insert into _rtest values (i,'C · Escritura', r.rol, r.email,
            'N3 · mover de municipio','BLOQUEADO por WITH CHECK','DEBE bloquear','✅');
        when others then
          execute 'reset role';
          if SQLERRM = '__UNDO__' then
            i:=i+1; insert into _rtest values (i,'C · Escritura', r.rol, r.email,
              'N3 · mover de municipio',
              case when nfilas>0 then 'PASO ('||nfilas||' filas)'
                   else 'sin filas alcanzables' end,
              'DEBE bloquear',
              case when nfilas>0 then '❌ HUECO (SQL 31)' else '✅' end);
          else
            i:=i+1; insert into _rtest values (i,'C · Escritura', r.rol, r.email,
              'N3 · mover de municipio','error: '||left(SQLERRM,70),'—','⚠️');
          end if;
      end;
    end if;

    ---------------------------------------------------------------
    -- N4 · jefe_seccion sobre alertas de OTRA seccion
    -- (verifica el SQL 32: alertas_update_destinatario acotada a su seccion)
    ---------------------------------------------------------------
    if r.rol = 'jefe_seccion' then
      begin
        perform set_config('request.jwt.claims',
                json_build_object('sub', r.id::text,'role','authenticated')::text, true);
        execute 'set local role authenticated';
        update public.alertas set leida = true
         where seccion is distinct from r.seccion;
        get diagnostics nfilas = row_count;
        raise exception '__UNDO__';
      exception
        when sqlstate '42501' then
          execute 'reset role';
          i:=i+1; insert into _rtest values (i,'C · Escritura', r.rol, r.email,
            'N4 · alertas de otra seccion','BLOQUEADO','0 filas','✅');
        when others then
          execute 'reset role';
          if SQLERRM = '__UNDO__' then
            i:=i+1; insert into _rtest values (i,'C · Escritura', r.rol, r.email,
              'N4 · alertas de otra seccion', nfilas||' filas','0 filas',
              case when nfilas=0 then '✅' else '❌ HUECO (SQL 32)' end);
          else
            i:=i+1; insert into _rtest values (i,'C · Escritura', r.rol, r.email,
              'N4 · alertas de otra seccion','error: '||left(SQLERRM,70),'—','⚠️');
          end if;
      end;
    end if;
  end loop;

  -- ================================================================
  -- D · RPCs por rol
  -- get_war_room_kpis solo debe responder a mando + consulta.
  -- En los demas, 'Rol no autorizado' es el comportamiento CORRECTO
  -- (esos roles aterrizan en otro modulo y nunca lo llaman).
  -- Este bloque fue el que detecto el bug del rol `consulta` (SQL 49).
  -- ================================================================
  for r in
    select u.id, u.rol, au.email
    from public.usuarios u join auth.users au on au.id = u.id
    where au.email like '%@demo.mx' order by u.rol, au.email
  loop
    begin
      perform set_config('request.jwt.claims',
              json_build_object('sub', r.id::text,'role','authenticated')::text, true);
      execute 'set local role authenticated';
      perform public.get_war_room_kpis();
      execute 'reset role';
      i:=i+1; insert into _rtest values (i,'D · RPC', r.rol, r.email,
        'get_war_room_kpis()','responde',
        case when r.rol = any(war_room) then 'debe responder' else 'debe rechazar' end,
        case when r.rol = any(war_room) then '✅'
             else '❌ rol sin War Room lo ejecuta' end);
    exception when others then
      execute 'reset role';
      i:=i+1; insert into _rtest values (i,'D · RPC', r.rol, r.email,
        'get_war_room_kpis()','RECHAZA: '||left(SQLERRM,50),
        case when r.rol = any(war_room) then 'debe responder' else 'debe rechazar' end,
        case when r.rol = any(war_room) then '❌ 400 en el hub' else '✅ por diseno' end);
    end;

    begin
      perform set_config('request.jwt.claims',
              json_build_object('sub', r.id::text,'role','authenticated')::text, true);
      execute 'set local role authenticated';
      perform public.get_avance_por_seccion();
      execute 'reset role';
      i:=i+1; insert into _rtest values (i,'D · RPC', r.rol, r.email,
        'get_avance_por_seccion()','responde','sin RAISE','✅');
    exception when others then
      execute 'reset role';
      i:=i+1; insert into _rtest values (i,'D · RPC', r.rol, r.email,
        'get_avance_por_seccion()','ERROR: '||left(SQLERRM,50),'sin RAISE','⚠️');
    end;
  end loop;

  execute 'reset role';
end $$;

-- ================================================================
-- RESULTADO: primero el resumen, luego el detalle
-- ================================================================
select veredicto, count(*) as pruebas
from _rtest group by veredicto order by 2 desc;

select n, bloque, rol, email, prueba, resultado, esperado, veredicto
from _rtest order by n;

-- =====================================================================
-- LO QUE ESTE SCRIPT NO PUEDE VERIFICAR (necesita navegador):
--   · aterrizaje de login por rol
--   · pestanas ocultas por rol (T12 / v76)
--   · botones de escritura ocultos para `consulta` (theme.js)
--   · guards por URL directa a un modulo prohibido
--   · banner de "modo reserva" del War Room (v74)
--   · captura real de un simpatizante desde el modulo
--   · perdida de escritura del call center con la red caida (v88)
--   · cierre del Dia E
-- Son ~20 pruebas de 2 minutos cada una. Ver el checklist de testing.
-- =====================================================================
