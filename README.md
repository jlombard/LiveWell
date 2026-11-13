# LiveWell — iOS app

The app behind the Surf at 60 goal. "Surf at 60" is the goal configured in it; LiveWell is the app.

Phase 1 of the build spec: HealthKit sync that writes the Mac's CSV files, the check-in,
the lock-screen widget and the Today dashboard. Built to the UX concepts canvas and the
"Built for later" rules (the app owns its data; goals and habits are configuration; every
value has a provenance; no double counting).

Phase 2 adds The Surf Report: a native reader for the daily issue, past issues and the recipe
box, the food check-in, votes on cards, and the Go deeper chat. The follow-ups (Nov 13, 2026)
add the cutover tools, sections, home-screen widgets, the biweekly plan review, the app icon
and a new-issue alert.

**Status.** Phases 1 and 2 run on the phone. The follow-ups build with no warnings and the core
library passes its 56 tests. Checked in the simulator against a copy of the real folder: the
plan review screen, the section filter, the icon render and the widget layouts (rendered
off-device). Not yet seen on a device: the new widgets on a home screen and in StandBy, the
tinted and dark icon, accepting a plan change, and the new-issue alert. See "Trying the
follow-ups" below.

## What's here

| Path | What it is |
| --- | --- |
| `Packages/LiveWellCore` | Pure Swift, no Apple frameworks. File formats, `checkins.csv` editing, habit counting, `data.json` decoding, widget line, reveal wording, the plan as configuration. Has the tests. |
| `App/Health/HealthSync.swift` | Observer queries with background delivery, anchored queries (adds, edits, deletions by HealthKit UUID), Exercise minutes, sleep, tap-to-log workouts. |
| `App/Files/HealthGlanceFolder.swift` | The folder bookmark; every read and write through `NSFileCoordinator`; watches `data.json`. |
| `App/Store` | SwiftData models and `AppModel`, the sync pipeline: Health → store → CSV files → `data.json` → widget. |
| `App/Shell` | The front page, Sections, Rituals, the Library, and what feeds them (editions, rituals, routing). |
| `App/Screens` | Health dashboard, Check-in (hub, pop-up timer, reveal, close the week), Settings with sync status, the Report and its Go deeper sheet. |
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

## The shell: Today, Sections, Rituals (Nov 13, 2026)

Step 1 of "Sections and Wealth": the app is now a shell for separate daily editions, with
Health moved into it unchanged. Built to the "Sections: Health + Wealth" row on the UX canvas.

- **Today** is the front page: the date as masthead, a goals card with one row per section that
  has something worth a glance (Health: goal and days, the Today line, habit icons), then
  today's editions as covers with story count, lead headline and an unread dot. When today's
  edition isn't there it says so: "on its way" before 8 AM, "didn't arrive" after. Settings
  sits behind the gear.
- **Sections** has a card per section (Health: five mini progress bars and what it contains),
  "Add a section", the Library (kept answers, recipes and Labs, searchable) and Data and privacy.
- **Section home**: Health's is the former Today dashboard, followed by today's edition, the
  check-in and the library. The front-page row and Sections → Health both open it, and so do
  the Health widgets.
- **Rituals** lists Due now, Coming up and Done recently: the weekly check-in, commit to the
  week and the plan review. The tab carries a badge for what is due.
- Optional parts are absent, not empty: a section with no goal shows no countdown, and Wealth
  doesn't appear anywhere until it has data.

## Wealth: holdings, prices, the board (step 2, Nov 13, 2026)

- **Holdings import.** Settings → Wealth → Import holdings CSV, or share a CSV to LiveWell.
  The importer finds the header row with a Symbol (or Ticker) and a Quantity (or Shares)
  column, keeps ticker, shares, cost basis and the security's name, adds up lots of the same
  holding, and skips cash and money-market lines. Account numbers and names are never stored;
  a file shared into the app is deleted after it is read.
- **Prices.** Finnhub's free plan has quotes but not daily history, so the app records each
  close itself: one quote per holding after each US close (4:10 PM New York), from the sync and
  background refresh. The key lives in the Keychain and travels in a header, not the URL.
