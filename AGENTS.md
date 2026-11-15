# AGENTS.md

Operating manual for this repository. Read this before changing the patch, the builder, the releases, or the upstream PR.

## What this repository is

`openchamber-btw` is a focused distribution repo for one change: making OpenChamber's `/btw` a stateless side question.

It is **not** a checkout of OpenChamber. It contains:

- a patch that applies to the OpenChamber source tree
- a builder that downloads upstream, applies the patch, and builds Linux/Android
- user documentation
- release assets
- no server, no bundled OpenChamber source, no build outputs

The full OpenChamber source lives in the fork:

- <https://github.com/opigod/openchamber>
- local checkout: `/home/opi/openchamber`
- working branch: `feat/stateless-btw-latest`

The fork exists because upstream needs a real branch for the pull request. This repo is the standalone product page and build entry point.

## Quick facts

| Item | Value |
| --- | --- |
| Upstream | `openchamber/openchamber` |
| Patch base | `1a151518c95cc5ff3578bab593d2f96862ff3bb8` (`v2.7.2`) |
| Upstream version at base | `2.7.2` |
| Fork branch | `feat/stateless-btw-latest` |
| PR branch | `feat/stateless-btw` |
| Current fork head | `329cde2` (`fix(btw): never send /btw from a new-session draft`) |
| Upstream PR | <https://github.com/openchamber/openchamber/pull/6547> |
| Feature request | <https://github.com/openchamber/openchamber/issues/6548> |
| Release | <https://github.com/opigod/openchamber-btw/releases/tag/v2.7.2> |
| Arch package | `openchamber-btw` |
| Package binary | `openchamber` |
| Android app id | `com.openchamber.app` |

The PR is closed by the OpenChamber bot because feature PRs need an issue marked `accepted`. It reopens automatically when issue `#6548` gets that label. Do not reopen it manually and do not spam the issue.

## Golden rules

1. **Edit the fork, not the patch.** The patch is generated output. Make source changes in `/home/opi/openchamber`, commit them, then regenerate `btw-stateless.patch`.
2. **Keep both fork branches in sync.** `feat/stateless-btw` is the PR head; `feat/stateless-btw-latest` is the working branch. Push the same commit to both.
3. **Do not commit build artifacts or caches.** `*.pkg.tar.*`, `*.apk`, `out/`, and the build cache stay out of git. The `.gitignore` covers the common cases.
4. **Do not hand-edit generated release assets.** Build them from a clean patched source tree.
5. **Never commit secrets.** No GitHub tokens, OpenChamber client tokens, desktop passwords, local config, or `settings.json`.
6. **Do not restart OpenChamber from inside an OpenChamber session.** A running agent session lives in that process. Kill it only when the user explicitly asks and the session is not needed.
7. **Keep the package identity.** The Arch package is `openchamber-btw`, installs to `/opt/openchamber`, creates `/usr/bin/openchamber`, and declares `conflicts=('openchamber-custom')` / `replaces=('openchamber-custom')`.
8. **Do not add a second source copy to this repo.** If someone needs to read the code, point them at the fork branch or the PR, not a duplicated `packages/` tree.

## Repository layout

```text
.
├── AGENTS.md                    # this file
├── README.md                    # user-facing documentation
├── CHANGELOG.md                 # release history
├── LICENSE                      # MIT
├── build-openchamber.sh         # Linux/Android builder
├── btw-stateless.patch          # generated diff against PATCH_BASE
├── assets/
│   └── btw-android-dialog.png   # Android dialog evidence
└── docs/
    └── HOW-IT-WORKS.md          # request flow, states, invariants, tests
```

`docs/HOW-IT-WORKS.md` is the technical reference. Keep it in sync when behavior changes. `README.md` is the public install/build page; keep its links and asset names current.

## The change in one paragraph

