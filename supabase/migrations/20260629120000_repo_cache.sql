-- Cache of fetched repository history, shared across all visitors.
--
-- Anti-poisoning: row level security is enabled with a read-only policy for
-- clients. There are deliberately no insert/update/delete policies, so anon and
-- authenticated clients can never write to the cache. Only the `fetch-repo`
-- edge function writes here, using the service role key (which bypasses RLS)
-- after fetching the data straight from the canonical git host. Clients can
-- therefore read the cache but can never inject or overwrite its contents.

create table if not exists public.repo_cache (
  repo_key text primary key,
  host text not null,
  commits jsonb not null,
  commit_count integer not null,
  fetched_at timestamptz not null default now()
);

alter table public.repo_cache enable row level security;

drop policy if exists "Public can read repo cache" on public.repo_cache;
create policy "Public can read repo cache"
  on public.repo_cache
  for select
  to anon, authenticated
  using (true);
