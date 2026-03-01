# Echo Launch Readiness Red Flags (Pre-Launch)

This audit highlights **must-fix** gaps before considering Echo launch-ready.

## 1) Release build/distribution is not production-ready (BLOCKER)

- Android release builds are still configured to use the **debug signing key** and include TODO placeholders for production app/release identity. (`android/app/build.gradle.kts`)
- The only Codemagic workflow is explicitly for an **unsigned iOS IPA** (`ios_sideloadly`) and not an App Store/TestFlight signed pipeline. (`codemagic.yaml`)

**Why this blocks launch:** You cannot ship to App Store / Play Store reliably without hardened release signing and reproducible release pipelines.

**Required fix:**
1. Set up release keystore + secure signing config for Android.
2. Add a production iOS workflow with distribution cert/provisioning profile and signed archive export.
3. Remove/retire debug-signing fallback from release builds.

## 2) Storage data is globally readable (BLOCKER unless intentionally public)

- Storage rules currently allow `read: if true` for all uploaded files. (`storage.rules`)

**Why this blocks launch:** Any uploaded voice file URL/object can be fetched by unauthenticated parties. If public-by-design, this needs explicit product/legal approval and user-facing disclosure.

**Required fix:**
1. Decide policy: public feed audio vs authenticated-only access.
2. If private/semi-private, require auth + path/claim checks in Storage rules.
3. If public, document this in Privacy Policy and in-product disclosure.

## 3) Posting abuse controls were client-side only (**Implemented in code; validate in production**)

- Server-enforced hourly post quota is now implemented through Firestore security rules + atomic post-counter updates in repository writes (`users/{uid}/post_rate_limits/hourly`), while keeping the local UX guard in `PostService` as a fast-fail convenience. (`firestore.rules`, `lib/services/firebase_repository.dart`, `lib/services/post_service.dart`)

**What still must be done before launch:**
1. Deploy updated Firestore rules to production.
2. Run emulator/real-project rules tests proving the 21st post in one hour is denied even for modified clients.
3. Add abuse telemetry/alerts for posting spikes.

## 4) Authentication/account lifecycle was incomplete (**Implemented in code; validate policy/coverage**)

- Account deletion now performs app data cleanup before Clerk deletion by purging user-owned voice notes + storage files and user-scoped Firestore subcollections, then deleting the Clerk account. (`lib/app/app_state.dart`, `lib/services/firebase_repository.dart`, `lib/services/auth_service.dart`, `lib/screens/settings_screen.dart`)

**What still must be done before launch:**
1. Confirm policy coverage for all user-linked data (including any future collections like replies/messages).
2. Validate deletion flow on production-like data volumes and failure retries.
3. Publish exact retention/deletion guarantees in Privacy Policy/Terms.

## 5) Placeholder/legal/safety surfaces are exposed but non-functional (BLOCKER)

- Settings presents legal and safety rows (`Privacy policy`, `Terms of service`, `Community guidelines`, `Blocked accounts`, `Report history`) but tiles are non-interactive placeholders (no navigation/action wired). (`lib/screens/settings_screen.dart`)

**Why this blocks launch:** Required legal disclosures and trust/safety controls are not actually accessible in-app.

**Required fix:**
1. Wire legal links to live hosted documents.
2. Implement blocked accounts and report history screens (or hide until implemented).

## 6) Core product area was unfinished in primary nav (**Implemented: tab removed for now**)

- The Inbox tab/route has been removed from shell navigation and bottom nav to avoid a dead-end “coming soon” surface. (`lib/app/router.dart`, `lib/widgets/bottom_nav.dart`)

**What still must be done before launch:**
1. If replies are part of MVP, ship a minimal end-to-end reply experience before reintroducing Inbox.
2. Keep navigation and onboarding copy aligned with currently available features.

## 7) Notification controls were exposed without backend delivery (**Implemented: controls removed for MVP**)

- Notification toggles/actions have been removed from Settings and onboarding permissions to avoid promising unsupported behavior before FCM delivery exists. (`lib/screens/settings_screen.dart`, `lib/screens/onboarding_permissions.dart`)

**What still must be done before launch:**
1. Keep notification controls hidden until end-to-end delivery is implemented.
2. When reintroduced, ship token registration, send pipeline, and user-visible failure handling together.

## 8) Secrets/config hygiene and environment separation need hardening (HIGH)

- Firebase app config files with project identifiers/API keys are checked into repository (`android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`).

**Why this is a launch risk:** While Firebase mobile API keys are not true secrets by themselves, committing production project config without strict environment separation increases accidental misconfiguration and abuse blast radius.

**Required fix:**
1. Use separate Firebase projects per environment (dev/staging/prod).
2. Ensure CI injects environment-specific config securely.
3. Restrict Firebase key usage and authorized app package/bundle identifiers.

## 9) Operational readiness gaps (BLOCKER)

- No production crash reporting/observability integration is visible in dependencies/config (e.g., Crashlytics/Sentry).
- No CI quality gate is visible for Flutter analysis/tests in repo workflows.

**Why this blocks launch:** Launching without telemetry and automated quality gates materially increases MTTR and regression risk.

**Required fix:**
1. Add crash/error reporting SDK + release symbol upload.
2. Add CI steps for `flutter analyze` and tests on PR/main.
3. Define launch SLOs and alerting thresholds.

## 10) QA evidence for physical-device signoff is missing (BLOCKER)

- Repo includes QA checklists (`docs/recording_qa_checklist.md`, `docs/autoplay_qa_checklist.md`, `docs/abuse_qa_checklist.md`) but no captured signoff artifacts in-repo.

**Why this blocks launch:** Audio apps are hardware/OS-behavior sensitive; emulator-only confidence is insufficient.

**Required fix:**
1. Complete and record real-device test passes for iOS + Android.
2. Capture known-device matrix, OS versions, and pass/fail evidence.

---

## Suggested launch gate (go/no-go)

Treat launch as **NO-GO** until items 1–7 and 9–10 are closed with evidence.