- **The weekly number** is the change across holdings weighted by value, measured from the last
  close of the previous week, in percent only. Until the app has that close it measures from
  its first close of the week and says "since Wed". The day's change is a setting.
- **The board** ("Why you own it") lists each holding with its share of the account, a status
  pill and what is next, largest first, with a note when one holding passes 40%. Every holding
  reads "Write it" until reasons exist (step 3).
- **Front page, Sections, Rituals** gain their Wealth row, card and the monthly holdings
  refresh once holdings are imported. Until then Wealth is absent.
- **Widgets:** a Wealth widget (small, and a lock-screen rectangle) and a combined medium
  widget with one line from each section. Same ink, no red or green.
- **For the morning run:** `app/wealth.json` holds each holding's ticker, name, share of the
  account in percent and status, plus the week's percent. No share counts or dollar amounts
  leave the phone.

## Wealth: Ask and your reasons (step 3)

- **Reasons.** Each holding has "why you own it": an "I believe" line, reasons, deal-breakers
  and things to watch. A thesis already in `investment-framework.md` (ASML) is read into the
  board in the app's words; reasons written in the app take precedence over it.
- **Ask.** A conversation scoped to a section. For a holding it is the guided way to write the
  reasons: nine lenses (Problem, Business model, Users, Developers, Supply chain, Smart money,
  Ceiling, Speed, Values), one at a time. For Wealth, Claude can search the web during an
  answer so lenses are grounded in filings. It proposes lines; a line joins the draft only when
  you tap "Add to my draft", and every line can be reworded or removed. The draft saves once it
  has a belief, a reason and a deal-breaker.
- **Language.** The app and the prompts use the everyday words from the spec's table; the
  framework's terms stay in the framework document.
- **Board, Rituals.** A written holding reads "Still true"; a started one shows its lens
  count. "Write why you own …" sits under Due now until every holding is written.
- **For the morning run:** `app/reasons.json` (words only).

## Wealth: the Build Wealth edition (step 4)

- **One edition per section.** Build Wealth issues live in `newsletter/wealth/issues/` and are
  never blended with The Surf Report. The front page shows a cover for each; the reader, past
  issues, votes and Go deeper work for both. Wealth has no countdown and no food check-in.
