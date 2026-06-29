-- A single-row counter of how many times the "Launch" button has been pressed.
--
-- Like the repo cache, clients can only read it. The counter is bumped through
-- the `increment_launches()` function, which is executable only by the service
-- role (used by the `fetch-repo` edge function), so visitors cannot inflate or
-- tamper with the count directly.

create table if not exists public.app_stats (
  id boolean primary key default true,
  launches bigint not null default 0,
  constraint app_stats_singleton check (id)
);

insert into public.app_stats (id, launches)
values (true, 0)
on conflict (id) do nothing;

alter table public.app_stats enable row level security;

drop policy if exists "Public can read app stats" on public.app_stats;
create policy "Public can read app stats"
  on public.app_stats
  for select
  to anon, authenticated
  using (true);

create or replace function public.increment_launches()
returns bigint
language sql
security definer
set search_path = public
as $$
  update public.app_stats set launches = launches + 1 where id returning launches;
$$;

revoke all on function public.increment_launches() from public, anon, authenticated;
grant execute on function public.increment_launches() to service_role;
