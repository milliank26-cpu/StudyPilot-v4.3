-- StudyPilot V4.0 additive database foundation
-- Run AFTER the existing V3 supabase-setup.sql.
-- This migration deliberately preserves studypilot_user_data and resources.
-- Run as the Supabase project owner in SQL Editor.

begin;

-- 1. Explicit administrator allow-list. No public policies: clients cannot grant themselves roles.
create table if not exists public.studypilot_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now(),
  granted_by uuid references auth.users(id) on delete set null
);
alter table public.studypilot_admins enable row level security;
revoke all on public.studypilot_admins from anon, authenticated;

-- Used by RLS policies. The function exposes only a boolean, not the admin list.
create or replace function public.studypilot_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.studypilot_admins a
    where a.user_id = (select auth.uid())
  );
$$;
revoke all on function public.studypilot_is_admin() from public;
grant execute on function public.studypilot_is_admin() to authenticated;

-- 2. Centrally managed curriculum. Students read published content; admins manage it.
create table if not exists public.curriculum_subjects (
  id uuid primary key default gen_random_uuid(),
  curriculum text not null default 'UACE',
  level text not null,
  name text not null,
  code text,
  description text,
  display_order integer not null default 0,
  is_published boolean not null default false,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (curriculum, level, name)
);

create table if not exists public.curriculum_topics (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.curriculum_subjects(id) on delete cascade,
  name text not null,
  term text,
  teaching_periods integer,
  description text,
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (subject_id, name)
);

create table if not exists public.curriculum_subtopics (
  id uuid primary key default gen_random_uuid(),
  topic_id uuid not null references public.curriculum_topics(id) on delete cascade,
  name text not null,
  description text,
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (topic_id, name)
);

create table if not exists public.curriculum_concepts (
  id uuid primary key default gen_random_uuid(),
  subtopic_id uuid not null references public.curriculum_subtopics(id) on delete cascade,
  name text not null,
  description text,
  difficulty smallint not null default 3 check (difficulty between 1 and 5),
  importance smallint not null default 3 check (importance between 1 and 5),
  learn_minutes integer not null default 30 check (learn_minutes > 0),
  review_minutes integer not null default 15 check (review_minutes > 0),
  practice_minutes integer not null default 25 check (practice_minutes > 0),
  target_repetitions integer not null default 3 check (target_repetitions > 0),
  target_questions integer not null default 10 check (target_questions >= 0),
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (subtopic_id, name)
);

create index if not exists curriculum_subjects_published_idx
  on public.curriculum_subjects (curriculum, level, display_order) where is_published;
create index if not exists curriculum_topics_subject_idx
  on public.curriculum_topics (subject_id, display_order);
create index if not exists curriculum_subtopics_topic_idx
  on public.curriculum_subtopics (topic_id, display_order);
create index if not exists curriculum_concepts_subtopic_idx
  on public.curriculum_concepts (subtopic_id, display_order);

-- 3. Student subject selections and progress are separate from shared curriculum.
create table if not exists public.student_subjects (
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid not null references public.curriculum_subjects(id) on delete restrict,
  selected_at timestamptz not null default now(),
  primary key (user_id, subject_id)
);

create table if not exists public.student_concept_progress (
  user_id uuid not null references auth.users(id) on delete cascade,
  concept_id uuid not null references public.curriculum_concepts(id) on delete cascade,
  status text not null default 'new' check (status in ('new','learning','reviewing','secure')),
  completed_sessions integer not null default 0 check (completed_sessions >= 0),
  mastery numeric(5,2) not null default 0 check (mastery between 0 and 100),
  last_studied_at timestamptz,
  next_review_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, concept_id)
);
create index if not exists student_progress_user_idx
  on public.student_concept_progress (user_id, updated_at desc);
create index if not exists student_progress_due_idx
  on public.student_concept_progress (user_id, next_review_at);

