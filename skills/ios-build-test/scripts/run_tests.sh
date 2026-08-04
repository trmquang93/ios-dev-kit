#!/usr/bin/env bash
# When stdout is piped (e.g. `run_tests.sh | tail -30`), default block buffering
# hides all progress for minutes. Re-exec with line buffering when possible.
if [ -z "${IOS_BUILD_TEST_LINEBUFFER:-}" ] && [ ! -t 1 ]; then
    if command -v stdbuf >/dev/null 2>&1; then
        export IOS_BUILD_TEST_LINEBUFFER=1
        exec stdbuf -oL -eL bash "$0" "$@"
    fi
fi

set -euo pipefail

# Print progress; prefer /dev/tty when interactive so piped stdout still shows status.
progress() {
    if { echo "$@" >/dev/tty; } 2>/dev/null; then
        return 0
    fi
    echo "$@"
}

ROSETTA=false
ROSETTA_CLI=false
VERBOSE=false
SCHEME_FLAG=""
TEST_TYPE="all"
TEST_IDENTIFIER=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --rosetta)
            ROSETTA_CLI=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --scheme)
            SCHEME_FLAG="$2"
            shift 2
            ;;
        unit|ui|all|single)
            TEST_TYPE="$1"
            shift
            if [ "$TEST_TYPE" = "single" ] && [ $# -gt 0 ]; then
                TEST_IDENTIFIER="$1"
                shift
            fi
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 [--rosetta] [--verbose] [--scheme <name>] [unit|ui|all|single <target>]"
            exit 1
            ;;
    esac
done

if [ -f .env ]; then
    set -a
    # shellcheck source=/dev/null
    source .env
    set +a
fi

# Resolve Rosetta/x86_64 destination: CLI > .env > Podfile auto-detect.
# Prefer destination arch=x86_64 on a native (arm64) xcodebuild. Do NOT wrap
# xcodebuild in `arch -x86_64` — modern Xcode's CoreSimulator plugin is arm64-only
# and fails to load under Rosetta.
if [ "$ROSETTA_CLI" = true ]; then
    ROSETTA=true
else
    case "${ROSETTA:-false}" in
        true|TRUE|1|yes|YES) ROSETTA=true ;;
        *) ROSETTA=false ;;
    esac
    if [ "$ROSETTA" != true ] && [ -f Podfile ] \
        && grep -F "EXCLUDED_ARCHS[sdk=iphonesimulator*]" Podfile 2>/dev/null | grep -q "arm64"; then
        ROSETTA=true
    fi
fi

