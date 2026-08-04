---
name: ios-build-test
description: Build and test any iOS Xcode project. MANDATORY for all iOS build and test operations — always use this skill's scripts instead of running xcodebuild directly. CRITICAL — invoke build.sh and run_tests.sh as the ONLY command in the shell; NEVER append | tee, | tail, | head, or | grep (causes hung pipelines that outlive a finished Xcode run). Use when user asks to build, compile, run tests, or verify an iOS project. Supports xcworkspace/xcodeproj auto-detection, Rosetta mode, Swift Testing and XCTest.
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# iOS Build and Test Skill

Use the scripts in this skill for **every** iOS build and test. They wrap `xcodebuild` with project/scheme/simulator detection, log capture, and reliable error extraction.

**Repo docs (e.g. `CLAUDE.md`, `README.md`) intentionally omit build/test commands.** When an agent has this skill, it is the **sole** source of truth for how to compile and test — do not expect or add wrapper scripts or skill paths in the repository.

## ⛔ Hard rule — no pipelines (read before every build/test)

**The shell command must be exactly one script invocation — nothing after it.**

```bash
# ✅ ONLY valid agent invocation
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh --scheme "nowlist" unit

# ❌ NEVER — hangs even when Xcode/tests already finished
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh --scheme "nowlist" unit 2>&1 | tail -50
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh --scheme "nowlist" unit | tee /tmp/out.log
${CLAUDE_SKILL_DIR}/scripts/build.sh --scheme "nowlist" 2>&1 | grep -E "error:|succeeded"
```

| Symptom | Likely cause |
|---------|----------------|
| Xcode finishes in ~1 min but agent terminal runs 5–10+ min with no new lines | You piped the script (`\| tail`, `\| tee`, `\| grep`) |
| Output shows `🎉 All tests passed!` but shell never exits | Pipeline hung — stdout from `run_tests.sh` did not close |
| Preflight prints, then silence for minutes | **Normal** in quiet mode — wait. **Abnormal** only if you also piped |
| User says "tests pass in Xcode" but agent terminal is stuck | Kill the piped command; re-run **without** a pipe |

**Want only the last N lines?** Run the script, wait for exit, then read the log file the script prints (`Log: .test_logs/...` or `Log: .build_logs/...`). Do not pipe live output to `tail`.

## Scripts

| Script | Purpose |
|--------|---------|
| `${CLAUDE_SKILL_DIR}/scripts/build.sh` | Compile for iOS Simulator |
| `${CLAUDE_SKILL_DIR}/scripts/run_tests.sh` | Run XCTest / Swift Testing targets |

`${CLAUDE_SKILL_DIR}` resolves to the directory containing this `SKILL.md` (e.g. `~/.claude/skills/ios-build-test`).

---

## Agent workflow (read this first)

Follow these steps **every time** you build or test after code changes.

### ⚠️ Invoke scripts directly — never pipe (critical)

**Run `build.sh` and `run_tests.sh` as the only command in the shell invocation.** Do not wrap them in a pipeline — not even "just `tail -50` to keep output short."

| Do | Don't |
|----|-------|
| `run_tests.sh --scheme "MyApp" unit` | `run_tests.sh ... \| tee log` |
| `build.sh --scheme "MyApp"` | `build.sh ... 2>&1 \| tail -30` |
| `build.sh --scheme "MyApp" --verbose` | `run_tests.sh ... \| grep passed` |
| Wait for exit, then `Read` `.test_logs/*.log` | `run_tests.sh ... 2>&1 \| tail -50` ← common agent mistake |

**Why piping breaks agent runs (even when Xcode is fast)**

- `run_tests.sh` uses bash job control (`set -m`) to manage `xcodebuild`. When the script is the left side of a pipe (`script \| tee`), it can print `🎉 All tests passed!` but **never close stdout**, so `tee`/`tail` and the parent shell wait forever.
- Piping to `tail`/`head`/`grep` block-buffers stdout and hides the preflight block and 30-second heartbeats — the run looks hung for minutes with **zero** new lines in the terminal file.
- Xcode GUI and a direct script run both finish in ~1–3 minutes; a **piped** agent run can appear stuck for 10+ minutes after tests already passed. That mismatch means you piped — not that the project is slow.
- The scripts already write full logs under `.build_logs/` and `.test_logs/`. Piping is redundant and harmful.

**Correct pattern (build or test)**

```bash
cd /path/to/MyApp
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh --scheme "My App" unit
```

