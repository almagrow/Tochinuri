-- TochiNuri v99: «Animar a entrenar» y retos por ejercicio (con o sin monedas, o juntos).
-- Solo añade cosas: la versión publicada (v94) sigue funcionando igual y no ve los retos nuevos.
do $$ declare c record; begin
  for c in select conname,pg_get_constraintdef(oid) d from pg_constraint where conrelid='public.friend_duels'::regclass and contype='c' loop
    if c.d like '%kind%' or c.d like '%stake%' then execute format('alter table public.friend_duels drop constraint %I',c.conname); end if;
  end loop; end $$;
alter table public.friend_duels add column if not exists ex text, add column if not exists mode text not null default 'vs';
alter table public.friend_duels add constraint friend_duels_kind_chk check (kind in ('days','kg','ex')),
  add constraint friend_duels_stake_chk check (stake in (0,20,50,100)),
  add constraint friend_duels_mode_chk check (mode in ('vs','team')),
  add constraint friend_duels_ex_chk check ((kind='ex')=(ex is not null and length(ex) between 1 and 60));

create or replace function public.duel_list()
 returns table(id uuid, kind text, stake integer, wk date, status text, mine boolean, my_score integer, their_score integer, friend_id uuid, friend_name text, created_at timestamptz)
 language sql stable security definer set search_path to 'public' as $f$
  select d.id,d.kind,d.stake,d.wk,d.status,d.a=auth.uid(),
    case when d.a=auth.uid() then d.a_score else d.b_score end,
    case when d.a=auth.uid() then d.b_score else d.a_score end,
    case when d.a=auth.uid() then d.b else d.a end,
    coalesce(p.name,''),d.created_at
  from friend_duels d left join friend_profiles p on p.user_id=case when d.a=auth.uid() then d.b else d.a end
  where (d.a=auth.uid() or d.b=auth.uid()) and d.wk>=madrid_monday()-56 and d.kind in ('days','kg') and d.stake>0
  order by d.wk desc,d.created_at desc $f$;

create or replace function public.duel_list2()
 returns table(id uuid, kind text, stake integer, wk date, status text, mine boolean, my_score integer, their_score integer, friend_id uuid, friend_name text, created_at timestamptz, ex text, mode text)
 language sql stable security definer set search_path to 'public' as $f$
  select d.id,d.kind,d.stake,d.wk,d.status,d.a=auth.uid(),
    case when d.a=auth.uid() then d.a_score else d.b_score end,
    case when d.a=auth.uid() then d.b_score else d.a_score end,
    case when d.a=auth.uid() then d.b else d.a end,
    coalesce(p.name,''),d.created_at,d.ex,d.mode
  from friend_duels d left join friend_profiles p on p.user_id=case when d.a=auth.uid() then d.b else d.a end
  where (d.a=auth.uid() or d.b=auth.uid()) and d.wk>=madrid_monday()-56
  order by d.wk desc,d.created_at desc $f$;

create or replace function public.duel_create2(p_friend uuid, p_kind text, p_stake integer, p_ex text default null, p_mode text default 'vs')
 returns uuid language plpgsql security definer set search_path to 'public' as $f$
declare uid uuid:=auth.uid(); w date:=madrid_monday(); nid uuid; x text:=nullif(left(trim(coalesce(p_ex,'')),60),''); m text:=coalesce(p_mode,'vs');
begin
  if uid is null then raise exception 'not_signed_in'; end if;
  if not exists(select 1 from friendships where user_id=uid and friend_id=p_friend) then raise exception 'not_friend'; end if;
  if p_kind<>'ex' then x:=null; m:='vs'; end if;
  if m='team' then p_stake:=0; end if;
  if exists(select 1 from friend_duels where wk=w and status in ('pending','accepted') and ((a=uid and b=p_friend) or (a=p_friend and b=uid))
            and kind=p_kind and coalesce(lower(ex),'')=coalesce(lower(x),'')) then raise exception 'already'; end if;
  if (select count(*) from friend_duels where wk=w and status in ('pending','accepted') and ((a=uid and b=p_friend) or (a=p_friend and b=uid)))>=3 then raise exception 'too_many'; end if;
  insert into friend_duels(a,b,kind,stake,wk,ex,mode) values(uid,p_friend,p_kind,p_stake,w,x,m) returning id into nid;
  return nid;
end $f$;

create or replace function public.duel_answer(p_id uuid, p_accept boolean)
 returns void language plpgsql security definer set search_path to 'public' as $f$
begin
  update friend_duels set status=case when p_accept then 'accepted' else 'declined' end
   where id=p_id and b=auth.uid() and status='pending' and wk=madrid_monday();
  if not found then raise exception 'not_found'; end if;
  if p_accept then
    update friend_duels d set a_score=coalesce(case when d.kind='days' then (fa.stats->>'week')::int else (fa.stats->>'kg')::int end,0)
      from friend_profiles fa where d.id=p_id and d.kind in ('days','kg') and fa.user_id=d.a and fa.stats->>'wk'=d.wk::text;
    update friend_duels d set b_score=coalesce(case when d.kind='days' then (fb.stats->>'week')::int else (fb.stats->>'kg')::int end,0)
      from friend_profiles fb where d.id=p_id and d.kind in ('days','kg') and fb.user_id=d.b and fb.stats->>'wk'=d.wk::text;
  end if;
end $f$;

