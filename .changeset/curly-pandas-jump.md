---
"posthog-ios": patch
---

Session replay now respects the session replay feature flag once the first remote config resolves. Recording still starts optimistically from the disk-cached flag at cold start, but snapshots are now buffered (not persisted) until the first live remote config response arrives: if the fresh flag is on they are flushed to the replay queue, and if it disagrees (cached-on but fresh-off) they are dropped — so a returning user no longer uploads a stale-cache recording window that the fresh config disallows. A subsequent remote config that turns the flag off also stops recording promptly instead of waiting for the next session rotation.
