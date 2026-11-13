# APPIC Hours

A native macOS app for psychology trainees to log practicum hours session by session and
get AAPI-ready totals, with a one-click Excel export for the APPIC application.

Log a session in a few seconds (from the window or the menu bar), keep clients, groups,
supervisors and semesters organized, and watch your hours add up. The AAPI Summary rolls
everything into the categories, columns and demographics the AAPI asks for.

> **Not affiliated with APPIC.** The hour rules below come from APPIC's
> [Practicum Hours Tracking Guide](https://www.appic.org/Portals/0/Website%20docs/AAPI_Prac_Hrs%20_Tracking_Guide_%20Sept%2010_2026.pdf)
> (September 2026). Your Director of Clinical Training decides which hours count, so check
> your totals with them before you apply.

## Privacy first

Everything stays on your Mac. There is no account, sync, network access or analytics.
Your data lives in a folder you choose (default `~/Documents/APPIC Tracker Data`): one
SQLite database (`tracker.db`), daily backups (the newest 30) and Excel exports.

- **Use pseudonyms or codes only.** Never enter client names, birthdates or contact details.
- The app refuses to keep data inside the app or this project folder, so client data can't
  end up in a Git commit by accident. `.gitignore` also blocks database and spreadsheet files.
- `~/Library/Application Support/APPIC Hours Tracker/config.json` stores only the paths of your
  data and export folders.

## Requirements

- macOS 26 (Tahoe) or later. The interface uses Liquid Glass.
- Apple's Command Line Tools with Swift 6.2 or later. Install them with `xcode-select --install`.
  You don't need Xcode.

## Build and run

```bash
git clone <this repository>
cd appic-hours
./scripts/build_app.sh             # builds "APPIC Hours.app" in this folder
./scripts/build_app.sh --install   # …and copies it into /Applications
```

Double-click **APPIC Hours.app**, or with `--install`, open it from Applications, Launchpad
or Spotlight. The first launch asks where to keep your data. Re-run the script after pulling
updates. Your data folder is never touched by a rebuild, and the database upgrades itself
(with a backup first) when its format changes.

You build the app on your own Mac, so macOS runs it without the "unidentified developer"
warning. If you share a built `.app` with someone else, they'll need to right-click it and
choose **Open** the first time, because the app isn't notarized.

### Try it with demo data

```bash
mkdir -p /tmp/appic-demo
swift run SelfTest seed /tmp/appic-demo/tracker.db
APPIC_TRACKER_DATA=/tmp/appic-demo "./APPIC Hours.app/Contents/MacOS/APPIC Hours"
```

`APPIC_TRACKER_DATA` points the app at another data folder for that launch only. The demo
has made-up sites, clients, groups, supervisors, semesters, recurring sessions and a few
months of sessions.

## What's in it

| Page | What it does |
|---|---|
| **Log** | Pick a client (or tap a recent one), tap a duration, press Return. Defaults remember what you used last. **Undo** for 15 seconds. "To Confirm" lists recurring and planned sessions whose date has come (✓ counts it, ✗ drops it). "This Week" shows a running breakdown. |
| **Sessions** | Every session, filterable by type (tiles show hours and counts), semester, activity, day or search. There's a year-long **activity heatmap**: click a day to see its sessions. Double-click to edit; select several to edit or delete together. |
| **Clients** | Therapy and assessment clients (assessment clients grouped by site), groups, families and couples. Each client has sessions, demographics, reports and an open/closed status. **Batch Add Clients** is a spreadsheet-style grid: paste from Excel or Sheets, or import CSV/XLSX. |
| **Supervisors** | Each supervisor's sessions and hours (individual vs. group), with a quick way to log more. |
| **Calendar** | Month view of logged, planned and recurring sessions. |
| **Recurring** | Weekly sessions that show up under To Confirm on their date; pause or delete them. |
| **AAPI Summary** | Every AAPI category with Doctoral / Terminal Master's / Total columns, demographics, instruments, sites, anticipated hours, **Goals** with projected finish dates, and a weekly chart. Pick an "as of" date, or use **Sept 30 Cutoff**. **Export to Excel** (⌘E). |
| **Setup** | Sites, supervisors, **semesters**, assessment instruments, internship start date, data and export folders, backups. |
| **Menu bar** | A clock icon opens Quick Log without bringing up the window. |

You also get:

- **Batch Add Sessions** (⇧⌘N): one client, many dates. Add them one at a time, as a weekly series, or pasted ("9/2, 9/9, 9/16"). It saves all or nothing.
- **Weekly recap**: the first time you open the app after Friday 11:59 PM, a "week in review" card shows that Saturday–Friday's hours, sessions, new clients, instruments and milestones. Reopen it any time with ⇧⌘R.
- **Semesters**: add each semester's first day in Setup. There's a preset for Temple University, Fall 2024 – Summer 2027. Each semester runs until the next one starts, and its supervisor is detected from your supervision sessions. The Sessions page and the export break hours down by semester.
- **Excel export**: AAPI Summary, Demographics, Instruments, Sites, Anticipated, Specify notes, Sessions, Semesters, Clients, Groups, Reports, Supervisors and Settings sheets. Every sheet honors the "as of" date.

### How hours are counted

- **Rounding.** Following APPIC, the AAPI Summary, Goals and export round each session up to
  the next 15 minutes (a 50-minute session counts as 1.00 hour). The Log and Sessions pages
  show the time you actually entered.
- **Cutoff.** The AAPI counts hours accrued through **September 30** of the year you apply.
  Use **Sept 30 Cutoff** on the AAPI Summary before exporting. Put hours you expect after
  that in the AAPI's anticipated section (the Anticipated tab helps).
- **Planned sessions.** A session dated in the future doesn't count until you confirm it
  happened.
- **Direct contact** = intervention + assessment.
- **Research settings.** APPIC counts assessment or intervention done in a research context
  as practicum hours only if your DCT confirms it meets your program's practicum requirements.
- **Known gap:** the demographics count individually seen clients only. People you saw only
  in a group, family or couple aren't counted individually, because groups don't record
  their members' demographics.

### Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘1 – ⌘8 | Log, Sessions, Clients, Supervisors, Calendar, Recurring, AAPI Summary, Setup |
| ⌥⌘1 – ⌥⌘4 | New Intervention / Assessment / Supervision / Support session |
| ⇧⌘N | Batch Add Sessions |
| ⇧⌘K | New Client |
| ⇧⌘R | Weekly Recap |
| ⌘E | Export to Excel |

**Close vs. delete:** closing a case keeps every hour and hides the client from quick log.
Deleting permanently removes the client and all of their sessions, reports and recurring
sessions. The confirmation lists exactly what will go.

## Tests

```bash
swift run SelfTest
```

This runs about 200 checks on the core: validation, recurring and planned sessions, undo,
case closure and deletion, the AAPI rollup (rounding, cutoffs, reports), semesters, weekly
recaps, batch import (CSV/XLSX), the Excel export and backups. The Command Line Tools don't
include XCTest, so `SelfTest` is a small runner of its own. It also has `seed DB` (demo data)
and `export DB OUT ASOF` modes.

## Project layout

```
Sources/TrackerCore/   SQLite wrapper, schema and migrations, Repo (all validation), AAPI rollup,
                       goals, semesters, weekly recap, batch parsing, XLSX reader/writer, export, config
Sources/APPICHours/    SwiftUI app (AppModel + one file per page)
Sources/SelfTest/      test runner, plus the demo-data seeder
scripts/               build_app.sh (builds the .app bundle), make_icon.swift (draws the icon)
```

It has no third-party dependencies. It uses only the system SQLite and Apple frameworks.

## License

[MIT](LICENSE). The software comes with no warranty, and you're responsible for checking
that the hours you report are accurate.
