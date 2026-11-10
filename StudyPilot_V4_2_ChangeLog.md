# StudyPilot V4.2 Change Log

## Curriculum bulk upload reliability
- Fixed missing `num()` helper that caused CSV preview validation to stop.
- Made the upload action permanently visible and disabled until validation succeeds.
- Added clearer validation, duplicate, progress, interruption and completion messages.
- Reset validation state when the selected file, level or subject changes.
- Kept imported subjects as drafts until an administrator explicitly publishes them.

See `README_V4_2_Curriculum_Upload_Fix.md` for deployment and testing instructions.
