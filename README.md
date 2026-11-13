# Surf at 60 — iOS app, Phase 1

Phase 1 of the build spec: HealthKit sync that writes the Mac's CSV files, the check-in,
the lock-screen widget and the Today dashboard. Built to the UX concepts canvas and the
"Built for later" rules (the app owns its data; goals and habits are configuration; every
value has a provenance; no double counting).

**Status: written in a cloud session without Xcode.** The core library is compiled and
tested (17 tests, on Linux). The app and widget code has only been syntax-checked; it has
never been compiled against the iOS SDK or run on a phone. Expect a first round of compiler
fixes on the Mac. See "First session on the Mac" below.

## What's here

| Path | What it is |
| --- | --- |
| `Packages/SurfCore` | Pure Swift, no Apple frameworks. File formats, `checkins.csv` editing, habit counting, `data.json` decoding, widget line, reveal wording, the plan as configuration. Has the tests. |
| `App/Health/HealthSync.swift` | Observer queries with background delivery, anchored queries (adds, edits, deletions by HealthKit UUID), Exercise minutes, sleep, tap-to-log workouts. |
| `App/Files/HealthGlanceFolder.swift` | The folder bookmark; every read and write through `NSFileCoordinator`; watches `data.json`. |
| `App/Store` | SwiftData models and `AppModel`, the sync pipeline: Health → store → CSV files → `data.json` → widget. |
| `App/Screens` | Today, Check-in (hub, pop-up timer, reveal, close the week), Settings with sync status, Report placeholder. |
| `Widget` | Lock-screen rectangular (Today line + five icons) and circular (active minutes). |
| `project.yml` | XcodeGen definition for the app and widget targets, capabilities and Info.plist. |

## First session on the Mac

1. Set the three `CHANGE` values in `project.yml` (Team ID, bundle ids, App Group id; the
   App Group id also lives in `Shared/AppGroup.swift`).
2. `brew install xcodegen`, then `xcodegen` in this folder, and open `SurfAt60.xcodeproj`.
3. Build. Fix whatever the compiler finds (this code has not met the iOS SDK yet).
4. **Match the file formats before trusting any output.** Read `engine/build.py` and the
   current files in `health/`, then correct `ExportFormats` in
   `Packages/SurfCore/Sources/SurfCore/ExportFiles.swift` and update the tests. Only the
   `workouts.csv` row format (`2026-10-15 20:29,yoga,21`) is confirmed. These are guesses:
   - whether any file has a header row (assumed none; `checkins.csv` is assumed to have one)
   - `exercise_minutes.csv` as `date,minutes`, only days with data, last 35 days
   - `vo2max.csv` and `weight.csv` as `yyyy-MM-dd,value` (2 and 1 decimals), one row per reading
   - `sleep_raw.txt` as `start,end,stage` with `yyyy-MM-dd HH:mm` times, last 14 days
   - other workout types as lower-case words (`high intensity interval training`)
   - whether `build.py` accepts one `checkins.csv` row per measurement day (the hub lets each
     measurement be taken on a different day, so a week can produce up to three rows)
5. Run on the phone: link the Health Glance folder, connect Health, check Settings → Sync.

## Trial mode (the spec's cutover plan)

Trial mode is on by default. The app writes to `health_app/` (including
`health_app/checkins.csv`) and never touches `health/` or the live `checkins.csv`. Run
`build.py` against both folders for about a week, then turn Trial mode off in Settings and
retire the Shortcuts and automations. The app never writes anything in `engine/`,
`fitclub/` or `newsletter/`.

## Decisions made while building (say if any should change)

- **Habits are counted over the last 7 days**, matching the Mac dashboard, and the tiles say
  "Last 7 days". The canvas says "This week".
- **Tap-to-log needs permission to save workouts**, so the app asks for that one write
  permission. The spec's technical notes said read-only; the later UX decisions ask for real
  workouts saved to Health.
- **The Plan tile shows the count but doesn't log yet.** The food check-in moves into the app
  in Phase 2; writing `plan_days.csv` now would fight the hourly sync task.
- **The reveal says "What you put in"**, not "What moved it", and lists the related habits with
  real counts. It doesn't claim a habit caused a result.
- **The log sheet doesn't promise Watch ring credit**; that needs checking on a device.
- **Goal, habits and measurements live in a settings file** (`config.json`, editable in
  Settings); workouts, readings, measurements, reflections and commitments live in SwiftData.
- **No Instrument Sans.** Body text is the system font so Dynamic Type works (UX decisions);
  headlines use Instrument Serif (bundled, SIL Open Font License).

## Not in Phase 1

The Surf Report reader, food check-in, Go deeper chat and feedback (Phase 2); the home-screen
and StandBy widgets; the biweekly plan review; an app icon.

## Running the core tests

```bash
cd Packages/SurfCore && swift test
```
