# Autoplay UI/Playback Desync Bug Report

## Reproduction (before fix)
1. Open a hashtag and enter the Autoplay player.
2. Observe audio starts immediately.
3. Observe UI can remain in loading/buffering until play/pause is tapped once.
4. Let a clip complete.
5. Observe play/pause becomes unreliable and state label/icon can diverge.

## Root causes
1. **No immediate sync from controller to player on screen attach**: attach/load updated queue state but did not force an immediate reconciliation from the active audio engine snapshot, so UI could remain on stale loading state until a later interaction emitted fresh state.
2. **Play/pause completion path missing**: `togglePlayPause()` did not have explicit handling for `AudioPlaybackPhase.completed`, so manual recovery after completion could end up in a no-op path depending on engine state.
3. **Mixed UI derivation paths**: UI state used a blend of `AutoplayState` and metrics conditionals without a canonical playback status enum, allowing icon/label/spinner decisions to drift.

## What changed
- Added `AutoplayController.syncFromPlayer()` and invoked it during attach + cached queue rebind so state is reconciled immediately on Autoplay entry.
- Added explicit completion handling in `togglePlayPause()`:
  - advance to next queue item when available,
  - otherwise replay by `seek(Duration.zero)` + `resume()`.
- Added canonical `PlaybackViewStatus` derivation in `autoplay_ui_sync.dart` so icon/spinner/label decisions share one playback status source.
- Added a dev-only playback debug panel in the Autoplay screen to display key sync fields (playing, processing phase, index, clip id, position/duration/buffered).
- Added regression tests for tapping play after completion.

## Before vs After
- **Before**: entering autoplay could show loading while audio was already audible; completion could leave controls desynced or unresponsive.
- **After**: autoplay screen forces immediate sync on entry, completion path is explicitly recoverable, and UI controls are driven by one canonical status derivation.
