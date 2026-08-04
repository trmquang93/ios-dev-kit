---
name: sync-string-catalog
description: Use when you need to sync the string catalog — build an iOS Xcode project and merge compiler-extracted Swift strings into Localizable.xcstrings via xcstringstool. Invoke after adding Text("…") or LocalizedStringKey copy, when the user says sync/update/extract string catalog, or before ios-localization translations.
allowed-tools: Bash, Read, Grep, Glob
---

# Sync String Catalog

Merge compiler-extracted strings into a project's `.xcstrings` String Catalog.

## When to use

- After adding or changing user-facing copy in Swift
- User asks to sync, update, or extract the string catalog
- Before translating new keys with the `ios-localization` skill

## Critical rules

1. **Never edit `Localizable.xcstrings` manually.**
2. Add copy as string **literals** in Swift so the compiler can extract them:
   - `Text("My label")`
   - `String(localized: "My label")`
   - `Button("Save") { … }`
3. Strings passed through variables are **not** extracted — e.g. `Text(LocalizedStringKey(someVariable))` will not appear in the catalog.
4. `xcodebuild` and Xcode UI builds alone do **not** write the source catalog. This skill runs `xcstringstool sync` after a build.

## Run the script

From the **Xcode project root** (directory containing `.xcodeproj` or `.xcworkspace`):

```bash
${CLAUDE_SKILL_DIR}/scripts/sync_string_catalog.sh $ARGUMENTS
```

`${CLAUDE_SKILL_DIR}` is the directory containing this `SKILL.md` (e.g. `~/.claude/skills/sync-string-catalog`).

### Flags

| Flag | Effect |
|------|--------|
| *(none)* | Headless simulator build via `ios-build-test`, then sync |
| `--open-xcode` | Same build + sync, then open the project in Xcode |
| `--xcode` | Open Xcode, build via AppleScript, then sync |
| `--scheme NAME` | Xcode scheme (default: `SCHEME` from `.env`, else auto-detect) |
| `--catalog PATH` | `.xcstrings` file (default: first `Localizable.xcstrings` found) |
| `--target NAME` | App target for `.stringsdata` (default: scheme name) |
| `--derived-data DIR` | DerivedData path (default: `./.derivedData`) |

## Agent workflow

1. `cd` to the iOS project root.
2. Confirm new/changed strings use literal `Text("…")` or `String(localized:)` in Swift — fix if they use indirect keys.
3. Run `${CLAUDE_SKILL_DIR}/scripts/sync_string_catalog.sh` with user flags.
4. Wait for the script to exit. Success lines:
   - `✓ Build succeeded`
   - `✓ Localizable.xcstrings updated.` or `Note: catalog timestamp unchanged`
5. If the user wants translations, hand off to the `ios-localization` skill **after** sync.

## Auto-detection

| Item | Detection |
|------|-----------|
| Project | First `.xcworkspace` or `.xcodeproj` in cwd (excludes Pods) |
| Scheme | `--scheme`, then `.env` `SCHEME`, then name matching project, then first non-Pods scheme |
| Catalog | First `Localizable.xcstrings` not under DerivedData/Pods |
| Target | `--target`, else scheme name (used to locate `*.build/Objects-normal/*.stringsdata`) |

## Prerequisites

- Xcode installed (`xcstringstool` via `xcrun --find xcstringstool`)
- `ios-build-test` skill at `~/.claude/skills/ios-build-test/scripts/build.sh`
- Optional `.env` with `DEVICE_ID` and `SCHEME`

## What the script does

1. Builds the app for iOS Simulator (DerivedData at `.derivedData` by default)
2. Collects `.stringsdata` from the app target's `Objects-normal` folder
3. Runs `xcstringstool sync` into the catalog file

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `No .stringsdata files found` | Pass `--target <app-target>` if it differs from scheme; try `--xcode` or clean DerivedData |
| `No Localizable.xcstrings found` | Pass `--catalog path/to/File.xcstrings` |
| `ios-build-test build script not found` | Install the `ios-build-test` skill |
| Catalog unchanged after sync | Strings may be indirect — use literals in Swift, rebuild, sync again |
| Simulator not found | Set `DEVICE_ID` in `.env` to an available simulator |

## Related

- `ios-localization` skill — translate keys after they exist in the catalog
- `ios-build-test` skill — underlying build script
