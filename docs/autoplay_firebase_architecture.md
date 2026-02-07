# Autoplay Firebase Architecture

## Storage + CDN

- Store clip audio at `gs://.../{userId}/{clipId}.m4a`.
- Prefer serving through a CDN URL prefix via:
  - `--dart-define=FIREBASE_STORAGE_CDN_BASE_URL=https://<cdn-host>`
- If CDN is not configured, app falls back to Firebase Storage download URLs and keeps an in-memory URL cache (6h TTL) to avoid repeated URL fetch latency.

## Firestore Feed Model

- `clips/{clipId}`
  - Canonical clip metadata:
  - `station_id`, `station_label`, `created_at`, `duration_seconds`, `storage_path`, `author_id`, `caption`, `status`, `expires_at`
- `stations/{stationId}/feed/{clipId}`
  - Ordered feed projection optimized for pagination:
  - `clip_id`, `station_id`, `created_at`, plus lightweight playback fields (`duration_seconds`, `storage_path`, `author_id`, `caption`, `status`, `expires_at`)

## Pagination + On-Device Shuffle

- Query station feed with cursor pagination:
  - order by `created_at desc`, then document id desc
  - fetch window `N=50`
- On-device deterministic shuffle:
  - remove repeats
  - avoid same-author adjacency when alternatives exist
  - return up to target window (autoplay consumes this as enqueue candidates)
- No random Firestore reads in playback loop.

## Compatibility

- Reads:
  - Prefer `stations/{stationId}/feed`
  - Fallback to legacy `voice_notes` query if station feed is unavailable
- Writes:
  - Try writing `voice_notes` + `clips` + `stations/{stationId}/feed` in a batch
  - If new-collection writes fail (rules rollout lag), fallback to `voice_notes` write so posting still works