`/btw` used to create a hidden fork session and mount a second composer. The patch deletes that path and calls OpenCode's `session.generate` instead. The question and answer never enter the parent session's history. A transient `BtwDialog` handles compose, running, answered, failed, retry, copy, and close. Each request owns an `AbortController` and a five-minute timeout. The dialog state is keyed by parent session and composer owner so two panels do not stack dialogs. Old `btw` forks stay hidden; a promoted fork gets a synthetic notice lifting the old constraints. A new-session draft has no parent session, so `/btw` says "Open a session first" and sends nothing.

## Key files in the patch

| File | Purpose |
| --- | --- |
| `packages/ui/src/lib/btw.ts` | Prompt, `generateSessionText` call, abort controller, timeout, retry state, runtime guard, legacy promotion notice. |
| `packages/ui/src/stores/useBtwStore.ts` | Per-parent-session request state and owner keys. |
| `packages/ui/src/components/chat/btw/BtwDialog.tsx` | Transient dialog UI. |
| `packages/ui/src/components/chat/ChatInput.tsx` | Recognizes `/btw` before normal send gates and mounts the dialog. |
| `packages/ui/src/components/chat/composer/submit/slashCommands.ts` | Plans `/btw` as a local action even without a session. |
| `packages/ui/src/lib/opencode/client.ts` | `generateSessionText` with abort-signal support. |
| `packages/ui/src/lib/btw.test.ts` | Request, timeout, abort, and legacy behavior. |
| `packages/ui/src/components/chat/btw/BtwDialog.test.tsx` | Dialog states and actions. |
| `packages/ui/src/components/chat/__tests__/ChatInput.magicPrompts.test.tsx` | Composer integration, including the new-draft guard. |
| `packages/ui/src/components/chat/composer/submit/__tests__/slashCommands.test.ts` | Planner behavior with and without a session. |

The patch also deletes:

- `packages/ui/src/components/chat/btw/BtwPanel.tsx`
- `packages/ui/src/components/chat/btw/useBtwPanelState.ts`
- the old btw panel tests
- `packages/ui/src/components/chat/FormCard.tsx`

`FormCard.tsx` is safe to delete because its only remaining consumer at the base commit was `BtwPanel`. `FormDock` is the normal form path.

The patch is large because it removes the fork machinery and updates i18n catalogs, docs, tests, and shared form routing. Do not try to make the patch smaller by leaving dead fork code behind; the point of the change is that `/btw` does not create a session.

## Changing behavior

Work in the fork:

```bash
cd /home/opi/openchamber
git fetch origin --tags
git switch feat/stateless-btw-latest
git rebase v2.7.2
# edit source
```

Then validate:

```bash
export PATH="$HOME/.bun/bin:$PATH"

bun install --frozen-lockfile
bun run type-check:ui
bun run --cwd packages/ui test
bun run check:changed
```

Targeted tests while iterating:

```bash
cd packages/ui
bun test src/components/chat/btw/BtwDialog.test.tsx
bun test src/components/chat/composer/submit/__tests__/slashCommands.test.ts
bun test src/components/chat/__tests__/ChatInput.magicPrompts.test.tsx
```

At the 2.7.2 base the full UI suite was `1350/1350` test files. Three files fail on the untouched `v2.7.2` tag too: `components/layout/HeaderProjectControls.test.tsx`, `components/layout/__tests__/issue-3175-browserCaptureRevealsPanel.test.ts`, and `lib/infiniteAnimations.test.ts`. Treat those as upstream failures; new failures are not acceptable.

Commit and push:

```bash
git add <files>
git commit -m "fix(btw): ..."
git push --force-with-lease fork feat/stateless-btw-latest

git fetch fork feat/stateless-btw
old=$(git rev-parse FETCH_HEAD)
git push --force-with-lease=refs/heads/feat/stateless-btw:$old \
  fork feat/stateless-btw-latest:feat/stateless-btw
```

