# Snapshots, refs, and selectors

## Default observation loop

```text
open → snapshot -i → press|fill|click|longpress --settle → use settled diff → …
```

- Prefer **`--settle`** on mutations; continue from its diff when it shows the next target or proof.
- Re-run `snapshot -i` only when you skipped settle, settle printed **not settled**, or the diff lacks what you need.
- If you skipped `--settle`, use `diff snapshot` / `diff snapshot -i` instead of dumping the full tree again.
- **Exception after `fill`:** even when settle prints `+@eN` for a CTA, prefer a **stable selector** for the next press (see [Authorized frame](#authorized-frame-post-fill-trap)).

## Snapshot flavors

| Command | Use when |
|---|---|
| `snapshot -i` | Need interactive refs for the next tap/fill (default exploration) |
| `snapshot` | Text fields / nested editables missing from `-i` (e.g. under `scroll-area`) |
| `snapshot -s "Label"` or `-s @e12` | Scope to a container; expand truncated previews |
| `snapshot -d 3` | Cap depth on huge trees |
| `snapshot --raw` / `--json` | Provider tree / rects for coordinate fallback |
| `snapshot --force-full` | Force full re-emit when baseline says unchanged |
| `diff snapshot [-i]` | Only added/removed/changed lines since last snapshot in this session |
| `screenshot path.png` | Visual ground truth when a11y is sparse, keyboard-dominated, or wrong |

**Anti-pattern:** `snapshot -i | grep …` or piping through `jq` / `head` — you lose refs, warnings, and settle hints. Read the raw command output.

## Refs (`@e12`)

- Minted by the latest snapshot (or settle) in the session.
- **Valid until** press, click, fill, type, scroll, back, alert handling, keyboard change, open, or other UI mutation.
- On **iOS**, stale refs are **rejected** for press/fill/click/longpress (`expired ref frame`). Refresh or use a selector.
- Optional pin to generation: `@e12~s4` (from `refsGeneration` / settle) when you must bind a ref to the tree that minted it.

```bash
ad snapshot -i
ad press @e12 --settle     # @e12 from THAT snapshot only
# after settle: do not reuse @e12 unless it appears again in the settled tail
```

### Authorized frame (post-fill trap)

Settle output can **display** many `+@eN` lines while the live frame only **authorizes** a subset (especially when the keyboard / typing predictions dominate).

Typical error:

```text
Error (COMMAND_FAILED): Ref @e60 needs a complete snapshot — the current frame only authorizes its emitted refs
Hint: Capture a fresh interactive snapshot (snapshot -i) or use a stable selector, then retry.
```

**What to do:**

1. Prefer `press 'label="Save…"' --settle` (or `id=…`) — selectors do not need the settle ref frame.
2. Or `snapshot -i` and press a **new** `@eN` from that snapshot.
3. Do **not** keep retrying the same `@eN` from the fill settle.

Verified pattern (Nowlist capture):

```bash
ad fill @e23 "Skill retest: water plants" --settle
# settle may show +@e60 [button] "Save as task without extracting"
# press @e60  → often FAILS (unauthorized in keyboard frame)
ad press 'label="Save as task without extracting"' --settle   # works
```

## Selectors (survive mutations)

Prefer selectors when the control is stable:

```bash
ad press 'label="Save as task without extracting"' --settle
ad press 'role=button label="Submit"' --settle
ad fill 'label="Email"' "a@b.com" --settle
ad wait 'id="order-confirm"' 5000
```

Allowed keys: `id`, `role`, `text`, `label`, `value`, `appname`, `windowtitle`, `visible`, `hidden`, `editable`, `selected`, `focused`, `enabled`, `hittable`.

Not selector keys: `placeholder`, `index`, bare `key=Enter` (use `keyboard enter` / `return`).

A literal `@` in a label is **not** a ref: use `label="@account.example"`.

## Accessibility label ≠ visible text

SwiftUI often exposes a **different** a11y label than the painted string.

| Visible UI | Common a11y reality |
|---|---|
| “Capture a task” | Sometimes exact label; sometimes parent / different string — trust the snapshot |
| “Save as task” | Full label may be `"Save as task without extracting"` |
| Icon-only controls | SF Symbol name or custom `accessibilityLabel` |

**Targeting order:**

1. Explicit `accessibilityLabel` / `accessibilityIdentifier` from product code or snapshot `id=` / `label=`
2. Snapshot `role` + `label` on the **hittable** control
3. `find text "…"` / visible text (can fail when text is on a non-hittable child)
4. Coordinates from `snapshot -i --json` rect center or screenshot (last resort)

When `find text "X" click` fails but you see “X” on screen: full `snapshot`, find the parent `button` / `cell` ref, press that.

## Text fields

```bash
# Prefer fill (replace) + settle
ad fill @e23 "Buy groceries before Friday" --settle
# or
ad fill 'role=text-field' "Buy groceries before Friday" --settle

# Append only after focus
ad press @e23 --settle
ad type " more"
```

- If `-i` omits `[text-field]`, run full `snapshot` and locate `[text-field] … [editable]`.
- Do **not** use `fill <target> ""` to clear — unsupported; use a clear control or report.
- After fill, keyboard tips / prediction bars may appear — see [interruptions.md](interruptions.md).
- After fill, **next CTA via selector**, not settle `@eN` (see authorized frame above).

## Truncated previews

Snapshot may show `preview="Leave at side..." truncated`. **Do not** `get text` first — expand:

```bash
ad snapshot -s @e13
```

## Off-screen items

Off-screen summaries are **hints**, not refs. `scroll down` / `scroll up`, then `snapshot -i`. Prefer short scroll loops over `scroll bottom/top` unless the task asks for the list edge.

## Coordinate fallback

When refs/selectors fail or nodes are non-hittable:

1. `screenshot` or `snapshot -i --json` for rects  
2. `press <x> <y>` at the visible center  
3. Verify with settle / `wait` / `diff snapshot -i`

iOS: if press reports success but UI does not change and the node was `hittable:false`, retarget — success can be a no-op on dead refs.
