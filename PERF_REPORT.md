# Echo autoplay performance investigation report

## Phase 0 — Inventory + reproducible path

### Playback architecture inventory
- Packages in use: `just_audio`, `audio_service`, and `rxdart` are direct dependencies. Playback orchestration is custom (controller + engine abstraction), not direct widget-level `just_audio` subscriptions.【F:pubspec.yaml†L43-L56】
- Core playback pipeline:
  - `AudioController` subscribes to engine snapshots (throttled at 100 ms) and emits `PlaybackMetrics` stream updates used by UI.【F:lib/services/audio_controller.dart†L78-L118】
  - `NativeAudioEngine` polls native playback state every 220 ms and emits snapshots with position/buffer state; this is the baseline high-frequency source for UI updates.【F:lib/services/audio_engine.dart†L638-L672】
  - `AutoplayController` listens to `AudioPlaybackController` (`_audio.addListener(_handleAudioChanged)`) and drives queue/phase state and transitions.【F:lib/services/autoplay_controller.dart†L203-L213】
- UI listener points:
  - Autoplay page root contains a `StreamBuilder<PlaybackMetrics>` that wraps a large widget subtree (title/avatar/layout/buttons/progress).【F:lib/screens/autoplay_player.dart†L239-L336】
  - Miniplayer container in `AppScaffold` also wraps a large blur/gradient card in a `StreamBuilder<PlaybackMetrics>`.【F:lib/widgets/app_scaffold.dart†L145-L220】

### Repro steps (for local profile run)
1. Launch app in profile mode: `flutter run --profile`.
2. Open a hashtag station, enter autoplay player, let 10–20 transitions occur.
3. Keep miniplayer visible while navigating between feed/detail/autoplay screen to force mixed UI listeners.
4. Use weak/throttled network for streaming URLs to increase buffering state transitions.
5. Record DevTools Performance timeline during transitions and while progress is advancing.

## Phase 1 — Measurement and evidence

### Instrumentation added
- Added `PlaybackPerfMonitor` with `WidgetsBinding.instance.addTimingsCallback` to record:
  - worst build/raster frame times
  - jank frame count (`build >16ms || raster >16ms`)
  - `playbackMetrics` event frequency, state-change frequency, track-change frequency every 5s log window.【F:lib/services/playback_perf_monitor.dart†L24-L73】
- Hooked monitor startup in `main()` so profile/dev runs emit periodic diagnostics without changing product behavior.【F:lib/main.dart†L12-L39】

### Environment limitation during this run
- `flutter` and `dart` executables are not available in this container, so profile-mode collection and test execution could not be run here. The added monitor is intended for immediate use on your local/device profile run.

## Phase 2 — Root causes (file/line evidence)

1. **High-frequency playback events are consumed directly by broad UI listeners.**
   - Prior behavior exposed raw `playbackMetrics` stream directly to page/miniplayer-level `StreamBuilder`s.【F:lib/screens/autoplay_player.dart†L239-L336】【F:lib/widgets/app_scaffold.dart†L145-L220】
2. **Update frequency mismatch between audio and UI composition cost.**
   - Engine updates are frequent (100 ms controller throttle + 220 ms native polling), which is too frequent for expensive blur/gradient/layout rebuild scopes in miniplayer/autoplay root.【F:lib/services/audio_controller.dart†L78-L84】【F:lib/services/audio_engine.dart†L638-L672】
3. **No explicit UI sampling layer in playback abstraction.**
   - `AudioPlaybackController` previously exposed only one metrics stream; widgets consumed it directly, encouraging over-rebuild patterns across multiple screens.【F:lib/services/audio_playback_controller.dart†L89-L114】

## Phase 3 — Implemented high-leverage fixes

### A) UI update throttling/sampling
- Added `playbackUiMetrics` stream to controller contract and implementation.
- Implemented UI sampling at 200 ms (`sampleTime`) in `AudioController` so visual consumers update at ~5 FPS max for stream-driven state, while audio engine can continue at higher internal cadence.【F:lib/services/audio_playback_controller.dart†L90-L94】【F:lib/services/audio_controller.dart†L67-L75】

### B/C) Reduce rebuild pressure by switching UI consumers to sampled stream
- Updated autoplay page and progress widget stream subscriptions from raw metrics to sampled UI metrics.【F:lib/screens/autoplay_player.dart†L239-L244】【F:lib/screens/autoplay_player.dart†L965-L980】
- Updated miniplayer container/progress/tracker subscriptions to sampled UI metrics.【F:lib/widgets/app_scaffold.dart†L145-L148】【F:lib/widgets/app_scaffold.dart†L413-L416】【F:lib/widgets/app_scaffold.dart†L615-L618】

### D) Regression guard
- Added test covering bursty engine snapshots and asserting `playbackUiMetrics` emits significantly fewer events than raw burst cadence, protecting against accidental removal of sampling behavior.【F:test/services/audio_controller_ui_metrics_test.dart†L9-L22】
- Updated test fake to satisfy new playback interface (`playbackUiMetrics`).【F:test/services/autoplay_controller_test.dart†L440-L444】

## Phase 4 — Verification plan and expected outputs

Because profile tooling is unavailable in this environment, run locally and capture:
- Before/after 30s autoplay timeline with monitor logs.
- DevTools frame chart during 3+ transitions.
- Compare monitor lines:
  - `metricsHz` should remain representative of backend cadence
  - jank count / worst build/raster should improve after sampled UI wiring

### Command checklist for local verification
- `flutter run --profile`
- Reproduce autoplay transitions
- Capture `[PlaybackPerf] ...` lines from device logs
- Optionally run: `flutter test test/services/audio_controller_ui_metrics_test.dart`

## Future work (post-main fix)
- Split root `StreamBuilder` rebuild scope further (avatar/header static vs controls/progress dynamic) for additional gains.
- Move miniplayer’s blurred background into a non-rebuilding child + lightweight overlay for status/progress updates.
- Evaluate prebuffer/preload policy in queue transition path if stalls remain under weak network.
