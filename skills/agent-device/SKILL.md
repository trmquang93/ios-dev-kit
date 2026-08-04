---
name: agent-device
description: Preferred automation tool for iOS simulators/devices and Android emulators/devices — use this instead of shelling out to raw `idb`, `simctl`, or `adb` for navigating apps, snapshots/screenshots, tapping, typing/filling, scrolling, and UI inspection. XCTest-based and reliable; raw `idb` can hang silently, so prefer this skill's commands.
---

# Mobile Automation with agent-device

For agent-driven exploration: use refs + `--settle`. For deterministic replay: use selectors / `.ad` scripts.

**Built-in docs (always current for the installed CLI):**

```bash
agent-device help              # command list + Agent Starting Point
agent-device help workflow    # full operating guide
agent-device help manual-qa   # checklist / scripted QA loop
agent-device help debugging   # logs, alerts, network, traces
agent-device <cmd> --help     # per-command flags
```

## Hard rules (read first)

1. **Prefer `agent-device` over raw `idb`.** Raw `idb` can hang silently (70–115s+) and stall the whole agent session. Use `agent-device` or `xcrun simctl` only for install/boot/erase/screenshot plumbing.
2. **Named session + free device in multi-agent setups.** Never steal or `close` another agent's live session. On `DEVICE_IN_USE`, pick another UDID — or **reuse the named session from the error** when it is yours / orphaned. See [references/session-and-devices.md](references/session-and-devices.md).
3. **Default loop:** `open` → `snapshot -i` → mutate with **`--settle`** → continue from the settled diff → **`close`**. Use `--settle` only on `press` / `click` / `fill` / `longpress` (never on `open` / `snapshot` / `close`).
4. **Refs expire after any mutation.** After press/fill/type/scroll/alert/keyboard, do not reuse prior `@eN`. Prefer a **stable selector** next (`label=…`, `id=…`), or re-run `snapshot -i`. On iOS, stale refs are rejected before dispatch.
5. **Settle can list refs you cannot press.** After `fill --settle`, the keyboard-dominated frame often authorizes only a subset of emitted `+@eN` lines. Prefer `press 'label="…"' --settle` for known CTAs; if you must use a settle `@ref`, only press refs that appear as **emitted interactive targets** in that settle frame — on `needs a complete snapshot` / `only authorizes its emitted refs`, switch to selector or `snapshot -i`.
6. **A11y label ≠ visible copy.** Target **accessibility** `label` / `id` / `role` first. Visible text may live on a child while the hittable button has a different label.
7. **Do not pipe `agent-device` through `grep` / `jq` / `head` / `2>/dev/null`.** Raw output carries refs, warnings, settle diffs, and diagnostics needed for the next step.
8. **Serial mutations per session.** Never parallelize open/press/fill against the same session. Parallelize only across **different** sessions/devices, or read-only work.
9. **Always `close --session …` when done.** Leaving sessions open creates orphan claims: empty `session list` but `DEVICE_IN_USE` on next open.
10. **Handle interruptions** (permission alerts, keyboard tips) before asserting success — see [references/interruptions.md](references/interruptions.md).

## Invoke the CLI

`agent-device` is often **not** on `PATH` even when the daemon is running. Resolve once, then use a **shell function** (string vars with spaces break in zsh):

```bash
# CORRECT — function (works in bash/zsh)
ad() { command -v agent-device >/dev/null 2>&1 && command agent-device "$@" || npx -y agent-device "$@"; }
ad --version
ad devices
ad session list
ad device status --platform ios
```

```bash
# WRONG — multi-word string + unquoted expansion fails in zsh:
#   AD="npx -y agent-device"; $AD devices
# → command not found: npx -y agent-device
```

If missing entirely: `npm i -g agent-device` or keep using `npx -y agent-device`.

Optional env defaults: `AGENT_DEVICE_SESSION`, `AGENT_DEVICE_PLATFORM`.

State / claims (for orphan debugging): `~/.agent-device/device-claims/`, `~/.agent-device/sessions/<name>/`, `~/.agent-device/daemon.json`.

## Quick start (settle-first)

```bash
ad() { command -v agent-device >/dev/null 2>&1 && command agent-device "$@" || npx -y agent-device "$@"; }

# Multi-agent: name the session and pin the device
ad session list
ad devices
ad device status --platform ios

SESSION="smoke-$(date +%s)"
ad open Settings \
  --session "$SESSION" \
  --platform ios \
  --udid <free-udid>

ad snapshot -i --session "$SESSION"
ad press @e12 --settle --session "$SESSION"   # real @ref from THAT snapshot
ad wait text "Camera" --session "$SESSION"
ad close --session "$SESSION"                 # always release
```

Without multi-agent contention, omit `--session` / `--udid` and let the CLI pick a target.

