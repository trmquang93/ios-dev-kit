#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SIM_POOL="$SKILL_DIR/scripts/sim-pool"

export AGENT_SIM_POOL_HOME
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "PASS: $1"
}

fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "FAIL: $1" >&2
}

setup_pool() {
    AGENT_SIM_POOL_HOME="$(mktemp -d)"
    export AGENT_SIM_POOL_HOME
    python3 - "$AGENT_SIM_POOL_HOME" <<'PY'
import json, sys
from pathlib import Path
home = Path(sys.argv[1])
home.mkdir(parents=True, exist_ok=True)
(home / "leases").mkdir(exist_ok=True)
(home / "pool.lock").touch()
config = {
    "devices": ["AAAA1111-1111-1111-1111-111111111111", "BBBB2222-2222-2222-2222-222222222222"],
    "defaults": {"timeout_seconds": 600, "ttl_seconds": 900, "poll_seconds": 1, "prefer": "shutdown"},
    "ephemeral": {"enabled": False, "clones_only": False},
}
(home / "config.json").write_text(json.dumps(config, indent=2) + "\n")
PY
}

teardown_pool() {
    if [ -n "${AGENT_SIM_POOL_HOME:-}" ] && [ -d "$AGENT_SIM_POOL_HOME" ]; then
        rm -rf "$AGENT_SIM_POOL_HOME"
    fi
}

test_acquire_and_release() {
    setup_pool
    out=$("$SIM_POOL" acquire --holder-pid $$ --owner test-a --session s1 2>&1) || { fail "acquire"; teardown_pool; return; }
    echo "$out" | grep -q "LEASE_ID=" || { fail "acquire missing LEASE_ID"; teardown_pool; return; }
    lease_id=$(echo "$out" | grep '^LEASE_ID=' | cut -d= -f2-)
    udid=$(echo "$out" | grep '^UDID=' | cut -d= -f2-)
    "$SIM_POOL" release --lease "$lease_id" >/dev/null
    out2=$("$SIM_POOL" acquire --holder-pid $$ --owner test-b --session s2 2>&1)
    udid2=$(echo "$out2" | grep '^UDID=' | cut -d= -f2-)
    if [ "$udid" = "$udid2" ]; then
        pass "acquire and release"
    else
        fail "acquire after release got different udid (ok if other device)"
        pass "acquire and release (partial)"
    fi
    teardown_pool
}

test_busy_timeout() {
    setup_pool
    python3 - "$AGENT_SIM_POOL_HOME" <<'PY'
import json, sys
from pathlib import Path
home = Path(sys.argv[1])
config = json.loads((home / "config.json").read_text())
config["devices"] = ["AAAA1111-1111-1111-1111-111111111111"]
config["defaults"]["poll_seconds"] = 1
(home / "config.json").write_text(json.dumps(config, indent=2) + "\n")
PY
    out1=$("$SIM_POOL" acquire --holder-pid $$ --owner hold1 --session h1 2>&1)
    lease1=$(echo "$out1" | grep '^LEASE_ID=' | cut -d= -f2-)
    if "$SIM_POOL" acquire --holder-pid $$ --owner wait --timeout 2 --no-ephemeral 2>/tmp/sim-pool-busy.err; then
        fail "third acquire should timeout"
    else
        code=$?
        if [ "$code" -eq 2 ] && grep -q SIM_POOL_BUSY /tmp/sim-pool-busy.err; then
            pass "busy timeout exit 2"
        else
            fail "busy timeout wrong exit ($code)"
        fi
    fi
    "$SIM_POOL" release --lease "$lease1" >/dev/null
    teardown_pool
}

test_dead_pid_gc() {
    setup_pool
    AGENT_SIM_POOL_HOME="$AGENT_SIM_POOL_HOME" python3 <<'PY'
import json, os, subprocess, time
from pathlib import Path
home = Path(os.environ["AGENT_SIM_POOL_HOME"])
udid = "AAAA1111-1111-1111-1111-111111111111"
lease = {
    "lease_id": "dead-lease",
    "udid": udid,
    "owner": "ghost",
    "pid": 999999999,
    "project": "t",
    "worktree": "/tmp",
    "session": "s",
    "purpose": "qa",
    "acquired_at": "2020-01-01T00:00:00+00:00",
    "expires_at": "2099-01-01T00:00:00+00:00",
}
(home / "leases" / f"{udid}.json").write_text(json.dumps(lease))
PY
    "$SIM_POOL" gc >/dev/null
    out=$("$SIM_POOL" acquire --holder-pid $$ --owner reclaim --session r1 2>&1)
    udid=$(echo "$out" | grep '^UDID=' | cut -d= -f2-)
    if [ "$udid" = "AAAA1111-1111-1111-1111-111111111111" ]; then
        pass "dead pid gc"
    else
        fail "dead pid gc did not reclaim AAAA"
    fi
    teardown_pool
}

