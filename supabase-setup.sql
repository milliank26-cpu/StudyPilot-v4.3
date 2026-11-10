-- StudyPilot cloud storage: one private JSON document per authenticated user.
-- Run this in Supabase Dashboard → SQL Editor as project owner.
create table if not exists public.studypilot_user_data (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.studypilot_user_data enable row level security;

-- Users can only read their own record.
create policy "Users read their own StudyPilot data"
  on public.studypilot_user_data for select
  to authenticated
  using (auth.uid() = user_id);

-- Users can only create their own record.
create policy "Users insert their own StudyPilot data"
  on public.studypilot_user_data for insert
  to authenticated
  with check (auth.uid() = user_id);

-- Users can only update their own record.
create policy "Users update their own StudyPilot data"
  on public.studypilot_user_data for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Restrict direct table access to authenticated users.
revoke all on public.studypilot_user_data from anon;
grant select, insert, update on public.studypilot_user_data to authenticated;
