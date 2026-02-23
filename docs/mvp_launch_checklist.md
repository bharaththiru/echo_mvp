# Echo MVP Launch Checklist

This checklist covers everything that should be complete before shipping Echo to real users. Items are grouped by priority — **Critical** items are blockers; **Important** items should be done but have workarounds; **Nice to Have** can follow in a post-launch update.

---

## 🔴 Critical (Launch Blockers)

### Security & Firebase Rules
- [ ] **Fix public audio read in Storage rules** — `storage.rules` currently allows anyone to read all audio files. Decide if that's intentional (public feed = public URLs) or if auth should be required, and document the decision.
- [ ] **Add server-side rate limiting** — `PostService` rate-limits on the client only (20 posts/hour). A determined user can bypass this. Add a Cloud Function or Firestore rule to enforce it server-side.
- [ ] **Validate audio duration server-side** — The 12-second cap is enforced client-side and in Firestore rules (`duration <= 12`). Confirm the Firestore rule is deployed and tested with a malicious write.
- [ ] **Review Firestore rules end-to-end** — Run the Firebase Rules Unit Test suite or manually test that unauthenticated users cannot write, users cannot read/write other users' private data, and reports are create-only.

### Firebase Configuration
- [ ] **Add `ios/Runner/GoogleService-Info.plist`** — This file is excluded from the repo. It must be present in the production build pipeline (Codemagic env vars or secrets).
- [ ] **Confirm `android/app/google-services.json`** is present in the build environment (not just locally).
- [ ] **Set `FIREBASE_STORAGE_CDN_BASE_URL`** in the Codemagic environment for production audio delivery performance.

### Authentication
- [ ] **Test Google Sign-In on a physical Android device** — Emulator behaviour differs.
- [ ] **Test Sign in with Apple on a physical iOS device** — Requires a real device with a real Apple ID.
- [ ] **Confirm email verification flow** — Decide if email verification is required before a user can post; implement if so.
- [ ] **Handle account deletion** — What happens to a user's voice notes when they delete their account? Define and implement the policy (delete notes, orphan them, etc.).

### App Store Requirements (iOS)
- [ ] **Code-sign the IPA for distribution** — Codemagic currently builds an *unsigned* IPA for sideloading. A proper App Store or TestFlight release requires a valid Distribution certificate and provisioning profile.
- [ ] **Complete App Store Connect listing** — App name, subtitle, description, keywords, screenshots (all required device sizes), app preview video (optional but recommended for audio app).
- [ ] **Privacy Nutrition Labels** — Declare all data collected: audio recordings, user ID, email, usage data.
- [ ] **Privacy Policy URL** — Required by App Store. Must be live before submission.

### App Store Requirements (Android)
- [ ] **Create a Google Play Console listing** — App description, screenshots, content rating questionnaire.
- [ ] **Sign the Android APK/AAB** — Confirm release signing key is configured in `android/app/build.gradle`.
- [ ] **Privacy Policy URL** — Required by Google Play.

### Legal
- [ ] **Privacy Policy** — Written, reviewed, and hosted at a public URL. Must cover: audio data collection and retention, Firebase/Google data processing, third-party sign-in providers.
- [ ] **Terms of Service** — Written, reviewed, and hosted at a public URL. Should cover: content ownership, acceptable use, 24-hour expiration of voice notes, moderation and bans.
- [ ] **Link Privacy Policy and Terms in the app** — Add links in the onboarding flow and Settings screen.
- [ ] **COPPA compliance** — If any users may be under 13, you need explicit age-gating and a kids' privacy policy.

---

## 🟡 Important (Ship Soon After Launch)

### Core Feature Completeness
- [ ] **Inbox / Replies** — The Inbox tab shows "Replies are coming soon." Either implement a basic version or remove the tab from the nav bar so it's not a dead end for users.
- [ ] **Push Notifications** — Notification preference toggles exist in Settings but nothing sends notifications. Either wire up Firebase Cloud Messaging (FCM) or hide the toggles until notifications are built.
- [ ] **Transcripts** — The `transcriptsEnabled` setting exists but transcripts are never shown. Either implement (Cloud Function → Speech-to-Text → Firestore) or remove the setting until ready.

