# Leo Tracker

<img width="1146" height="674" alt="image" src="https://github.com/user-attachments/assets/5ab3863a-b52c-4fc3-8712-8cd0ab30a843" />

Native macOS time tracker built with SwiftUI. Sessions are stored locally in SQLite. The app supports project-based tracking, hourly rates with currency, configurable auto-stop, project reports, CSV export, and full JSON backup import/export.

## Features

- Track work sessions by project.
- Continue a finished session with the same name.
- Edit session names and start/end times.
- Manage projects from Settings: add, rename, change hourly rate, change currency, and delete projects.
- Deleting a project also deletes all sessions for that project.
- Set a default project for new tracking sessions.
- Configure auto-stop inactivity timeout.
- View reports by selected project and period.
- See report totals, calendar hours by day, amount, sessions, and average session time.
- Export reports to CSV with quarter-hour billing units:
  - `15 min = 0,25`
  - `30 min = 0,5`
  - `45 min = 0,75`
  - `1 hour = 1`
- Configure which CSV columns are exported. Export settings are stored in SQLite.
- Export/import all local data as a JSON backup.

## Requirements

- macOS 14 or later;
- Xcode 16 or later;
- Command Line Tools matching the installed Xcode version.

## Run with Xcode

Use Xcode if you want to run Leo Tracker like a normal Mac app:

1. Open Xcode.
2. Choose **File → Open** and open `Package.swift` from the project root.
3. Wait for Xcode to index the Swift package.
4. Select the **LeoTracker** scheme.
5. Select **My Mac** as the run destination.
6. Press **Run** or use `⌘R`.

On first launch, SQLite automatically creates the local database.

## Run from the terminal

Clone the repository, then open the project directory:

```sh
git clone <repository-url>
cd leo-tracker
```

If multiple Xcode versions are installed, select the active one:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

Check the environment and run the app:

```sh
swift --version
swift run LeoTracker
```

This launches the app from the terminal, but it does not install Leo Tracker into `/Applications`, Launchpad, or Spotlight.

## Build a normal macOS app

To create a clickable `.app` bundle with a bundle identifier:

```sh
bash scripts/build-app.sh
open dist/LeoTracker.app
```

The generated app is written to `dist/LeoTracker.app`. You can copy it to `/Applications` if you want it to appear with your other macOS apps.

Run tests with:

```sh
swift test
```

## Continuous integration

GitHub Actions is configured in `.github/workflows/ci.yml`. CI runs on macOS and checks:

```sh
swift build
swift test
```

If you see an error about incompatible Swift and macOS SDK versions, update Xcode or run `xcode-select` again with the path to the installed full Xcode app.

## Local data

The database is stored at:

```text
~/Library/Application Support/LeoTracker/tracker.sqlite
```

All records stay on the user's computer and are not sent anywhere.

The database stores:

- projects, including hourly rate and currency;
- time sessions;
- app settings such as default project and CSV export columns.

Use **Settings → Export All Data** to create a JSON backup. Use **Settings → Import Backup** to restore from a backup. Import replaces the current local database contents.