-- 4. Feedback and support reports. Keep diagnostic details free of secrets/private study content.
create table if not exists public.studypilot_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in ('suggestion','complaint','feature_request','other')),
  rating smallint check (rating between 1 and 5),
  message text not null check (char_length(message) between 3 and 5000),
  status text not null default 'new' check (status in ('new','reviewing','resolved','closed')),
  admin_response text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.studypilot_support_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  category text not null default 'other',
  user_message text not null check (char_length(user_message) between 3 and 3000),
  diagnostic_code text,
  app_version text,
  page_name text,
  status text not null default 'open' check (status in ('open','investigating','resolved','closed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table if not exists public.studypilot_admin_audit (
  id bigint generated always as identity primary key,
  admin_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  target_type text,
  target_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists feedback_user_created_idx
  on public.studypilot_feedback (user_id, created_at desc);
create index if not exists feedback_status_created_idx
  on public.studypilot_feedback (status, created_at desc);
create index if not exists support_status_created_idx
  on public.studypilot_support_reports (status, created_at desc);
create index if not exists audit_created_idx
  on public.studypilot_admin_audit (created_at desc);

-- 5. RLS: published curriculum is readable to signed-in students; only admins write.
alter table public.curriculum_subjects enable row level security;
alter table public.curriculum_topics enable row level security;
alter table public.curriculum_subtopics enable row level security;
alter table public.curriculum_concepts enable row level security;
alter table public.student_subjects enable row level security;
alter table public.student_concept_progress enable row level security;
alter table public.studypilot_feedback enable row level security;
alter table public.studypilot_support_reports enable row level security;
alter table public.studypilot_admin_audit enable row level security;

drop policy if exists "Signed-in users read published subjects" on public.curriculum_subjects;
create policy "Signed-in users read published subjects" on public.curriculum_subjects
  for select to authenticated using (is_published or public.studypilot_is_admin());
drop policy if exists "Admins manage subjects" on public.curriculum_subjects;
create policy "Admins manage subjects" on public.curriculum_subjects
  for all to authenticated using (public.studypilot_is_admin()) with check (public.studypilot_is_admin());

drop policy if exists "Signed-in users read published topics" on public.curriculum_topics;
create policy "Signed-in users read published topics" on public.curriculum_topics
  for select to authenticated using (
    public.studypilot_is_admin() or exists (
      select 1 from public.curriculum_subjects s
      where s.id = subject_id and s.is_published
    )
  );
drop policy if exists "Admins manage topics" on public.curriculum_topics;
create policy "Admins manage topics" on public.curriculum_topics
  for all to authenticated using (public.studypilot_is_admin()) with check (public.studypilot_is_admin());

drop policy if exists "Signed-in users read published subtopics" on public.curriculum_subtopics;
create policy "Signed-in users read published subtopics" on public.curriculum_subtopics
  for select to authenticated using (
    public.studypilot_is_admin() or exists (
      select 1 from public.curriculum_topics t
      join public.curriculum_subjects s on s.id = t.subject_id
      where t.id = topic_id and s.is_published
    )
  );
drop policy if exists "Admins manage subtopics" on public.curriculum_subtopics;
create policy "Admins manage subtopics" on public.curriculum_subtopics
  for all to authenticated using (public.studypilot_is_admin()) with check (public.studypilot_is_admin());

drop policy if exists "Signed-in users read published concepts" on public.curriculum_concepts;
create policy "Signed-in users read published concepts" on public.curriculum_concepts
  for select to authenticated using (
    public.studypilot_is_admin() or exists (
      select 1 from public.curriculum_subtopics st
      join public.curriculum_topics t on t.id = st.topic_id
      join public.curriculum_subjects s on s.id = t.subject_id
      where st.id = subtopic_id and s.is_published
    )
  );
drop policy if exists "Admins manage concepts" on public.curriculum_concepts;
create policy "Admins manage concepts" on public.curriculum_concepts
  for all to authenticated using (public.studypilot_is_admin()) with check (public.studypilot_is_admin());

-- Students can manage only their own selections and progress.
drop policy if exists "Students manage own subject selections" on public.student_subjects;
create policy "Students manage own subject selections" on public.student_subjects
  for all to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id and exists (
      select 1 from public.curriculum_subjects s
      where s.id = subject_id and s.is_published
    )
  );
drop policy if exists "Students manage own concept progress" on public.student_concept_progress;
create policy "Students manage own concept progress" on public.student_concept_progress
  for all to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id and exists (
      select 1 from public.curriculum_concepts c
      join public.curriculum_subtopics st on st.id = c.subtopic_id
      join public.curriculum_topics t on t.id = st.topic_id
      join public.curriculum_subjects s on s.id = t.subject_id
      where c.id = concept_id and s.is_published
    )
  );

