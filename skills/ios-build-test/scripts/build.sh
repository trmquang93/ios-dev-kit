#!/usr/bin/env bash
set -euo pipefail

ROSETTA=false
ROSETTA_CLI=false
VERBOSE=false
SCHEME_FLAG=""
EXTRA_ARGS=()

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
        *)
            EXTRA_ARGS+=("$1")
            shift
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
    echo "Run this script from the directory that contains the app workspace/project (not Pods.xcworkspace)."
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
    echo "Warning: DEVICE_ID=$DEVICE_ID is not available; picking another iPhone simulator."
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
mkdir -p "$DERIVED_DATA_PATH" .build_logs
LOG_FILE=".build_logs/build_$(date +%Y%m%d_%H%M%S).log"
START_EPOCH=$(date +%s)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "iOS build — xcodebuild (via ios-build-test build.sh)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Project:     $PROJECT_FILE ($PROJECT_FLAG)"
echo "  Scheme:      $SCHEME"
echo "  Simulator:   ${SIMULATOR_NAME} (${DEVICE_ID})"
echo "  Destination: $DESTINATION"
echo "  DerivedData: $DERIVED_DATA_PATH"
if [ "$ROSETTA" = true ]; then
    echo "  Mode:        x86_64 destination (native xcodebuild)"
fi
if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    echo "  Extra args:  ${EXTRA_ARGS[*]}"
fi
echo "  Log file:    $LOG_FILE"
echo ""
if [ "$VERBOSE" = true ]; then
    echo "Verbose mode: xcodebuild output streams below and is saved to the log."
else
    echo "Quiet mode: xcodebuild output goes only to the log file."
    echo "            Pass --verbose to stream live output to the terminal."
fi
echo ""
echo "⏳ Build in progress — typically 1–5 minutes (large projects may take longer)."
echo "   Wait until this script exits and prints ✓ Build succeeded or ✗ Build failed."
echo "   Do not treat partial output as success; read the final status line."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    BUILD_CMD=(xcodebuild "$PROJECT_FLAG" "$PROJECT_FILE" -scheme "$SCHEME" -destination "$DESTINATION" -derivedDataPath "$DERIVED_DATA_PATH" build "${EXTRA_ARGS[@]}")
else
    BUILD_CMD=(xcodebuild "$PROJECT_FLAG" "$PROJECT_FILE" -scheme "$SCHEME" -destination "$DESTINATION" -derivedDataPath "$DERIVED_DATA_PATH" build)
fi

if [ "$VERBOSE" = true ]; then
    "${BUILD_CMD[@]}" 2>&1 | tee "$LOG_FILE"
    BUILD_STATUS=${PIPESTATUS[0]}
else
    "${BUILD_CMD[@]}" > "$LOG_FILE" 2>&1
    BUILD_STATUS=$?
fi

ELAPSED=$(( $(date +%s) - START_EPOCH ))
ELAPSED_MIN=$(( ELAPSED / 60 ))
ELAPSED_SEC=$(( ELAPSED % 60 ))

# Always scan the log for compile errors, regardless of xcodebuild's exit code.
# xcodebuild can occasionally report success (exit 0) while individual targets
# in the build graph emitted compile errors — particularly with incremental
# builds, filesystem-synchronized groups, and locally-resolved SPM packages.
# We canonicalize on the swiftc/clang error pattern: "path/to/file.ext:LINE:COL: error: ..."
# and on the fatal banners "** BUILD FAILED **" / "BUILD INTERRUPTED".
COMPILE_ERRORS=$(grep -E "^/.+:[0-9]+:[0-9]+: error: " "$LOG_FILE" || true)
FATAL_BANNER=$(grep -E "\*\* BUILD FAILED \*\*|BUILD INTERRUPTED" "$LOG_FILE" || true)

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$COMPILE_ERRORS" ] || [ -n "$FATAL_BANNER" ] || [ $BUILD_STATUS -ne 0 ]; then
    echo "✗ Build failed (${ELAPSED_MIN}m ${ELAPSED_SEC}s, xcodebuild exit ${BUILD_STATUS})"
    echo "  Log: $LOG_FILE"
    echo ""
    if [ -n "$COMPILE_ERRORS" ] && [ $BUILD_STATUS -eq 0 ]; then
        echo "WARNING: xcodebuild exited 0 but the log contains compile errors. Treating as failure."
        echo ""
    fi
    echo "Errors (summary):"
    if [ -n "$COMPILE_ERRORS" ]; then
        echo "$COMPILE_ERRORS"
    else
        grep -E "error:" "$LOG_FILE" | grep -v "LLVM Profile Error" | tail -20 || echo "(no error lines matched — see log file)"
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Read the full log:"
    echo "       less \"$LOG_FILE\""
    echo "  2. Grep compile errors:"
    echo "       grep -E '^/.+:[0-9]+:[0-9]+: error: ' \"$LOG_FILE\" | tail -30"
    echo "  3. Re-run with live output:"
    echo "       $0 --verbose --scheme \"$SCHEME\""
    if [ "$ROSETTA" = true ]; then
        echo "     (keep --rosetta if you used it above)"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi

echo "✓ Build succeeded (${ELAPSED_MIN}m ${ELAPSED_SEC}s)"
echo "  Log: $LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit 0
