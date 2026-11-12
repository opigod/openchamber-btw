# Changelog

## 2.7.0 — first standalone release

Base: OpenChamber `9d6ab41` (2.7.0).

### `/btw`

- `/btw` is now one stateless `session.generate` request. No session is created, forked, or written to.
- The answer opens in a transient dialog with compose, running, answered, failed, retry, copy, and close states.
- Each request has its own `AbortController`; closing or dismissing it never aborts the main turn.
- A five-minute timeout turns an unanswered request into a retryable error.
- Requests are isolated by runtime key and owner key, so a runtime switch or a second panel cannot deliver a stale answer or stack two dialogs.
- Legacy `/btw` forks stay hidden. Promoted forks receive the notice that lifts the old side-chat constraints.
- `/btw` in a new-session draft shows "Open a session first", keeps the text, and sends nothing.

### Builds

- Added `build-openchamber.sh` for Linux and Android.
- Linux: builds an Arch `openchamber-btw` package and installs it through `pkexec` and pacman.
- Android: builds the shared UI and a Capacitor debug APK, then installs over adb when a device is present.
- The builder provisions Bun, Temurin JDK 21, and the Android SDK when missing.
- Android SDK platform resolution handles both older (`platforms;android-35`) and newer (`platforms;android-37.0`) package names.
- The install step removes an existing `openchamber-btw` or `openchamber-custom` before installing, because pacman will not replace a conflicting package under `--noconfirm`.

### Verified

- Full UI suite: 1350/1350 test files passed.
- `bun run check:changed`: type-check, lint, dead code, and anti-slop passed.
- Linux package built and installed on Arch.
- Android debug APK built and tested on an emulator against a running OpenChamber server. `/btw` answered in the dialog and left the transcript unchanged; the new-session guard sent nothing.
