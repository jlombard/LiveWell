# LiveWell — iOS app, Phases 1 and 2

The app behind the Surf at 60 goal. "Surf at 60" is the goal configured in it; LiveWell is the app.

Phase 1 of the build spec: HealthKit sync that writes the Mac's CSV files, the check-in,
the lock-screen widget and the Today dashboard. Built to the UX concepts canvas and the
"Built for later" rules (the app owns its data; goals and habits are configuration; every
value has a provenance; no double counting).

Phase 2 adds The Surf Report: a native reader for the daily issue, past issues and the recipe
box, the food check-in, votes on cards, and the Go deeper chat.

**Status.** Phase 1 runs on the phone. Phase 2 builds with no warnings, the core library
passes its 29 tests (including decoding all 20 real issues), and every Report screen and
figure type has been checked in the simulator against a copy of the real folder. Not yet
exercised by hand: saving a food check-in, voting, and a live Go deeper answer (no API key on
the Mac). See "Trying Phase 2" below.

## What's here

| Path | What it is |
| --- | --- |
| `Packages/LiveWellCore` | Pure Swift, no Apple frameworks. File formats, `checkins.csv` editing, habit counting, `data.json` decoding, widget line, reveal wording, the plan as configuration. Has the tests. |
| `App/Health/HealthSync.swift` | Observer queries with background delivery, anchored queries (adds, edits, deletions by HealthKit UUID), Exercise minutes, sleep, tap-to-log workouts. |
| `App/Files/HealthGlanceFolder.swift` | The folder bookmark; every read and write through `NSFileCoordinator`; watches `data.json`. |
| `App/Store` | SwiftData models and `AppModel`, the sync pipeline: Health → store → CSV files → `data.json` → widget. |
| `App/Screens` | Today, Check-in (hub, pop-up timer, reveal, close the week), Settings with sync status, the Report and its Go deeper sheet. |
| `App/Report` | `ReportStore` (issues, plan days, votes, kept answers), figure and rich-text views, `ClaudeClient` (streaming Messages API call, key in the Keychain). |
| `LiveWellCore/Report.swift`, `PlanDays.swift` | Issue decoding (lenient), archive and recipe index, inline-HTML runs, `plan_days.csv`, feedback files, the chat prompt. |
| `Widget` | Lock-screen rectangular (Today line + five icons) and circular (active minutes). |
| `project.yml` | XcodeGen definition for the app and widget targets, capabilities and Info.plist. |

## Set up on the Mac (done 2026-11-12)

- Team `597RDXUTMT`, bundle ids `ink.boundless.livewell` and `ink.boundless.livewell.widget`,
  App Group `group.ink.boundless.livewell` (in `project.yml`; the group id also lives in
  `Shared/AppGroup.swift`).
- `xcodegen` in this folder regenerates `LiveWell.xcodeproj` after `project.yml` changes.

## File formats, as checked against build.py

`build.py` skips blank lines and any line whose first cell isn't a date, so headers are optional
everywhere. `ExportFormats` copies what the Shortcut files have today. Rewriting the live
files through the app's writer and running `build.py` on both gave the same `data.json`.

| File | Format | Notes |
| --- | --- | --- |
| `workouts.csv` | `start,type,minutes` header, then `2026-10-15 20:29,yoga,21` | Counted by substring of the type: `strength`, `rowing`, `yoga`. |
| `exercise_minutes.csv` | `2026-11-06,121`, no header | Only the last 7 days are read. Its modified time tells `build.py` Health has synced. |
| `vo2max.csv` | `2026-11-07,29.26`, no header | One row per reading. |
| `weight.csv` | `2026-11-12,172.1`, no header | One row per reading; `build.py` rounds to 1 decimal anyway. |
| `sleep_raw.txt` | `2026-11-04 00:34:40,2026-11-04 00:57:15,Core`, no header | Seconds included. Modified time is read too. |
| `checkins.csv` | `date,waist_in,popups_30s,sit_to_rise` | The Shortcut wrote one row per measurement; `build.py` takes the last row in file order with a value. The app reads several rows for a date as one, folds them when it saves that date, and keeps rows in date order. |

Things in `build.py` that the formats can't fix (decide before the cutover):

- **Trial mode has nothing to read it.** `build.py` only reads `<root>/health/` and
  `<root>/checkins.csv`; it has no way to point at `health_app/`. Comparing needs a staging
  root (settings, `fitclub/`, and `health_app/` copied in as `health/`) or a folder argument.
