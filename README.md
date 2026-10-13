# Shiksha Desk

Offline-first education management platform for schools, junior colleges and coaching institutes.
Built in phases; this is **build 1f (safety)**. Phase 1 is complete.

## What is built so far

Build 1a (skeleton): responsive app shell, design system, module registry, English text file, demo mode, CI builds.

Build 1b (data core):
- One encrypted database file per institution (SQLite3MultipleCiphers). The key lives in the
  Android Keystore / Windows Credential Manager and never leaves the device.
- Permanent random ids (UUID v7) for every record; standard columns on every table.
- Every change writes an audit entry (who, what, when, old and new value) and an outbox entry for future sync.
- Repositories always filter by institution.
- Versioned schema with step-by-step migrations, a test for every step, and an automatic copy of the
  database before any upgrade.
- Module choices and theme are now saved.
- Settings > Data on this device shows encryption status and database version.

Build 1c (institution setup, database version 3):
- Setup wizard creates a real institution in its own encrypted file: details, board and medium,
  first academic year, classes and divisions from a template, logo and brand colour.
- Tap the institution name in the top bar to switch institutions or add one. The demo stays available.
- Settings > Institution profile, Academic years (add, make active, close) and Classes and divisions
  (add, rename, reorder, delete) with rules checked in the data layer.
- No institution name exists anywhere in the source code; it is typed into the app.

Build 1d (students, database version 4):
- One permanent record per student: code (STU-000001, never reused), names, personal details, caste and
  sub-caste (profile only), health (blood group, height, weight), admission, leaving, photo, notes.
- Guardians shared between siblings; official numbers (GR, PEN, APAAR, Saral, admission, Aadhaar) unique per institution.
- Aadhaar: checksum-verified, encrypted a second time, shown masked; showing it in full is audited.
- Enrollment per year with roll number; moving division keeps history; mark as left; recycle bin (30 days).
- Search by name, code, number or mobile; filters by class, division and status; duplicate warning before saving.
- Settings > Student fields: the institution's own extra fields and category list.
- The demo institution has 500 fictional students.

Build 1e (import and export, database version 5):
- Students > ⋮ > Import from Excel: .xlsx or .csv; finds the header row; matches columns automatically
  (English and Marathi headings); saved matchings reused next time; class/division from columns or one chosen
  division; missing classes created; every row checked (OK / warning / error) before saving; error rows
  downloadable; existing students skipped or only their empty fields filled; all-or-nothing import.
- Students > ⋮ > Import photos: many images or a .zip; matched by file name to serial number (from an Excel
  import), GR, admission number, student code, PEN, APAAR, Saral ID, roll in a division or full name; the
  best key is suggested; photos resized to 600 px JPEG.
- Settings > Imports: every import listed, each with Undo.
- Students > ⋮ > Export to Excel or CSV (follows the current search and filters).

Build 1f (safety):
- App PIN (4-6 digits, required once a real institution exists), fingerprint/face/Windows Hello, auto-lock after
  1-30 minutes or immediately, growing wait after 5 wrong tries, one-time recovery code.
- Backups: one .sdbak file per institution (all data, photos, logo) sealed with a backup password
  (AES-256-GCM, PBKDF2). Save anywhere: Google Drive, pen drive, email.
- Automatic backups: daily (7 daily + 4 weekly kept) and before imports and restores.
- Restore: password check, damage check, summary first; replaces the same institution (a safety copy of the
  current data is kept) or adds a new one; backups from newer app versions are refused.
- Dashboard reminder when no backup was saved off the device in 7 days.
- Settings > Data health: integrity, broken links, duplicate rolls, duplicate numbers, unplaced students.

The build workflow also switches Android's MainActivity to FlutterFragmentActivity (needed for fingerprint unlock).

## How to build (flat upload)

GitHub's "choose your files" button cannot upload folders, so every file is
named with its folder in the name, using `__` in place of `/`.
For example `lib__app__app.dart` means `lib/app/app.dart`.
The build puts them back into folders automatically.

One time only, create the workflow file:
1. In the repo choose **Add file > Create new file**.
2. Type the name `.github/workflows/build.yml` (the slashes create the folders).
3. Paste everything from `COPY-INTO-.github-workflows-build.yml.txt` and commit.

Then, every time:
1. **Add file > Upload files > choose your files**, select all the other files, commit.
2. Open the **Actions** tab and wait for "Build Shiksha Desk" to turn green.
3. Download `shiksha-desk-android` (APK) and `shiksha-desk-windows` (zip).

## Permanent signing key (one time, before installing build 1b)

1. Actions tab > "Build Shiksha Desk" > **Run workflow** > tick
   "ONE TIME ONLY: create the permanent Android signing key" > Run workflow.
2. When it finishes, download `shiksha-desk-signing-key-KEEP-SAFE` (available for 1 day).
   Keep the three files in two safe places. Never upload them to the repository.
3. Repo **Settings > Secrets and variables > Actions > New repository secret**, twice:
   - `ANDROID_KEYSTORE_BASE64` = contents of `ANDROID_KEYSTORE_BASE64.txt`
   - `ANDROID_KEYSTORE_PASSWORD` = contents of `ANDROID_KEYSTORE_PASSWORD.txt`
4. Uninstall build 1a from the phone one last time, then install build 1b.
   From now on, new builds install over the old one and keep the data.

## Folder map

```
lib/app/             start-up, router, responsive shell
lib/design_system/   tokens, theme, components (Sd...)
lib/platform/        organization, modules registry, demo data
lib/modules/         dashboard, students, settings
lib/l10n/            screen text (English)
test/                registry and layout tests
docs/adr/            architecture decisions
```
