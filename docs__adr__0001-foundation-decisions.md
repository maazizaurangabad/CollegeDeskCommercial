# ADR 0001 - Foundation decisions

Date: 2026-10-09
Status: accepted

| Decision | Choice | Why |
| --- | --- | --- |
| Product name | Shiksha Desk | Neutral across schools, colleges and coaching institutes |
| Application ID | in.shikshadesk.app | Permanent. Never change it, or installed apps cannot update |
| Stack | Flutter + Drift (SQLite) + Riverpod + go_router | One code base for Android, Windows and later web; strong migrations |
| Platforms in Phase 1 | Android and Windows | Both built by CI from one code base |
| Language | English only in version 1 | All screen text in lib/l10n/*.arb so other languages can be added later |
| Aadhaar | Full 12 digits, encrypted, masked on screen | Needed for documents; visible in full only with students.view_sensitive |
| Existing apps | M.A Aziz and Hamidia apps stay until import works | No disruption for the college office |
| Data ownership | No real student or institution data in this repository | Privacy; demo data only |

Full reasoning: "Shiksha Desk - Commercial Architecture Blueprint" document.

## Build 1b additions (2026-10-09)

| Decision | Choice | Why |
| --- | --- | --- |
| Encryption | SQLite3MultipleCiphers via the sqlite3 package build hook | Works on Android and Windows with one setting; SQLCipher plugin is end-of-life |
| Key storage | flutter_secure_storage, one random 256-bit key per institution | Hardware-backed on Android; never written in plain text |
| Missing key | Refuse to open, never create a new key over an existing file | Prevents silent data loss |
| Android backup | Disabled | The key is not backed up, so a restored database would be unreadable |
| Dates | Stored as ISO-8601 text in UTC | Readable, sortable, sync-friendly |
| Signing | One PKCS12 key created by CI once, held by the owner, applied with apksigner | Updates install over old versions and keep data |