Set `block_until_ms: 300000` (or `600000` for large projects) and `required_permissions: ["all"]`. Wait until the shell command exits.

**If you need a copy of the log elsewhere** (goal mode, implementer artifacts, CI), run the script first, then copy the log file the script prints — do not tee live output:

```bash
cd /path/to/MyApp
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh --scheme "My App" unit
cp .test_logs/MyAppTests_*.log /path/to/artifact.log
```

Or read the log path from the script's preflight block (`Log file: .test_logs/...`) or final `Log saved to:` line.

**How to know the run actually finished**

- Build: shell exited **and** output contains `✓ Build succeeded`
- Tests: shell exited **and** output contains `🎉 All tests passed!` or `💥 Some tests failed!`
- Do **not** treat `🎉 All tests passed!` alone as completion when the command was piped — that message can appear while the pipeline is still hung.
- Some agent harnesses report `exit_code: -1` on the wrapper even when the script returned `0`. Trust the script's final status line; optionally confirm with `; echo "EXIT=$?"` appended (still **no pipe** on the script itself).

### ⚠️ Wait for the script to finish (critical)

**The build can take several minutes with almost no terminal output in quiet mode.** The script prints a preflight summary, then runs `xcodebuild` (often 1–5+ minutes), then prints `✓ Build succeeded` or `✗ Build failed`.

**You must block until the shell command exits.** Do not:

- Stop or interrupt the command because output stalled after `Build in progress`
- Assume success from the preflight lines alone
- Move on after seeing only `Building …` from an older version of the script
- Poll a background job unless you explicitly backgrounded it with a long `block_until_ms`

**When invoking from Cursor / agent tools:**

- Set **`block_until_ms` to at least `300000`** (5 minutes) for typical apps; use **`600000`** (10 minutes) for large CocoaPods projects
- Default tool timeouts are too short — the command will look "stuck" while xcodebuild is still compiling
- Request **`required_permissions: ["all"]`** in sandboxed environments so Xcode can write `.derivedData` and access simulators
- Only treat the build as passed after the script prints **`✓ Build succeeded`** and exit code `0`

The same wait rules apply to **`run_tests.sh`** (tests often take longer than builds).

**Do not pipe either script** — not to `tee`, `tail`, `head`, or `grep`. Invoke directly; read `.build_logs/` or `.test_logs/` afterward. Wait for the shell to exit and for `🎉 All tests passed!` or `💥 Some tests failed!`.

### 1. Go to the project root

```bash
cd /path/to/MyApp
```

The current directory **must** contain the app's `.xcworkspace` or `.xcodeproj` (not `Pods.xcworkspace`).

**Do not** pass the workspace/project path as a script argument — detection is cwd-based only.

### 2. Run the skill script

```bash
${CLAUDE_SKILL_DIR}/scripts/build.sh --scheme "My App"
```

Common flags:

| Flag | When to use |
|------|-------------|
| `--scheme "Name"` | Scheme differs from folder name (e.g. project `Top Music`, scheme `Top Music`) |
| `--rosetta` | Force x86_64 simulator destination (also auto-enabled when Podfile excludes arm64 sim) |
| `--verbose` / `-v` | Full xcodebuild output to terminal **and** log file |
| Extra xcodebuild args | e.g. `-configuration Release CODE_SIGNING_ALLOWED=NO` (build.sh only) |

### 3. Wait for completion

- **Always block until the script exits.** Quiet mode captures xcodebuild to the log file — the terminal may show no new lines for minutes. That is normal.
- Set a generous timeout when invoking from an agent shell: **300–600 seconds** (`block_until_ms: 300000` minimum; `600000` for large Pod projects).
- Xcode builds need full permissions (`required_permissions: ["all"]`) in sandboxed environments.
- Success = final line **`✓ Build succeeded`** (or test equivalent) **and** exit code `0`. Anything else means keep waiting or diagnose failure.

### 4. Read the result

The script prints a preflight block, then (after xcodebuild finishes) one of:

```
✓ Build succeeded
Log: .build_logs/build_20260608_061656.log
```

```
✗ Build failed (2m 14s, xcodebuild exit 65)
  Log: .build_logs/build_20260608_061656.log

Errors (summary):
/path/to/File.swift:42:10: error: ...

Next steps:
  1. Read the full log: ...
  2. Grep compile errors: ...
  3. Re-run with live output: .../build.sh --verbose --scheme "..."
```