-- Students submit and read their own feedback; admins can review all feedback.
drop policy if exists "Students read own feedback" on public.studypilot_feedback;
create policy "Students read own feedback" on public.studypilot_feedback
  for select to authenticated using (auth.uid() = user_id or public.studypilot_is_admin());
drop policy if exists "Students submit feedback" on public.studypilot_feedback;
create policy "Students submit feedback" on public.studypilot_feedback
  for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Admins update feedback" on public.studypilot_feedback;
create policy "Admins update feedback" on public.studypilot_feedback
  for update to authenticated using (public.studypilot_is_admin()) with check (public.studypilot_is_admin());

-- Signed-in students submit support reports; they can only see their own.
drop policy if exists "Students submit support reports" on public.studypilot_support_reports;
create policy "Students submit support reports" on public.studypilot_support_reports
  for insert to authenticated with check (user_id is null or auth.uid() = user_id);
drop policy if exists "Students read own support reports" on public.studypilot_support_reports;
create policy "Students read own support reports" on public.studypilot_support_reports
  for select to authenticated using (auth.uid() = user_id or public.studypilot_is_admin());
drop policy if exists "Admins manage support reports" on public.studypilot_support_reports;
create policy "Admins manage support reports" on public.studypilot_support_reports
  for update to authenticated using (public.studypilot_is_admin()) with check (public.studypilot_is_admin());

-- Audit records are admin-readable; no client insert/update/delete policy.
drop policy if exists "Admins read audit log" on public.studypilot_admin_audit;
create policy "Admins read audit log" on public.studypilot_admin_audit
  for select to authenticated using (public.studypilot_is_admin());

-- Least-privilege grants. RLS remains the row-level boundary.
revoke all on public.curriculum_subjects, public.curriculum_topics,
  public.curriculum_subtopics, public.curriculum_concepts,
  public.student_subjects, public.student_concept_progress,
  public.studypilot_feedback, public.studypilot_support_reports,
  public.studypilot_admin_audit from anon;
grant select on public.curriculum_subjects, public.curriculum_topics,
  public.curriculum_subtopics, public.curriculum_concepts to authenticated;
grant insert, update, delete on public.curriculum_subjects, public.curriculum_topics,
  public.curriculum_subtopics, public.curriculum_concepts to authenticated;
grant select, insert, update, delete on public.student_subjects,
  public.student_concept_progress to authenticated;
grant select, insert, update on public.studypilot_feedback to authenticated;
grant select, insert, update on public.studypilot_support_reports to authenticated;
grant select on public.studypilot_admin_audit to authenticated;
grant usage, select on sequence public.studypilot_admin_audit_id_seq to authenticated;


-- V4 Complete Platform additions: admin overview, user directory, and audit triggers.
-- Append to the V4 foundation migration before running it, or run after V4 foundation.

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
    'registered_users', (select count(*) from auth.users),
    'active_users_30d', (
      select count(*) from public.studypilot_user_data d
      where d.updated_at >= now() - interval '30 days'
    ),
    'subject_selections', (select count(*) from public.student_subjects),
    'published_subjects', (
      select count(*) from public.curriculum_subjects where is_published
    ),
    'concept_completions', (
      select count(*)
      from public.studypilot_user_data d
      cross join lateral jsonb_array_elements(
        case when jsonb_typeof(d.data->'sessions') = 'array'
          then d.data->'sessions' else '[]'::jsonb end
      ) s
      where s->'completed' = 'true'::jsonb
    ),
    'open_feedback', (
      select count(*) from public.studypilot_feedback
      where status in ('new','reviewing')
    ),
    'open_support_reports', (
      select count(*) from public.studypilot_support_reports
      where status in ('open','investigating')
    ),
    'updated_at', now()
  ) into result;
  return result;