test_ttl_reclaim() {
    setup_pool
    python3 - "$AGENT_SIM_POOL_HOME" <<'PY'
import json, sys
from datetime import datetime, timezone, timedelta
from pathlib import Path
home = Path(sys.argv[1])
udid = "AAAA1111-1111-1111-1111-111111111111"
past = (datetime.now(timezone.utc) - timedelta(seconds=10)).replace(microsecond=0).isoformat()
lease = {
    "lease_id": "ttl-lease",
    "udid": udid,
    "owner": "stale",
    "pid": 1,
    "project": "t",
    "worktree": "/tmp",
    "session": "s",
    "purpose": "qa",
    "acquired_at": past,
    "expires_at": past,
}
(home / "leases" / f"{udid}.json").write_text(json.dumps(lease))
PY
    "$SIM_POOL" gc >/dev/null
    out=$("$SIM_POOL" acquire --holder-pid $$ --owner new --session n1 2>&1)
    if echo "$out" | grep -q "UDID=AAAA"; then
        pass "ttl reclaim"
    else
        fail "ttl reclaim"
    fi
    lease_id=$(echo "$out" | grep '^LEASE_ID=' | cut -d= -f2-)
    if "$SIM_POOL" renew --lease ttl-lease 2>/dev/null; then
        fail "renew on gone lease should fail"
    else
        pass "LEASE_GONE on stale renew"
    fi
    "$SIM_POOL" release --lease "$lease_id" >/dev/null 2>&1 || true
    teardown_pool
}

test_parallel_acquire() {
    setup_pool
    SIM_POOL_TEST_HOLDER_PID=$$ python3 - "$AGENT_SIM_POOL_HOME" "$SIM_POOL" <<'PY'
import json, os, subprocess, sys, tempfile, time
from pathlib import Path

home = Path(sys.argv[1])
sim_pool = sys.argv[2]
config = json.loads((home / "config.json").read_text())
config["devices"] = ["AAAA1111-1111-1111-1111-111111111111"]
config["defaults"]["poll_seconds"] = 1
(home / "config.json").write_text(json.dumps(config))

env = os.environ.copy()
env["AGENT_SIM_POOL_HOME"] = str(home)

holder = int(os.environ.get("SIM_POOL_TEST_HOLDER_PID", str(os.getppid())))
p1 = subprocess.Popen(
    [sim_pool, "acquire", "--holder-pid", str(holder), "--owner", "p1", "--session", "s1", "--timeout", "30"],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env,
)
time.sleep(0.5)
p2 = subprocess.Popen(
    [sim_pool, "acquire", "--holder-pid", str(holder), "--owner", "p2", "--session", "s2", "--timeout", "30"],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env,
)
time.sleep(0.5)
if p2.poll() is not None:
    sys.exit("second acquire finished too fast")

out1, _ = p1.communicate(timeout=5)
lease1 = [l.split("=", 1)[1] for l in out1.splitlines() if l.startswith("LEASE_ID=")][0]
subprocess.run([sim_pool, "release", "--lease", lease1], env=env, check=True)
out2, err2 = p2.communicate(timeout=10)
if "UDID=" not in out2:
    sys.exit(f"p2 failed: {out2} {err2}")
print("ok")
PY
    if [ $? -eq 0 ]; then
        pass "parallel acquire wait then release"
    else
        fail "parallel acquire"
    fi
    teardown_pool
}

test_no_create_in_script() {
    if grep -q 'simctl.*create' "$SKILL_DIR/scripts/sim-pool"; then
        fail "sim-pool script calls simctl create"
    else
        pass "no simctl create in sim-pool"
    fi
}

test_ephemeral_when_busy() {
    setup_pool
    python3 - "$AGENT_SIM_POOL_HOME" <<'PY'
import json, sys
from pathlib import Path
home = Path(sys.argv[1])
config = json.loads((home / "config.json").read_text())
config["devices"] = ["AAAA1111-1111-1111-1111-111111111111"]
config["ephemeral"] = {"enabled": True, "clones_only": False, "max_devices": 4, "max_concurrent": 4, "delete_on_release": True}
(home / "config.json").write_text(json.dumps(config, indent=2) + "\n")
PY
    out1=$("$SIM_POOL" acquire --holder-pid $$ --owner hold-ephemeral --session e1 2>&1)
    lease1=$(echo "$out1" | grep '^LEASE_ID=' | cut -d= -f2-)
    out2=$(SIM_POOL_TEST_PROVISION_UDID="CCCC3333-3333-3333-3333-333333333333" \
        "$SIM_POOL" acquire --holder-pid $$ --owner ephemeral --session e2 --timeout 10 2>&1)
    udid2=$(echo "$out2" | grep '^UDID=' | cut -d= -f2-)
    ephemeral=$(echo "$out2" | grep '^EPHEMERAL=' | cut -d= -f2-)
    if [ "$udid2" = "CCCC3333-3333-3333-3333-333333333333" ] && [ "$ephemeral" = "true" ]; then
        pass "ephemeral acquire when busy"
    else
        fail "ephemeral acquire when busy (udid=$udid2 ephemeral=$ephemeral)"
    fi
    lease2=$(echo "$out2" | grep '^LEASE_ID=' | cut -d= -f2-)
    "$SIM_POOL" release --lease "$lease2" >/dev/null
    if [ -f "$AGENT_SIM_POOL_HOME/config.json" ] && grep -q CCCC3333 "$AGENT_SIM_POOL_HOME/config.json"; then
        fail "ephemeral device still in config after release"
    else
        pass "ephemeral deleted on release"
    fi
    "$SIM_POOL" release --lease "$lease1" >/dev/null
    teardown_pool
}

