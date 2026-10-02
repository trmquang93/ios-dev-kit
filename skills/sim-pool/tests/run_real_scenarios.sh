#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SIM_POOL="$SKILL_DIR/scripts/sim-pool"
EVIDENCE_DIR="$SCRIPT_DIR/evidence"
mkdir -p "$EVIDENCE_DIR"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG="$EVIDENCE_DIR/real-scenarios-$RUN_ID.log"
exec > >(tee -a "$LOG") 2>&1

echo "=== sim-pool real scenarios $RUN_ID ==="

export AGENT_SIM_POOL_HOME
AGENT_SIM_POOL_HOME="$(mktemp -d)"
export AGENT_SIM_POOL_HOME

UDIDS=()
if command -v xcrun >/dev/null 2>&1; then
    while IFS= read -r u; do
        [ -n "$u" ] && UDIDS+=("$u")
    done < <(python3 <<'PY'
import json, subprocess
proc = subprocess.run(["xcrun","simctl","list","devices","available","-j"], capture_output=True, text=True, check=True)
data = json.loads(proc.stdout)
out = []
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for d in devices:
        if d.get("isAvailable", True) and "iPhone" in d.get("name",""):
            out.append(d["udid"])
            if len(out) >= 2:
                break
    if len(out) >= 2:
        break
for u in out:
    print(u)
PY
)
fi