end;
$$;
revoke all on function public.studypilot_admin_overview() from public, anon;
grant execute on function public.studypilot_admin_overview() to authenticated;

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
  order by u.created_at desc
  limit greatest(1, least(coalesce(p_limit,100),500));
end;
$$;
revoke all on function public.studypilot_admin_users(integer) from public, anon;
grant execute on function public.studypilot_admin_users(integer) to authenticated;

create or replace function public.studypilot_admin_log(
  p_action text, p_target_type text default null,
  p_target_id text default null, p_details jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.studypilot_is_admin() then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  insert into public.studypilot_admin_audit(admin_user_id, action, target_type, target_id, details)
  values (auth.uid(), left(coalesce(p_action,'admin_action'),100),
          left(p_target_type,100), left(p_target_id,200),
          coalesce(p_details,'{}'::jsonb));
end;
$$;
revoke all on function public.studypilot_admin_log(text,text,text,jsonb) from public, anon;
grant execute on function public.studypilot_admin_log(text,text,text,jsonb) to authenticated;

-- Basic server-side audit trail for curriculum and feedback changes.
create or replace function public.studypilot_audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  rid text;
  act text;
begin
  rid := coalesce(to_jsonb(new)->>'id', to_jsonb(old)->>'id');
  act := lower(tg_op);
  insert into public.studypilot_admin_audit(admin_user_id, action, target_type, target_id, details)
  values (auth.uid(), 'row_' || act, tg_table_name, rid,
    jsonb_build_object('table',tg_table_name,'operation',act));
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;
revoke all on function public.studypilot_audit_row_change() from public, anon, authenticated;

drop trigger if exists studypilot_audit_subjects on public.curriculum_subjects;
create trigger studypilot_audit_subjects after insert or update or delete on public.curriculum_subjects
for each row execute function public.studypilot_audit_row_change();
drop trigger if exists studypilot_audit_topics on public.curriculum_topics;
create trigger studypilot_audit_topics after insert or update or delete on public.curriculum_topics
for each row execute function public.studypilot_audit_row_change();
drop trigger if exists studypilot_audit_subtopics on public.curriculum_subtopics;
create trigger studypilot_audit_subtopics after insert or update or delete on public.curriculum_subtopics
for each row execute function public.studypilot_audit_row_change();
drop trigger if exists studypilot_audit_concepts on public.curriculum_concepts;
create trigger studypilot_audit_concepts after insert or update or delete on public.curriculum_concepts
for each row execute function public.studypilot_audit_row_change();
drop trigger if exists studypilot_audit_feedback on public.studypilot_feedback;
create trigger studypilot_audit_feedback after update on public.studypilot_feedback
for each row execute function public.studypilot_audit_row_change();

-- The trigger function is called by PostgreSQL triggers; no direct client execution.

commit;

-- ADMIN SETUP (run separately after creating your own account):
-- 1) Sign up / sign in to StudyPilot once.
-- 2) Find your account UUID in Supabase Dashboard -> Authentication -> Users.
-- 3) Replace the UUID below and run this statement as project owner:
-- insert into public.studypilot_admins (user_id)
-- values ('YOUR-AUTH-USER-UUID')
-- on conflict (user_id) do nothing;
--
-- Do not create a public admin-signup form. Do not put service_role keys in config.js.
--
-- IMPORTANT V4.0 boundary:
-- Existing V3 planner data remains in studypilot_user_data.data (private JSON).
-- No automatic migration to student_concept_progress is performed yet. First map
-- the actual V3 concept/session identifiers and agree a stable curriculum import mapping.
