---
name: sim-pool
description: >-
  Host-global iOS simulator lease manager for parallel agents. Acquire before
  simulator QA when multiple agents or worktrees share one Mac. Leases fixed
  pool devices; when busy, simslim-clones a slim ephemeral sim and deletes it
  on release. TTL and dead-pid recovery.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# sim-pool — shared simulator lease manager

Use when **more than one agent** (or worktree, or project) may run simulator QA on the same Mac. `sim-pool` decides **which UDID you may use**; `agent-device` drives the UI on that UDID.

Install: symlink this skill to `~/.claude/skills/sim-pool/` only.

**Simulator boot/slim:** use [SimSlim](https://github.com/MobAI-App/simslim) (`brew install mobai-app/tap/simslim`) for boot, shutdown, slim profiles, and fleet status — not raw `simctl boot` / `shutdown`. Keep `simctl` for install, screenshots, and media. See Cursor rule `simulator-simslim.mdc`.

## Hard rules

1. **Acquire before simulator QA** — `sim-pool acquire` then use printed `UDID` for `ios-build-test` and `agent-device`.
2. **Clones only (default)** — `devices` in config are **templates** (slim source sims). They are **never leased** for QA. Every **`acquire`** uses a free existing clone or **`simslim clone`**s from `clone_udid` / first template. **`release` drops the lease only** — clones stay in CoreSimulator until you remove them (`simslim delete <udid>` or Xcode). Set `delete_on_release: true` only if you want the pool to delete clones on release/TTL GC. Never run builds, tests, or sim-eyes on the template UDID. Disable clone-only with `clones_only: false` in config or `SIM_POOL_CLONES_ONLY=0`. Never `simctl create`.
3. **Named session** — pass `--session` to acquire; reuse on every `agent-device` command.
4. **Renew on long QA** — `sim-pool renew --lease <id>` every ~5 min (default TTL 15 min).
5. **Release politely** — `agent-device close` then `sim-pool release --lease <id>`. Ephemeral sims are removed on release. TTL and dead-pid GC recover if you forget.
6. **On exit 2 (`SIM_POOL_BUSY`)** — pool and ephemeral limits exhausted, or simslim unavailable; report inconclusive.
7. **On `LEASE_GONE`** — stop using that UDID; re-acquire or mark QA inconclusive.

## Ephemeral simulators (default on)

Configured under `~/.agent-sim-pool/config.json` → `ephemeral`:

| Key | Default | Meaning |
|-----|---------|---------|
| `clones_only` | `true` | Never lease template sims; only ephemeral clones |
| `enabled` | `true` | Allow simslim clone on acquire |
| `clone_udid` | `""` | Slim template; empty = first entry in `devices` |
| `max_concurrent` | `8` | Max ephemeral leases at once |
| `max_devices` | `16` | Max ephemeral sims on disk |
| `delete_on_release` | `false` | `true` = `simslim delete` after `release` / TTL GC (more churn). `false` = keep clone for the next `acquire` (recommended for multi-agent). |

Permanent pool devices: one-time `simslim on <udid>` (not deleted on release).

## CLI

```bash
SP="${CLAUDE_SKILL_DIR}/scripts/sim-pool"

$SP status
$SP init                    # discover iPhones into whitelist (no create)
$SP acquire --holder-pid $$ --owner "agent-$$" --project "$(basename "$PWD")" --worktree "$PWD" --session "qa-$$"
$SP acquire … --no-ephemeral   # fail with SIM_POOL_BUSY instead of cloning
$SP renew --lease <id>
$SP release --lease <id>
$SP gc
$SP doctor
$SP register --udid <udid>
$SP force-release --udid <udid> --reason "user approved"
```

Throwaway QA state: `AGENT_SIM_POOL_HOME=/tmp/sim-pool-qa-$$ $SP ...`

**Acquire output (parseable):**

```
LEASE_ID=...
UDID=...
SIMULATOR_NAME=...
EXPIRES_AT=...
EPHEMERAL=true|false
```

Exit codes: `0` ok, `2` SIM_POOL_BUSY, `1` error.

## Agent workflow

```bash
SP="${CLAUDE_SKILL_DIR}/scripts/sim-pool"
SESSION="qa-$(basename "$PWD")-$$"

eval "$($SP acquire --holder-pid $$ --owner "agent-$$" --project "$(basename "$PWD")" --worktree "$PWD" --session "$SESSION")"
export DEVICE_ID="$UDID"
simslim boot "$UDID"

# build + test with ios-build-test (reads DEVICE_ID from .env or env)
# UI with agent-device on same UDID + session

$SP renew --lease "$LEASE_ID"   # repeat every ~5 min on long runs

ad close --session "$SESSION"
$SP release --lease "$LEASE_ID"   # deletes simulator when EPHEMERAL=true
```

Use a `trap` so release runs on failure:

```bash
cleanup() {
  ad close --session "$SESSION" 2>/dev/null || true
  $SP release --lease "$LEASE_ID" 2>/dev/null || true
}
trap cleanup EXIT
```

## Orphan recovery (no close signal)

| Layer | What happens |
|---|---|
| TTL | No renew within 15 min → lease expires → next acquire/gc frees UDID; ephemeral sim deleted |
| Dead pid | Acquire process gone → immediate reclaim on next acquire/gc |
| GC | Every acquire runs GC before picking a device |
| force-release | User-approved steal when status shows a stuck lease |

`release` speeds reuse; **TTL + dead-pid are the guarantees**.

## Multi-agent with agent-device

1. `sim-pool acquire` → get UDID
2. `ad open … --udid $UDID --session $SESSION`
3. Never open a UDID without a sim-pool lease in multi-agent setups
4. `doctor` warns when a UDID has an `agent-device` claim but no sim-pool lease

## Multi-agent with sim-eyes MCP

`sim-eyes` v1.1+ calls `sim-pool` itself: each MCP process leases a UDID and uses a unique `agent-device` session (`sim-eyes-<pid>-<hex>`). Prefer tools `acquire` → QA → `release`; `look`/`open` auto-acquire if needed. When the pool is saturated, ephemeral clone applies the same way. On `SIM_POOL_BUSY`, report QA inconclusive.

Do **not** set `SIM_EYES_DEVICE=iPhone 17` in shared MCP config (that forced every agent onto one sim). Optional prefer only: `SIM_EYES_PREFER_UDID` / `DEVICE_ID`.

See also: `ios-verify` (simulator check step 0), `agent-device` session-and-devices reference.

## Worktrees

Worktrees do **not** get a sticky `DEVICE_ID` in `.env` anymore. Set `DEVICE_ID` at QA time from `sim-pool acquire` output (or export before `ios-build-test`).
