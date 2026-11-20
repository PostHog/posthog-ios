---
"posthog-ios": patch
---

Stop sending a plain `UIViewController`'s `title` as the session replay screen name for frames captured through the Flutter native-screen bridge, matching other replay frames.
