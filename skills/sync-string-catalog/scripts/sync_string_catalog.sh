#!/usr/bin/env bash
# Build an iOS Xcode project and merge compiler-extracted strings into a .xcstrings catalog.
#
# xcodebuild alone does not write back to the source catalog; this script runs
# `xcstringstool sync` after a build to apply .stringsdata → .xcstrings.
#
# Usage:
#   sync_string_catalog.sh [options]
#
# Options:
#   --scheme NAME       Xcode scheme (default: SCHEME from .env, else auto-detect)
#   --catalog PATH      Path to .xcstrings file (default: first Localizable.xcstrings found)
#   --target NAME       App target whose .stringsdata to sync (default: scheme name)
#   --derived-data DIR  DerivedData path (default: ./.derivedData)
#   --open-xcode        Open the project in Xcode when done
#   --xcode             Build via Xcode UI (AppleScript), then sync
#   -h, --help          Show help
#
set -euo pipefail

OPEN_XCODE=false
XCODE_BUILD=false
SCHEME_FLAG=""
CATALOG_FLAG=""
TARGET_FLAG=""
DERIVED_DATA=""

usage() {
    sed -n '2,18p' "$0"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --open-xcode) OPEN_XCODE=true; shift ;;
        --xcode) XCODE_BUILD=true; OPEN_XCODE=true; shift ;;
        --scheme) SCHEME_FLAG="$2"; shift 2 ;;
        --catalog) CATALOG_FLAG="$2"; shift 2 ;;
        --target) TARGET_FLAG="$2"; shift 2 ;;
        --derived-data) DERIVED_DATA="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ -f .env ]]; then
    set -a
    # shellcheck source=/dev/null
    source .env
    set +a
fi

WORKSPACE=$(find . -maxdepth 1 -name "*.xcworkspace" ! -name "Pods.xcworkspace" | head -n 1)
PROJECT=$(find . -maxdepth 1 -name "*.xcodeproj" ! -name "Pods.xcodeproj" | head -n 1)

if [[ -n "${WORKSPACE}" ]]; then
    PROJECT_PATH="${WORKSPACE}"
    PROJECT_FLAG="-workspace"
    PROJECT_NAME=$(basename "${WORKSPACE}" .xcworkspace)
elif [[ -n "${PROJECT}" ]]; then
    PROJECT_PATH="${PROJECT}"
    PROJECT_FLAG="-project"
    PROJECT_NAME=$(basename "${PROJECT}" .xcodeproj)
else
    echo "Error: No .xcworkspace or .xcodeproj found in $(pwd)" >&2
    exit 1
fi

if [[ -n "${SCHEME_FLAG}" ]]; then
    SCHEME="${SCHEME_FLAG}"
elif [[ -n "${SCHEME:-}" ]]; then
    SCHEME="${SCHEME}"
else
    ALL_SCHEMES=$(xcodebuild -list "${PROJECT_FLAG}" "${PROJECT_PATH}" 2>/dev/null \
        | sed -n '/Schemes:/,/^$/p' | tail -n +2 | sed 's/^[[:space:]]*//' | grep -v '^$' || true)
    MATCHING_SCHEME=$(echo "${ALL_SCHEMES}" | grep -i "^${PROJECT_NAME}$" || true)
    if [[ -n "${MATCHING_SCHEME}" ]]; then
        SCHEME="${MATCHING_SCHEME}"
    else
        SCHEME=$(echo "${ALL_SCHEMES}" | grep -v -i "pods" | head -n 1)
    fi
fi

if [[ -z "${SCHEME}" ]]; then
    echo "Error: No scheme found. Pass --scheme or set SCHEME in .env" >&2
    exit 1
fi

if [[ -n "${CATALOG_FLAG}" ]]; then
    XCSTRINGS="${CATALOG_FLAG}"
else
    XCSTRINGS=$(find . -name "Localizable.xcstrings" \
        ! -path "*/DerivedData/*" \
        ! -path "*/.derivedData/*" \
        ! -path "*/.build/*" \
        ! -path "*/Pods/*" \
        2>/dev/null | head -n 1)
