# How the stateless `/btw` works

This document is for people reading or maintaining the patch. It describes the request path, what is deliberately not touched, and the invariants the tests protect.

## The old behavior

OpenChamber's `/btw` used to create a hidden fork of the current session, mount a special composer for it, and route the question there. The fork was real: it had messages, metadata, a model selection, and a lifecycle. It could not start while the main turn was busy, and it left a session behind even if the user only wanted one answer.

The replacement has no fork. It asks the OpenCode server for one generated answer and renders it in a dialog.

## Request flow

```text
composer types /btw <question>
        │
        ▼
ChatInput recognizes the local action
        │
        ├── no current session ──► toast "Open a session first"; nothing is sent
        │
        ▼
runBtwQuestion(parentSessionId, ownerKey, directory, question)
        │
        ▼
store.begin(parentSessionId, requestId, ownerKey, ...)
        │
        ▼
opencodeClient.generateSessionText(
  parentSessionId,
  BTW_INSTRUCTION + question,
  { directory, signal }
)
        │
        ▼
POST /api/session/:id/generate
        │
        ▼
OpenCode session.generate
        │
        ▼
dialog: answered | failed | timeout
```

`session.generate` reads the parent session's context on the server and returns text. The client does not reconstruct context from the live store, and it does not append the question or answer to the session.

## Why a transient dialog state store

The dialog is not a second chat. It has only the states the one request needs:

```text
compose ──► running ──► answered
                │
                └────► failed ──► running (retry)
```

`useBtwStore` keeps that state under the parent session id. The composer that opened it also records an owner key:

```text
ownerKey = <composer column id>:<session id>
```

A session can be open in the main panel and the side panel at once. The owner key makes only the composer that opened the dialog render it, so the same session does not stack two modals.

Dismissing a running request calls `dismissBtw`, which aborts the request's own controller. It never calls the session abort path, so the main agent keeps running.

## Request isolation

Each request gets:

- its own `AbortController`
- a unique request id
- a five-minute timeout
- a runtime key captured when the request starts

The runtime key matters in OpenChamber because the app can switch between OpenCode endpoints. A response that arrives after a runtime switch is discarded, and `disposeBtwRequests` aborts anything still in flight.

The store ignores an older request's result if a newer one has replaced it, so a slow first attempt cannot overwrite a retry.

## What is not written

The patch removes the old fork writers instead of repurposing them. `/btw` no longer:

- creates or forks a session
- writes `openchamber.btw` metadata
- creates a pending composer or draft in the main session
- changes the main session's model, agent, or effort selection
- writes messages or synthetic parts to the parent session

The only persistent change a user sees after a side question is the dialog itself. Closing it leaves no trace.

## Legacy fork sessions

Older versions of OpenChamber may already have `/btw` fork sessions on disk. The patch keeps them hidden from normal session lists. If one is promoted to a normal session, its old fork-boundary instructions are still in the transcript. The promoted session gets one synthetic notice explaining that the old `/btw` constraints no longer apply and that normal tools and permissions are back.

This is why `buildBtwSyntheticTexts` still exists even though new `/btw` requests never create a fork.

## The slash-command path

`planLocalSlashCommand` normally returns `null` for an action command when there is no current session, leaving the text to the normal OpenCode command router. That is correct for `undo`, `redo`, `timeline`, and friends: they need a session.

`/btw` is the exception. If the planner returned `null` in a new-session draft, the text would be sent as a normal prompt, which creates the session the command is supposed to avoid. The planner therefore returns a local action for `/btw` even without a session, and `ChatInput` handles the no-session case with the existing "Open a session first" toast. The text stays in the composer.

## Failure handling

| Failure | Dialog behavior |
| --- | --- |
| No text returned | "The model returned no answer. Retry." |
| Five-minute timeout | "The side question timed out. Retry." |
| Server does not know `session.generate` | "This OpenCode version does not support side questions. Update OpenCode." |
| Session disappeared | "This chat is no longer available." |
| Other API error | The server message, or a generic failure with retry |

The request is aborted when the user closes a running dialog. If the abort came from the timeout, the dialog shows the timeout error; if it came from dismissal, the dialog is already gone.

## Surfaces

The shared `packages/ui` code is used by:

- the desktop Electron app
- the browser build
- the VS Code extension
- the hosted mobile surface
- the Capacitor iOS/Android apps

The Android build copies the same web UI into the Capacitor shell. That is why the dialog and the new-session guard work there without a separate mobile implementation. Copy uses the shared clipboard helper, which falls back to `execCommand` when the async Clipboard API is unavailable in a WebView.

## Tests

The patch adds or updates:

- `packages/ui/src/components/chat/btw/BtwDialog.test.tsx`
- `packages/ui/src/components/chat/__tests__/ChatInput.magicPrompts.test.tsx`
- `packages/ui/src/components/chat/composer/submit/__tests__/slashCommands.test.ts`
- `packages/ui/src/stores/useBtwStore.test.ts`
- `packages/ui/src/lib/btw.test.ts`
- `packages/ui/src/lib/opencode/client.test.ts`

Coverage includes:

- `/btw` opens the dialog without calling `sendMessage`
- `/btw` in a new-session draft sends nothing and creates nothing
- request ids and owner keys prevent stale or duplicate dialogs
- dismissal aborts only the side request
- timeout and retry states
- `generateSessionText` sends the prompt, directory header, and abort signal
- legacy promotion notices

At the 2.7.2 base the full UI suite ran 1386 files: 1383 passed, and the same three files (`HeaderProjectControls`, `issue-3175-browserCaptureRevealsPanel`, `infiniteAnimations`) fail on the untouched `v2.7.2` tag. `bun run check:changed -- --base 1a15151` passed.
