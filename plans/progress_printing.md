# Progress Printing

> Design doc for an **opt-in progress reporter** for `glink` code generation.
> Status: proposed. Born out of profiling the full GitLab schema
> (4143 types → ~1.34M LOC Dart client), where a single generation run can take
> tens of seconds with **zero feedback** — to the point where a genuine
> exponential blow-up looked indistinguishable from a normal slow run.

---

## Motivation

GraphLink targets *enterprise* schemas. The GitLab schema alone produces:

| Metric | Value |
|---|---|
| Types + interfaces | 4143 |
| Inputs | 783 |
| Enums | 400 |
| Root query fields (operations) | 165 |
| Generated Dart client | **~1,343,803 LOC** |

For schemas this size, "generate everything in a matter of seconds" is the goal,
but even a healthy run is long enough that a silent CLI is a problem:

1. **No way to tell a slow run from a hung run.** During development we hit an
   exponential walk in `elementArgumentVariables` that pinned a core at 99% CPU
   with no output. It was indistinguishable from "just slow" until we hand-wired
   `print` statements through five files.
2. **No sense of how far along generation is.** A 30-second run with no output
   feels broken even when it's fine.
3. **No cheap, always-available profiling.** When a customer reports "generation
   is slow on our schema," we want them to flip one flag and paste the output —
   not patch the source.

This doc proposes a small, structured progress facility to replace the ad-hoc
`print` debugging we did during the GitLab investigation.

---

## Goals

- **Opt-in.** Zero output and zero measurable overhead when disabled (the
  default). Generated code is never affected.
- **Two levels:** a high-level **progress** view (for end users watching a long
  run) and a detailed **profile** view (for diagnosing slowness).
- **Pipeline-wide.** One mechanism that covers both the *parse* phases
  (`GLParser`) and the *generation* phases (generators + serializers).
- **Cheap to add a probe.** Instrumenting a new hot spot should be one line, the
  way `_timed(...)` already wraps each parse phase.

## Non-goals

- A fancy TUI. A single rewriting line (carriage-return progress bar) is the
  ceiling; everything else is plain log lines.
- Per-file or per-token tracing. Probes live at phase / per-operation
  granularity, not per-AST-node.

---

## How it's enabled

Three independent switches, lowest-friction first:

| Mechanism | Scope | Example |
|---|---|---|
| Env var | quick / CI | `GLINK_PROGRESS=1`, `GLINK_PROGRESS=profile` |
| CLI flag | per-run | `glink -c config.json --progress` / `--profile` |
| Config key | per-project | `"progress": "bar" \| "steps" \| "profile" \| "off"` |

Resolution order: CLI flag > env var > config key > **off**.

Modes:

- `off` (default) — silent.
- `steps` — one line per phase as it starts/completes (the `[phase]` / `[step]`
  lines we used).
- `bar` — a single rewriting progress bar with a percentage and the current
  phase label.
- `profile` — `steps` **plus** per-phase elapsed-ms timing, only logging steps
  slower than a threshold (the re-enabled `_timed` behaviour).

---

## What gets reported (the probe points we discovered)

The instrumentation we added during the GitLab investigation maps directly onto
the natural progress checkpoints. These are the points worth keeping:

### Parse phases — `GLParser` (`_timed` wrappers)

Already wrapped in `gl_parser.dart`; representative timings from GitLab:

```
forceCyclicEdgesNullable          31ms
createAllFieldsFragments         119ms
generateQueryDefinitions           7ms
fillTypedFragments                 6ms
validateProjections                9ms
updateFragmentDependencies        54ms
propagateFieldArgumentVariables  290ms
createProjectedTypes            1588ms   ← dominant parse cost
```

### Generation phases — generators

Per-target generator steps (Dart shown):

```
init serializers
generating enums (400)
generating inputs (783)
generating types + interfaces (4143)
generating client + adapters       ← per-operation work lives here
writing N files to disk
generating barrel file
```

### Per-operation rendering — client serializer

The single most useful **progress** signal for big schemas, because it's a long
loop with a known total (`buildOperationMethods`):

```
query   ops  42/165
mutation ops 10/98
```

This is the natural home for the percentage / progress bar:
`overall % = weighted(parse, types, operations, file IO)`.

---

## Proposed API

A single `Progress` sink threaded through the pipeline (or accessed via a
process-global, like the existing `writeCount`), with a no-op default.

```dart
abstract class Progress {
  /// Marks the start of a named phase. Returns a handle to close it.
  ProgressStep step(String label, {int? total});

  /// No-op implementation used when progress is disabled (the default).
  static Progress get disabled => const _NoopProgress();
}

abstract class ProgressStep {
  /// For loop-style phases with a known [total]; advances the bar.
  void tick([int by = 1]);
  /// Closes the step, recording elapsed time (surfaced in `profile` mode).
  void done();
}
```

Usage mirrors today's `_timed` / `step(...)` closures:

```dart
final s = progress.step('generating client + adapters', total: operationCount);
for (final def in ops) {
  render(def);
  s.tick();
}
s.done();
```

- **`steps` mode** → prints `▶ generating client + adapters` then `✓ … (1.2s)`.
- **`bar` mode** → rewrites one line: `[██████░░░░] 62%  generating client …`.
- **`profile` mode** → like `steps`, but only logs steps over the
  `_slowStepThreshold` and includes cumulative totals.
- **`off`** → `_NoopProgress`, every call inlines to nothing.

### Why a sink, not raw `print`

The throwaway approach used `print` directly in `GLParser`, the generators, and
three serializers. That's why it was scattered and hard to remove. A single
injected `Progress` object:

- centralises formatting and the enable/disable check,
- keeps serializers pure (they receive the sink, they don't decide policy),
- lets `bar` mode own the carriage-return line without every call site knowing.

---

## Overhead when disabled

`_NoopProgress.step()` returns a const no-op `ProgressStep`; `tick`/`done` are
empty. No stopwatch is started, no string is built (labels are passed as-is, so
avoid interpolating expensive strings at the call site — pass a builder if
needed). Target: unmeasurable difference vs. removing the calls entirely.

---

## Implementation sketch

1. Add `Progress` + `_NoopProgress` + console implementations under
   `lib/src/progress/`.
2. Resolve the mode in `main.dart` (flag > env > config) and construct the sink
   once.
3. Thread it into `GLParser` (replacing the re-enabled `_timed`/`profile`) and
   into each generator (replacing the `step(...)` closures).
4. Give `buildOperationMethods` a `total` so per-operation `tick()` drives the
   bar — this is the dominant visible phase on large schemas.
5. Weight overall percentage across phases using rough cost ratios observed on
   GitLab (parse ~2.3s, types ~0.8s, operations dominate on `bar`).

---

## Appendix: probe points from the GitLab investigation

For reference, the temporary `print` probes that this feature formalises lived
in:

- `lib/src/main.dart` — `[phase]` read/parse/generation-complete.
- `lib/src/model/new_parser/gl_parser.dart` — `_timed` / `profile` per parse phase.
- `lib/src/generators/dart_client_generator.dart` — `[step]` per generation phase.
- `lib/src/serializers/gl_client_serializer.dart` — per-operation `op #i/N`.
- `lib/src/serializers/client_serializers/dart_client_serializer.dart` —
  `queryToMethod` sub-steps.
- `lib/src/serializers/gl_graphql_serializer.dart` — `divideQuery` sub-steps.

All were removed once the exponential walk in `elementArgumentVariables`
(`gl_grammar_projection_extension.dart`) was fixed with a visited guard; this doc
captures the design so the next person doesn't have to re-wire them by hand.