fi

if [[ -z "${XCSTRINGS}" || ! -f "${XCSTRINGS}" ]]; then
    echo "Error: No Localizable.xcstrings found. Pass --catalog PATH" >&2
    exit 1
fi

TARGET="${TARGET_FLAG:-${SCHEME}}"
DERIVED_DATA="${DERIVED_DATA:-$(pwd)/.derivedData}"
BUILD_SCRIPT="${HOME}/.claude/skills/ios-build-test/scripts/build.sh"
XCSTRINGSTOOL="$(xcrun --find xcstringstool)"
PROJECT_ROOT="$(pwd)"

catalog_mtime_before="$(stat -f "%m" "${XCSTRINGS}")"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "String catalog sync — ${SCHEME}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Project:  ${PROJECT_PATH}"
echo "  Catalog:  ${XCSTRINGS}"
echo "  Target:   ${TARGET}"
echo "  Derived:  ${DERIVED_DATA}"

if [[ "${XCODE_BUILD}" == true ]]; then
    echo "Opening Xcode and building..."
    open -a Xcode "${PROJECT_ROOT}/${PROJECT_PATH}"
    sleep 3
    if ! osascript - "${PROJECT_ROOT}/${PROJECT_PATH}" <<'APPLESCRIPT'
on run argv
    set projectPath to item 1 of argv
    tell application "Xcode"
        activate
        if (count of workspace documents) = 0 then
            open POSIX file projectPath
            delay 2
        end if
        set doc to workspace document 1
        build doc
    end tell
end run
APPLESCRIPT
    then
        echo "Error: Xcode build failed." >&2
        exit 1
    fi
    echo "Xcode build finished."
else
    if [[ ! -x "${BUILD_SCRIPT}" ]]; then
        echo "Error: ios-build-test build script not found at ${BUILD_SCRIPT}" >&2
        exit 1
    fi
    echo "Building ${SCHEME} (simulator)..."
    DERIVED_DATA_PATH="${DERIVED_DATA}" "${BUILD_SCRIPT}" --scheme "${SCHEME}"
fi

stringsdata_dir="${DERIVED_DATA}/Build/Intermediates.noindex"
stringsdata_count="$(find "${stringsdata_dir}" \
    -path "*/${TARGET}.build/Objects-normal/*/*.stringsdata" \
    ! -path "*Tests.build/*" \
    ! -path "*UITests.build/*" \
    2>/dev/null | wc -l | tr -d ' ')"

if [[ "${stringsdata_count}" -eq 0 ]]; then
    echo "Error: No .stringsdata files found for target '${TARGET}' under ${stringsdata_dir}" >&2
    echo "Hint: pass --target <app-target-name>, use --xcode, or delete DerivedData and retry." >&2
    exit 1
fi

echo "Syncing ${stringsdata_count} .stringsdata files into $(basename "${XCSTRINGS}")..."
find "${stringsdata_dir}" \
    -path "*/${TARGET}.build/Objects-normal/*/*.stringsdata" \
    ! -path "*Tests.build/*" \
    ! -path "*UITests.build/*" \
    -print0 | xargs -0 "${XCSTRINGSTOOL}" sync "${XCSTRINGS}" --stringsdata

catalog_mtime_after="$(stat -f "%m" "${XCSTRINGS}")"

if [[ "${catalog_mtime_before}" == "${catalog_mtime_after}" ]]; then
    echo "Note: catalog timestamp unchanged — no new strings detected in this build."
else
    echo "✓ $(basename "${XCSTRINGS}") updated."
fi

if [[ "${OPEN_XCODE}" == true && "${XCODE_BUILD}" == false ]]; then
    echo "Opening Xcode..."
    open -a Xcode "${PROJECT_ROOT}/${PROJECT_PATH}"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Done. Review ${XCSTRINGS} in Xcode's String Catalog editor."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