Do not rewrite unrelated fork commits. Keep the four-part history readable: main feature, Android/WebView fixes, latest-main reconciliation, new-draft guard.

## Regenerating the patch

After the fork branch is final:

```bash
cd /home/opi/openchamber
base=$(git rev-parse v2.7.2)
git diff "$base"..HEAD > /home/opi/openchamber-btw/btw-stateless.patch
```

Then update `PATCH_BASE` in `build-openchamber.sh` to `$base`, and update the compatibility section in `README.md` if the version/base changed.

The patch must be generated from a tree that includes every fork commit. Do not generate it from a dirty worktree unless those changes are intentional and committed first.

Sanity-check the patch against a fresh base checkout:

```bash
tmp=$(mktemp -d)
git -C /home/opi/openchamber worktree add --detach "$tmp" "$base"
git -C "$tmp" apply --check /home/opi/openchamber-btw/btw-stateless.patch
git -C /home/opi/openchamber worktree remove "$tmp"
```

If `git apply --check` fails, rebase the fork and regenerate. Do not force a patch to apply by editing context lines by hand.

## Builder reference

`build-openchamber.sh` is the only supported build entry point.

```text
--target linux|android|all   default: linux
--install                    install the result (pacman and/or adb)
--ref REF                    upstream branch (default: main)
--workdir DIR                cache/build directory
--patch FILE                 alternate patch path
--help
```

Environment variables:

```text
OPENCHAMBER_REF
OPENCHAMBER_BTW_WORKDIR
OPENCHAMBER_BTW_PATCH
ANDROID_HOME / ANDROID_SDK_ROOT
JAVA_HOME
ANDROID_CMDLINE_TOOLS_URL
ANDROID_COMPILE_SDK
ANDROID_BUILD_TOOLS
ANDROID_PLATFORM_PACKAGE
```

Default work directory:

```text
~/.cache/openchamber-btw-builder/
├── source/          # shallow upstream clone with the patch applied
├── out/             # final package and APK
├── android-sdk/     # provisioned command-line tools + platforms + build-tools
└── jdk21/           # downloaded Temurin JDK 21 when no system JDK 21 exists
```

### Build flow

1. Clone or refresh upstream at `--ref` (`--depth 1`).
2. Reset hard and `git clean -fd` (not `-fdx`; ignored `node_modules` and caches stay).
3. Fetch `PATCH_BASE` if the shallow clone does not have its blobs.
4. `git apply --3way btw-stateless.patch`.
5. `bun install --frozen-lockfile`.
6. Read the version from `packages/electron/package.json`.
7. Linux: build the Electron dir, generate a `PKGBUILD`, run `makepkg -f`, copy the package to `out/`.
8. Android: provision JDK 21 and the Android SDK, run `bun run --cwd packages/mobile build:android:debug`, copy the APK to `out/`.

### Linux install behavior

With `--install`, the script:

1. Checks for installed `openchamber-btw` and `openchamber-custom`.
2. Removes them with `pkexec pacman -Rns --noconfirm`.
3. Installs the new package with `pkexec pacman -U --noconfirm`.

The separate removal matters. pacman will not replace a conflicting package in the same `--noconfirm` transaction. If a user reports the conflict, this is the fix.

The generated package:

- name: `openchamber-btw`
- version: `packages/electron/package.json` version, `pkgrel=1`
- installs `/opt/openchamber`
- symlinks `/usr/bin/openchamber`
- installs `/usr/share/applications/openchamber.desktop`
- installs the 512x512 icon and MIT license
- `conflicts=('openchamber-custom')`
- `replaces=('openchamber-custom')`

If you change the patch without changing upstream's version, `pkgrel` stays `1`. For a new public build, bump `pkgrel` (or use a new release tag and tell users to remove the old package first). Do not publish two different files with the same release asset name.

### Android install behavior

With `--install`, the script picks the first adb device in `device` state and runs `adb install -r`. If no device is present, it leaves the APK and says so.

