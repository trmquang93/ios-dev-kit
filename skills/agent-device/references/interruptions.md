# Interruptions: alerts, keyboard, permissions

System and keyboard UI steal focus mid-flow. Treat them as first-class steps, not noise.

## Platform alerts (permissions, system dialogs)

```bash
ad alert get
ad alert wait 10000
ad alert accept     # primary / Allow
ad alert dismiss    # secondary / Don’t Allow / Cancel
```

Or snapshot and press the button:

```bash
ad snapshot -i
# @e2 [button] "Don’t Allow"
# @e3 [button] "Allow"
ad press @e3 --settle
```

Common iOS sheets during app flows:

- “Would Like to Send You Notifications”
- Photos / Camera / Microphone / Local Network
- “Paste from …”

**Pattern after first save / first media attach:** re-snapshot or `alert get` before asserting the success screen.

## Keyboard tips and onboarding (simulator)

Fresh simulators often show **keyboard intro cards**, e.g.:

- “Type English and Vietnamese”
- “Continue” button over the keyboard
- Typing predictions / Memoji strip

These can:

- Appear right after the first `fill` / focus on a text field  
- Dominate `snapshot -i` (dozens of `key` nodes)  
- Make Save / primary CTAs hard to see in the interactive tree  
- Cause settle to **list** CTA refs that are **not authorized** for press (`needs a complete snapshot`)

**Recovery:**

```bash
ad snapshot -i
# if button "Continue" (tip) is present:
ad press 'label="Continue"' --settle
# or
ad find text "Continue" click

# Prefer selector for app CTAs while keyboard is up
ad press 'label="Save as task without extracting"' --settle

# hide keyboard if it blocks the next target AND direct press failed
ad keyboard dismiss
ad keyboard return    # when submission is intended
```

Per CLI guidance: the on-screen keyboard usually **does not** block presses — try pressing the real target first (**selector** after fill); dismiss only if press fails or has no effect.

## Fill → tip → Save sequence (worked in practice)

```bash
ad open MyApp --session t --platform ios --udid "$UDID" --relaunch
ad snapshot -i --session t
ad press @e9 --settle --session t          # open capture / form
# full snapshot if text-field missing from -i
ad snapshot --session t
ad fill @e23 "Task title here" --settle --session t
# if bilingual keyboard tip:
ad press 'label="Continue"' --settle --session t
# SELECTOR — do not press settle-emitted @eN for Save after fill
ad press 'label="Save as task without extracting"' --settle --session t
# if notification alert:
ad alert dismiss --session t   # or accept, per product need
ad wait text "Task title here" 5000 --session t
ad close --session t
```

## App-owned sheets vs system alerts

| Kind | How to handle |
|---|---|
| System permission / SpringBoard alert | `alert accept/dismiss` or snapshot buttons |
| App confirmationDialog / sheet | Normal UI: `snapshot -i`, press label/ref |
| Camera / photo picker | App UI; may also trigger system permission first |

After dismissing any interruption, **refs from before the alert are stale** — use settle output, a selector, or a fresh `snapshot -i`.

## Verification after interruption

Named expectations need an explicit check:

```bash
ad wait text "Order placed" 5000
ad find "Buy groceries" exists
ad is visible 'label="Buy groceries…"'
```

A bare `screenshot` helps humans/agents see the screen but is **not** enough alone when the script names a result.
