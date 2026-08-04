# Troubleshooting

## Decision tree

```text
Command failed?
├─ command not found / zsh multi-word $AD → use ad() function or npx -y agent-device
├─ DEVICE_IN_USE
│  ├─ session list empty but error names a session → orphan: reuse --session NAME (if yours)
│  ├─ foreign live session → other free UDID; never close theirs
│  └─ user reclaim → close --session NAME then new open
├─ needs a complete snapshot / only authorizes its emitted refs → selector or snapshot -i
├─ expired ref / stale @eN → selector or snapshot -i; never reuse post-mutation refs
├─ find/press no match → full snapshot; a11y label/id; screenshot
├─ 0 nodes / wrong app → appstate; open --relaunch; wait; snapshot again
├─ hang >30s with "idb" in command → kill idb; switch to agent-device
├─ first open slow → wait (runner build); prepare ios-runner; raise daemon timeout
└─ unknown → doctor; events; session runner.log; help debugging
```

## Error catalog

### `command not found: agent-device`

CLI not on `PATH` (daemon under `~/.agent-device/` may still be running).

```bash
# Function form (required when using npx — multi-word strings break in zsh)
ad() { command -v agent-device >/dev/null 2>&1 && command agent-device "$@" || npx -y agent-device "$@"; }
ad --version
```

```bash
# WRONG in zsh:
AD="npx -y agent-device"
$AD devices   # → command not found: npx -y agent-device
```

### `DEVICE_IN_USE`

Device claimed by a session name in the error text.

```bash
ad session list
ad devices
ad device status --platform ios
```

| Observation | Fix |
|---|---|
| Error: in use by `"foo"`; that session is **yours** / same task | `open … --session foo` (reuse; do not invent a second name) |
| `session list` empty, `device status` still shows `live session=foo` | **Orphan claim** — reuse `--session foo`; if stuck and you own it, `close --session foo` then open with a new name |
| Another agent clearly owns it | Boot/open a **different** UDID with a **new** `--session` |
| User asks to reclaim | `close --session foo` then open |

Do not close foreign live sessions unless the user requests reclaim.

See [session-and-devices.md](session-and-devices.md).

### `Ref @eN needs a complete snapshot` / `only authorizes its emitted refs`

The settle (or partial) frame **printed** `@eN` but did not authorize it for dispatch — common right after `fill` when the keyboard tree dominates.

```bash
# Prefer selector for known CTAs
ad press 'label="Save as task without extracting"' --settle
# or refresh interactive tree
ad snapshot -i
ad press @eNEW --settle
```

Do not retry the same unauthorized `@eN`.

### `Ref @eN belongs to an expired ref frame`

UI changed since the snapshot that minted the ref.

- Use a **selector** for the next action, or  
- `snapshot -i` and use a **new** `@eN`  
- Prefer `press … --settle` so the response carries the next tree  

### `find did not match any element` / `COMMAND_FAILED`

- Run full `snapshot` (not only `-i`)  
- Match **a11y** `label` / `id`, not only painted text  
- Wait for animation: `wait 500` or `wait text "…"`  
- Check for alert/keyboard tip covering the control  

### XCTest / runner failures (`XCTEST_RECORDED_FAILURE`)

- Hint often says session will restart — **fresh snapshot** after recovery  
- `prepare ios-runner --platform ios --timeout 240000`  
- Inspect session `runner.log` (under `~/.agent-device/sessions/<name>/`)  
- Another daemon may own the runner — stop the **owning** daemon on that Mac; do not assume prepare fixes foreign ownership  

### 0 nodes / empty interactive tree

- Foreground app changed or splash still up: `appstate`, wait, `open --relaunch`  
- Sparse recovery: `screenshot` as visual truth, leave bad screen if needed, retry `snapshot -i`  

### App not installed

```bash
ad apps --platform ios --udid "$UDID"
ad reinstall com.example.app /path/to/App.app --platform ios --udid "$UDID"
```

### Slow snapshots (p95 multi-second warnings)

- Device load / cold runner / stale daemon  
- Prefer `snapshot -i`, scoped `-s`, and `--settle` over full trees  
- `doctor --platform ios`  

### Daemon / lock issues

- Stale metadata: `~/.agent-device/daemon.json`, `~/.agent-device/daemon.lock`  
- Claims: `~/.agent-device/device-claims/`  
- `agent-device daemon stop` only when you own that daemon and understand impact on other agents  
- Raise timeout: `AGENT_DEVICE_DAEMON_TIMEOUT_MS=120000`  

### `idb` hang

```bash
pkill -9 -f idb 2>/dev/null || true
# use agent-device only for the rest of the session
```

If forced to use idb:

```bash
idb kill; sleep 1
perl -e 'alarm shift; exec @ARGV' 25 idb ui describe-all --udid <udid>
```

After one watchdog kill, **abandon idb** for the session.

## Evidence without flooding context

```bash
ad events
ad logs clear --restart
ad logs mark "before repro"
# … repro …
ad logs path
ad network dump --include headers
ad screenshot /tmp/fail.png
```

Do not `cat` entire log files into the model — open/grep a narrow window.

## Physical iOS

See `agent-device help physical-device`:

- Team ID: `AGENT_DEVICE_IOS_TEAM_ID`  
- Optional: `AGENT_DEVICE_IOS_SIGNING_IDENTITY`, `AGENT_DEVICE_IOS_PROVISIONING_PROFILE`  
- Device trusted, Developer Mode on, unlocked  

## Still stuck

```bash
ad doctor --platform ios --app <name>
ad help debugging
ad help workflow
```