The Android app is a Capacitor shell. It connects to an existing OpenChamber server; it does not embed OpenChamber or OpenCode. A connected app still needs a server with an OpenCode version that supports `session.generate`.

### Android SDK resolution

The script reads `compileSdkVersion` from `packages/mobile/android/variables.gradle` and resolves the platform package from `sdkmanager --list`:

1. `platforms;android-<compileSdk>`
2. `platforms;android-<major>.0`
3. any `platforms;android-<major>.*`, newest first

This handles the old `platforms;android-35` naming and the newer `platforms;android-37.0` naming. `ANDROID_PLATFORM_PACKAGE` overrides it.

Build-tools default to `<major>.0.0`. At the 2.7.2 base, Android uses compile SDK 37, platform `platforms;android-37.0`, build-tools `37.0.0`, and Gradle wrapper `9.9.0`.

Do not assume `/opt/homebrew` paths from the mobile package's scripts; the builder exports `JAVA_HOME`, `ANDROID_HOME`, and `ANDROID_SDK_ROOT` explicitly.

## Linux verification checklist

```bash
cd /home/opi/openchamber-btw
./build-openchamber.sh --target linux --install
pacman -Q openchamber-btw
ls -l /opt/openchamber/openchamber /usr/bin/openchamber
```

Then restart the desktop app (outside an active session) and verify:

- `/btw` opens the dialog.
- The dialog answer does not add a message to the transcript.
- `/btw` opens while the main agent is running a command.
- Closing the dialog does not stop the main turn.

## Android verification checklist

Build:

```bash
cd /home/opi/openchamber-btw
./build-openchamber.sh --target android
```

APK:

```text
~/.cache/openchamber-btw-builder/out/OpenChamber-btw-<version>-android-debug.apk
```

Install:

```bash
adb install -r ~/.cache/openchamber-btw-builder/out/OpenChamber-btw-<version>-android-debug.apk
```

The test emulator used for 2.7.0 was a phone AVD named `openchamber-phone`, API 35, with the emulator binary under `/tmp/opencode/tools/android-sdk`. A Wear OS image without WebView cannot render the app; use a phone/tablet Google APIs image.

Manual test:

1. Connect the app to `http://10.0.2.2:<server-port>` from an emulator, or the host LAN address from a device.
2. Authenticate with the server password or a client token. Never print or commit either one.
3. Open an existing session with at least one message.
4. Type `/btw what model are you using` and send.
5. Confirm the dialog appears over the chat and the answer is not in the transcript.
6. Open a new-chat draft, type `/btw why`, and send. Confirm the "Open a session first" toast, the text staying in the composer, and no new session.

The screenshot at `assets/btw-android-dialog.png` came from this flow. If the dialog UI changes, replace it and update the PR screenshot too.

## Testing notes

- `bun run --cwd packages/ui test` runs isolated test files; it is the primary suite.
- `bun run check:changed` checks type-check, lint, dead code, and anti-slop against the base.
- The OpenChamber base has unrelated lint warnings in `OfficeArtifact.tsx`, `PluginPane.tsx`, `useDraftStarters.ts`, and `useTextareaInlinePicker.tsx`. Warnings are fine; new errors are not.
- The test suite uses happy-dom and a mocked fetch. Do not add network calls to unit tests.
- Live `session.generate` tests need a running OpenChamber server and a model. Do not commit test sessions or model output.
- If a local test creates a real session, delete that test session afterward. The OpenChamber API accepts `DELETE /api/session/<id>` with the session directory header.

## Release process

Current release: `v2.7.2` with:

```text
openchamber-btw-2.7.2-1-x86_64.pkg.tar.zst
OpenChamber-btw-2.7.2-android-debug.apk
SHA256SUMS
```

Build both targets:

```bash
cd /home/opi/openchamber-btw   # or the local path on this machine
./build-openchamber.sh --target all
```

Checksums:

```bash
cd ~/.cache/openchamber-btw-builder/out
sha256sum openchamber-btw-*.pkg.tar.zst OpenChamber-btw-*-android-debug.apk > SHA256SUMS
```

Create a release and upload assets. `gh` is not installed on this machine by default; use the GitHub API with a token from `git credential fill`. Never echo the token.

```bash
cred=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill)
pass=$(printf '%s\n' "$cred" | sed -n 's/^password=//p')

# Create the release (write body to /tmp/release-body.md first)
jq -n --rawfile body /tmp/release-body.md \
  '{tag_name:"vX.Y.Z",target_commitish:"main",name:"vX.Y.Z — stateless /btw",body:$body,draft:false,prerelease:false}' \
  > /tmp/release.json
curl -sS -X POST \
  -H "Authorization: Bearer $pass" \
  -H 'Accept: application/vnd.github+json' \
  -H 'Content-Type: application/json' \
  --data-binary @/tmp/release.json \
  https://api.github.com/repos/opigod/openchamber-btw/releases

# Upload each asset
curl -sS -X POST \
  -H "Authorization: Bearer $pass" \
  -H 'Content-Type: application/octet-stream' \
  --data-binary @~/.cache/openchamber-btw-builder/out/<asset> \
  'https://uploads.github.com/repos/opigod/openchamber-btw/releases/<release-id>/assets?name=<asset-name>'
```

After publishing:

- verify all three asset download URLs return `206`/`200`
- update `README.md` if the release link or asset names changed
- add a `CHANGELOG.md` entry
- update this file's quick facts if the base or commit changed
- update the PR body if the standalone release link moved

## Upstream PR process

Current state:

- PR `#6547` is closed by `openchamber-bot` with `needs-accepted-issue`.
- Issue `#6548` is open and not marked `accepted`.
- The bot rechecks when the issue is labeled `accepted` or `bug`.
- PR head `feat/stateless-btw` and working branch `feat/stateless-btw-latest` point at the same commit.
- The PR body starts with `Part of #6548`, includes the change summary, verification, screenshots, and the standalone repo link.
- The PR screenshot is hosted on the fork branch `pr-evidence` at `pr-evidence/btw-android-dialog.png`.

If you update the screenshot:

```bash
# In a throwaway worktree of the fork
git switch --orphan pr-evidence
mkdir -p pr-evidence
cp /path/to/new-screenshot.png pr-evidence/btw-android-dialog.png
git add pr-evidence/btw-android-dialog.png
git commit -m "docs: refresh Android /btw screenshot"
git push fork pr-evidence
```

Then update the `<img src="...">` URL in the PR body if the path changed.

Do not open a duplicate PR while `#6547` exists. Do not mark the issue `accepted` yourself; only the maintainer should do that.

## Common failures

| Symptom | Cause | Fix |
| --- | --- | --- |
| `openchamber-btw and openchamber-custom are in conflict` | pacman will not replace a conflicting package under `--noconfirm` | Remove the old package in a separate transaction; the script already does this. |
| `git apply --3way` fails | Patch base blobs missing or upstream changed touched code | Let the script fetch `PATCH_BASE`, or rebase the fork and regenerate the patch. |
| `Failed to find package 'platforms;android-37'` | SDK package is named `platforms;android-37.0` | Use the script's resolver or set `ANDROID_PLATFORM_PACKAGE=platforms;android-37.0`. |
| Android build uses JDK 27 / fails on Java 21 | System JDK is too new | Set `JAVA_HOME` to JDK 21 or let `ensure_jdk21` download Temurin 21. |
| Emulator shows "This app requires a WebView" | Wear OS image has no Android System WebView | Use a phone/tablet Google APIs image. |
| `/btw` returns "does not support side questions" | Server's OpenCode is too old for `session.generate` | Update the OpenChamber/OpenCode server. |
| Clipboard copy fails in Android WebView | Async Clipboard API unavailable | Use `copyTextToClipboard`; it falls back to `execCommand`. |
| Build cache behaves strangely | `git clean -fd` leaves ignored files, stale `node_modules` | Remove `~/.cache/openchamber-btw-builder/source` and rebuild. |
| Desktop app still reports 2.6.1 after install | The old process is still running | Restart OpenChamber when no agent session depends on it. |
| App update banner offers a different version | The bundled app updater does not know pacman packages | Ignore it; rebuild/reinstall this package. |

