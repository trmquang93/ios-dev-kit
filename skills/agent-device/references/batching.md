# Batching

Use `batch` when the agent already knows a short, screen-local sequence and wants fewer round trips.

## Invocation

```bash
ad() { command -v agent-device >/dev/null 2>&1 && command agent-device "$@" || npx -y agent-device "$@"; }

ad batch \
  --session my-run \
  --platform ios \
  --udid <udid> \
  --steps-file /tmp/batch-steps.json
```

Inline (small only):

```bash
ad batch --steps '[{"command":"open","positionals":["settings"]},{"command":"wait","positionals":["100"]}]'
```

Flags: `--on-error stop`, `--max-steps <n>`, `--out <path>`, `--json`.

## Step shape

```json
[
  { "command": "open", "positionals": ["MyApp"], "flags": { "relaunch": true } },
  { "command": "wait", "positionals": ["1500"] },
  { "command": "fill", "positionals": ["role=text-field", "Buy milk"], "flags": {} },
  { "command": "wait", "positionals": ["500"] },
  { "command": "click", "positionals": ["label=\"Save as task without extracting\""], "flags": {} },
  { "command": "wait", "positionals": ["label=\"Buy milk\"", "10000"], "flags": {} }
]
```

Exact field names can vary by CLI version — when in doubt, start from a recorded `.ad` / `help workflow` batch examples, or use one exploratory ref-based pass then encode selectors.

## Best practices

- **One screen-local flow** per batch (navigate **or** act **or** verify — split phases if flaky).
- Add **sync guards** (`wait`, `is exists`) after mutating steps.
- Prefer **selectors** over `@refs` inside batches (refs are session-generation specific; post-fill settle refs are often unauthorized).
- Prefer `--steps-file` over huge inline JSON.
- Keep batches moderate (**~5–20** steps).
- On failure, use `step` / `partialResults` to replan from the failed step — do not blindly re-run the whole batch without a fresh snapshot.
- Rapid mutations can outrun a11y updates: insert waits; split navigate → verify → cleanup.
- Always end exploratory flows with `close --session` even if the batch itself did not open the session.

## When not to batch

- First-time exploration of unknown UI (use snapshot + settle loop).
- Flows full of system alerts / keyboard tips until those are dismissed once on the sim.
- Debugging a single flaky control (isolate with one press --settle + screenshot).
