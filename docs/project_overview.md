# Echo Project Overview

This document is a high-level map of the repository after a full codebase pass.

## 1) What this project is

Echo is a Flutter mobile app for short-form voice notes organized around hashtag-based stations. The app has:

- onboarding and authentication,
- a listening/discovery experience,
- recording and posting flows,
- autoplay playback with queue management,
- basic moderation controls (hide/report/block), and
- Firebase-backed persistence.

The project is configured as a Flutter app (Android + iOS), with Firebase Auth, Firestore, and Storage as backend services.

## 2) Repository layout

### Application code

- `lib/`
  - `app/`: app wiring (`AppState`, router, dependency setup, settings persistence)
  - `screens/`: UI screens (listen, record, player, onboarding, auth, settings, etc.)
  - `services/`: business logic and integrations (auth, posting, feed fetch/shuffle, moderation, autoplay, audio playback/cache, skip quota, Firebase repository)
  - `models/`: typed domain models (`Hashtag`, `VoiceNote`)
  - `widgets/`: reusable components and shells
  - `theme/`: design tokens and theme system
  - `data/`: static seeds and hashtag style metadata
  - `utils/`: utility helpers (time formatting, ids, responsive spacing)

### Configuration and backend rules

- Firebase: `firebase.json`, `firestore.rules`, `storage.rules`
- Flutter config: `pubspec.yaml`, `analysis_options.yaml`
- Platform folders: `android/`, `ios/`, `web/`

### QA and operations docs

- `docs/` includes targeted checklists for recording, autoplay, abuse controls, and an MVP launch checklist.

### Tooling / scripts

- `scripts/seed_hashtags.js` and `scripts/hashtag_seed.json` seed hashtag docs into Firestore via `firebase-admin`.

## 3) Runtime architecture

## Bootstrap and DI

- `main.dart` initializes Firebase and creates `AppState`.
- `AppState.create()` performs central dependency assembly and lifecycle wiring:
  - `AuthService`
  - `FirebaseRepository`
  - `AudioController` + `AudioCacheService`
  - `SkipQuotaService`
  - `ModerationService`
  - `FeedService`
  - `PostService`
  - `AutoplayController`
- `AppScope` exposes `AppState` through an inherited notifier for UI access.

## Navigation

- `go_router` controls route flow.
- Router uses onboarding gating + shell navigation (listen/record/inbox/profile tabs).
- Full-screen detail routes are separate (`/hashtag/:id`, `/player/:hashtagId`, settings, post options, auth).

## State model

`AppState` is the façade used by UI; it delegates behavior to services while exposing observable state and helper methods. Persistent local settings (theme, motion/transcript toggles, onboarding flags, hashtag preferences) are stored in `SharedPreferences`.

## Data and backend model

Repository logic is concentrated in `FirebaseRepository` with compatibility support between:

- legacy collection: `voice_notes`
- newer feed model: `clips` + `stations/{stationId}/feed`

Firestore/Storage rules include:

- signed-in enforcement for protected writes,
- ownership checks for posting,
- report write restrictions,
- user subcollections for daily skip usage and blocks,
- public storage reads by default.

## 4) Feature walkthrough

## Onboarding and auth

- Onboarding routes are required until completion is persisted.
- Auth supports email/password, Google sign-in, and Apple sign-in.
- Local development can bypass auth (`SKIP_AUTH`) with optional auto sign-in.

## Discovery and listening

- `ListenTab` and `HashtagDetail` present stations and note lists.
- Feed behavior includes local persistence for saved/recent hashtags.
- Queue construction avoids repeats and applies moderation filters.

## Playback and autoplay

- `AutoplayController` manages queue state, transitions, preloading, phase changes, and sync with audio engine state.
- Audio paths include native platform handling and a fallback `audio_service`-based engine.
- Player UI includes progress, mute/volume controls, skip behavior, and reporting/blocking actions.

## Recording and posting

- `RecordTab` handles record lifecycle and draft behavior.
- `PostService` coordinates upload/post creation, startup draft recovery, and posting constraints (including throttling hooks).
- Audio files are uploaded to Storage with Firestore document writes via repository methods.

## Moderation and safety

- `ModerationService` provides hide/report/block operations.
- Hidden/blocked entities are synchronized with autoplay suppression and feed filtering.
- Abuse QA checklist exists in docs and aligns with implemented controls.

## 5) Testing and quality posture

Current automated tests in `test/` focus on:

- `AutoplayController` state/flow behavior,
- `AutoplayPlayer` widget-level interaction.

Repo docs indicate broader real-device QA expectations (recording, autoplay soak tests, abuse controls) and a launch checklist with known blocker items.

## 6) Notable implementation characteristics

- The app is intentionally mobile-first; web Firebase config is not enabled.
- Significant effort has gone into autoplay continuity and audio state correctness.
- There is explicit compatibility handling for feed model migration.
- Existing docs highlight several launch-hardening tasks (atomic post writes, permissions UX, fallback seek behavior, production/legal readiness).

## 7) Recommended next reading order for contributors

1. `README.md`
2. `docs/mvp_launch_checklist.md`
3. `lib/app/app_state.dart`
4. `lib/services/firebase_repository.dart`
5. `lib/services/autoplay_controller.dart`
6. `lib/services/post_service.dart`
7. `lib/screens/autoplay_player.dart`, `lib/screens/record_tab.dart`, `lib/screens/listen_tab.dart`
8. `firestore.rules` and `storage.rules`

This sequence gives the fastest route to understanding current architecture, risk areas, and user-critical flows.
