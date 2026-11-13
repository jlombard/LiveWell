# For surf-at-60/dashboard-guide.md: the LiveWell app

Paste this into `surf-at-60/dashboard-guide.md` in the Live Well project (this Mac can't write to
the project). It describes what the app changes for anyone working on the dashboard.

## The LiveWell iPhone app (from Nov 2026)

LiveWell replaces the Export Shortcut, the three Watch "workout ended" automations, the Monday
check-in Shortcut and the lock-screen wallpaper. `engine/build.py` still computes every pillar and
writes `data.json`; the app reads that file for its progress bars, the Today line and its widgets.

**What the app writes in the Health Glance folder**

| File | What |
| --- | --- |
| `health/workouts.csv` | Every workout in Apple Health, `start,type,minutes` with a header. Every session counts; duplicates are removed by HealthKit id. |
| `health/exercise_minutes.csv` | Apple Exercise minutes per day, last 35 days. |
| `health/vo2max.csv`, `health/weight.csv` | The latest reading of each day. |
| `health/sleep_raw.txt` | Sleep segments with seconds, last 14 days. |
| `health/plan_days.csv` | Food check-ins, `date,on,slips,note,at`. |
| `checkins.csv` | Waist, pop-ups and sit-to-rise, one row per date. |
| `settings.json` | Only goal values, and only when Joe accepts a plan review change. |
| `app/` | `status.json`, `feedback.json`, `saved.json`, `plan_review.json` for the morning run. |

While `app/status.json` says `trial_mode: true`, the Health files and check-ins go to
`health_app/` instead and the Shortcuts are still live. `health/workouts_log.csv` is retired at
cutover (the app moves it to `health/old/`).

**Checking the app against the Shortcuts.** `python3 engine/compare_trial.py` builds from
`health/` and `health_app/` and prints habits and pillars side by side. `build.py` takes
`--health <folder>` for the same purpose; the daily run never passes it.

**Goals.** The app owns goals. A biweekly plan review can change one habit or pillar goal; the
app records it as a dated plan version and writes the value into `settings.json`, so the frame,
the Mac dashboard and the app agree. Read goals from `settings.json`, never from memory.

**Lift.** The app counts Lift the way `build.py` does: strength workouts from Health plus days
with an ARX main set in `fitclub/sets.json`.
