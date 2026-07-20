# Leo Tracker

Native macOS time tracker built with SwiftUI. Sessions are stored locally in SQLite. The app includes automatic stop after 5 minutes of system inactivity, reports, and export to CSV / Excel-compatible `.xls`.

## Requirements

- macOS 14 or later;
- Xcode 16 or later;
- Command Line Tools matching the installed Xcode version.

## Run with Xcode

1. Open Xcode.
2. Choose **File → Open** and open `Package.swift` from the project root.
3. Wait for Xcode to index the Swift package.
4. In the top toolbar, select the **LeoTracker** scheme and **My Mac** as the run destination.
5. Press **Run** or use `⌘R`.

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

Run tests with:

```sh
swift test
```

If you see an error about incompatible Swift and macOS SDK versions, update Xcode or run `xcode-select` again with the path to the installed full Xcode app.

## Local data

The database is stored at:

```text
~/Library/Application Support/LeoTracker/tracker.sqlite
```

All records stay on the user's computer and are not sent anywhere.
