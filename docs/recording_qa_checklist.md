# Recording QA Checklist

Use this checklist on real devices (Android and iOS where possible).

## Permission flow

- First-time mic permission deny:
  - The app shows a clear message and does not loop prompts.
- Retry permission:
  - The system prompt appears again and recording can start.
- Deny twice:
  - The app stops prompting and explains to enable permission in Settings.

## Recording reliability

- Start recording and let the timer finish:
  - Recording stops cleanly and the preview is available.
- Interrupt recording with a call or by backgrounding the app:
  - Recording stops and the clip is preserved if possible.
- Re-record:
  - Old draft is cleared and a fresh recording starts.

## Posting pipeline

- Upload fail mid-way:
  - Post stays retryable (no duplicate posts).
- Spam tap "Post":
  - Only one post is created.
- Hang/slow upload:
  - Timeout surfaces a calm error, retry succeeds.
- File missing or zero bytes:
  - User is asked to record again.

## Debug targets

- Permission state machine: no repeated prompts after repeated denial.
- Draft persistence: pending recording + post draft survive navigation.
- Idempotent post: retries reuse the same clip id.
