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
- clerk_flutter
- clerk_auth
- cloud_firestore
- firebase_storage

## Clerk authentication setup

Echo uses Clerk as the identity provider for posting flows.

### Flutter SDK beta reference

Clerk's official Flutter SDK is currently in public beta.

- Frontend package: `clerk_flutter`
- Server-side packages: `clerk_auth`, `clerk_backend_api`
- Recommended beta version at time of writing: `0.0.8-beta`

The app currently pins:

- `clerk_flutter: 0.0.8-beta`
- `clerk_auth: 0.0.8-beta`
- `clerk_backend_api: 0.0.14-beta`

Keep these pinned to exact patch versions while the SDK is stabilizing.

### 1) Pass publishable key

Use dart-define at run/build time:

```bash
flutter run --dart-define=CLERK_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Do not commit real keys to source control. `.env` is gitignored for local-only development.

### 2) Behavior

- Browsing stations and listening works as a guest.
- After onboarding, users are routed to sign-up once.
- Posting flows (record/upload) require Clerk sign-in.
- Settings includes sign up/sign in, sign out, and delete-account entry points.

### 3) OAuth platform notes

If you enable Apple/Google in Clerk, complete redirect configuration in Clerk Dashboard plus platform manifests:
- iOS: Bundle ID + URL schemes / universal links as required by Clerk provider setup.
- Android: Intent filters for Clerk redirect URIs in `AndroidManifest.xml`.

Follow `clerk_flutter` README for exact provider-specific values.
