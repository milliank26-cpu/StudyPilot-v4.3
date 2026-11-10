# StudyPilot V4.2 – Curriculum upload fix

This is a focused fix to the Bulk upload screen in the V4.1 redesign package.

## What was wrong

The CSV preview attempted to call `num()` for optional numeric columns, but that helper was missing from `admin.js`. This stopped validation before the preview could finish and before the old dynamically-created import button could appear.

## What changed

- Added the missing safe numeric conversion helper. Blank optional values use the documented defaults; invalid numeric values are reported during validation.
- Added a permanently visible **2. Upload curriculum** button. It remains disabled until the selected CSV passes validation and the database duplicate check.
- Kept Preview & Validate as a separate first step.
- Shows the number of valid rows, new concepts and existing concepts that will be skipped.
- Shows upload progress and a final saved-count message.
- Invalidates a previous validation whenever the file, academic level or subject changes.
- Uses conflict-safe inserts for concepts so re-uploading after an interrupted connection does not create duplicates.
- Leaves the subject unpublished after import. Publish it separately from Curriculum Management only after checking the imported hierarchy.

## How to use

1. Deploy these updated files over the matching V4.1 files.
2. Keep your real Supabase URL and public anon/publishable key in `config.js`. The config in this package contains placeholders; do not overwrite a live config with placeholders.
3. Sign in to `admin.html` as an authorised administrator.
4. Open **Bulk upload**.
5. Select the academic level, subject and a CSV with the headers `Topic,Subtopic,Concept`.
6. Click **1. Preview & validate**. Review the results.
7. Click **2. Upload curriculum**. Wait for the success message.
8. Open **Curriculum**, select the same level and subject, and inspect the topic/subtopic/concept hierarchy.
9. Publish the subject only after confirming the imported curriculum is correct.

## Database requirements

This patch does not add or change database tables and does not require a new SQL migration. It uses the existing V4 curriculum tables and their unique constraints. The V4 base migration must already have been applied to the Supabase project. The administrator must have the required database permissions and the existing admin authorization.

## Verification performed here

- JavaScript syntax checks passed for `admin.js`, `app.js` and `auth.js`.
- The upload controls and event handlers were checked for matching IDs.
- The archive was checked for ZIP integrity.

## Not verified here

This package has not been connected to your live Supabase project, so a real database upload and student-side display still need to be tested in your deployed site. This fix does not certify the rest of the database, RLS or deployment configuration.