**On failure:** follow the script's **Next steps** block, or open the log file it names and grep for `error:` — do not guess from a truncated terminal buffer.

**On success:** you may report build passed. If you changed compile-sensitive code, a green build is required before telling the user the task is done.

### 5. Fix → rebuild loop

After fixing compile errors, **run `build.sh` again** and wait for the new result. Repeat until `✓ Build succeeded`.

---

## Quick examples

```bash
# Default build (auto-detect workspace, scheme, simulator)
cd /path/to/MyApp
${CLAUDE_SKILL_DIR}/scripts/build.sh

# Explicit scheme (recommended when name has spaces or differs from folder)
${CLAUDE_SKILL_DIR}/scripts/build.sh --scheme "Top Music"

# Verbose — when the summary is empty but build failed
${CLAUDE_SKILL_DIR}/scripts/build.sh --verbose --scheme "Top Music"

# Unit tests only
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh unit --scheme "Top Music"

# Single test target
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh single MyAppTests --scheme "Top Music"
```

---

## What the scripts do for you

| Concern | Handled by script |
|---------|-------------------|
| Pick workspace vs project | Prefers `*.xcworkspace` (excludes Pods) |
| Pick scheme | `--scheme` → `.env SCHEME` → name match → first non-Pods scheme |
| Pick simulator | `.env DEVICE_ID` → first available iPhone simulator |
| Isolated DerivedData | Uses project-local `.derivedData` (override with `DERIVED_DATA_PATH` in `.env`) |
| Capture output | Writes `.build_logs/build_YYYYMMDD_HHMMSS.log` (or `.test_logs/…`) |
| Detect silent failures | Scans log for `file:line:col: error:` even if xcodebuild exits 0 |
| Summarize errors | Prints compile error lines and **Next steps** on failure |
| Preflight + timing | Prints project/scheme/simulator/log path before build; elapsed time after |

---

## .env configuration (optional)

Create `.env` in the project root to avoid repeated flags:

```bash
DEVICE_ID=4019771F-38B3-4DA7-B4D7-B458E99A5394  # from: xcrun simctl list devices available
SCHEME=MyApp
# ROSETTA=true  # optional; also auto-detected from Podfile EXCLUDED_ARCHS arm64
# DERIVED_DATA_PATH=.derivedData  # optional; this is the default
```

`.env` is optional; scripts auto-detect when omitted. If `DEVICE_ID` is missing or no longer available, the scripts pick a booted (else first available) iPhone simulator.

---

## Build artifacts and logs

| Type | Path |
|------|------|
| DerivedData | `.derivedData/` (isolated per project; add to `.gitignore`) |
| Build log | `.build_logs/build_YYYYMMDD_HHMMSS.log` |
| Test log | `.test_logs/<target>_YYYYMMDD_HHMMSS.log` |

Paths are relative to the **project root** (cwd when you ran the script). Builds and tests never write to the global `~/Library/Developer/Xcode/DerivedData` unless you override `DERIVED_DATA_PATH`.

Useful grep patterns:

```bash
grep -E "^/.+:[0-9]+:[0-9]+: error: " .build_logs/build_*.log | tail -20
grep -E "warning:|error:" .build_logs/build_*.log | tail -40
```

---

## Testing (`run_tests.sh`)

```bash
# All tests — run directly, no pipe
cd /path/to/MyApp
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh --scheme "My App" unit
```

```bash
# All / unit / UI / single target
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh unit
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh ui
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh all
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh single MyAppTests
```

Positional args: `[unit|ui|all|single <target>]` after flags.

Full xcodebuild output is always saved under `.test_logs/<target>_YYYYMMDD_HHMMSS.log` (path printed in the preflight block). Read or copy that file — do not use `| tee` to capture output.

The test script also detects xctest process crashes (`=== TEST PROCESS CRASHED ===`) and fail-fast kills runaway restarts. See script comments for full crash-marker list.

---

## Auto-detection details

### Project

1. `*.xcworkspace` (not `Pods.xcworkspace`)
2. else `*.xcodeproj` (not `Pods.xcodeproj`)

### Scheme

1. `--scheme <name>`
2. `SCHEME` in `.env`
3. Scheme matching project/workspace basename
4. First non-Pods scheme from `xcodebuild -list`

### Simulator

1. `DEVICE_ID` in `.env`
2. First available iPhone from `xcrun simctl list devices available -j`

---

## Rules for agents