- **Back-to-back sessions count differently.** Rows from `workouts_log.csv` are dropped when
  the same type started within 90 minutes; rows in `workouts.csv` are all counted. Two yoga
  sessions 11 minutes apart are 1 today and would be 2 from the app's file.
- **`workouts_log.csv` is still read.** After the cutover its old rows are matched against the
  app's rows by type and time (within 90 minutes), so the Watch automations must be off and
  long sessions near the cutover may count twice until they age out of the 7 days.
- **Two readings on one day:** `build.py` sorts by (date, value), so the higher VO2 max or
  weight of the day is shown as the latest, whichever came last.

## On the phone

Open `LiveWell.xcodeproj`, pick the phone, and run (Xcode registers the bundle ids and App
Group on first build). Then link the Health Glance folder, connect Health, and check
Settings → Sync.

## The Surf Report in the app (Phase 2)

Built to mirror the web page (`engine/surf_report_template.html`) and the editor's guide.

- **Reader.** Reads `newsletter/issues/YYYY-MM-DD.json` straight from the folder; the newest
  file is today's issue. Every card kind and all five figure types (tiles, spark, scale, pairs,
  SVG drawing) are drawn natively; "win" cards invert. Unknown or malformed fields are dropped,
  never fatal. Past issues and the recipe box are built from the same files.
- **Food check-in.** The Plan check-in card writes `plan_days.csv` as `date,on,slips,note,at`
  (`build.py` reads the first three columns). The Plan tile on Today now counts from it (the 7
  days ending yesterday, as `build.py` does) and tapping the tile opens the card.
- **Votes and kept answers** go to `app/feedback.json` and `app/saved.json`.
- **Go deeper** sends the card and the issue's profile to Claude from the phone, with the same
  instructions the web page uses. It needs an Anthropic API key (Settings → Go deeper chat),
  stored in the iOS Keychain only. Default model `claude-opus-5-5`; Sonnet and Haiku are
  selectable.
- **`app/status.json`** tells the morning run whether the app is on trial.

The morning run's guide (`engine/surf_report_guide.md`) was updated on 2026-11-12 to read these
files (old copy in `engine/old/surf_report_guide_2026-11-12.md`). On trial it merges the app's
check-ins with the web page's, newest change winning, so a day logged in either place counts.
After cutover it stops writing `health/plan_days.csv` and the app owns it.

### Trying Phase 2

1. Run the new build on the phone and open the Report tab. If it says no issues were found,
   open the Files app once and let `Health Glance/newsletter/issues` download.
2. Log yesterday on the Plan check-in card, then check `health_app/plan_days.csv` on the Mac.
3. Vote on a card and check `app/feedback.json`.
4. Add an API key in Settings, tap Go deeper on a card, ask a starter question, and keep the
   answer (`app/saved.json`).

## Trial mode (the spec's cutover plan)

Trial mode is on by default. The app writes to `health_app/` (including
`health_app/checkins.csv` and `health_app/plan_days.csv`) and `app/`, and never touches
`health/` or the live `checkins.csv`. Run
`build.py` against both folders for about a week, then turn Trial mode off in Settings and
retire the Shortcuts and automations. The app never writes anything in `engine/`,
`fitclub/` or `newsletter/`.

## Decisions made while building (say if any should change)

- **Habits are counted over the last 7 days**, matching the Mac dashboard, and the tiles say
  "Last 7 days". The canvas says "This week".
- **Tap-to-log needs permission to save workouts**, so the app asks for that one write
  permission. The spec's technical notes said read-only; the later UX decisions ask for real
  workouts saved to Health.
- **The Report uses the app's dark theme**, not the web page's black on white; "win" cards
  are the light ones.
- **Recipes are shared with the iOS share sheet** (which includes Copy) in place of the web
  page's copy button.
- **Go deeper keeps no history between sheets**, like the web page; only answers you keep are saved.
- **The reveal says "What you put in"**, not "What moved it", and lists the related habits with
  real counts. It doesn't claim a habit caused a result.
- **The log sheet doesn't promise Watch ring credit**; that needs checking on a device.
- **Goal, habits and measurements live in a settings file** (`config.json`, editable in
  Settings); workouts, readings, measurements, reflections and commitments live in SwiftData.
- **No Instrument Sans.** Body text is the system font so Dynamic Type works (UX decisions);
  headlines use Instrument Serif (bundled, SIL Open Font License).

## Not built yet

The home-screen and StandBy widgets; the biweekly plan review; an app icon; a notification
when a new issue arrives.

## Running the core tests

```bash
cd Packages/LiveWellCore && swift test
```
