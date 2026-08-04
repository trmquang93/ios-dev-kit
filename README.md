# ios-dev-kit

A Claude Code plugin bundling skills for **iOS app development** — from SwiftUI best practices and Apple platform APIs through build/test automation, simulator control, localization, and structured debugging.

## Skills

| Skill | What it does |
|-------|----------------|
| **ios-application-dev** | Broad iOS app development guide — UIKit, SwiftUI, navigation, accessibility, Liquid Glass, Foundation Models, StoreKit, visionOS widgets, and more |
| **swiftui-specialist** | Authoritative SwiftUI best practices from Apple — performance, `@Observable`, `ForEach` identity, localization, soft-deprecated APIs |
| **apple-dev** | Apple platform reference docs — SwiftUI, UIKit, AppKit, WidgetKit, SwiftData, AppIntents, MapKit, FoundationModels |
| **ios-build-test** | Build and test Xcode projects via `build.sh` / `run_tests.sh` — **always use these instead of raw `xcodebuild`** |
| **debug-ios** | Systematic bug workflow — structured logs, unit-test repros, console analysis, cleanup |
| **agent-device** | Simulator/device automation — snapshots, tap, type, scroll, UI inspection (preferred over raw `idb`/`simctl`) |
| **xcode-project** | Add/remove file references in `project.pbxproj` via Ruby xcodeproj gem |
| **sync-string-catalog** | Build project and merge compiler-extracted strings into `Localizable.xcstrings` |
| **ios-localization** | Translate `Localizable.xcstrings` to multiple languages |
| **hero-swiftui** | Hero shared-element transitions in SwiftUI apps with UIKit navigation wrappers |

## Layout

```
ios-dev-kit/
├── .claude-plugin/
│   ├── plugin.json
│   └── marketplace.json
└── skills/
    ├── ios-application-dev/     ← SKILL.md + references/
    ├── swiftui-specialist/      ← SKILL.md + references/
    ├── apple-dev/               ← SKILL.md + docs/
    ├── ios-build-test/          ← SKILL.md + scripts/build.sh, run_tests.sh
    ├── debug-ios/               ← SKILL.md + references/
    ├── agent-device/            ← SKILL.md + references/
    ├── xcode-project/           ← SKILL.md + scripts/xcodeproj_helper.rb
    ├── sync-string-catalog/     ← SKILL.md + scripts/sync_string_catalog.sh
    ├── ios-localization/        ← SKILL.md + scripts/*.py
    └── hero-swiftui/            ← SKILL.md + HeroContainer.swift
```

## Install from GitHub

### Claude Code (plugin marketplace)

```
/plugin marketplace add trmquang93/ios-dev-kit
/plugin install ios-dev-kit@ios-dev-kit-marketplace
```

### Any agent via [`vercel-labs/skills`](https://github.com/vercel-labs/skills)

```bash
# List the skills in this repo
npx skills add trmquang93/ios-dev-kit --list

# Install all skills, prompting which agents to target
npx skills add trmquang93/ios-dev-kit --skill '*'

# Or install a single skill to a specific agent
npx skills add trmquang93/ios-dev-kit -s ios-build-test -a claude-code
npx skills add trmquang93/ios-dev-kit -s swiftui-specialist -a cursor
```

Skills land in the agent's standard skill directory (e.g. `.claude/skills/`, `.cursor/skills/`). Bundled scripts under each skill's `scripts/` directory ship alongside `SKILL.md`.

## Typical workflow

1. `/ios-application-dev` or `/swiftui-specialist` — implement or review SwiftUI/UIKit code against Apple conventions.
2. `/xcode-project add MyView.swift --target MyApp` — register new files in the Xcode project.
3. `/sync-string-catalog` — extract new `Text("…")` strings into `Localizable.xcstrings`.
4. `/ios-localization` — add translations for target languages.
5. `/ios-build-test` — compile and run tests (`build.sh` / `run_tests.sh`; never pipe output).
6. `/agent-device` — drive the simulator to verify UI behavior.
7. `/debug-ios` — investigate failures with structured logging and test repros.

## Requirements

- macOS with Xcode installed (for build, test, simulator, and string-catalog skills)
- Ruby + `xcodeproj` gem (for `xcode-project`)
- Python 3 (for `ios-localization` scripts)