- **Card fields for Wealth:** a `verdict` that leads the card ("Is why you own it still true?
  Yes."), the lens (shown by its everyday name), and Owned or Watching. Every Build Wealth card
  kind draws in the shared card grammar.
- **Editor's guide:** `engine/build_wealth_guide.md`, with the language table, rules, card
  kinds, the issue format and the daily steps. The scheduled morning task still has to be told
  to run it; that task lives in your Claude account, not on this Mac.
- **Notification:** one for all of the day's editions ("Your editions are ready"), updated in
  place when a second edition lands, with "Wealth: 1 thing to do" at most once a week.

Not checked yet: a live Finnhub call and a live Ask answer with web search (no keys on the
Mac), a real Build Wealth issue from the morning run, and the Wealth widgets on a device.

## Wealth: the weekly puzzle (step 5)

"Name the company" is a card kind that plays inside the card, ported from the prototype: a
treemap of revenue by type with generic labels, six guesses with type-ahead over 49 companies
and their aliases, a clue unlocked by each miss, and three squares of closeness per guess
(sector, industry, niche). The reveal names the company, explains the shape, gives the lesson
and the sources, and offers a share grid in black and white squares. Results, streaks and stats
stay on the phone. While the newest edition's puzzle is unplayed, the front page shows it as an
extra. Go deeper never sees the answer. The guide tells the morning run how to write one.

Still to come: the "Still true?" and earnings rituals, the watchlist, and move alerts.

## Follow-ups (Nov 13, 2026)

**Cutover**
- `python3 engine/compare_trial.py` (in the Health Glance folder) builds from `health/` and
  `health_app/` and prints habits and pillars side by side; `--days 7` covers the last week.
  `build.py` gained `--health <folder>` for it (old copy in `engine/old/build_2026-11-13.py`).
- Every session counts: no merging and no minimum length. Duplicates go by HealthKit UUID.
- `vo2max.csv` and `weight.csv` hold only the latest reading of each day.
- Turning Trial mode off in Settings moves `health/workouts_log.csv` to `health/old/`. Turning
  off the three Watch automations and the Export Shortcut is still yours to do that day.
- Lift counts FitClub days from `fitclub/sets.json` as well as Health strength workouts, the
  way `build.py` does, so the tile and the review agree with the Mac.

**Sections.** `config.json` is section-first: each section has a key, name, icon and accent,
and optionally a goal, habits, measurements and a dashboard. Health is the only one today; an
older `config.json` loads as the Health section with every edit kept. Issues and cards carry a
`section` (missing means `health`); the Report shows section chips once an issue or the archive
has more than one, and votes, kept answers and the Go deeper prompt carry it. Today reads the
dashboard section and habit icons come from the config, so nothing there is fitness-specific.

**Widgets.** Small (also StandBy): days left, the Today line, five icons lit or dim. Medium:
the Today line, icons with counts, five progress lines with the current dot. Both mark their
accent parts for iOS 18's tinted mode. The lock-screen widgets are unchanged.

**Plan review.** Every other week, after "Commit to the week": two weeks of each habit, each
pillar's 4-week trend, and at most one proposal. First match wins: a habit met both weeks with
a flat pillar steps up; a habit missed both weeks gets a smaller target; a pillar past its goal
is offered the next goal from `settings.json`; otherwise stay the course. Accept writes a dated
plan version into `config.json` and the goal into `settings.json` (only that number changes).
Every decision is appended to `app/plan_review.json`, and the morning guide now tells the run to
explain it. Pillar trends come from check-ins, Health and a daily record the app keeps from
`data.json`; Strength has no trend until that record is four weeks old.

**Weekly commitment overrides.** In "Commit to the week" each row has a stepper that changes
that habit's target for this week only (sessions and plan days by 1, active minutes by 25, down
to 0 or up for a stretch week), with one optional reason. The closing line adapts and names what
comes back and when. A long press on a Today tile changes the current week mid-week. While a
week is in force: a habit at 0 shows "Off this week" and is neither met nor missed, a lowered
target lights up when met, an off habit leaves the widgets, and the Today line never suggests
it. Targets return to the usual goals when the week ends. The plan review treats a changed
week as planned, never as a miss, and proposes nothing permanent from it. Weeks are kept in
SwiftData and written to `app/commitments.json`; `build.py` applies the week in force to habit
goals and the Today line, the frame shows "off", and the morning guide tells the run to write
to the week Joe chose. Known edge, left as agreed: for a few days after an override week the
rolling 7-day count still includes the off days.

**App icon.** D1 "Rising progress", rendered from the spec's geometry at 1024 px in standard,
dark and tinted variants (`App/Assets.xcassets`).

**New-issue alert.** When a newer file appears in `newsletter/issues`, the app posts a local
notification with the lead headline (Settings → The Surf Report). It fires from the folder
watch and from background refresh, and never while the app is in front.

**Guides.** `engine/surf_report_guide.md` now covers the `section` field and plan reviews (old
copy in `engine/old/surf_report_guide_2026-11-13.md`). The text for
`surf-at-60/dashboard-guide.md` is in `docs/dashboard-guide-app-section.md`, to paste into the
Live Well project.

### Trying the follow-ups

1. Run `python3 engine/compare_trial.py --days 7` on the Mac each day of the trial.
2. Add the small and medium widgets to a home screen; try tinted mode and StandBy.
3. Close a week in Check-in and go through the plan review. Accept only a change you want: it
   edits `settings.json`.
4. Leave the app in the background overnight and see whether the new-issue alert arrives.
5. In Check-in, close a week with one habit lowered; long-press a Today tile to change it
   again. Check `app/commitments.json`, and that the Mac dashboard shows the same target.
6. Log a workout from Today and check the Watch rings before the log sheet promises credit.

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

Money and Family sections (the architecture is in; there is no content yet); swiping between
stories full screen in the Report; Phase 3 experiments.

## Running the core tests

```bash
cd Packages/LiveWellCore && swift test
```