pick_available_iphone() {
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

device_is_available() {
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

WORKSPACE=$(find . -maxdepth 1 -name "*.xcworkspace" ! -name "Pods.xcworkspace" | head -n 1)
PROJECT=$(find . -maxdepth 1 -name "*.xcodeproj" ! -name "Pods.xcodeproj" | head -n 1)

if [ -n "$WORKSPACE" ]; then
    PROJECT_FILE="$WORKSPACE"
    PROJECT_FLAG="-workspace"
    PROJECT_NAME=$(basename "$WORKSPACE" .xcworkspace)
elif [ -n "$PROJECT" ]; then
    PROJECT_FILE="$PROJECT"
    PROJECT_FLAG="-project"
    PROJECT_NAME=$(basename "$PROJECT" .xcodeproj)
else
    echo "Error: No .xcworkspace or .xcodeproj found in current directory"
    exit 1
fi

if [ -n "$SCHEME_FLAG" ]; then
    SCHEME="$SCHEME_FLAG"
elif [ -n "${SCHEME:-}" ]; then
    : # Use SCHEME from .env
else
    ALL_SCHEMES=$(xcodebuild -list "$PROJECT_FLAG" "$PROJECT_FILE" 2>/dev/null | sed -n '/Schemes:/,/^$/p' | tail -n +2 | sed 's/^[[:space:]]*//' | grep -v '^$' || true)

    MATCHING_SCHEME=$(echo "$ALL_SCHEMES" | grep -i "^${PROJECT_NAME}$" || true)

    if [ -n "$MATCHING_SCHEME" ]; then
        SCHEME="$MATCHING_SCHEME"
    else
        FIRST_SCHEME=$(echo "$ALL_SCHEMES" | grep -v -i "pods" | head -n 1)
        if [ -n "$FIRST_SCHEME" ]; then
            SCHEME="$FIRST_SCHEME"
        else
            echo "Error: No scheme found. Please specify with --scheme or add SCHEME to .env"
            exit 1
        fi
    fi
fi

if [ -n "${DEVICE_ID:-}" ] && ! device_is_available "$DEVICE_ID"; then
    progress "Warning: DEVICE_ID=$DEVICE_ID is not available; picking another iPhone simulator."
    DEVICE_ID=""
fi

if [ -z "${DEVICE_ID:-}" ]; then
    DEVICE_ID=$(pick_available_iphone || true)
    if [ -z "$DEVICE_ID" ]; then
        echo "Error: No simulator found. Please add DEVICE_ID to .env file"
        echo "Run: xcrun simctl list devices available"
        exit 1
    fi
fi

DESTINATION="platform=iOS Simulator,id=$DEVICE_ID"

# Prefer destination arch=x86_64 on a native (arm64) xcodebuild. Do NOT wrap
# xcodebuild in `arch -x86_64` — modern Xcode's CoreSimulator plugin is arm64-only
# and fails to load under Rosetta.
if [ "$ROSETTA" = true ]; then
    DESTINATION="${DESTINATION},arch=x86_64"
fi

SIMULATOR_NAME=$(xcrun simctl list devices available -j 2>/dev/null | DEVICE_ID="$DEVICE_ID" python3 -c "
import json, os, sys
target = os.environ.get('DEVICE_ID', '')
for runtime, device_list in json.load(sys.stdin).get('devices', {}).items():
    for device in device_list:
        if device.get('udid') == target:
            print(device.get('name', 'unknown'))
            sys.exit(0)
print('unknown')
" || echo "unknown")

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-.derivedData}"
mkdir -p "$DERIVED_DATA_PATH"

# Targets are only listed with -project, not -workspace
if [ -n "$PROJECT" ]; then
    ALL_TARGETS=$(xcodebuild -list -project "$PROJECT" 2>/dev/null | sed -n '/Targets:/,/^$/p' | tail -n +2 | sed 's/^[[:space:]]*//' | grep -v '^$' || true)
else
    ALL_TARGETS=$(xcodebuild -list "$PROJECT_FLAG" "$PROJECT_FILE" 2>/dev/null | sed -n '/Targets:/,/^$/p' | tail -n +2 | sed 's/^[[:space:]]*//' | grep -v '^$' || true)
fi

UNIT_TARGETS=$(echo "$ALL_TARGETS" | grep -E "Tests$" | grep -v "UITests" || true)
UI_TARGETS=$(echo "$ALL_TARGETS" | grep -E "UITests$" || true)

extract_test_failure_details() {
    local test_name="$1"
    local full_output="$2"
    local xcresult_path="$3"
    local method_name=$(echo "$test_name" | sed 's/.*\.//' | sed 's/()$//')

    if [ "$VERBOSE" = true ]; then
        echo "[DEBUG] Extracting failure details for: $test_name" >&2
        echo "[DEBUG] Method name: $method_name" >&2
        echo "[DEBUG] xcresult path: $xcresult_path" >&2
    fi

    if [ -n "$xcresult_path" ] && [ -d "$xcresult_path" ] && command -v xcrun >/dev/null 2>&1; then
        if [ "$VERBOSE" = true ]; then
            echo "[DEBUG] Attempting xcresulttool extraction..." >&2
        fi

        local failure_details=$(xcrun xcresulttool get --format json --path "$xcresult_path" 2>/dev/null |
            jq -r --arg test_name "$test_name" '
            .. | objects |
            select(.testIdentifier? == $test_name or (.identifier? // .name? // .title?) | test($test_name)) |
            (.failureSummary? // .message? // .issueDocument?.message? // empty)' 2>/dev/null |
            grep -v "null" | head -5)

        if [ -n "$failure_details" ] && [ "$failure_details" != "null" ] && [ "$failure_details" != "" ]; then
            echo "$failure_details"
            return
        fi

        local issue_details=$(xcrun xcresulttool get --format json --path "$xcresult_path" 2>/dev/null |
            jq -r --arg test_name "$test_name" '
            .. | objects | select(.issues?) | .issues[] |
            select(.testCaseName? == $test_name or .message | contains($test_name)) |
            .message' 2>/dev/null | head -3)

        if [ -n "$issue_details" ] && [ "$issue_details" != "null" ] && [ "$issue_details" != "" ]; then
            echo "$issue_details"
            return
        fi
    fi

    if [ "$VERBOSE" = true ]; then
        echo "[DEBUG] Searching for error patterns in output..." >&2
    fi

    local swift_testing_errors=$(echo "$full_output" | grep -A 20 -B 5 "$method_name" |
        grep -E "(failed|error|assertion|expectation|Issue recorded|XCTAssert)" | head -5)

    if [ -n "$swift_testing_errors" ]; then
        echo "$swift_testing_errors"
        return
    fi

    local service_errors=$(echo "$full_output" |
        grep -E "\[$method_name\].*❌|\[$method_name\].*failed|❌.*$method_name|error.*$method_name" | head -3)

    if [ -n "$service_errors" ]; then
        echo "$service_errors"
        return
    fi

    local test_context=$(echo "$full_output" | grep -A 15 -B 5 "$test_name")
    local failure_indicators=$(echo "$test_context" | grep -E "(failed|error|assertion|❌|✗|Issue recorded)" | head -3)

    if [ -n "$failure_indicators" ]; then
        echo "$failure_indicators"
        return
    fi

    local nearby_errors=$(echo "$full_output" |
        grep -A 50 -B 10 "Test \"$method_name\"" |
        grep -E "(❌|failed|error|assertion)" | head -3)

    if [ -n "$nearby_errors" ]; then
        echo "$nearby_errors"
        return
    fi

    if [ "$VERBOSE" = true ]; then
        echo "Test failed - detailed context:"
        echo "$test_context" | head -10
        return
    fi

    echo "Test failed - run with --verbose for more details or individually: xcodebuild test -only-testing:\"$test_name\""
}

run_tests() {
    local target="$1"
    local name="$2"

    mkdir -p .test_logs
    log_file=".test_logs/${target}_$(date +%Y%m%d_%H%M%S).log"
    local start_epoch
    start_epoch=$(date +%s)

    progress ""
    progress "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    progress "iOS tests — xcodebuild (via ios-build-test run_tests.sh)"
    progress "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    progress "  Target:      $target ($name)"
    progress "  Project:     $PROJECT_FILE ($PROJECT_FLAG)"
    progress "  Scheme:      $SCHEME"
    progress "  Simulator:   ${SIMULATOR_NAME} (${DEVICE_ID})"
    progress "  Destination: $DESTINATION"
    progress "  DerivedData: $DERIVED_DATA_PATH"
    if [ "$ROSETTA" = true ]; then
        progress "  Mode:        x86_64 destination (native xcodebuild)"
    fi
    progress "  Log file:    $log_file"
    progress ""
    if [ "$VERBOSE" = true ]; then
        progress "Verbose mode: xcodebuild output streams below and is saved to the log."
    else
        progress "Quiet mode: xcodebuild output goes only to the log file."
        progress "            Pass --verbose to stream live output to the terminal."
    fi
    progress ""
    progress "⏳ Tests in progress — typically 1–3 minutes (first run may take longer)."
    progress "   Wait until this script exits and prints ✓ or ✗ for this target."
    progress "   Do not pipe to tail; it hides progress unless /dev/tty is available."
    progress "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    progress ""

    # xcodebuild has no flag to disable its built-in "Restarting after unexpected
    # exit, crash, or test timeout" relaunch loop. We handle that below by killing
    # xcodebuild's process group the moment a crash marker shows up in the log.
    # (Don't add -test-iterations 1 — xcodebuild rejects values < 2.)
    TEST_CMD=(xcodebuild test "$PROJECT_FLAG" "$PROJECT_FILE" -scheme "$SCHEME" -destination "$DESTINATION" -derivedDataPath "$DERIVED_DATA_PATH" -only-testing:"$target")

    # Markers that mean "the test process died, stop waiting for xcodebuild to
    # finish on its own." Kept narrow on purpose: only signatures that
    # unambiguously indicate a crashed xctest process (not assertion failures,
    # which xcodebuild handles normally).
    # Keep in sync with CRASH_PATTERNS below for memory/signal crashes. Anything
    # that means "xctest is dead, xcodebuild is about to relaunch or hang" goes
    # here so the live watcher can SIGTERM the process group immediately rather
    # than waiting minutes for xcodebuild to give up.
    EARLY_KILL_PATTERNS='Restarting after unexpected exit, crash, or test timeout|__BUG_IN_CLIENT_OF_LIBMALLOC|malloc: \*\*\* error|pointer being freed was not allocated|Crashed Thread:|Exception Type:[[:space:]]+EXC_|EXC_BAD_ACCESS|EXC_CRASH|SIGABRT|SIGSEGV|SIGBUS|SIGILL|Message from debugger: killed|terminating with uncaught exception|NSInternalInconsistencyException'

    : > "$log_file"

    set +e
    # Launch xcodebuild in its own process group so we can signal the whole tree
    # (xcodebuild → xctest → testmanagerd helpers) at once. macOS bash has no
    # `setsid`, but `set -m` (job control) puts each backgrounded job in its own
    # process group with the job's pid as the pgid — exactly what we need.
    set -m
    "${TEST_CMD[@]}" >"$log_file" 2>&1 &
    local xcb_pid=$!
    set +m

    # Watch the log live. As soon as a crash marker shows up, kill the whole
    # xcodebuild process group so we don't sit through its automatic relaunch.
    local crash_detected=0
    (
        tail -n +1 -F "$log_file" 2>/dev/null | while IFS= read -r line; do
            if echo "$line" | grep -qE "$EARLY_KILL_PATTERNS"; then
                # Touch a sentinel the parent shell can see; the parent owns
                # the actual kill (subshell can't signal sibling cleanly).
                : > "${log_file}.crash"
                exit 0
            fi
            # Stop tailing once xcodebuild has exited and log is stable.
            if ! kill -0 "$xcb_pid" 2>/dev/null; then
                exit 0
            fi
        done
    ) &
    local tail_pid=$!

    # Poll: either xcodebuild finishes naturally, or the watcher drops a
    # sentinel signalling a crash. Cheap loop, no extra deps.
    local last_heartbeat=0
    while kill -0 "$xcb_pid" 2>/dev/null; do
        if [ -e "${log_file}.crash" ]; then
            crash_detected=1
            # TERM the process group, then escalate.
            kill -TERM "-$xcb_pid" 2>/dev/null || kill -TERM "$xcb_pid" 2>/dev/null || true
            sleep 2
            kill -KILL "-$xcb_pid" 2>/dev/null || kill -KILL "$xcb_pid" 2>/dev/null || true
            # Belt-and-suspenders: stragglers that escaped the group.
            pkill -KILL -f "xctest|testmanagerd" 2>/dev/null || true
            break
        fi
        local now elapsed
        now=$(date +%s)
        elapsed=$((now - start_epoch))
        if [ $((now - last_heartbeat)) -ge 30 ]; then
            progress "⏳ Still running (${elapsed}s elapsed) — log: $log_file"
            last_heartbeat=$now
        fi
        sleep 1
    done

    wait "$xcb_pid" 2>/dev/null
    local exit_code=$?
    kill "$tail_pid" 2>/dev/null || true
    wait "$tail_pid" 2>/dev/null || true
    rm -f "${log_file}.crash"

    if [ "$crash_detected" -eq 1 ] && [ "$exit_code" -eq 0 ]; then
        exit_code=1
    fi

    output=$(cat "$log_file")
    if [ "$VERBOSE" = true ]; then
        # Surface the captured output to the terminal, matching prior `tee` behavior.
        printf '%s\n' "$output"
    fi
    set -e

    local elapsed_total=$(( $(date +%s) - start_epoch ))
    local elapsed_min=$(( elapsed_total / 60 ))
    local elapsed_sec=$(( elapsed_total % 60 ))

    progress "Log saved to: $log_file (${elapsed_min}m ${elapsed_sec}s)"

    if echo "$output" | grep -q "BUILD FAILED\|fatal error:\|error:.*\.swift\|Build input file cannot be found\|Compilation failed"; then
        echo "💥 $name: Build failed"
        echo ""
        echo "🔥 Build Errors:"
        echo "$output" | grep -E "error:.*\.swift|fatal error:|Build input file cannot be found|.*\.swift:[0-9]+:[0-9]+: error:" | head -15 | sed 's/^/   /'
        echo ""
        echo "📋 Build Output (last 20 lines):"
        echo "$output" | tail -20 | sed 's/^/   /'
        return 1
    fi

    if echo "$output" | grep -q "Unable to find a destination\|does not contain a scheme"; then
        echo "💥 $name: Configuration error"
        echo ""
        echo "🔧 Configuration Issues:"
        echo "$output" | grep -E "Unable to find a destination|does not contain a scheme" | sed 's/^/   /'
        return 1
    fi

    # Crash detection: surface Swift runtime crashes (assertionFailure / fatalError /
    # preconditionFailure), memory corruption, signal crashes, and unexpected-exit
    # restarts. xcodebuild may keep going and report pass/fail counts that look fine,
    # or exit 0 entirely, so we scan the raw output for crash signatures and treat
    # any hit as a test failure regardless of xcodebuild's own exit code.
    #
    # Exclude host-app bootstrap noise: xcodebuild often logs "Test crashed with signal
    # kill before establishing connection" for the app host while the xctest bundle still
    # runs and ends with ** TEST SUCCEEDED **.
    CRASH_PATTERNS="Fatal error:|precondition failed:|Swift/[A-Za-z]+\.swift:[0-9]+: Fatal error|Restarting after unexpected exit, crash, or test timeout|Test crashed|test process .* (crashed|exited)|EXC_BAD_ACCESS|EXC_BAD_INSTRUCTION|EXC_CRASH|EXC_RESOURCE|SIGABRT|SIGKILL|SIGSEGV|SIGBUS|SIGILL|terminating with uncaught exception|NSInternalInconsistencyException|libsystem_kernel.*__pthread_kill|Thread [0-9]+ [Cc]rashed|Crashed Thread:|Exception Type:[[:space:]]+EXC_|received signal SIG[A-Z]+|caught signal SIG[A-Z]+|malloc:.*error|pointer being freed was not allocated|__BUG_IN_CLIENT_OF_LIBMALLOC|__deallocating_deinit|RESOLVER:.*not resolved|Message from debugger: killed"
    CRASH_IGNORE_PATTERNS="\[Crashlytics\]|non-Crashlytics handler|GADRegisterSignalHandlers|will interfere with reporting|before establishing connection|Early unexpected exit, operation never finished bootstrapping|operation never finished bootstrapping"

    crash_lines=$(echo "$output" | grep -nE "$CRASH_PATTERNS" \
        | grep -vE "$CRASH_IGNORE_PATTERNS" \
        || true)

    final_test_banner=$(echo "$output" | grep -E '\*\* TEST (SUCCEEDED|FAILED) \*\*' | tail -1 || true)
    if [ -n "$crash_lines" ] && echo "$final_test_banner" | grep -q "TEST SUCCEEDED"; then
        if echo "$output" | grep -qE '✔ Test run with [0-9]+ tests.*passed|Test Case .* passed'; then
            crash_lines=""
        fi
    fi

    if [ -n "$crash_lines" ]; then
        # ANSI red for visibility (gracefully ignored if terminal doesn't support color)
        RED=$'\033[1;31m'
        RESET=$'\033[0m'
        echo ""
        echo "${RED}========================================${RESET}"
        echo "${RED}=== TEST PROCESS CRASHED ===${RESET}"
        echo "${RED}========================================${RESET}"
        echo "💥 $name: Test process crashed (xcodebuild exit=$exit_code)"
        echo ""
        echo "🔥 Crash Signatures (first 15):"
        echo "$crash_lines" | head -15 | sed 's/^/   /'

        # Extract crashing test from "Restarting after unexpected exit, crash, or
        # test timeout in <TestClass>.<testMethod>()" — the most reliable signal.
        crashing_tests=$(echo "$output" \
            | grep -oE "Restarting after unexpected exit, crash, or test timeout in [^[:space:]]+(\.[^[:space:]]+)?" \
            | sed 's/Restarting after unexpected exit, crash, or test timeout in //' \
            | sort -u)
        # Also catch "<TestClass>.<testMethod>() ... crashed" style lines
        crashing_methods=$(echo "$output" \
            | grep -oE "[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*\(\)[^[:space:]]* (crashed|failed to terminate)" \
            | sort -u)
        if [ -n "$crashing_tests" ] || [ -n "$crashing_methods" ]; then
            echo ""
            echo "💀 Crashing test(s):"
            [ -n "$crashing_tests" ]   && echo "$crashing_tests"   | sed 's/^/   - /'
            [ -n "$crashing_methods" ] && echo "$crashing_methods" | sed 's/^/   - /'
        fi

        fatal_msgs=$(echo "$output" | grep -E "Fatal error:|precondition failed:|NSInternalInconsistencyException|pointer being freed was not allocated|__BUG_IN_CLIENT_OF_LIBMALLOC|malloc:.*error|Exception Type:|Crashed Thread:" | head -8)
        if [ -n "$fatal_msgs" ]; then
            echo ""
            echo "📍 Fatal messages:"
            echo "$fatal_msgs" | sed 's/^/   /'
        fi

        # Show ~30 lines of context around the first crash marker — useful for
        # seeing the top of a backtrace when xcodebuild interleaves it inline.
        first_crash_line=$(echo "$crash_lines" | head -1 | cut -d: -f1)
        if [ -n "$first_crash_line" ] && [[ "$first_crash_line" =~ ^[0-9]+$ ]]; then
            start=$(( first_crash_line > 5 ? first_crash_line - 5 : 1 ))
            end=$(( first_crash_line + 25 ))
            echo ""
            echo "🧵 Context around first crash marker (lines ${start}-${end}):"
            echo "$output" | sed -n "${start},${end}p" | sed 's/^/   /'
        fi

        # Surface xcresult bundle (if xcodebuild emitted one) and the macOS
        # DiagnosticReports directory — the OS dumps a full .ips crash report
        # there for xctest process aborts (e.g. malloc bug) that xcodebuild
        # itself doesn't capture.
        xcresult_path=$(echo "$output" | grep -oE '/[^[:space:]]+\.xcresult' | tail -1)
        if [ -n "$xcresult_path" ]; then
            echo ""
            echo "📦 xcresult bundle: $xcresult_path"
        fi
        echo ""
        echo "🩺 Look for a recent xctest crash report in:"
        echo "   ~/Library/Logs/DiagnosticReports/"
        echo "   (hint: ls -t ~/Library/Logs/DiagnosticReports/ | head -5)"

        echo ""
        echo "📋 Full log: $log_file"
        echo "${RED}========================================${RESET}"
        # Force non-zero return even if xcodebuild itself returned 0
        return 1
    fi

    if echo "$output" | grep -q "Test run with.*tests\? "; then
        swift_test_summary=$(echo "$output" | grep -E "Test run with [0-9]+ tests?" | tail -1)

        if [ -n "$swift_test_summary" ]; then
            if echo "$swift_test_summary" | grep -q "✔ Test run with.*passed"; then
                total=$(echo "$swift_test_summary" | grep -o '[0-9]\+ tests\?' | head -1 | grep -o '[0-9]\+' || echo "")
                if [ -n "$total" ]; then
                    passed="$total"
                    failed="0"
                else
                    passed="0"
                    failed="0"
                fi
            elif echo "$swift_test_summary" | grep -q "✘ Test run with.*failed"; then
                total=$(echo "$swift_test_summary" | grep -o '[0-9]\+ tests\?' | head -1 | grep -o '[0-9]\+' || echo "")
                issues=$(echo "$swift_test_summary" | grep -o 'with [0-9]\+ issues\?' | grep -o '[0-9]\+' || echo "")

                if [ -n "$total" ] && [ -n "$issues" ]; then
                    failed="$issues"
                    passed=$((total - issues))
                else
                    passed="0"
                    failed="0"
                fi
            else
                passed="0"
                failed="0"
            fi
        else
            passed="0"
            failed="0"
        fi

        filtered_output=$(echo "$output" | grep -E "(✔ Test.*passed|✗ Test.*failed|✘ Test.*failed|◇ Test.*started)" || true)
    else
        filtered_output=$(echo "$output" | grep -iE "(Test Case|Test Suite.*failed|Test Suite.*passed)" || true)

        # Prefer xcodebuild's summary line (authoritative). Fall back to counting
        # per-case outcome lines anchored on "' passed (" / "' failed (" so test
        # method names containing "failed" (e.g. testFoo_failedLoad_bar) are not
        # miscounted as failures.
        executed_summary=$(echo "$output" | grep -E "Executed [0-9]+ tests?, with [0-9]+ failures?" | tail -1 || true)
        if [ -n "$executed_summary" ]; then
            total=$(echo "$executed_summary" | grep -oE 'Executed [0-9]+' | grep -oE '[0-9]+' || echo "0")
            failed=$(echo "$executed_summary" | grep -oE 'with [0-9]+ failures?' | grep -oE '[0-9]+' || echo "0")
            passed=$((total - failed))
        else
            passed=$(echo "$filtered_output" | grep -icE "Test Case '.*' passed \(" || true)
            failed=$(echo "$filtered_output" | grep -icE "Test Case '.*' failed \(" || true)
        fi
    fi

    passed=$(echo "$passed" | tr -d ' \t\n\r')
    failed=$(echo "$failed" | tr -d ' \t\n\r')

    if [ -z "$passed" ] || [ -z "$failed" ] || ! [[ "$passed" =~ ^[0-9]+$ ]] || ! [[ "$failed" =~ ^[0-9]+$ ]]; then
        echo "⚠️ $name: Failed to parse test results"
        echo ""
        echo "🔍 Debug Output (last 10 lines):"
        echo "$output" | tail -10 | sed 's/^/   /'
        return 1
    fi

    total=$((passed + failed))

    if [ "$failed" -eq 0 ] && [ "$total" -gt 0 ]; then
        echo "✅ $name: $total tests - $passed passed, $failed failed"
        return 0
    elif [ "$total" -eq 0 ]; then
        if [ "$exit_code" -eq 0 ] && echo "$output" | grep -q "\*\* TEST SUCCEEDED \*\*"; then
            echo "✅ $name: Tests passed (0 test cases counted — xcodebuild reported success)"
            return 0
        fi
        echo "⚠️ $name: No tests found or build failed"
        if [ "$exit_code" -ne 0 ]; then
            echo ""
            echo "🔍 Debug Information:"
            echo "$output" | grep -E "Testing failed|BUILD FAILED|No tests|error:|fatal error:" | head -10 | sed 's/^/   /'
            echo ""
            echo "🔍 Full Build Output (last 30 lines):"
            echo "$output" | tail -30 | sed 's/^/   /'
        fi
        return 1
    else
        echo "❌ $name: $total tests - $passed passed, $failed failed"
        echo ""

        if echo "$output" | grep -q "✗.*failed\|✘.*failed\|Failing tests:"; then
            echo "   Failed tests:"
            if echo "$filtered_output" | grep -q "✗.*failed\|✘.*failed"; then
                echo "$filtered_output" | grep -E "✗.*failed|✘.*failed" | sed 's/^/   - /'
            fi
            if echo "$output" | grep -q "Failing tests:"; then
                echo "$output" | sed -n '/Failing tests:/,/^$/p' | grep -E "^\s*[A-Za-z].*\(\)" | sed 's/^/   - /'
            fi
            echo ""
            echo "   Detailed Failures:"

            if echo "$output" | grep -q "Failing tests:"; then
                failed_tests=$(echo "$output" | sed -n '/Failing tests:/,/^$/p' | grep -E "^\s*[A-Za-z].*\(\)" | sed 's/^\s*//' | sed 's/()$//')
            else
                failed_tests=$(echo "$filtered_output" | grep -E "✗.*failed|✘.*failed" | sed 's/.*Test "//' | sed 's/" failed.*//')
            fi
        else
            echo "   Failed tests:"
            echo "$filtered_output" | grep -E "Test Case '.*' failed \(" | sed 's/.*Test Case /   - /' | sed 's/ failed.*//' | sed "s/'//g"
            echo ""
            echo "   Detailed Failures:"

            failed_tests=$(echo "$filtered_output" | grep -E "Test Case '.*' failed \(" | sed 's/.*Test Case //' | sed 's/ failed.*//' | sed "s/'//g")
        fi

        xcresult_path=$(echo "$output" | grep -o '/.*\.xcresult' | tail -1)

        while IFS= read -r test_name; do
            if [ -n "$test_name" ]; then
                echo "   📍 $test_name:"

                failure_details=$(extract_test_failure_details "$test_name" "$output" "$xcresult_path")

                if [ -n "$failure_details" ]; then
                    echo "$failure_details" | while IFS= read -r error_line; do
                        if [ -n "$error_line" ]; then
                            clean_line=$(echo "$error_line" | sed 's/^[0-9-]* [0-9:]* *[+-][0-9]* //' | sed 's/\[.*\] //' | sed 's/❌ //')

                            file_info=$(echo "$error_line" | grep -o '[^/]*\.swift:[0-9]*')

                            if [ -n "$file_info" ]; then
                                echo "      ❌ $clean_line ($file_info)"
                            else
                                echo "      ❌ $clean_line"
                            fi
                        fi
                    done
                else
                    echo "      ❌ Test failed - run with --verbose or check:"
                    echo "         xcodebuild test -only-testing:\"$test_name\" -enableCodeCoverage NO"
                fi
                echo ""
            fi
        done <<< "$failed_tests"

        return 1
    fi
}

overall_failures=0

if [ "$TEST_TYPE" = "single" ]; then
    if [ -z "$TEST_IDENTIFIER" ]; then
        echo "Error: single test type requires a test target name"
        echo "Usage: $0 single <target>"
        exit 1
    fi

    run_tests "$TEST_IDENTIFIER" "Single Test Target" || overall_failures=1
elif [ "$TEST_TYPE" = "unit" ]; then
    if [ -z "$UNIT_TARGETS" ]; then
        echo "⚠️ No unit test targets found"
        echo "   Available targets: $(echo "$ALL_TARGETS" | tr '\n' ' ')"
        exit 1
    fi

    while IFS= read -r target; do
        if [ -n "$target" ]; then
            run_tests "$target" "Unit Tests" || overall_failures=1
        fi
    done <<< "$UNIT_TARGETS"
elif [ "$TEST_TYPE" = "ui" ]; then
    if [ -z "$UI_TARGETS" ]; then
        echo "⚠️ No UI test targets found"
        echo "   Available targets: $(echo "$ALL_TARGETS" | tr '\n' ' ')"
        exit 1
    fi

    while IFS= read -r target; do
        if [ -n "$target" ]; then
            run_tests "$target" "UI Tests" || overall_failures=1
        fi
    done <<< "$UI_TARGETS"
else
    if [ -n "$UNIT_TARGETS" ]; then
        while IFS= read -r target; do
            if [ -n "$target" ]; then
                run_tests "$target" "Unit Tests" || overall_failures=1
            fi
        done <<< "$UNIT_TARGETS"
    fi

    if [ -n "$UI_TARGETS" ]; then
        while IFS= read -r target; do
            if [ -n "$target" ]; then
                run_tests "$target" "UI Tests" || overall_failures=1
            fi
        done <<< "$UI_TARGETS"
    fi

    if [ -z "$UNIT_TARGETS" ] && [ -z "$UI_TARGETS" ]; then
        echo "⚠️ No test targets found"
        echo "   Available targets: $(echo "$ALL_TARGETS" | tr '\n' ' ')"
        exit 1
    fi
fi

echo ""
echo "=================="
if [ $overall_failures -eq 0 ]; then
    echo "🎉 All tests passed!"
else
    echo "💥 Some tests failed!"
fi
echo "=================="

exit $overall_failures
