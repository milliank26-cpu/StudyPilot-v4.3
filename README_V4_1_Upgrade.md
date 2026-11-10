# StudyPilot V4.1 upgrade guide

This package is an additive upgrade to the supplied V4 project.

## 1. Before publishing
1. Keep a copy of your currently deployed V4 files.
2. Confirm the Supabase project URL and **public anon/publishable key** in `config.js`. The copy in this ZIP intentionally retains placeholders; do not deploy it over your live config until you restore the real public values.
3. Never place a Supabase `service_role` or secret key in browser code.

## 2. Apply the database migration
In Supabase SQL Editor, run `StudyPilot_V4_1_Noticeboard_Levels_Suggestions.sql` against the same project where V4 is installed.

The migration adds:
- `student_academic_profiles` for O Level/A Level audience targeting.
- `studypilot_notices` and `studypilot_notice_reads` for the in-app Noticeboard and unread state.
- `studypilot_concept_suggestions` for student-submitted concepts and administrator review.
- RLS policies for these features.
- Read access for authenticated students and administrator-only management for the existing `resources` table.

It does not delete or rewrite `studypilot_user_data`, existing V3 resources, or the existing V4 curriculum tables.

## 3. Create O Level and A Level subjects
1. Open `admin.html` and sign in with an account already authorised in `studypilot_admins`.
2. Open **Curriculum**.
3. Select **O Level** or **A Level**.
4. Add each subject. New O/A Level subjects are stored with `curriculum='UNEB'`; existing UACE/Senior Five/Senior Six rows are left untouched.
5. Select a subject and add concepts manually or use **Bulk upload**.
6. Publish a subject only when its curriculum is ready for students.

## 4. CSV format
Choose the academic level and subject in Bulk upload before selecting the CSV. The file should contain these headers:

```csv
Topic,Subtopic,Concept
Cell Biology,Cell Structure,Describe the structure of an animal cell
Cell Biology,Cell Structure,Compare plant and animal cells
Cell Biology,Cell Organelles,Explain the functions of mitochondria
```

Optional columns:
`Description`, `Difficulty`, `Importance`, `LearnMinutes`, `ReviewMinutes`, `PracticeMinutes`, `TargetRepetitions`, `TargetQuestions`.

The preview checks required fields, numeric ranges, repeated rows and concepts already present in the selected subject. Existing concepts are skipped rather than duplicated. If the network fails during an import, re-importing the same CSV is safe because existing concepts are checked again.

## 5. Student workflow
1. Student signs in and opens Settings → My academic level and subjects.
2. Student selects O Level or A Level, checks the published subjects, and saves.
3. The selected official curriculum appears in My Curriculum and the revision planner.
4. Students can change the level or subjects later. The app retains their planner sessions and stable concept IDs so history can reconnect when a subject is selected again.
5. Students read announcements in StudyPilot Noticeboard, submit missing-concept suggestions, and browse Learning Resources.

## 6. Noticeboard
Administrators can publish notices to:
- All students
- O Level students
- A Level students
- A selected subject (optionally scoped to an academic level)

Notice types include general announcements, exam reminders, maintenance, study tips, platform updates and instructions. Students see unread notices in the dashboard preview and can mark them as read. This is an in-app system; browser push notifications are not included in this upgrade.

## 7. Concept suggestions
Students submit suggestions only. They cannot create, edit or delete the official curriculum from the student interface. Administrators review suggestions and can approve a suggestion into the selected level/subject curriculum.

## 8. Test before deployment
- Sign in as an administrator and confirm the admin page opens.
- Create an O Level subject and an A Level subject with a test concept each.
- Publish both subjects.
- Test CSV preview with a valid row, a missing field, an invalid difficulty, a repeated row and an existing concept.
- Sign in as a student and confirm the correct level/subjects appear.
- Change level and confirm old session history is still present when the old subject is selected again.
- Publish a general notice and a level-specific notice; verify student visibility and unread state.
- Submit a concept suggestion and approve it from the admin page.
- Add a resource and verify it appears for an authenticated student.
- Confirm a normal student cannot access administrator operations or edit the official curriculum.

## Important notes
- This package does not automatically migrate old UACE Senior Five/Senior Six curriculum rows into O Level/A Level. Existing rows remain intact. Add/import the new O/A Level curriculum separately.
- The existing administrator membership in `studypilot_admins` remains the source of admin authorization. The admin page does not expose a way for students to grant themselves admin access.
- The admin overview now reports student counts, activity, subject selections, published O/A subjects, official concept totals, completed planner sessions, pending suggestions, notices, resources, feedback and support. Completed-session counts are read from the existing private planner JSON; detailed concept mastery-by-subject analytics are a later reporting enhancement because the current planner does not yet sync every mastery calculation into `student_concept_progress`.
