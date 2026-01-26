# Echo (Flutter)

Echo is a Flutter rebuild of the original Echo iOS concept. The app focuses on short voice notes, calm discovery, and low-pressure sharing.

## Requirements
- Flutter 3.38+
- Dart 3.10+

## Setup
```
flutter pub get
flutter run
```

## Supabase
Auth is wired to Supabase. Provide your project URL and anon key at run time:
```
flutter run --dart-define=SUPABASE_URL=YOUR_URL --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```
Enable the Email/Password provider in Supabase Auth settings (email confirmations are supported).
The storage bucket defaults to `voice-notes` (override with `SUPABASE_STORAGE_BUCKET`).

### Schema + seed
Automated (recommended):
```
$env:SUPABASE_DB_URL="postgresql://postgres:YOUR_PASSWORD@db.YOUR_REF.supabase.co:5432/postgres"
.\scripts\apply_supabase_schema.ps1
```
```
export SUPABASE_DB_URL="postgresql://postgres:YOUR_PASSWORD@db.YOUR_REF.supabase.co:5432/postgres"
chmod +x scripts/apply_supabase_schema.sh
./scripts/apply_supabase_schema.sh
```
If your Supabase CLI does not support `--db-url`, link the project first:
```
supabase link --project-ref YOUR_REF
```
If your CLI does not support `db execute`, the script falls back to migrations via `supabase db push`.
If `supabase/config.toml` is missing, run `supabase init` once.

Manual fallback: run the SQL in `supabase/schema.sql` and `supabase/seed.sql` in the Supabase SQL editor.

Required tables/bucket:
- `hashtags` and `voice_notes` tables (RLS enabled).
- `voice-notes` storage bucket (public read, authenticated upload).

### Dev ergonomics
Skip auth gating and auto sign-in for local testing:
```
flutter run \
  --dart-define=SUPABASE_URL=YOUR_URL \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  --dart-define=SKIP_AUTH=true \
  --dart-define=DEV_EMAIL=you@example.com \
  --dart-define=DEV_PASSWORD=your-password
```
`SKIP_AUTH` bypasses login UI; `DEV_EMAIL`/`DEV_PASSWORD` enable automatic sign-in so you can post.

## Notes
- Recording and playback are implemented with native platform channels:
  - Android: MediaRecorder and MediaPlayer
  - iOS: AVAudioRecorder and AVAudioPlayer
- The microphone permission is required to record.
- Lora variable font is bundled locally under `assets/fonts`. License is in `assets/licenses/Lora-OFL.txt`.
- Web builds are not supported because audio and file storage rely on native platform APIs.

## Packages
Core packages:
- go_router
- shared_preferences
- path_provider
- supabase_flutter