1. **Never** call `xcodebuild` directly — use `build.sh` / `run_tests.sh`.
2. **Always** `cd` to the project root first.
3. **Always wait for the script to finish** — use `block_until_ms: 300000` or higher; do not abort during quiet compiles.
4. **Never pipe** `build.sh` or `run_tests.sh` — no `| tee`, `| tail`, `| head`, `| grep`, or `2>&1 | …` of any kind. The command string must end at the script's last argument. Read `.build_logs/` / `.test_logs/` afterward instead.
5. **Never truncate live output** to save tokens — if the full terminal buffer is too long, read the log file path from the script's final lines.
6. **Always** read the log file on failure before attempting fixes (use the **Next steps** the script prints).
7. **Always** rebuild after compile fixes and wait again until `✓ Build succeeded`.
8. Use `--scheme` when the app name contains spaces or doesn't match the repo folder.
9. Use `--verbose` when failure summary is empty, exit code is ambiguous, or you need live progress.
10. Request `all` sandbox permissions for Xcode tool invocations.
11. **Do not** background the command just because output pauses after the preflight block — xcodebuild is still running in quiet mode.
12. If the user reports "Xcode finished in a minute but your terminal hung", assume a piped command — kill it and re-run without a pipe.

---

## Troubleshooting

### "No .xcworkspace or .xcodeproj found"

You are not in the project root. `cd` to the directory that contains the app workspace/project.

### "No scheme found"

```bash
${CLAUDE_SKILL_DIR}/scripts/build.sh --scheme "Exact Scheme Name"
# or add SCHEME=... to .env
```

### "No simulator found"

```bash
xcrun simctl list devices available
# add DEVICE_ID=<udid> to .env
```

### Build fails on Apple Silicon (old x86 pods / EXCLUDED_ARCHS arm64)

```bash
${CLAUDE_SKILL_DIR}/scripts/build.sh --rosetta
# or set ROSETTA=true in .env
```

`--rosetta` (and Podfile auto-detect of `EXCLUDED_ARCHS[sdk=iphonesimulator*]=arm64`) sets the destination to `arch=x86_64` while keeping **native** `xcodebuild`. Do not wrap xcodebuild in `arch -x86_64` — modern Xcode's CoreSimulator plugin is arm64-only and fails under Rosetta.

### Script exits 65 with almost no terminal output

**Expected in quiet mode** — xcodebuild output goes to the log file while the script runs. You should see the preflight block and `Build in progress` first; then wait until `✓` or `✗` appears. Read `.build_logs/build_*.log` (path printed by the script). Re-run with `--verbose` if you need live progress.

### Agent stopped early / "Building …" then nothing

The build was still running. Re-run with `block_until_ms: 300000` (or `600000`) and wait for the final status line. Do not background unless you plan to poll until completion.

### `run_tests.sh` shows no output for minutes

**Do not pipe the script** (`| tee`, `| tail`, `| head`, etc.). Run it directly from the project root and wait for the shell to exit with `🎉 All tests passed!` or `💥 Some tests failed!`. Use `--verbose` if you need live xcodebuild output. Typical unit-test runs take 1–3 minutes; first run after a clean build can take longer.

### Tests print "All tests passed" but the command never exits

You piped the script (usually `| tee` or `| tail -N`). The test run finished, but the pipeline is hung because `run_tests.sh` did not close stdout. Kill the stuck shell, re-run **without a pipe**, then `cp` or `Read` the `.test_logs/` file if you need an artifact.

### Xcode / user finished in ~1 min but agent terminal still "running"

Same root cause: a pipe on `run_tests.sh` or `build.sh`. The tests/build completed; `tail`/`tee` is waiting forever. **Do not** increase `block_until_ms` or background-poll — fix the invocation. Re-run:

```bash
cd /path/to/project
${CLAUDE_SKILL_DIR}/scripts/run_tests.sh --scheme "nowlist" unit
```

Then read `.test_logs/` for details. Trust the user's Xcode timing over a hung piped terminal.

### Orphan `tail -F .test_logs/...` processes after test runs

The test script's crash watcher can leave stray `tail` processes. Safe cleanup before a new run:

```bash
pkill -f "tail -n +1 -F .test_logs" 2>/dev/null || true
```

### xcodebuild exit 0 but build actually failed

The script scans for compile errors in the log and treats that as failure. Trust the script's `✓` / `✗` line, not raw xcodebuild exit codes alone.
