#!/usr/bin/env bash
# Sourced by build.sh / run_tests.sh — do not execute directly.
# Simulator policy: sim-pool + simslim (see ios-build-test SKILL.md).

ios_build_test_sim_pool_cli() {
    if [ -n "${SIM_POOL_CLI:-}" ]; then
        echo "$SIM_POOL_CLI"
        return 0
    fi
    local default="$HOME/.claude/skills/sim-pool/scripts/sim-pool"
    if [ -f "$default" ]; then
        echo "$default"
        return 0
    fi
    return 1
}

ios_build_test_pick_available_iphone() {
    xcrun simctl list devices available -j | python3 -c "
import sys, json
devices = json.load(sys.stdin)['devices']
booted = None
fallback = None
for runtime, device_list in devices.items():
    if 'iOS' not in runtime:
        continue
    for device in device_list:
        if 'iPhone' not in device.get('name', '') or not device.get('isAvailable', False):
            continue
        if device.get('state') == 'Booted' and booted is None:
            booted = device['udid']
        if fallback is None:
            fallback = device['udid']
print(booted or fallback or '')
"
}

ios_build_test_is_template_udid() {
    local id="$1"
    local pool_home="${AGENT_SIM_POOL_HOME:-$HOME/.agent-sim-pool}"
    python3 - "$pool_home" "$id" <<'PY'
import json, sys
from pathlib import Path
home = Path(sys.argv[1])
udid = sys.argv[2]
path = home / "config.json"
if not path.is_file():
    sys.exit(0)
cfg = json.loads(path.read_text())
if not cfg.get("ephemeral", {}).get("clones_only", True):
    sys.exit(0)
templates = set(cfg.get("devices", []))
clone = (cfg.get("ephemeral") or {}).get("clone_udid", "")
if isinstance(clone, str) and clone.strip():
    templates.add(clone.strip())
sys.exit(1 if udid in templates else 0)
PY
}

ios_build_test_device_is_available() {
    local id="$1"
    xcrun simctl list devices available -j | DEVICE_ID="$id" python3 -c "
import json, os, sys
target = os.environ.get('DEVICE_ID', '')
for runtime, device_list in json.load(sys.stdin).get('devices', {}).items():
    for device in device_list:
        if device.get('udid') == target and device.get('isAvailable', False):
            sys.exit(0)
sys.exit(1)
"
}

ios_build_test_session_env_file() {
    echo "${IOS_BUILD_TEST_SESSION_ENV:-.build_logs/.sim-pool-session.env}"
}

ios_build_test_load_session_env() {
    local f
    f=$(ios_build_test_session_env_file)
    if [ -f "$f" ]; then
        # shellcheck source=/dev/null
        set -a
        source "$f"
        set +a
    fi
}

ios_build_test_save_session_env() {
    local f
    f=$(ios_build_test_session_env_file)
    mkdir -p "$(dirname "$f")"
    cat >"$f" <<EOF
# Written by ios-build-test after sim-pool acquire — do not commit. Remove after sim-pool release.
DEVICE_ID=${DEVICE_ID}
SIM_POOL_LEASE_ID=${SIM_POOL_LEASE_ID:-}
SIM_POOL_EPHEMERAL=${SIM_POOL_EPHEMERAL:-false}
EOF
}

ios_build_test_resolve_device_id() {
    if [ -z "${DEVICE_ID:-}" ]; then
        ios_build_test_load_session_env
    fi

    if [ -n "${DEVICE_ID:-}" ]; then
        if ios_build_test_is_template_udid "$DEVICE_ID"; then
            echo "Error: DEVICE_ID=$DEVICE_ID is a sim-pool template (source simulator)."
            echo "Never run builds/tests on the template — use: sim-pool acquire (gets or creates a clone)."
            return 1
        fi
        if ! ios_build_test_device_is_available "$DEVICE_ID"; then
            echo "Error: DEVICE_ID=$DEVICE_ID is not available in simctl."
            echo "Do not pick another simulator — re-run: sim-pool acquire → export DEVICE_ID"
            echo "If another agent holds the lease, wait or use ephemeral clone (default on)."
            return 1
        fi
        return 0
    fi

    if [ "${SIM_POOL_SKIP:-0}" = "1" ]; then
        DEVICE_ID=$(ios_build_test_pick_available_iphone || true)
        if [ -z "${DEVICE_ID:-}" ]; then
            echo "Error: No simulator found (SIM_POOL_SKIP=1 legacy mode)."
            echo "Run: xcrun simctl list devices available"
            return 1
        fi
        export DEVICE_ID
        return 0
    fi

    local sp
    if ! sp=$(ios_build_test_sim_pool_cli); then
        echo "Error: DEVICE_ID is unset and sim-pool was not found."
        echo "  sim-pool acquire --holder-pid \$\$ --owner \"agent-\$\$\" --project \"\$(basename \"\$PWD\")\" --worktree \"\$PWD\" --session \"qa-\$\$\""
        echo "  export DEVICE_ID=\"\$UDID\""
        echo "Or set SIM_POOL_SKIP=1 to allow auto-picking any iPhone (not safe with multiple agents)."
        return 1
    fi

    local session="${SIM_POOL_SESSION:-ios-build-test-$$}"
    local out
    if ! out=$("$sp" acquire \
        --holder-pid "$$" \
        --owner "ios-build-test-$$" \
        --project "$(basename "$PWD")" \
        --worktree "$PWD" \
        --session "$session" 2>&1); then
        echo "$out" >&2
        echo "Error: sim-pool acquire failed. On SIM_POOL_BUSY, pool and ephemeral limits are exhausted." >&2
        return 1
    fi
    eval "$out"
    export DEVICE_ID="$UDID"
    export SIM_POOL_LEASE_ID="${LEASE_ID:-}"
    export SIM_POOL_EPHEMERAL="${EPHEMERAL:-false}"
    IOS_BUILD_TEST_SIM_POOL_ACQUIRED=1
    ios_build_test_save_session_env
    echo "  sim-pool:    acquired lease_id=${SIM_POOL_LEASE_ID} ephemeral=${SIM_POOL_EPHEMERAL}"
    echo "  (release after QA: sim-pool release --lease \"\$SIM_POOL_LEASE_ID\")"
    return 0
}

ios_build_test_boot_simulator() {
    if [ "${SIMSLIM_SKIP_BOOT:-0}" = "1" ]; then
        return 0
    fi
    if ! command -v simslim >/dev/null 2>&1; then
        echo "Warning: simslim not in PATH; skipping simslim boot (install: brew install mobai-app/tap/simslim)"
        return 0
    fi
    simslim boot "$DEVICE_ID"
}
