# StudyPilot V4.0 — Complete Platform Build (deployment candidate)

This package builds on the supplied StudyPilot V3 project. It preserves the existing student planner and its private `studypilot_user_data` JSON records, and adds a separate role-protected administrator workspace plus central UACE curriculum tables.

## Package contents

- `index.html`, `app.js`, `styles.css`, `curriculum-overview.css` — existing student application, with curriculum selection and feedback/report forms added.
- `auth.js` — existing Supabase authentication/cloud sync plus student curriculum, feedback and support-report operations.
- `admin.html`, `admin.js`, `admin.css` — administrator sign-in and control centre.
- `config.js` — public Supabase project URL and publishable/anon key.
- `supabase-setup.sql` — original V3 table setup (keep; do not replace with the V4 migration).
- `StudyPilot_V4_0_Complete_Migration.sql` — additive V4 database migration.
- `README_V4_Complete.md` — this guide.

## Before touching production

1. Make a backup of your current hosted V3 website files.
2. In Supabase, create a database backup / confirm your recovery point.
3. Do not delete or rename `studypilot_user_data` or `resources`.
4. First test this package on a staging copy of the website and a non-production Supabase project if possible.

## Database installation

1. Open Supabase Dashboard → SQL Editor.
2. Confirm the existing V3 setup has already created `public.studypilot_user_data`. If it has not, run the existing `supabase-setup.sql` first.
3. Run `StudyPilot_V4_0_Complete_Migration.sql` as the project owner.
4. Confirm the SQL Editor reports success. The migration is additive and does not delete the existing V3 student-data table or the `resources` table.
5. The migration creates the admin allow-list, curriculum hierarchy, student subject selections, separate progress-ready table, feedback/support tables, audit log, RLS policies and admin reporting RPCs.

If you previously ran the earlier V4 foundation migration, this complete migration can be run again: it uses `IF NOT EXISTS`, replaces policies safely, and recreates its triggers. Still take a backup first.

## Configure the website

1. Open `config.js`.
2. Set `SUPABASE_URL` to your Supabase Project URL.
3. Set `SUPABASE_PUBLIC_KEY` to the project's publishable key (or legacy anon public key).
4. Never put the `service_role` / secret key in `config.js`, HTML, JavaScript, or any file deployed to the browser.
5. Upload all package files to the same website root directory, preserving the filenames and relative paths.
6. Confirm the student site opens at `/index.html` and the admin centre at `/admin.html`.

## Authorise your administrator account

There is deliberately no public admin registration.

1. Open the student website and create/sign in to the account you want to use as the administrator.
2. In Supabase Dashboard → Authentication → Users, locate that account and copy its UUID.
3. In Supabase SQL Editor, run the following statement after replacing the placeholder with that UUID:

```sql
insert into public.studypilot_admins (user_id)
values ('YOUR-AUTH-USER-UUID')
on conflict (user_id) do nothing;
```

4. Open `/admin.html`, sign in with that same account, and confirm the administrator overview loads.
5. Do not share the administrator account. Enable MFA for the account in Supabase Auth if available for your project.

## Load the central curriculum

1. Sign in to `/admin.html`.
2. Open Curriculum.
3. Select Senior Five or Senior Six.
4. Upload the prepared CSV. Required columns: `subject`, `topic`, `subtopic`, `name`. Optional fields include `description`, `difficulty`, `importance`, `learnMin`, `reviewMin`, `practiceMin`, `targetReps`, `targetQuestions`, and `term`.
5. Imports create/update draft subjects. Review the subject list and publish each subject.
6. Students sign in to the main site → Settings & backup → Official UACE curriculum, choose their level and published subjects, then load the curriculum.

The student curriculum loader keeps existing non-central concepts and session history. It adds official concepts using their stable database IDs, and re-importing matching curriculum rows updates the central curriculum rather than intentionally creating a new concept ID.

## What the administrator can see