## Secrets and local state

Never print, log, or commit:

- `~/.config/openchamber/settings.json` contents (`desktopLocalClientToken`, `desktopUiPassword`)
- GitHub tokens from `~/.git-credentials`
- client pairing secrets in `~/.config/openchamber/client-pairing-sessions.json`
- any `.env`, key, certificate, or token file

To use the GitHub token, retrieve it into a shell variable without echoing:

```bash
cred=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill)
pass=$(printf '%s\n' "$cred" | sed -n 's/^password=//p')
```

`gh` is not installed on this machine. Use `curl` and the GitHub API, or install `gh` if the user asks.

## Current machine state (not portable)

These paths exist on the current workstation:

```text
/home/opi/openchamber                    # fork checkout, branch feat/stateless-btw-latest
/home/opi/openchamber-btw                # this repo
/home/opi/openchamber-btw-builder        # symlink to this repo
/home/opi/.cache/openchamber-btw-builder # patched source, JDK, Android SDK, outputs
/opt/openchamber                         # installed app
/usr/bin/openchamber                     # installed symlink
```

Installed package:

```text
openchamber-btw 2.7.2-1
```

The desktop app may still be the old 2.7.0 process after a package install. Do not kill it from an active session; restart it outside the session when the user is ready.

Test emulator data (may be wiped):

```text
/tmp/opencode/tools/android-sdk          # emulator, platform-tools, phone system image
AVD: openchamber-phone (API 35)
```

The build script's own SDK and JDK live in the cache directory above, separate from the emulator SDK.

## Documentation conventions

- `README.md`: user-facing. Keep the screenshot, install commands, release links, and compatibility base current.
- `docs/HOW-IT-WORKS.md`: technical. Update the flow, state table, and tests when behavior changes.
- `CHANGELOG.md`: one entry per release, with base version, behavior, build changes, and verification.
- `AGENTS.md`: this file. Update when the workflow, paths, links, or release process changes.
- Prefer short concrete commands and exact paths. Avoid marketing language in technical docs.

## Definition of done

Before calling a change complete:

- [ ] Source change is committed on `feat/stateless-btw-latest`
- [ ] `bun run type-check:ui` passes
- [ ] `bun run --cwd packages/ui test` passes
- [ ] `bun run check:changed` passes
- [ ] `feat/stateless-btw` is force-pushed to the same commit
- [ ] `btw-stateless.patch` is regenerated from the new base
- [ ] `PATCH_BASE` and README compatibility text are updated
- [ ] Linux package builds and installs
- [ ] Android APK builds and the dialog is manually verified
- [ ] New-draft `/btw` guard is manually verified
- [ ] `CHANGELOG.md` is updated
- [ ] Release assets and checksums are uploaded
- [ ] PR body and screenshot are current
- [ ] README/docs links still work

## Links

- Standalone repo: <https://github.com/opigod/openchamber-btw>
- Releases: <https://github.com/opigod/openchamber-btw/releases>
- Fork: <https://github.com/opigod/openchamber>
- Fork feature branch: <https://github.com/opigod/openchamber/tree/feat/stateless-btw-latest>
- Upstream PR: <https://github.com/openchamber/openchamber/pull/6547>
- Upstream issue: <https://github.com/openchamber/openchamber/issues/6548>
- Upstream project: <https://github.com/openchamber/openchamber>
- OpenCode: <https://opencode.ai>