## Core workflow

1. **Claim a free device** (multi-agent) → named `--session` + `--udid` / `--device`
2. **Open** app or deep link: `open [app|url] [url]` (`--relaunch` for fresh process)
3. **Snapshot** for refs: `snapshot -i` (interactive); full `snapshot` when text fields are missing from `-i`
4. **Mutate** with `press` / `fill` / `click` / `longpress` **and `--settle`**
5. Continue from the **settled diff** — for the **next known CTA**, prefer a **selector** over a settle-emitted `@eN` (especially after `fill` / keyboard)
6. **Verify** with `wait text|selector`, `is`, `get`, or settled evidence — not a bare screenshot alone when a named expectation exists
7. **`close --session …`** when done so the device is free

If you skip `--settle`, verify with `diff snapshot` / `diff snapshot -i` (changed lines only), not a full tree dump.

### Capture / form pattern (verified on Nowlist)

```bash
ad open com.quangtm.nowlist --session t --platform ios --udid "$UDID" --relaunch
ad snapshot -i --session t
ad press 'label="Capture a task"' --settle --session t   # or @ref from snapshot
ad snapshot --session t                                   # text-field often only here
ad fill @e23 "Buy milk before Friday" --settle --session t
# Prefer selector for post-fill CTA (settle @refs often unauthorized):
ad press 'label="Save as task without extracting"' --settle --session t
ad wait text "Buy milk before Friday" 5000 --session t
ad close --session t
```

## Avoid raw `idb`

| Need | Don't use | Use |
|---|---|---|
| UI tree | `idb ui describe-all` | `ad snapshot -i` |
| Screenshot | `idb ui screenshot` | `ad screenshot out.png` |
| Tap | `idb ui tap` | `ad press @ref` / selector / `x y` |
| Type | `idb ui type` | `ad fill @ref "text" --settle` |
| Launch | `idb launch` | `ad open <app>` |
| Install / erase / boot | — | `ad install` / `reinstall`, or `xcrun simctl …` |

No-session screenshot fallback: `xcrun simctl io <udid> screenshot <path>`.

If you **must** use `idb`: `idb kill; sleep 1`, then run under a watchdog; on timeout abandon `idb` for the rest of the session.

```bash
perl -e 'alarm shift; exec @ARGV' 25 idb ui describe-all --udid <udid>
```

Symptom of wrong tool: shell command with `idb` runs >30s with no output → `pkill -9 -f idb` and switch.

## Snapshot modes

| Goal | Command |
|---|---|
| Next tap / button / control | `snapshot -i` |
| Text fields nested under scroll | full `snapshot` (or `snapshot -s "…"`) |
| Only what changed | `diff snapshot` / `diff snapshot -i` |
| Truncated preview | `snapshot -s @e12` (expand), not `get text` first |
| Visual truth when tree is sparse/wrong | `screenshot` (+ optional read image) |

Details: [references/snapshot-refs.md](references/snapshot-refs.md).

## Selectors (stable targeting)

Selector keys only: `id`, `role`, `text`, `label`, `value`, `appname`, `windowtitle`, `visible`, `hidden`, `editable`, `selected`, `focused`, `enabled`, `hittable`.

```bash
ad press 'label="Submit"' --settle
ad press 'role=button label="Submit"' --settle
ad fill 'label="Email"' "user@example.com" --settle
ad wait 'label="Order placed"' 5000
```

Shell-quoting hazard for labels with `'` (e.g. `Don't`): prefer the `@ref` from the latest **full** `snapshot -i`, not from a keyboard settle.

## Commands (cheat sheet)

### Navigation & session

```bash
ad devices
ad device status --platform ios
ad session list
ad doctor --platform ios --app nowlist
ad prepare ios-runner --platform ios --timeout 240000   # optional pre-warm
ad boot --platform ios --udid <udid>
ad open <app> --session <name> --platform ios --udid <udid>
ad open <app> --relaunch
ad open <app> "myapp://path" --platform ios
ad close --session <name>
ad install <path> | install <app> <path>
ad reinstall <app> <path>
```

### Snapshot / verify

```bash
ad snapshot -i
ad snapshot                  # full tree when -i hides fields
ad snapshot -s "Composer"
ad diff snapshot -i
ad wait text "Settings"
ad wait 1000
ad is visible 'id="settings_anchor"'
ad find "Sign In" click
ad get text @e1
ad screenshot out.png
ad appstate
```

### Interactions

```bash
ad press @e1 --settle
ad click @e1 --settle          # alias of press
ad fill @e2 "text" --settle    # clear-then-type (prefer for fields)
ad type "more text"            # append to focused field only
ad press 300 500               # coordinate fallback
ad longpress @e1 800
ad swipe 540 1500 540 500 120
ad scroll down 0.5
ad keyboard dismiss
ad home | back | app-switcher
```

