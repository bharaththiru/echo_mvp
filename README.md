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

## Firebase
Echo uses Firebase Auth + Firestore + Storage. Make sure these files are in place:
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

Enable Email/Password in Firebase Auth. (Google/Apple can be enabled later.)

### Rules
Firebase rules are tracked in:
- `firestore.rules`
- `storage.rules`
- `firebase.json`

### Firestore data
Collections used:
- `hashtags` (documents keyed by hashtag id)
  - `name` (string)
  - `description` (string)
  - `note_count` (number)
  - `is_active` (bool, optional)
- `voice_notes`
  - `hashtag_id`, `hashtag_label`, `author_id`
  - `created_at`, `expires_at`
  - `duration_seconds`, `storage_path`
  - `allow_replies`, `caption`, `status`

### Dev ergonomics
Skip auth gating and auto sign-in for local testing:
```
flutter run \
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
- firebase_core
- firebase_auth
- cloud_firestore
- firebase_storage
