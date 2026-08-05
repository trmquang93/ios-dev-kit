# SwiftUI Layout Debug Pattern

For **visual/layout bugs** — elements jumping, resizing, or animating unexpectedly — especially in bottom sheets, toolbars, and mode pickers.

Validated on: Magic Edit `EditorView` bottom chrome tab bar jumping when switching editor modes.

---

## When to use this track

| Signal | Use layout track |
|--------|-------------------|
| UI "jumps", "shifts", or "bounces" on tap | Yes |
| Element position changes between states | Yes |
| Works in Preview but jumps on device | Yes |
| SDK returns empty then populated | No — use SDK/race track in main SKILL |
| Crash or logic error | No — use tests + console logs |

---

## 1. Hypothesize layout causes (before fixing)

List 3–5 hypotheses with IDs. Common SwiftUI layout culprits:

| ID | Hypothesis | Typical evidence |
|----|------------|------------------|
| H1 | Sibling content above/below changes height | `GeometryReader` height differs per state |
| H2 | `.animation(_:value:)` on a parent animates layout, not just opacity | Tab bar `globalMinY` animates between values |
| H3 | Root-level `.animation` on a container re-layouts children | Whole dock frame shifts on one binding change |
| H4 | `ZStack` without fixed height swaps views of different sizes | Content area height swings (e.g. 31pt → 152pt) |
| H5 | `matchedGeometryEffect` or transitions fight layout | Frame jumps during chrome mode toggle |

**Do not fix until logs confirm which hypothesis matches.**

---

## 2. Read the view hierarchy first

Before instrumenting, trace:

1. **Container** — `VStack` / `ZStack` / `HStack` that owns the jumping element
2. **State driver** — which `@State` / ViewModel property triggers the swap
3. **Animations** — `.animation`, `withAnimation`, `.transition` on ancestors
4. **Variable-height children** — `switch` on mode, `@ViewBuilder` branches, conditional panels

Map: *state change → which branch renders → expected height delta*.

---

## 3. Instrument with GeometryReader + NDJSON logs

### Cursor debug mode (preferred when available)

When the session provides a debug ingest endpoint and log path:

| Config | Use exact values from system reminder |
|--------|----------------------------------------|
| HTTP endpoint | `http://127.0.0.1:7329/ingest/<uuid>` |
| Log file | `<workspace>/.cursor/debug-<sessionId>.log` |
| Session ID | e.g. `c77c2e` |

**Why HTTP POST, not file append:** iOS Simulator sandboxes the app — it cannot write to the Mac workspace path. POST to `127.0.0.1` reaches the host ingest server from Simulator.

### Minimal logger (temporary, `#if DEBUG` only)

```swift
#if DEBUG
// #region agent log
private enum AgentDebugLog {
    static func log(
        hypothesisId: String,
        location: String,
        message: String,
        data: [String: CustomStringConvertible] = [:],
        runId: String = "pre-fix"
    ) {
        let payload: [String: Any] = [
            "sessionId": "<sessionId>",
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data.mapValues { String(describing: $0) },
            "timestamp": Int(Date().timeIntervalSince1970 * 1000),
            "runId": runId,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: URL(string: "<ingest-endpoint>")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("<sessionId>", forHTTPHeaderField: "X-Debug-Session-Id")
        request.httpBody = body
        URLSession.shared.dataTask(with: request).resume()
    }
}
// #endregion
#endif
```

Wrap every debug block in `// #region agent log` … `// #endregion` so it folds cleanly.

### What to measure

Log **frame geometry**, not just booleans:

```swift
.background {
    GeometryReader { geometry in
        Color.clear
            .onAppear { logFrame(geometry, hypothesisId: "H1", label: "onAppear") }
            .onChange(of: someState) { _, _ in logFrame(geometry, hypothesisId: "H1", label: "stateChange") }
            .onChange(of: geometry.size.height) { _, h in
                AgentDebugLog.log(hypothesisId: "H1", location: "MyView.swift:panel",
                    message: "height changed", data: ["height": h])
            }
    }
}
```

For jumping elements, always log:

- `geometry.size.height` / `width`
- `geometry.frame(in: .global).minY` — **this is the smoking gun for vertical jump**
- Current mode/state string (e.g. `currentMode.rawValue`, `chromeMode`)

### Placement guide

| Attach to | Measures | Hypothesis |
|-----------|----------|------------|
| Variable content area (above tabs) | Action panel height | H1 |
| Tab bar / picker row | `globalMinY` stability | H1, H2 |
| `ZStack` swapping select/edit panels | Content area height | H4 |
| Outermost chrome container | Total dock height + `globalMinY` | H3, H5 |

**Cap at ~6 log sites** — enough to confirm/reject all hypotheses in one run.

---

## 4. Build and reproduce

### Build (mandatory)

```bash
cd /path/to/project
~/.cursor/plugins/cache/ios-dev-kit-marketplace/ios-dev-kit/6b2377b6c703a102bf3ba4f2e16165075b2a8216/skills/ios-build-test/scripts/build.sh --scheme "<scheme>"
```

Never run raw `xcodebuild`. Never pipe build output.

### Reproduce — agent-device (agent can run end-to-end)

When the user says "build and run yourself" or you need deterministic repro:

```bash
ad() { command -v agent-device >/dev/null 2>&1 && command agent-device "$@" || npx -y agent-device "$@"; }

SESSION="layout-debug-$(date +%s)"
UDID="<simulator-udid>"   # from: ad devices

ad install ".derivedData/Build/Products/Debug-iphonesimulator/App.app" --platform ios --udid "$UDID"
ad open "com.example.app" --session "$SESSION" --platform ios --udid "$UDID" --relaunch
ad snapshot -i --session "$SESSION"

# Navigate to the bug surface, then trigger each state:
ad press 'label="Edit"' --settle --session "$SESSION"
for mode in Replace Blur Recolor Outline Style Remove; do
  ad press "label=\"$mode\"" --settle --session "$SESSION"
done

ad close --session "$SESSION"
```

**Before each run:** delete only your session log file (e.g. `.cursor/debug-<sessionId>.log`) — never other sessions' logs.

### Reproduce — user-assisted (fallback)

Provide numbered steps in `<reproduction_steps>` and ask user to run Debug build from Xcode.

---

## 5. Analyze logs → confirm root cause

Read NDJSON lines from the log file. Evaluate each hypothesis:

```
H1 CONFIRMED — action content height 52–92pt across modes
H2 CONFIRMED — tab bar globalMinY shifted 616→820 between mode taps
H4 CONFIRMED — glassDock content 31pt (select) vs 152pt (edit)
H5 CONFIRMED — dock globalMinY swung ~40pt (616–656)
```

**Pre-fix vs post-fix comparison table** (example from Magic Edit):

| Metric | Pre-fix | Post-fix |
|--------|---------|----------|
| Tab bar `globalMinY` | 616–820 (varies) | 725.0 (stable) |
| Action content height | 52–92pt | 108pt (fixed frame) |
| Dock content height | 112–152pt | 168pt (fixed) |

Only implement fixes supported by log lines. Remove code from rejected hypotheses.

---

## 6. Fix patterns for layout jumps

### Pattern A — Fixed-height slot for variable content

When a `switch` or `@ViewBuilder` swaps views of different heights, **reserve the tallest measured slot**:

```swift
private enum Layout {
    static let actionAreaHeight: CGFloat = 92  // measured max from logs
}

actionContent
    .frame(maxWidth: .infinity)
    .frame(height: Layout.actionAreaHeight, alignment: .top)
```

Content shorter than the slot aligns top; tab bar below stays anchored.

### Pattern B — Fixed-height ZStack for mode swapping

When `if mode == .a { ViewA } else { ViewB }` swaps different heights:

```swift
ZStack(alignment: .top) {
    if chromeMode == .select { brushSlider.transition(.opacity) }
    if chromeMode == .edit { editorPanel.transition(.opacity) }
}
.frame(height: ChromeLayout.modePanelHeight, alignment: .top)  // measured max
.animation(.easeInOut(duration: 0.25), value: chromeMode)      // scoped here only
```

### Pattern C — Remove parent layout animations

**Avoid** animating layout on a parent that contains fixed-position chrome:

```swift
// BAD — animates tab bar position when sibling height changes
VStack { actionContent; tabBar }
    .animation(.easeInOut, value: currentMode)

// GOOD — no VStack animation; optional opacity on content only
VStack { actionContent.frame(height: fixed); tabBar }
```

Remove root `.animation(_:value:)` on screens where it re-layouts bottom chrome.

### Measure constants from logs, not guesses

Use the **max height observed in pre-fix logs** for frame constants. Round down slightly if needed (92pt for 92.33pt measured).

---

## 7. Verify with post-fix logs

1. Change `runId` to `"post-fix"` in logger (or tag verification run)
2. Delete log file
3. Rebuild, reinstall, rerun the same agent-device tap sequence
4. Confirm stability:
   - Tab bar `globalMinY` identical across all mode changes
   - Container heights constant
   - No `glass dock total height changed` lines after initial layout (optional)

**Do not remove instrumentation until post-fix logs prove success.**

---

## 8. Clean up

After verification:

1. Remove `AgentDebugLog` enum and all `#region agent log` blocks
2. Remove `#if DEBUG` geometry backgrounds used only for logging
3. **Keep** the layout fix (fixed frames, scoped animations)
4. Grep: `AgentDebugLog|hypothesisId|#region agent log|7329/ingest`
5. Final build via `ios-build-test`

See [cleanup-checklist.md](cleanup-checklist.md).

---

## Real example: bottom chrome tab bar jump

**Bug:** Mode tabs (Remove, Replace, Blur…) jumped vertically when selected.

**Root cause (log-proven):**
- `EditorBottomPanel` action views ranged 52–92pt tall
- `VStack` reflow pushed `ModeTabBar` up/down
- `.animation(.easeInOut, value: currentMode)` animated the shift
- `glassDock` `ZStack` resized between Draw (31pt) and Edit (152pt)

**Fix:**
- `actionContent.frame(height: 92, alignment: .top)` in `EditorBottomPanel`
- `ZStack.frame(height: 168, alignment: .top)` in `EditorView.glassDock`
- Removed broad `.animation` from panel VStack and root view
- Kept scoped `.animation` on ZStack for Draw/Edit opacity crossfade only

**Files touched:** `EditorBottomPanel.swift`, `EditorView.swift`