### Alerts

```bash
ad alert get
ad alert wait 10000
ad alert accept
ad alert dismiss
```

### Apps list

```bash
ad apps --platform ios         # user-installed (default)
ad apps --platform ios --all   # include system/OEM
ad apps --platform ios --udid <udid>
```

Do **not** use `--user-installed` (not a valid flag).

### Batch (known short flows)

```bash
ad batch --session <name> --platform ios --udid <udid> \
  --steps-file /tmp/steps.json
```

See [references/batching.md](references/batching.md).

### Replay / record

```bash
ad open App --relaunch --save-script=./flow.ad
# … drive to destination with --settle …
ad session save-script          # publish without close
ad replay ./flow.ad
ad record start ./proof.mp4
ad record stop
```

## Best practices

- **`--settle` first, full re-snapshot second.** Settled diffs often include the next target + an “unchanged interactive” tail.
- **After `fill`, prefer selectors for the next CTA.** Keyboard settle frames frequently reject settle-emitted `@eN` with `needs a complete snapshot`.
- After mutation, if the next control has a **known** label/id, press the selector directly (no intermediate snapshot).
- **Text fields:** `fill <target> <text> --settle`. Do not `fill ""` to clear — use a clear control or report unsupported.
- Keyboard covering a button: try pressing the target first (selector); dismiss only if press fails (`keyboard dismiss` or tip “Continue”).
- Deep links: prefer in-app control when flaky; then `open App "scheme://…"`.
- Missing app on free sim: build (project skill), then `ad reinstall <app> <path/to/App.app>`.
- First iOS open may build the XCTest runner (15–60s+). Use `prepare ios-runner` in CI; increase `AGENT_DEVICE_DAEMON_TIMEOUT_MS` (e.g. `120000`) on slow physical devices.
- Physical iOS signing: `AGENT_DEVICE_IOS_TEAM_ID`, optional `AGENT_DEVICE_IOS_SIGNING_IDENTITY` / `AGENT_DEVICE_IOS_PROVISIONING_PROFILE` — see `agent-device help physical-device`.
- Daemon issues: check `~/.agent-device/daemon.json` / `daemon.lock`; session `runner.log` for XCTest; `doctor` for inventory.

## Expected timing (agent shells)

| Step | Typical |
|---|---|
| First `open` / runner build | 15–60s |
| Later `open` / snapshot | 1–8s |
| `boot` cold simulator | 15–40s |

Use generous shell timeouts (120s+ for first open/boot). Do not treat quiet output as hung until those windows pass.

## Smoke test (skill health)

```bash
ad() { command -v agent-device >/dev/null 2>&1 && command agent-device "$@" || npx -y agent-device "$@"; }
ad devices
ad session list
ad device status --platform ios
# pick a free UDID, then:
SESSION="skill-smoke-$(date +%s)"
ad open Settings --session "$SESSION" --platform ios --udid <free-udid>
ad snapshot -i --session "$SESSION"
ad close --session "$SESSION"
# confirm release:
ad session list
ad device status --platform ios
```

## Troubleshooting (short)

| Symptom | Action |
|---|---|
| `command not found: agent-device` | Use `ad()` function or `npx -y agent-device` (do not store multi-word cmd in a bare string var) |
| `DEVICE_IN_USE` + empty `session list` | **Orphan claim** — reuse `--session <name>` from the error hint if it is yours; else free UDID. See session ref |
| `DEVICE_IN_USE` + foreign live session | Pick another free UDID; do **not** close others' sessions |
| `needs a complete snapshot` / `only authorizes its emitted refs` | Do not press that settle `@eN` — use selector or fresh `snapshot -i` |
| `expired ref frame` / stale `@eN` | Selector or re-`snapshot -i`; never reuse post-mutation refs |
| `find did not match` | Full `snapshot`; match a11y label/id, not only visible text |
| 0 nodes / wrong app | `appstate`; `open … --relaunch`; retry snapshot |
| Sparse tree / keyboard dominates | `screenshot`; handle tip/alert; press CTA via **label** selector; `keyboard dismiss` only if needed |
| App missing on sim | Build + `reinstall` / `simctl install` |
| `idb` hang | Kill idb; switch to agent-device |

Full matrix: [references/troubleshooting.md](references/troubleshooting.md).

## References

- [references/session-and-devices.md](references/session-and-devices.md) — multi-agent, free UDID, orphan claims, named sessions
- [references/snapshot-refs.md](references/snapshot-refs.md) — refs, settle authorization, labels vs text
- [references/interruptions.md](references/interruptions.md) — alerts, keyboard tips, permissions
- [references/batching.md](references/batching.md) — JSON step batches
- [references/troubleshooting.md](references/troubleshooting.md) — recovery playbook