create or replace function public.duel_score(p_id uuid, p_score integer)
 returns void language sql security definer set search_path to 'public' as $f$
  update friend_duels set a_score=case when a=auth.uid() then greatest(0,least(p_score,1000000)) else a_score end,
                          b_score=case when b=auth.uid() then greatest(0,least(p_score,1000000)) else b_score end
   where id=p_id and kind='ex' and status='accepted' and wk=madrid_monday() and (a=auth.uid() or b=auth.uid()) $f$;

-- friends_publish: igual que antes, pero solo actualiza los retos de días y kg
create or replace function public.friends_publish(p_name text, p_stats jsonb)
 returns void language plpgsql security definer set search_path to 'public' as $function$
declare st jsonb; uid uuid:=auth.uid(); lst jsonb:='[]'::jsonb; e jsonb; n int:=0;
begin
  if jsonb_typeof(p_stats->'last')='array' then
    for e in select * from jsonb_array_elements(p_stats->'last') loop
      exit when n>=6;
      if jsonb_typeof(e)='object' then
        lst:=lst||jsonb_build_array(jsonb_build_object('id',left(coalesce(e->>'id',''),40),'d',left(coalesce(e->>'d',''),10),'t',left(coalesce(e->>'t',''),60),'r',left(coalesce(e->>'r',''),30),'ty',left(coalesce(e->>'ty',''),12)));
        n:=n+1;
      end if;
    end loop;
  end if;
  st:=jsonb_build_object('week',coalesce((p_stats->>'week')::int,0),'month',coalesce((p_stats->>'month')::int,0),'streak',coalesce((p_stats->>'streak')::int,0),
    'kg',coalesce((p_stats->>'kg')::int,0),'ch',coalesce((p_stats->>'ch')::int,0),'mkg',coalesce((p_stats->>'mkg')::int,0),'mch',coalesce((p_stats->>'mch')::int,0),
    'mpr',coalesce((p_stats->>'mpr')::int,0),'tot',coalesce((p_stats->>'tot')::int,0),'bd',coalesce((p_stats->>'bd')::int,0),
    'pl',coalesce((p_stats->>'pl')::int,0),'pk',left(coalesce(p_stats->>'pk',''),10),'pn',left(coalesce(p_stats->>'pn',''),20),
    'wk',left(coalesce(p_stats->>'wk',''),10),'mo',left(coalesce(p_stats->>'mo',''),7),'last',lst);
  update friend_profiles set name=left(coalesce(p_name,''),40),stats=st,updated_at=now() where user_id=uid;
  if (st->>'wk') ~ '^\d{4}-\d{2}-\d{2}$' then
    update friend_duels set a_score=case when kind='days' then (st->>'week')::int else (st->>'kg')::int end where a=uid and status='accepted' and kind in ('days','kg') and wk=(st->>'wk')::date;
    update friend_duels set b_score=case when kind='days' then (st->>'week')::int else (st->>'kg')::int end where b=uid and status='accepted' and kind in ('days','kg') and wk=(st->>'wk')::date;
  end if;
end $function$;

-- Animar a entrenar
create table if not exists public.friend_nudges(
  id uuid primary key default gen_random_uuid(),
  from_user uuid not null references auth.users(id) on delete cascade,
  to_user uuid not null references auth.users(id) on delete cascade,
  msg text not null check (length(msg) between 1 and 80),
  created_at timestamptz not null default now(),
  seen_at timestamptz,
  check (from_user<>to_user));
create index if not exists friend_nudges_to_idx on public.friend_nudges(to_user,created_at desc);
alter table public.friend_nudges enable row level security;

create or replace function public.nudge_send(p_to uuid, p_msg text)
 returns void language plpgsql security definer set search_path to 'public' as $f$
declare uid uuid:=auth.uid();
begin
  if uid is null then raise exception 'not_signed_in'; end if;
  if not exists(select 1 from friendships where user_id=uid and friend_id=p_to) then raise exception 'not_friend'; end if;
  if exists(select 1 from friend_nudges where from_user=uid and to_user=p_to and created_at>now()-interval '20 hours') then raise exception 'too_soon'; end if;
  insert into friend_nudges(from_user,to_user,msg) values(uid,p_to,left(coalesce(nullif(trim(p_msg),''),'¡Vamos a entrenar!'),80));
end $f$;

create or replace function public.nudge_inbox()
 returns table(id uuid, from_user uuid, from_name text, msg text, created_at timestamptz)
 language sql stable security definer set search_path to 'public' as $f$
  select n.id,n.from_user,coalesce(p.name,''),n.msg,n.created_at from friend_nudges n left join friend_profiles p on p.user_id=n.from_user
  where n.to_user=auth.uid() and n.seen_at is null and n.created_at>now()-interval '7 days' order by n.created_at desc limit 10 $f$;

create or replace function public.nudge_seen(p_ids uuid[])
 returns void language sql security definer set search_path to 'public' as $f$
  update friend_nudges set seen_at=now() where to_user=auth.uid() and id=any(p_ids) and seen_at is null $f$;

create or replace function public.nudge_sent()
 returns table(to_user uuid, created_at timestamptz)
 language sql stable security definer set search_path to 'public' as $f$
  select to_user,max(created_at) from friend_nudges where from_user=auth.uid() and created_at>now()-interval '20 hours' group by to_user $f$;

do $$ declare f text; begin
  foreach f in array array['duel_list2()','duel_create2(uuid,text,integer,text,text)','duel_score(uuid,integer)','nudge_send(uuid,text)','nudge_inbox()','nudge_seen(uuid[])','nudge_sent()'] loop
    execute format('revoke all on function public.%s from public, anon',f);
    execute format('grant execute on function public.%s to authenticated',f);
  end loop; end $$;
