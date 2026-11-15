# Changelog

## 2.7.2 — rebased onto OpenChamber 2.7.2

Base: OpenChamber `v2.7.2` (`1a15151`).

### `/btw`

- Rebased the stateless `/btw` onto upstream 2.7.2. The dialog behavior is unchanged.
- Upstream now renders `FormCard` in the transcript (`TranscriptForms`) as well as the dock, so the patch keeps the file and removes only `BtwPanel` and its state.
- `/btw` still answers through `session.generate` and never creates or forks a session.

### Builds

- The builder now targets the supported release tag `v2.7.2` by default. `--ref` still selects any tag or branch, but the patch only applies to its base.
- `PATCH_BASE` is `1a15151`.
- Fixed the stale "known-good `--ref c60bf01`" hint in the patch-application error.

### Verified

- `bun run type-check:ui`: passed.
- Full UI suite: 1383/1386 files passed. The three failures (`HeaderProjectControls`, `issue-3175-browserCaptureRevealsPanel`, `infiniteAnimations`) also fail on the untouched `v2.7.2` tag.
- `bun run check:changed -- --base 1a15151`: type-check, lint, dead code, and anti-slop passed.
- `/btw` tests: `btw.test.ts`, `useBtwStore.test.ts`, `BtwDialog.test.tsx`, `ChatInput.magicPrompts.test.tsx`, and `slashCommands.test.ts` passed.

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
