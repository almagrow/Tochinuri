-- TochiNuri · estructura de la base de datos (ya aplicada en el proyecto "tochinuri" de Supabase)
-- Se guarda aquí como referencia o por si alguna vez hay que recrearla.

create table public.docs (
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  id text not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);
alter table public.docs enable row level security;
create policy "docs: leer los míos" on public.docs for select to authenticated using ((select auth.uid()) = user_id);
create policy "docs: crear los míos" on public.docs for insert to authenticated with check ((select auth.uid()) = user_id);
create policy "docs: cambiar los míos" on public.docs for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "docs: borrar los míos" on public.docs for delete to authenticated using ((select auth.uid()) = user_id);

create table public.admins (user_id uuid primary key references auth.users(id) on delete cascade);
alter table public.admins enable row level security;
create policy "admins: ver si soy admin" on public.admins for select to authenticated using ((select auth.uid()) = user_id);

create or replace function public.is_admin() returns boolean
language sql stable security invoker set search_path = ''
as $$ select exists (select 1 from public.admins where user_id = (select auth.uid())) $$;
revoke execute on function public.is_admin() from anon, public;
grant execute on function public.is_admin() to authenticated;

create table public.shop (id text primary key, data jsonb not null, created_at timestamptz not null default now());
alter table public.shop enable row level security;
create policy "shop: ver" on public.shop for select to authenticated using (true);
create policy "shop: añadir (admin)" on public.shop for insert to authenticated with check ((select public.is_admin()));
create policy "shop: cambiar (admin)" on public.shop for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "shop: quitar (admin)" on public.shop for delete to authenticated using ((select public.is_admin()));

-- Para hacer administradora a alguien (puede gestionar la tienda), una vez registrada:
-- insert into public.admins (user_id) select id from auth.users where email = 'su@email.com';

-- 20/11/2026 (v81): solicitudes de amistad. Funciones nuevas: friend_request, friend_requests_list,
-- friend_answer y friend_cancel; tabla friend_requests (RLS sin políticas: solo vía funciones).
-- friends_publish admite además mpr, tot, bd, pl, pk y pn. friends_disable borra también las solicitudes.
-- Hecho al publicar v81: friends_add ahora llama a friend_request (crea solicitud).

-- 21/11/2026 (v89): recordatorio en días fijos. push_prefs.days smallint[] (1=lunes … 7=domingo, check push_prefs_days_ok).
-- push_due() avisa «Hoy toca entrenar» (kind 'plan') si hoy es uno de tus días, a tu hora, y aún no hay entreno con fecha de hoy.
-- Tiene prioridad sobre los avisos de racha y de días sin entrenar; como mucho un aviso de cada tipo al día (push_log).
