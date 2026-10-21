-- Optional: free Supabase project for automatic outing reply sync.
-- Run this in Supabase > SQL Editor. Only outing details and replies are stored
-- (names, picked time slots, activity, gear). Never anyone's location.

create table if not exists public.outings (
  id text primary key,
  data jsonb not null,
  created_at timestamptz default now()
);

create table if not exists public.responses (
  outing_id text not null references public.outings(id) on delete cascade,
  name text not null,
  data jsonb not null,
  updated_at timestamptz default now(),
  primary key (outing_id, name)
);

alter table public.outings enable row level security;
alter table public.responses enable row level security;

-- Anyone with the (unguessable) outing id can read/write that outing's rows.
create policy "outings insert" on public.outings for insert to anon with check (true);
create policy "outings update" on public.outings for update to anon using (true);
create policy "outings read"   on public.outings for select to anon using (true);
create policy "responses insert" on public.responses for insert to anon with check (true);
create policy "responses update" on public.responses for update to anon using (true);
create policy "responses read"   on public.responses for select to anon using (true);
