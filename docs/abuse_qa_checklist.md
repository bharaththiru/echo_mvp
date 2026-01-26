# Echo Abuse Controls QA Checklist

## Block + Report (launch safety)

- Block a user while their clip is playing
  - Confirm playback advances immediately.
  - Confirm the blocked user never reappears in the current session.
- Report a clip
  - Confirm the clip is hidden immediately.
  - Confirm report succeeds (online) and shows success copy.
  - If offline, confirm clip is hidden and the user sees a failure message.
- Hide a clip (no report)
  - Confirm it disappears from the feed and autoplay queue.
  - Confirm it does not reappear after a refresh.

## Rate limiting (spam guard)

- Post 20 clips in a short window
  - Confirm the app prevents additional posts with a clear message.
  - Confirm posting resumes after the rate window passes.

## Regression checks

- Block list persists across app restarts.
- Autoplay queue never plays a blocked or hidden clip.
- Hashtag feed never shows blocked/hidden clips after refresh.