test_missing_sim_gc() {
    setup_pool
    python3 - "$AGENT_SIM_POOL_HOME" <<'PY'
import json, sys
from pathlib import Path
home = Path(sys.argv[1])
config = json.loads((home / "config.json").read_text())
ghost = "DEAD0000-0000-0000-0000-000000000001"
config["ephemeral_devices"] = [{
    "udid": ghost,
    "name": "ghost-clone",
    "clone_source": "AAAA1111-1111-1111-1111-111111111111",
    "created_at": "2020-01-01T00:00:00+00:00",
}]
config["devices"] = ["AAAA1111-1111-1111-1111-111111111111"]
config["ephemeral"] = {"enabled": False, "clones_only": False}
(home / "config.json").write_text(json.dumps(config, indent=2) + "\n")
leases = home / "leases"
leases.mkdir(parents=True, exist_ok=True)
(leases / f"{ghost}.json").write_text(json.dumps({
    "lease_id": "lease-ghost",
    "udid": ghost,
    "owner": "gone",
    "pid": 99999999,
    "project": "t",
    "session": "s",
    "purpose": "qa",
    "acquired_at": "2026-10-02T10:00:00+00:00",
    "expires_at": "2026-10-02T10:15:00+00:00",
    "ephemeral": True,
}, indent=2) + "\n")
PY
    dropped=$("$SIM_POOL" gc 2>&1)
    if echo "$dropped" | grep -q "missing_sim"; then
        pass "gc drops lease when simulator missing from simctl"
    else
        fail "gc missing_sim (got: $dropped)"
    fi
    if [ -f "$AGENT_SIM_POOL_HOME/leases/DEAD0000-0000-0000-0000-000000000001.json" ]; then
        fail "ghost lease file still present"
    else
        pass "ghost lease file removed"
    fi
    teardown_pool
}

test_live_clone_survives_gc() {
    setup_pool
    fake_bin="$(mktemp -d)"
    clone="C10E0000-0000-0000-0000-000000000001"
    cat > "$fake_bin/xcrun" <<EOF
#!/bin/bash
echo '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"$clone","name":"sim-pool-ephemeral-abcd1234","state":"Booted","isAvailable":true}]}}'
EOF
    chmod +x "$fake_bin/xcrun"
    python3 - "$AGENT_SIM_POOL_HOME" "$clone" "$$" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
home, clone, pid = Path(sys.argv[1]), sys.argv[2], int(sys.argv[3])
config = json.loads((home / "config.json").read_text())
now = datetime.now(timezone.utc).replace(microsecond=0)
config["ephemeral_devices"] = [{
    "udid": clone,
    "name": "sim-pool-ephemeral-abcd1234",
    "clone_source": "AAAA1111-1111-1111-1111-111111111111",
    "created_at": now.isoformat(),
}]
config["ephemeral"] = {"enabled": False, "clones_only": True}
(home / "config.json").write_text(json.dumps(config, indent=2) + "\n")
(home / "leases" / f"{clone}.json").write_text(json.dumps({
    "lease_id": "lease-clone",
    "udid": clone,
    "owner": "live",
    "pid": pid,
    "project": "t",
    "session": "s",
    "purpose": "qa",
    "acquired_at": now.isoformat(),
    "expires_at": (now + timedelta(minutes=10)).isoformat(),
    "ephemeral": True,
}, indent=2) + "\n")
PY
    PATH="$fake_bin:$PATH" "$SIM_POOL" gc >/dev/null 2>&1
    if [ -f "$AGENT_SIM_POOL_HOME/leases/$clone.json" ] && grep -q "$clone" "$AGENT_SIM_POOL_HOME/config.json"; then
        pass "live lease on sim-pool-ephemeral-* clone survives gc (clone is reused, not re-cloned)"
    else
        fail "gc dropped lease/registry for clone named sim-pool-ephemeral-* (missing_sim false positive)"
    fi
    rm -rf "$fake_bin"
    teardown_pool
}

test_acquire_and_release
test_missing_sim_gc
test_live_clone_survives_gc
test_busy_timeout
test_dead_pid_gc
test_ttl_reclaim
test_parallel_acquire
test_no_create_in_script
test_ephemeral_when_busy

echo ""
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
fi