- Total registered accounts.
- Accounts with planner data updated in the last 30 days (an activity proxy, not a live-online count).
- Official curriculum subject selections.
- Published subject count.
- Completed learning-session count from V3 planner JSON.
- Per-student counts of concepts, sessions and completed sessions, plus registration / last-sign-in / planner-updated timestamps.
- Feedback and student-submitted support reports.
- Curriculum and administrative audit entries.

The admin centre does not display student private notes, personal reflections, or full planner content. V3 session-completion analytics count completed sessions, not unique mastered concepts. Activity is based on planner data updates, not presence in the app at that exact moment.

## Important limitations / verification still required

- This package has been syntax-checked for its JavaScript files and checked for expected project files. It has **not** been run against your live Supabase project or hosting account.
- A live browser test is still required for sign-in, email confirmation, RLS, admin role authorisation, CSV import, subject publication, student selection, feedback submission, support reporting, and mobile layout.
- The V3 planner continues to store each student's working concepts and learning sessions in their private JSON record. The new `student_concept_progress` relational table is a foundation for a future migration; this build does not silently migrate or rewrite existing progress into it.
- The support centre currently collects student-submitted reports. It is not a full external uptime/error-monitoring service and cannot report failures when the browser cannot reach Supabase.
- Supabase Auth MFA, email confirmation, password policy, rate limits, backups and recovery should be reviewed in the Supabase project settings before public launch.
- The admin dashboard's account directory is deliberately limited to account metadata and aggregate progress counts. It does not expose personal notes or study reflections.

## Rollback

If a staging test fails, restore the previous hosted V3 files. The V4 migration is additive; do not attempt to roll it back by dropping tables if students have started using it. Keep the V3 `studypilot_user_data` table and existing resources intact.


## V4 intelligent planning decisions (approved product behaviour)

The student planning engine is configured around these decisions:

1. **Plan approval:** a student requests a plan, reviews the proposed session count, total minutes and shortfall, then approves before unlocked future sessions are replaced. Routine progress-driven recalculation is automatic.
2. **Insufficient time:** StudyPilot reports the shortfall, recommends additional study time, and prioritises important/difficult/weak/overdue concepts rather than pretending all work fits. Students can also extend the planning horizon or narrow their exam scope.
3. **Concept completion:** students may explicitly mark a concept as covered. This is a self-reported coverage declaration, not evidence of mastery. Logged learning/retrieval/practice results remain separate.
4. **Weekends:** Saturday and Sunday are excluded unless the student enables the weekend option. Date-specific availability overrides remain available.
5. **Assignments:** assignments are split into manageable sessions and placed backwards from their deadline. Students can move and lock a session manually. Completion is accumulated across chunks.
6. **Student control:** automatic recommendations and recalculation coexist with manual editing, moving and locking sessions.

### Learning activity allocation

Each concept supports separate estimated durations for first learning, research, experimentation/practical work, retrieval review and exam practice. Research and experimentation are optional per-concept activities (zero minutes means not scheduled). Students can record completion and results for each scheduled activity. The scheduler respects weekly availability, daily buffer, maximum session length, exam scope, priority and prerequisites.

### Recalculation behaviour

After a student logs a learning activity or completes an assignment chunk, StudyPilot automatically rebuilds the remaining unlocked plan. Completed history and manually locked sessions are preserved. A manual full replan asks for approval before replacing unlocked future sessions.

### Theme

The student interface includes a light/dark toggle. Theme preference is stored with the student's planner settings and follows their signed-in cloud record.

### Limits to understand

- The timetable is a heuristic scheduler, not an AI guarantee. Estimated activity durations and student availability need to be realistic.
- Concept completion is student-declared; mastery still depends on recorded practice/retrieval evidence.
- Assignment scheduling is limited to the configured planning horizon. Work that cannot fit before its deadline is reported as a shortfall.
- Browser-level testing with real Supabase accounts and devices is still required before production launch.
