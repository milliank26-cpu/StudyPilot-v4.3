begin;

-- StudyPilot V4.1: O Level/A Level profiles, general noticeboard and concept suggestions.
-- Additive migration: preserves existing V3/V4 planner records and curriculum rows.

create table if not exists public.student_academic_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  academic_level text not null check (academic_level in ('O Level','A Level')),
  updated_at timestamptz not null default now()
);

create table if not exists public.studypilot_notices (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  category text not null default 'announcement'
    check (category in ('announcement','exam_reminder','maintenance','study_tip','platform_update','instruction','other')),
  target_level text not null default 'all'
    check (target_level in ('all','O Level','A Level')),
  target_subject_id uuid null references public.curriculum_subjects(id) on delete set null,
  is_published boolean not null default false,
  created_by uuid references auth.users(id) on delete set null,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists studypilot_notices_published_idx
  on public.studypilot_notices (is_published, published_at desc);

create table if not exists public.studypilot_notice_reads (
  notice_id uuid not null references public.studypilot_notices(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (notice_id,user_id)
);

create table if not exists public.studypilot_concept_suggestions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  academic_level text not null check (academic_level in ('O Level','A Level')),
  subject_name text not null,
  topic_name text not null,
  subtopic_name text,
  concept_name text not null,
  description text,
  status text not null default 'pending'
    check (status in ('pending','reviewing','approved','declined')),
  admin_notes text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
create index if not exists studypilot_concept_suggestions_status_idx
  on public.studypilot_concept_suggestions (status,created_at desc);

alter table public.student_academic_profiles enable row level security;
alter table public.studypilot_notices enable row level security;
alter table public.studypilot_notice_reads enable row level security;
alter table public.studypilot_concept_suggestions enable row level security;

drop policy if exists "Admins read academic profiles" on public.student_academic_profiles;
create policy "Admins read academic profiles"
  on public.student_academic_profiles for select to authenticated
  using (public.studypilot_is_admin());

drop policy if exists "Students manage own academic profile" on public.student_academic_profiles;
create policy "Students manage own academic profile"
  on public.student_academic_profiles for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Students read notices for their audience" on public.studypilot_notices;
create policy "Students read notices for their audience"
  on public.studypilot_notices for select to authenticated
  using (
    is_published = true and (
      target_level = 'all'
      or exists (
        select 1 from public.student_academic_profiles p
        where p.user_id = auth.uid() and p.academic_level = studypilot_notices.target_level
      )
    ) and (
      target_subject_id is null
      or exists (
        select 1 from public.student_subjects ss
        where ss.user_id = auth.uid() and ss.subject_id = studypilot_notices.target_subject_id
      )
    )
  );

drop policy if exists "Admins manage notices" on public.studypilot_notices;
create policy "Admins manage notices"
  on public.studypilot_notices for all to authenticated
  using (public.studypilot_is_admin()) with check (public.studypilot_is_admin());

drop policy if exists "Students read own notice receipts" on public.studypilot_notice_reads;
create policy "Students read own notice receipts"
  on public.studypilot_notice_reads for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "Students create own notice receipts" on public.studypilot_notice_reads;
create policy "Students create own notice receipts"
  on public.studypilot_notice_reads for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "Students update own notice receipts" on public.studypilot_notice_reads;
create policy "Students update own notice receipts"
  on public.studypilot_notice_reads for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Students read own concept suggestions" on public.studypilot_concept_suggestions;
create policy "Students read own concept suggestions"
  on public.studypilot_concept_suggestions for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "Students submit concept suggestions" on public.studypilot_concept_suggestions;
create policy "Students submit concept suggestions"
  on public.studypilot_concept_suggestions for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "Admins manage concept suggestions" on public.studypilot_concept_suggestions;
create policy "Admins manage concept suggestions"
  on public.studypilot_concept_suggestions for all to authenticated
  using (public.studypilot_is_admin()) with check (public.studypilot_is_admin());

grant select, insert, update on public.student_academic_profiles to authenticated;
grant select on public.studypilot_notices to authenticated;
grant insert, update on public.studypilot_notice_reads to authenticated;
grant select, insert on public.studypilot_concept_suggestions to authenticated;
grant select, insert, update, delete on public.studypilot_notices to authenticated;
grant select, update on public.studypilot_concept_suggestions to authenticated;

-- The existing curriculum tables and student planner JSON are intentionally retained.
-- New O/A Level subjects use curriculum='UNEB' and level='O Level' or 'A Level'.

-- Resource library: authenticated students may read; administrators may manage.
alter table public.resources enable row level security;
revoke all on table public.resources from public, anon, authenticated;
grant select, insert, update, delete on table public.resources to authenticated;
do $$
declare resource_seq text;
begin
  resource_seq := pg_get_serial_sequence('public.resources','id');
  if resource_seq is not null then
    execute format('grant usage, select on sequence %s to authenticated', resource_seq);
  end if;
end $$;
drop policy if exists "Authenticated users read resources" on public.resources;
create policy "Authenticated users read resources"
  on public.resources for select to authenticated using (true);
drop policy if exists "Admins manage resources" on public.resources;
create policy "Admins manage resources"
  on public.resources for all to authenticated
  using (public.studypilot_is_admin()) with check (public.studypilot_is_admin());


-- Refresh the administrator overview with O/A curriculum and Noticeboard activity.
create or replace function public.studypilot_admin_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if not public.studypilot_is_admin() then
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'registered_users', (
      select count(*) from auth.users u
      where not exists (select 1 from public.studypilot_admins a where a.user_id = u.id)
    ),
    'active_users_30d', (
      select count(*) from public.studypilot_user_data d
      where d.updated_at >= now() - interval '30 days'
        and not exists (select 1 from public.studypilot_admins a where a.user_id = d.user_id)
    ),
    'subject_selections', (select count(*) from public.student_subjects),
    'published_subjects', (
      select count(*) from public.curriculum_subjects where is_published
    ),
    'o_level_subjects', (
      select count(*) from public.curriculum_subjects
      where curriculum = 'UNEB' and level = 'O Level' and is_published
    ),
    'a_level_subjects', (
      select count(*) from public.curriculum_subjects
      where curriculum = 'UNEB' and level = 'A Level' and is_published
    ),
    'total_official_concepts', (select count(*) from public.curriculum_concepts),
    'concept_completions', (
      select count(*)
      from public.studypilot_user_data d
      cross join lateral jsonb_array_elements(
        case when jsonb_typeof(d.data->'sessions') = 'array'
          then d.data->'sessions' else '[]'::jsonb end
      ) s
      where s->'completed' = 'true'::jsonb
    ),
    'pending_suggestions', (
      select count(*) from public.studypilot_concept_suggestions where status in ('pending','reviewing')
    ),
    'published_notices', (
      select count(*) from public.studypilot_notices where is_published
    ),
    'resource_count', (select count(*) from public.resources),
    'open_feedback', (
      select count(*) from public.studypilot_feedback where status in ('new','reviewing')
    ),
    'open_support_reports', (
      select count(*) from public.studypilot_support_reports where status in ('open','investigating')
    ),
    'updated_at', now()
  ) into result;
  return result;
end;
$$;
revoke all on function public.studypilot_admin_overview() from public, anon;
grant execute on function public.studypilot_admin_overview() to authenticated;


-- Keep administrator accounts out of the student directory.
create or replace function public.studypilot_admin_users(p_limit integer default 100)
returns table (
  user_id uuid,
  email text,
  display_name text,
  registered_at timestamptz,
  last_sign_in_at timestamptz,
  planner_updated_at timestamptz,
  concepts_count integer,
  session_count integer,
  completed_sessions integer,
  selected_subjects_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.studypilot_is_admin() then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  return query
  select u.id, u.email::text,
         coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', '')::text,
         u.created_at, u.last_sign_in_at, d.updated_at,
         coalesce(jsonb_array_length(case when jsonb_typeof(d.data->'concepts') = 'array'
           then d.data->'concepts' else '[]'::jsonb end),0)::integer,
         coalesce(jsonb_array_length(case when jsonb_typeof(d.data->'sessions') = 'array'
           then d.data->'sessions' else '[]'::jsonb end),0)::integer,
         (select count(*)::integer from jsonb_array_elements(
           case when jsonb_typeof(d.data->'sessions') = 'array'
             then d.data->'sessions' else '[]'::jsonb end
         ) ss where ss->'completed' = 'true'::jsonb),
         (select count(*)::integer from public.student_subjects ssb where ssb.user_id = u.id)
  from auth.users u
  left join public.studypilot_user_data d on d.user_id = u.id
  where not exists (select 1 from public.studypilot_admins a where a.user_id = u.id)
  order by u.created_at desc
  limit greatest(1, least(coalesce(p_limit,100),500));
end;
$$;
revoke all on function public.studypilot_admin_users(integer) from public, anon;
grant execute on function public.studypilot_admin_users(integer) to authenticated;

commit;
