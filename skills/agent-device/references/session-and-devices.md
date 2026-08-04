# Sessions and devices

## Why this matters

`agent-device` binds **one session ↔ one device**. Parallel agents on the same Mac often share simulators. Stealing `default` or closing someone else's **live** session corrupts their run.

## Discovery

```bash
ad() { command -v agent-device >/dev/null 2>&1 && command agent-device "$@" || npx -y agent-device "$@"; }

ad devices
ad session list
ad device status --platform ios
ad doctor --platform ios
```

| Command | What it tells you |
|---|---|
| `devices` | Simulators/emulators/hardware + booted flag |
| `session list` | **Daemon-tracked** active sessions (may be **empty** while a claim file still exists) |
| `device status` | Advisory host-local ownership claims — often more complete than `session list` |
| `apps --udid …` | Whether the target app is installed on that sim |

Treat an empty `session list` as **inconclusive**. Always also check `device status` and the `DEVICE_IN_USE` error text.

## Multi-agent recipe (preferred)

```bash
# 1) Inventory
ad session list
ad devices
ad device status --platform ios

# 2) Choose a FREE target
#    - Prefer Shutdown simulators (boot them yourself)
#    - Or booted sims with NO matching claim/session
#    - Never take a UDID that another agent actively owns unless the user says so

# 3) Named session (unique per agent/task)
SESSION="agent-$(whoami)-$$"
UDID="<free-udid>"

ad boot --platform ios --udid "$UDID"   # if not booted
ad open MyApp \
  --session "$SESSION" \
  --platform ios \
  --udid "$UDID" \
  --relaunch

# 4) Pass --session on every command in the flow
ad snapshot -i --session "$SESSION"
ad press @e3 --settle --session "$SESSION"

# 5) Always release when done
ad close --session "$SESSION"
# optional: also shut down the sim you started
# ad close --session "$SESSION" --shutdown
```

Env alternative: `export AGENT_DEVICE_SESSION=my-run` so you don't repeat `--session`.

## On `DEVICE_IN_USE`

```
Error (DEVICE_IN_USE): Device is already in use by session "nowlist-task-test".
Hint: … rerun with --session nowlist-task-test. To open a new session … first run agent-device close --session nowlist-task-test.
```

### Decision order

1. **Read the session name in the error** (and the hint).
2. Run `ad session list` **and** `ad device status --platform ios`.
3. Classify:

| Situation | Action |
|---|---|
| Foreign **live** session (another agent, recent activity, user says leave it) | Pick **another free UDID**; new `--session` name. Do **not** close theirs. |
| **Your** session from this task / earlier in this conversation | **Reuse** `--session <that-name>` on open and every command (do not invent a second name for the same device). |
| **Orphan claim** — `session list` empty (or session dead) but `device status` / error still names a session; claim is under `~/.agent-device/device-claims/` | Prefer **reuse** `--session <name-from-error>` (safest, no steal). If reuse fails and **you** own the claim (same workspace, same agent run history, user wants this device), then `ad close --session <name>` and open with a **new** session name. |
| User explicitly asks to reclaim the device | `ad close --session <name>` then open with a fresh `--session`. |

**Don't:**

- Close foreign live sessions without user approval
- Retry `open` with a **new** session name on the same UDID in a loop (always hits the claim)
- Assume empty `session list` means the device is free

### Orphan claim forensics (optional)

```bash
# Advisory status often still shows: live session=NAME workspace=…
ad device status --platform ios

# Claim file (daemon-owned)
ls ~/.agent-device/device-claims/
# Session dir may still exist even when session list is empty
ls ~/.agent-device/sessions/
```

Claim JSON includes `session`, `device.id` (UDID), `workspace`, `ownerPid`. Prefer CLI reuse/close over hand-deleting claim files.

## Implicit `default` session

- Unnamed commands use a worktree-scoped default session.
- Fine for solo use; **dangerous** when multiple agents share the host.
- If you opened with `--session name`, **every** later command in that flow needs the same `--session`.

## Target selectors

Pass one of:

| Flag | Example |
|---|---|
| `--udid` | iOS simulator/device UDID |
| `--device` | Name, e.g. `"iPhone 16 Pro (worktree-1)"` |
| `--serial` | Android serial |
| `--platform` | `ios` / `android` / `web` / `macos` / … |

`boot` requires an active session **or** an explicit selector (`--platform`, `--device`, `--udid`, `--serial`).

## App missing on the free simulator

Free sims often lack the app that was installed only on the shared one.

```bash
# After project build produces MyApp.app / .apk:
ad reinstall com.example.app /path/to/MyApp.app --platform ios --udid "$UDID"
# or
ad install /path/to/MyApp.app --platform ios --udid "$UDID"
# or
xcrun simctl install "$UDID" /path/to/MyApp.app
```

Then `open … --relaunch` on that UDID.

```bash
ad apps --platform ios --udid "$UDID"        # confirm install
ad apps --platform ios --all --udid "$UDID"  # include system if needed
```

## Parallelism

| OK in parallel | Not OK |
|---|---|
| Different sessions on **different** devices | Two mutations on the **same** session |
| Read-only probes on separate sessions | Parallel open/press/fill/scroll/close on one session |

## Session hygiene

- **Always** `close --session …` when the task ends — this is the main prevention for orphan claims.
- Prefer not to leave orphan sessions overnight; `session list` + `device status` + close stale ones **you** own.
- After close, spot-check: `device status` should show no claim on that UDID.
- `close --shutdown` ends the session **and** shuts down the associated simulator/emulator — only if you booted it for this task and nothing else needs it.
