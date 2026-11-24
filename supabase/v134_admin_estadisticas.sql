-- v134: estadísticas del modo admin calculadas en el servidor
-- 1) admin_user_list() añade: last_seen (último uso de la app), last_data (último dato guardado)
--    y last_workout (último entreno guardado o editado).
-- 2) admin_usage_stats(p_days) devuelve todo el panel «Uso de la app» ya resumido,
--    sin descargar los eventos uno a uno (antes había un límite de 20.000 eventos).
-- Solo para administradoras (tabla public.admins).

create index if not exists events_user_created_idx on public.events (user_id, created_at desc);

drop function if exists public.admin_user_list();
create function public.admin_user_list()
returns table(
  user_id uuid, email text, created_at timestamptz, last_sign_in_at timestamptz,
  workouts bigint, name text, free_shop boolean, is_admin boolean,
  last_seen timestamptz, last_data timestamptz, last_workout timestamptz)
language plpgsql stable security definer set search_path to ''
as $function$
begin
  if not exists (select 1 from public.admins a where a.user_id = (select auth.uid())) then
    raise exception 'Solo para administradoras';
  end if;
  return query
    select u.id, u.email::text, u.created_at, u.last_sign_in_at,
      (select count(*) from public.docs d where d.user_id = u.id and d.id <> '_profile'),
      (select d.data->>'name' from public.docs d where d.user_id = u.id and d.id = '_profile'),
      exists (select 1 from public.free_shop f where f.user_id = u.id),
      exists (select 1 from public.admins a2 where a2.user_id = u.id),
      (select max(e.created_at) from public.events e where e.user_id = u.id),
      (select max(d.updated_at) from public.docs d where d.user_id = u.id),
      (select max(d.updated_at) from public.docs d where d.user_id = u.id and d.id <> '_profile')
    from auth.users u order by u.created_at;
end $function$;

create or replace function public.admin_usage_stats(p_days integer default 30)
returns jsonb
language plpgsql stable security definer set search_path to ''
as $function$
declare
  tz constant text := 'Europe/Madrid';
  n integer := greatest(1, least(coalesce(p_days, 30), 365));
  today date := (now() at time zone 'Europe/Madrid')::date;
  first_day date;
  since timestamptz;
  today_start timestamptz;
  res jsonb;
begin
  if not exists (select 1 from public.admins a where a.user_id = (select auth.uid())) then
    raise exception 'Solo para administradoras';
  end if;
  first_day := today - (n - 1);
  since := first_day::timestamp at time zone tz;
  today_start := today::timestamp at time zone tz;

  with ev as (
    select e.user_id, e.session_id, e.type, e.view, e.seconds,
           (e.created_at at time zone tz)::date as dia
    from public.events e where e.created_at >= since
  )
  select jsonb_build_object(
    'days', n, 'today', today, 'since', since,
    'totals', jsonb_build_object(
      'users',         (select count(*) from auth.users),
      'new_users',     (select count(*) from auth.users u where u.created_at >= since),
      'active_today',  (select count(distinct e.user_id) from public.events e where e.created_at >= today_start),
      'active_7',      (select count(distinct e.user_id) from public.events e where e.created_at >= now() - interval '7 days'),
      'active_period', (select count(distinct user_id) from ev),
      'sessions',      (select count(distinct session_id) from ev),
      'secs',          (select coalesce(sum(seconds), 0) from ev where type = 'time'),
      'events',        (select count(*) from ev),
      'installed',     (select count(distinct user_id) from ev where type = 'start' and view = 'app instalada'),
      'workouts',      (select count(*) from public.docs d where d.id <> '_profile' and d.updated_at >= since)
    ),
    'daily', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'd', g.dia, 'users', coalesce(x.users, 0), 'sessions', coalesce(x.sessions, 0),
               'events', coalesce(x.events, 0), 'secs', coalesce(x.secs, 0), 'signups', coalesce(s.n, 0))
             order by g.dia), '[]'::jsonb)
      from (select gs::date as dia from generate_series(first_day::timestamp, today::timestamp, interval '1 day') gs) g
      left join (select dia, count(distinct user_id) users, count(distinct session_id) sessions, count(*) events,
                        coalesce(sum(seconds) filter (where type = 'time'), 0) secs
                 from ev group by dia) x on x.dia = g.dia
      left join (select (u.created_at at time zone tz)::date as dia, count(*) n
                 from auth.users u where u.created_at >= since group by 1) s on s.dia = g.dia
    ),
    'views', (
      select coalesce(jsonb_object_agg(v.view, v.n), '{}'::jsonb)
      from (select view, count(*) n from ev where type = 'view' and view is not null and view <> 'usage' group by view) v
    ),
    'view_secs', (
      select coalesce(jsonb_object_agg(v.view, v.n), '{}'::jsonb)
      from (select view, sum(seconds) n from ev where type = 'time' and view is not null and seconds > 0 group by view) v
    ),
    'per_user', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'user_id', p.user_id, 'sessions', p.sessions, 'secs', p.secs, 'days', p.days, 'top_view', p.top_view)), '[]'::jsonb)
      from (
        select e.user_id, count(distinct e.session_id) sessions,
               coalesce(sum(e.seconds) filter (where e.type = 'time'), 0) secs,
               count(distinct e.dia) days,
               (select e2.view from ev e2
                 where e2.user_id = e.user_id and e2.type = 'view' and e2.view is not null and e2.view <> 'usage'
                 group by e2.view order by count(*) desc limit 1) top_view
        from ev e group by e.user_id
      ) p
    )
  ) into res;
  return res;
end $function$;

revoke all on function public.admin_user_list() from public, anon;
grant execute on function public.admin_user_list() to authenticated;
revoke all on function public.admin_usage_stats(integer) from public, anon;
grant execute on function public.admin_usage_stats(integer) to authenticated;