if [ ${#UDIDS[@]} -lt 1 ]; then
    UDIDS=("REAL0001-0000-0000-0000-000000000001" "REAL0002-0000-0000-0000-000000000002")
    echo "WARN: no simctl iPhones; using synthetic UDIDs for lease-only scenarios"
fi

python3 - "$AGENT_SIM_POOL_HOME" "${UDIDS[@]}" <<'PY'
import json, sys
from pathlib import Path
home = Path(sys.argv[1])
udids = sys.argv[2:]
(home / "leases").mkdir(parents=True, exist_ok=True)
(home / "pool.lock").touch()
config = {
    "devices": udids[:2] if len(udids) >= 2 else udids,
    "defaults": {"timeout_seconds": 600, "ttl_seconds": 900, "poll_seconds": 1, "prefer": "shutdown"},
}
(home / "config.json").write_text(json.dumps(config, indent=2) + "\n")
PY

SIM_COUNT_BEFORE=""
if command -v xcrun >/dev/null 2>&1; then
    SIM_COUNT_BEFORE=$(xcrun simctl list devices available | grep -c iPhone || true)
fi

echo "--- R1 parallel acquire ---"
python3 - "$AGENT_SIM_POOL_HOME" "${UDIDS[0]}" <<'PY'
import json, sys
from pathlib import Path
home = Path(sys.argv[1])
udid = sys.argv[2]
config = json.loads((home / "config.json").read_text())
config["devices"] = [udid]
config["defaults"]["poll_seconds"] = 1
(home / "config.json").write_text(json.dumps(config, indent=2) + "\n")
PY
OUT1=$("$SIM_POOL" acquire --holder-pid $$ --owner r1-a --project proj-a --session r1s1 --timeout 30)
LEASE1=$(echo "$OUT1" | grep '^LEASE_ID=' | cut -d= -f2-)
UDID1=$(echo "$OUT1" | grep '^UDID=' | cut -d= -f2-)
"$SIM_POOL" acquire --holder-pid $$ --owner r1-b --project proj-b --session r1s2 --timeout 8 > /tmp/r1-wait.out 2>/tmp/r1-wait.err &
WAIT_PID=$!
sleep 1
if kill -0 "$WAIT_PID" 2>/dev/null; then
    echo "R1: second acquire blocked (ok)"
else
    echo "R1 FAIL: second acquire did not block"
    exit 1
fi
"$SIM_POOL" release --lease "$LEASE1"
wait "$WAIT_PID" || true
OUT2=$(cat /tmp/r1-wait.out)
UDID2=$(echo "$OUT2" | grep '^UDID=' | cut -d= -f2-)
LEASE2=$(echo "$OUT2" | grep '^LEASE_ID=' | cut -d= -f2-)
"$SIM_POOL" release --lease "$LEASE2" 2>/dev/null || true
echo "R1 UDIDs: $UDID1 -> $UDID2"

echo "--- R2 crash orphan ---"
"$SIM_POOL" acquire --holder-pid $$ --owner r2 --session r2s --timeout 5 > /tmp/r2-acquire.out
LEASE_R2=$(grep '^LEASE_ID=' /tmp/r2-acquire.out | cut -d= -f2-)
python3 - "$AGENT_SIM_POOL_HOME" "$LEASE_R2" <<'PY'
import json, os, sys
from pathlib import Path
home = Path(sys.argv[1])
lease_id = sys.argv[2]
for path in (home / "leases").glob("*.json"):
    data = json.loads(path.read_text())
    if data.get("lease_id") == lease_id:
        data["pid"] = 999999999
        path.write_text(json.dumps(data, indent=2) + "\n")
PY
OUT_R2=$("$SIM_POOL" acquire --holder-pid $$ --owner r2b --session r2s2 --timeout 5)
echo "R2 reclaim: $OUT_R2"
LEASE_R2B=$(echo "$OUT_R2" | grep '^LEASE_ID=' | cut -d= -f2-)
"$SIM_POOL" release --lease "$LEASE_R2B" 2>/dev/null || true

echo "--- R3 TTL reclaim ---"
OUT_R3=$("$SIM_POOL" acquire --holder-pid $$ --owner r3 --session r3s --ttl 3 --timeout 5)
LEASE_R3=$(echo "$OUT_R3" | grep '^LEASE_ID=' | cut -d= -f2-)
sleep 4
if "$SIM_POOL" renew --lease "$LEASE_R3" 2>/tmp/r3-renew.err; then
    echo "R3 WARN: renew still ok immediately after short ttl window"
else
    echo "R3 renew failed as expected: $(cat /tmp/r3-renew.err)"
fi
OUT_R3B=$("$SIM_POOL" acquire --holder-pid $$ --owner r3b --session r3s2 --timeout 5)
LEASE_R3B=$(echo "$OUT_R3B" | grep '^LEASE_ID=' | cut -d= -f2-)
"$SIM_POOL" release --lease "$LEASE_R3B" 2>/dev/null || true

echo "--- R4 busy timeout ---"
python3 - "$AGENT_SIM_POOL_HOME" "${UDIDS[@]}" <<'PY'
import json, sys
from pathlib import Path
home = Path(sys.argv[1])
udids = sys.argv[2:]
config = json.loads((home / "config.json").read_text())
config["devices"] = udids[:2] if len(udids) >= 2 else udids
config["defaults"]["poll_seconds"] = 1
(home / "config.json").write_text(json.dumps(config, indent=2) + "\n")
PY
"$SIM_POOL" gc >/dev/null
H1=$("$SIM_POOL" acquire --holder-pid $$ --owner h1 --session h1s --timeout 5)
H2=$("$SIM_POOL" acquire --holder-pid $$ --owner h2 --session h2s --timeout 5)
L1=$(echo "$H1" | grep '^LEASE_ID=' | cut -d= -f2-)
L2=$(echo "$H2" | grep '^LEASE_ID=' | cut -d= -f2-)
if "$SIM_POOL" acquire --holder-pid $$ --owner h3 --timeout 3 2>/tmp/r4.err; then
    echo "R4 FAIL: should be busy"
    exit 1
fi
if grep -q SIM_POOL_BUSY /tmp/r4.err; then
    echo "R4 SIM_POOL_BUSY ok"
else
    echo "R4 FAIL: missing SIM_POOL_BUSY in $(cat /tmp/r4.err)"
    exit 1
fi
"$SIM_POOL" release --lease "$L1" >/dev/null
"$SIM_POOL" release --lease "$L2" >/dev/null

echo "--- R5 no-create invariant ---"
if [ -n "$SIM_COUNT_BEFORE" ]; then
    SIM_COUNT_AFTER=$(xcrun simctl list devices available | grep -c iPhone || true)
    if [ "$SIM_COUNT_BEFORE" = "$SIM_COUNT_AFTER" ]; then
        echo "R5 sim count unchanged: $SIM_COUNT_BEFORE"
    else
        echo "R5 FAIL: sim count $SIM_COUNT_BEFORE -> $SIM_COUNT_AFTER"
        exit 1
    fi
else
    echo "R5 skip (no xcrun)"
fi

echo "--- R6 cross-project status ---"
"$SIM_POOL" gc >/dev/null
P1=$("$SIM_POOL" acquire --holder-pid $$ --owner p1 --project alpha --session p1s --timeout 5)
P2=$("$SIM_POOL" acquire --holder-pid $$ --owner p2 --project beta --session p2s --timeout 5)
"$SIM_POOL" status | tee /tmp/r6-status.out
if ! grep -qE 'project=alpha|owner=p1' /tmp/r6-status.out; then
    echo "R6 FAIL: missing alpha/p1 in status"
    exit 1
fi
if ! grep -qE 'project=beta|owner=p2' /tmp/r6-status.out; then
    echo "R6 FAIL: missing beta/p2 in status"
    exit 1
fi
LP1=$(echo "$P1" | grep '^LEASE_ID=' | cut -d= -f2-)
LP2=$(echo "$P2" | grep '^LEASE_ID=' | cut -d= -f2-)
"$SIM_POOL" release --lease "$LP1" >/dev/null
"$SIM_POOL" release --lease "$LP2" >/dev/null
echo "R6 ok"

rm -rf "$AGENT_SIM_POOL_HOME"
echo ""
echo "All real scenarios passed. Log: $LOG"
