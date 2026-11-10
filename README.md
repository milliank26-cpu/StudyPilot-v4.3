# StudyPilot — Adaptive Academic Revision Planner

StudyPilot is a browser-based academic revision planner. Student planner records are held in memory while the page is open and saved to the signed-in student's private Supabase account. Planner records are not persisted in browser localStorage.

## What it can do

- Organise concepts by subject, topic, subtopic and learning objective.
- Track first learning, retrieval practice, assessment results, assistance, confidence, marks and reflections.
- Estimate mastery and review timing from the evidence you log.
- Generate an adaptive timetable from today's date, your availability, commitments, goals, exam deadlines and chosen planning strategy.
- Use a rolling planning window from 1 to 365 days. The default is 14 days. Dates are calculated from the current local date rather than being fixed to a specific October/November range; the plan refreshes when the date changes while the page is open and on subsequent loads.
- Keep academic revision capacity separate from the informational project-work budget.
- Export/import JSON backups and export schedule, history and report CSV files.
- Sign up and sign in with email/password from the account icon in the top bar.
- Show the signed-in student name and profile photo in the account area.
- Automatically sync each signed-in student's planner data to their own private Supabase row.

## Important limits

- It does not magically know your syllabus, marks, assignments, or progress. Enter these or import them; recommendations are only as good as the information provided.
- Mastery, priority and review intervals are transparent heuristics, not validated predictions or guarantees of exam results.
- The 365-day setting is a rolling planning horizon, not a promise that the app will pre-generate a perfect ten-year calendar. You can keep using it year after year and add future exam dates as they become known.
- Students should sign in before entering important study data. When signed out, planner changes are not saved. If cloud saving fails, the page reports the failure; changes not yet synced may be lost when the page closes.
- Cloud sync requires your own Supabase project and a hosted copy of this site. This package does not create the Supabase account or publish the site for you.
- Cloud data syncs as one private record per account. Each student has a separate row protected by row-level security. The current planner is personal per account and does not support simultaneous collaborative editing.

## Run locally

Open `index.html` in a modern browser. For the most consistent behavior, use a local server from this directory, for example:

```bash
python -m http.server 8000
```

Then open `http://localhost:8000`.

## Configure the site's Supabase connection once

1. Create or select your Supabase project.
2. In the Supabase dashboard, open **SQL Editor** and run `supabase-setup.sql` if the StudyPilot data table and row-level security policies have not already been set up. If you already created the `studypilot_user_data` table and its policies, do not rerun SQL blindly; the app expects a JSONB column named `data`.
3. In **Authentication → Providers**, ensure Email/password authentication is enabled. Configure email confirmation and password reset settings as appropriate.
4. In **Project Settings → API** (or API Keys), copy the Project URL and the public publishable key / legacy `anon` key. Never use a `service_role` or secret key in browser code.
5. Open `config.js` in a text editor and paste those two values into `SUPABASE_URL` and `SUPABASE_PUBLIC_KEY`. This is a one-time site-owner configuration. Students never enter a URL or key. The publishable/anon key is visible to website visitors by design; RLS and authentication enforce data access.
6. Host the entire folder on an HTTPS static host (for example, Netlify, Vercel or GitHub Pages). Keep `config.js`, `index.html`, `app.js`, `auth.js` and `styles.css` together. The Supabase browser SDK is loaded from a CDN, so the site needs internet access for account/cloud features.
7. Open the hosted site and click the account icon. Students can sign up or sign in using their email and password. If email confirmation is enabled, they must confirm the email before signing in.
8. After sign-in, StudyPilot first clears the in-memory planner, then loads that account's row from `studypilot_user_data` and autosaves updates to its `data` JSONB field. A new account with no cloud row always starts with a clean planner; data from a previous account or old browser storage is never copied into it. Sign out clears the on-screen planner. The Supabase client may retain an authentication session in browser storage so a student can stay signed in, but StudyPilot planner records are not saved there.
9. On another device, open the same hosted URL and sign in to the same account. The website owner configures the URL/key once for the deployed site, not once per student or device.

The app uses the existing `user_id` ownership model and the Supabase Row Level Security policies; each signed-in student can only access their own row. The current schema includes both `planner_data` and `data` in some guided setups; this client uses `data`. Do not disable RLS or expose a service-role key. Cloud syncing should still be tested on the actual hosted site before inviting students.

## First setup

1. Edit the student profile and subjects.
2. Add concepts individually, paste structured concepts, or import CSV.
3. Set weekday academic availability and date-specific exceptions.
4. Add real exam deadlines and scope.
5. Select a planning strategy and horizon on **Timetable**, then recalculate.
6. Log outcomes after learning/retrieval/practice so the planner can adapt.
7. Export a JSON backup occasionally even when cloud sync is enabled.

## Research foundations

- Dunlosky et al. (2013), [Improving Students' Learning With Effective Learning Techniques](https://doi.org/10.1177/1529100612453266)
- Cepeda et al. (2006), [Distributed Practice in Verbal Recall Tasks](https://doi.org/10.1037/0033-2909.132.3.354)
- Donoghue & Hattie (2021), [A Meta-Analysis of Ten Learning Techniques](https://doi.org/10.3389/feduc.2021.581216)
- Institute of Education Sciences, [Organizing Instruction and Study to Improve Student Learning](https://ies.ed.gov/ncee/wwc/PracticeGuide/1)


## Visual refresh (November 2026)

The refreshed interface keeps the existing planner data model, page IDs, account flow and Supabase table contract. It adds:
- A floating, horizontally scrollable bottom navigation dock on small screens; desktop retains the sidebar.
- A dashboard coverage ring built from the student's actual concept counts (first-pass coverage, evidence-secure concepts and not-yet-studied concepts).
- Animated progress fills and a subtle indeterminate activity indicator while cloud data is loading or syncing. No estimated/fake completion percentages are shown.
- Click-to-enlarge profile-photo previews from the profile and sidebar avatar.
- Updated spacing, cards, colors, responsive layouts, focus states and reduced-motion support.

The redesign does not change Supabase configuration or SQL. Keep using the same `studypilot_user_data` table and the same public client key configuration. The `resources` table is not modified.


## Curriculum management v2 — Subject and Topic Explorer

This version adds an interactive explorer to the existing Concepts page:
- Open a subject to see its topics.
- See topic-level counts of subtopics and learning objectives.
- Open a topic to view objectives grouped by subtopic.
- Edit an objective or log a learning session directly from the explorer.
- Coverage labels use the existing learning-session evidence and mastery logic.

This is an additive interface change. It reuses existing concept records and does not require SQL migrations, new tables, or changes to authentication, RLS, the `resources` table, or the Supabase JSONB storage contract.

## Curriculum management v3 — Topic Builder

This version adds a **Build topic** workflow to the existing Concepts page:
- Enter or select a subject and provide a topic name.
- Optionally group the learning objectives under a subtopic and paper/component.
- Paste multiple learning objectives, one per line; StudyPilot creates one existing-format concept record per objective.
- Likely duplicates within the same subject, topic, subtopic and objective name are skipped rather than overwritten.
- New records use the existing learning defaults and continue to work with sessions, mastery calculations and revision planning.

This is additive and uses the existing concepts array and cloud JSONB record. No SQL migration or Supabase schema change is required. Existing records and session history are not rewritten.
