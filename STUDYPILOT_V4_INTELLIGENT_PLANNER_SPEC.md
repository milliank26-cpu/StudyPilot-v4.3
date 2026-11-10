# StudyPilot V4 — Intelligent Planner Specification

## Approved student decisions

| Decision | Approved behaviour |
|---|---|
| Timetable generation | Generate a proposal and require student approval before replacing unlocked future sessions |
| Insufficient time | Combine shortfall warning, extra-time recommendation and priority-based triage |
| Concept completion | Student can mark a concept covered; this does not claim mastery |
| Weekends | Optional; excluded unless enabled by the student |
| Assignments | Automatically distribute work before deadline; allow manual edits |
| Student control | Both automatic planning and manual editing |

## Inputs

- Selected curriculum concepts and exam scope
- Weekly available minutes by day
- Optional weekend availability
- Date-specific availability overrides
- Daily buffer, maximum session length and break preference
- Exam date and subject scope
- Concept difficulty, importance, prerequisite links and recorded learning evidence
- Per-concept minutes for learning, research, experimentation, retrieval/review and practice
- Assignment title, estimated workload, priority and due date

## Scheduler rules

1. Keep completed work and manually locked sessions.
2. Reserve available time for assignments, allocating chunks backwards from the due date.
3. Build learning/revision queue from concepts still requiring work.
4. Respect prerequisite readiness where possible.
5. Rank by exam relevance, importance, weakness, difficulty, overdue status and novelty.
6. Allocate only within the student's available capacity and configured horizon.
7. Report all unallocated work with minutes and reasons. Never silently mark work complete.
8. Ask for approval before a manual full replan replaces unlocked future sessions.
9. After a student logs an activity or completes an assignment chunk, automatically recalculate remaining unlocked work.
10. Allow the student to move and lock individual sessions.

## Learning cycle

A concept can have separate estimated durations for:

- First learning
- Research (optional)
- Experimentation/practical work (optional)
- Retrieval/review
- Exam practice

A student may mark a concept covered. That updates syllabus coverage only; it does not create a mastery score. Mastery/performance remains based on recorded assessment evidence.

## Insufficient-time response

StudyPilot should show the total outstanding minutes, available capacity and shortfall. It should recommend a combination of: adding realistic study time, prioritising high-importance/difficult/weak concepts, and narrowing scope or extending the planning horizon. It must clearly identify assignments that cannot be completed by their deadline with the available capacity.

## Student experience

- Plan proposal and approval
- Weekly timetable and today's tasks
- Remaining work and deadline view
- Manual move/lock controls
- Automatic recalculation after logged progress
- Optional weekend scheduling
- Light/dark theme toggle
- Mobile-friendly controls

## Release verification still required

The JavaScript syntax and package contents can be checked offline, but a real browser test is still needed for timetable approval, assignment splitting, completion tracking, auto-rescheduling, cloud sync, mobile layouts and theme persistence against Supabase.
