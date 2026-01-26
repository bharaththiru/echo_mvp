# Autoplay QA Checklist

Use this checklist on real devices (Android and iOS where possible).

## Core flow

- Open a hashtag and enter the autoplay player.
- Confirm playback starts quickly with no jarring UI flashes.
- Let a clip finish:
  - Expect a short, calm gap (~200-400ms).
  - The next clip should begin automatically.
- Listen through multiple clips:
  - No repeat clips until the queue is exhausted.

## Continuity stress tests

- Run a 30-60 minute soak test per device.
- Let 50 clips run end-to-end without touching the UI.
- Spam Play/Pause/Skip/Mute during transitions:
  - No crashes, no double-audio, no stuck loading.
- Exhaust the queue:
  - Confirm the loop/end-of-queue behavior is calm and consistent.

## Skip quota validation

- Rapid skip taps (10x):
  - At most one quota unit consumed per transition.
- Skip during buffering:
  - Consumes one skip only.
- Forced clip load failure:
  - Auto-skip does not consume quota.
- Midnight rollover:
  - Reset aligns with local date from server profile.
- Timezone change:
  - No early/late reset.
- Offline mode:
  - Skip behavior stays consistent; no bypass.

## Controls and state accuracy

- Tap play/pause rapidly several times:
  - Audio state and button icon should stay in sync.
- Tap skip while playing:
  - Current audio should stop immediately.
  - Next clip should start after the short inter-clip delay.
- Mute mid-clip:
  - Silence is instant and only affects the current clip.
- Pause while muted, then resume:
  - Clip remains muted until unmuted.
- Adjust volume:
  - Volume changes should be immediate.
  - Volume percent text should match slider position.
- Toggle hands-free mode:
  - Control size should change.
  - Playback should continue uninterrupted.

## Interruptions and background behavior

- Lock the screen while autoplay is running:
  - Audio should continue.
- Background the app and return:
  - Audio and progress should remain correct.
  - No double-audio or overlapping playback.
- Trigger an interruption (phone call, another media app, or Bluetooth change):
  - Playback should pause.
  - It should resume only if the user did not pause manually.

## Background + interruptions (stress)

- Lock/unlock the screen 10 times mid-clip:
  - No resets, no stuck loading, no clip jumps.
- Switch apps repeatedly while playing:
  - Playback continues or pauses gracefully, then resumes correctly.
- Open the camera (forces audio session changes on some devices):
  - Playback should pause and resume without swapping clips.
- Phone call / FaceTime interruption (real call if possible):
  - Pause on begin, resume only if user did not pause.
- Bluetooth on/off, AirPods connect/disconnect mid-clip:
  - No crashes, no wrong-clip resume.
- Wired headphones unplug mid-clip:
  - Playback pauses and does not auto-resume.

## Network and failure handling

- With a weak connection, start autoplay:
  - Expect subtle buffering status text only when needed.
- Disable the network mid-clip:
  - The app should not crash.
  - It should recover or skip to the next playable clip.
- Re-enable the network:
  - Autoplay should continue working.
- Inject bad clip URLs (404, slow timeout, corrupt file):
  - The player should auto-skip the dead clip.
  - No skip quota should be consumed.
  - A calm, brief status message is shown.
  - After repeated failures, a recoverable error state is shown.

## Route and hashtag changes

- While playing, switch to a different hashtag/player:
  - The previous playback should stop cleanly.
  - The new queue should start without overlap.
- Rapidly switch hashtags 10-20 times:
  - No overlapping audio, no mixed queues, no stale hashtag UI.

## Debug targets

- Single audio instance: no overlapping playback after skips or interruptions.
- State machine truth: UI always reflects engine state.
- Preload boundary: next clip should be ready before the current ends.
- Audio session config: focus + route changes do not break playback.
- Interruption handling: pause/resume rules remain consistent.
- Skip quota correctness: no double-consume, no bypass, no offline reset.