### Audio & Recording
- [ ] **Test recording on both platforms with a real device** — Run through `docs/recording_qa_checklist.md` fully on a physical iPhone and Android phone.
- [ ] **Microphone permission denial handling** — Verify the permission-denied state shows a clear recovery path (deep-link to system settings).
- [ ] **Background audio behaviour** — Confirm playback pauses correctly when the app goes to background or another app takes audio focus (phone call, etc.).
- [ ] **Earpiece vs. speaker routing** — Test audio output on devices with and without headphones.

### Content & Feed
- [ ] **Seed real hashtag content** — The feed is empty without posts. Seed at least 3–5 hashtag stations with real voice notes before launch so new users have something to listen to immediately.
- [ ] **Test pagination edge cases** — Empty feed, single item, exactly one page, network failure mid-scroll.
- [ ] **24-hour note expiration** — Confirm expired notes are actually removed from feeds (server-side TTL, scheduled Cloud Function, or Firestore TTL policy).

### Moderation
- [ ] **Run through `docs/abuse_qa_checklist.md`** — Block, hide, and report flows should all work end-to-end.
- [ ] **Moderation escalation path** — What happens after a user submits a report? Define the human review process (email to an admin inbox, Firestore admin panel, etc.).
- [ ] **Blocked user data isolation** — Verify a blocked user's notes don't appear in any feed or search results for the blocker.

### Error Handling & Resilience
- [ ] **Network failure states** — Show a helpful UI when Firestore or Storage is unreachable (no empty/blank screens).
- [ ] **Audio playback failure recovery** — If a clip fails to load, the autoplay queue should skip gracefully without freezing.
- [ ] **Auth token expiry handling** — Confirm the app refreshes Firebase ID tokens silently and re-prompts login only when truly expired.

### Performance
- [ ] **Profile feed load time** — Measure cold-start feed load on a mid-range Android device. Target < 3 seconds to first audio.
- [ ] **Audio engine warm-up** — Measure latency from tap-to-play. Pre-warm `just_audio` player pool if needed.
- [ ] **Memory leaks** — Run the autoplay queue for 15+ minutes and check for memory growth via Flutter DevTools.

---

## 🟢 Nice to Have (Post-Launch)

- [ ] **Crash reporting** — Integrate Firebase Crashlytics (or Sentry) to capture production crashes automatically.
- [ ] **Analytics** — Integrate Firebase Analytics or PostHog to track key events: session start, first record, first post, skip used, station entered, share action.
- [ ] **Offline support** — Cache the most recent feed locally so the app isn't entirely broken with no connection.
- [ ] **Server-side audio processing** — Normalise loudness, trim silence, validate codec on upload via a Cloud Function.
- [ ] **Admin dashboard** — Lightweight tool to review reports, manage banned users, and promote hashtag stations.
- [ ] **App icon & splash screen** — Confirm final icon assets are in place for all required sizes (iOS and Android).
- [ ] **Accessibility audit** — Screen reader labels on all interactive elements, sufficient colour contrast in both light and dark themes.
- [ ] **Localisation** — Not required for MVP, but stub the `intl` package now if international expansion is planned.
- [ ] **Automated tests** — Current coverage is 2 test files. Add integration tests for the record → post → listen flow before shipping significant new features.
- [ ] **Web support** — Currently throws `UnsupportedError`. Either add a "use the mobile app" landing page or remove web from the build matrix entirely.

---

## Definition of MVP Done

The app is ready to ship when:
1. All 🔴 Critical items are checked off.
2. The app has been tested end-to-end on at least one physical iPhone and one physical Android device.
3. Privacy Policy and Terms of Service are live at public URLs.
4. The App Store / Play Store listings are complete and the builds are signed.
5. At least one hashtag station has real content for new users to discover.
