---
"posthog-ios": patch
---

Session replay (screenshot mode): capture on a timer as well as on view layout, so a screen that changes its pixels without laying out any view — video, a Core Animation loop, a redraw-only update — no longer replays as a still frame. Frames that render identical pixels back off to one render every 8 ticks.
