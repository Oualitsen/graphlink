# Model-layer memory & speed optimizations

Squeezing memory and parse speed out of the `lib/src/model/` IR layer, measured
against the GitHub schema (the largest real-world schema we have).

- **Benchmark harness:** `test/github_schema/github_bench.dart`
- **Run:** `fvm dart run test/github_schema/github_bench.dart 2`
- **Config (normal usage path):** `generateAllFieldsFragments: true`,
  `autoGenerateQueries: true`, `validate: true` (default). Parse only — no
  serializer / no code generation.

Schema: **1,513,018 chars / 72,825 lines**.
Parsed: types **1008**, inputs **401**, enums **252**, interfaces **99**,
fragments **3876**, queries **298**.

> Deterministic input — 1–2 iterations are representative. Times wobble a few %
> run-to-run; compare warm/min, not single cold samples. RSS won't shrink
> instantly (Dart GC retains pages), so peak RSS and the retained per-parse
> delta are the metrics that matter.

---

## Baseline (before any change)

| Metric | Value |
|---|---|
| Parse time — iter 1 (cold) | 1367 ms |
| Parse time — iter 2 (warm) | 1219 ms |
| RSS before any parse | 221.9 MB |
| RSS after parse (warm) | 378.6 MB |
| Peak RSS | 388.5 MB |

Per-parse working set ≈ **150–157 MB** over the ~222 MB Dart baseline.

Almost all cost is in `parse()`; `generateClient()` itself is ~0.4 ms. With this
config most of `parse()` is fragment + auto-query generation (3876 fragments,
298 queries), which allocates a lot of per-token / per-field IR — so per-instance
waste multiplies hard.

---

## Results table

| Change | Parse warm (ms) | RSS after parse (MB) | Peak RSS (MB) | Mem Δ vs baseline |
|---|---|---|---|---|
| baseline | 1219 | 378.6 | 388.5 | — |
| #2 lazy `GLToken._staticImports` | 1212 | 363.5 | 373.7 | **−~15 MB peak (≈10%)** |
| #1 lazy `TokenInfo.sourceLine` | 1152–1183 | 358–366 | 368–375 | peak ~flat; **~3–5% faster** |
| #3 lazy `GLDirectivesMixin` collections | 1120–1139 | 339 | 339–341 | **−~30 MB peak**; ~3% faster |
| **cumulative (#1+#2+#3)** | **~1130** | **~339** | **~340** | **−48 MB peak (≈12%), ~7% faster** |

---

## Catalogue of opportunities (ranked)

### #1 — `TokenInfo.sourceLine` lazy — DONE
`token_info.dart`. Every `TokenInfo.ofLexer` eagerly did `lexer.lineAt(line)` →
`source.substring(...)`, retaining a fresh copy of the whole source line for
every lexer token. `sourceLine` is read in exactly one place
(`parse_exception.dart`) to render the single failing token — so ~all of those
substrings were never used.
**Fix:** store the shared `source` string reference + the line-start offset
(derived from the column we already compute — no scan), and materialize the line
lazily in the `sourceLine` getter. Synthetic tokens (`ofString`) carry no source.
**Result (measured):** **~3–5% faster parse**, peak memory ~flat. The speed win
is reduced allocation churn during lexing (tens of thousands fewer substrings).
Memory was flat because the retained heap is dominated by the synthetic IR from
fragment/auto-query generation (3876 fragments) — those `TokenInfo`s come from
`ofString`/`ofNewName` and never carried a source-line substring to begin with.
Still strictly better (less allocation, less retained, faster, no downside).

### #2 — `GLToken._staticImports` lazy — DONE
`gl_token.dart`. Was `final Set<String> _staticImports = {}` on every `GLToken`
(every `GLType`, argument, directive value, query element). `addImport` is only
ever called on a handful of server/serializer tokens; the rest stayed empty.
**Fix:** `Set<String>? _staticImports`, allocate lazily in `addImport`; getter
returns `const {}` when null; `getImportDependecies` default returns `const {}`.
**Result:** ~15 MB peak ↓ (≈10% of working set), time flat.

### #3 — `GLDirectivesMixin` lazy collections — DONE
`gl_directives_mixin.dart`. Every mixer (`GLField`, `GLArgumentDefinition`,
`GLTypeDefinition`, `GLQueryElement`) eagerly allocated both `_decorators`
(List) and `_directives` (Map). Most fields have zero directives → ~2 empty
collections × tens of thousands of fields (incl. all the synthetic fields in the
3876 generated fragments). **Fix:** both nullable/lazy, allocated on first
`addDirective`/`addDirectiveIfAbsent`; read paths (`getDirectiveByName`,
`hasDirective`, `removeDirectiveByName`) treat null as empty; `getDirectives`
returns/caches `const []` when both are null.
**Result (measured):** **−~30 MB peak**, ~3% faster. The single biggest memory
win — it hits the fragment-generation IR that dominates the heap (the reason #1
looked flat).

### #4 — `GLTokenWithFields.hasField` — DONE (cheap)
`gl_token_with_fields.dart`. `hasField` → `fieldNames.contains`, which lazily
materializes a full `Set<String>` copy of `_fieldMap.keys`. **Fix:** use
`_fieldMap.containsKey(name)` directly.
**Result:** within noise at the macro benchmark (not hot enough to register
here) but strictly cheaper per call — no set materialization. Kept.

### #5 — Lexer identifier scanning — DONE (cheap, speed)
`gl_lexer.dart`. `_scanIdentifier` built a `StringBuffer`, wrote each char (via a
1-char `source[_pos]` string + `codeUnitAt(0)`), then called `toString()` twice.
`_scanDollarIdentifier` had the same char-by-char `StringBuffer` pattern.
**Fix:** scan positions with `source.codeUnitAt(_pos)` and slice once with
`source.substring(start, _pos)` — one allocation per identifier, no StringBuffer,
no per-char strings, no double `toString`.
**Result:** within noise at the macro benchmark — lexing is only ~tens of ms of
the ~1130 ms parse (the bulk is fragment/auto-query generation), so it can't move
the macro number. But it's a strict win in the lexing phase (identifiers are the
most common token) and cleaner code. Kept.

---

## Considered and rejected

### `const` constructors for `GLToken` / `GLType` — not viable
Asked: make `TokenInfo` const-constructible and detach `GLType` from `GLToken`,
then make `GLType`/`GLListType` const. **Mechanically possible** (drop mutable
lazy fields, move `token.trim()` out of the const ctor, detach base class) — but
**inert**: in Dart `const` means *compile-time constant*. Every `GLType` is built
at runtime from a lexer-derived `TokenInfo` (runtime line/col/source), so `const
GLType(...)` can never be written at those call sites. The instances stay
ordinary runtime heap objects — identical cost. `const` ≠ cheaper runtime
objects; it only canonicalizes compile-time-known values, which parsed IR is not.
The detach also has real cost (equality, `token` getter, 37 construction sites)
for zero payoff. Skipped.

### Interning `TokenInfo` — measured, net wash, rejected
Probe: ~82% of the 235k `TokenInfo`s constructed during a full parse are
value-duplicates (key = token·line·col·file, so dedup loses no location). Looked
promising. Implemented a value `==`/`hashCode` (suite stayed green) + a
session-scoped global intern cache, then measured **apples-to-apples (single
parse, separate processes, #1–#5 held constant):**

| | Parse | ΔRSS | Peak RSS | cache |
|---|---|---|---|---|
| intern OFF | 1212 ms | 109.4 MB | 324.8 MB | — |
| intern ON | 1414 ms | 106.5 MB | 320.9 MB | 42,993 |

**Memory ≈ wash (~3 MB, within noise); ~200 ms slower.** Reason: the cache pins
all 42,993 distinct `TokenInfo`s for the whole session — including the ones that
were previously **transient** (created during fragment generation, then GC'd).
The retained-duplicate memory the dedup *removes* is almost exactly cancelled by
the cache memory it *adds*, and you pay a hash+lookup per construction on the hot
path. Confirms the earlier reasoning: the duplicates are mostly transient, so
interning just relocates transient garbage into a retained cache. **Fully
reverted** (cache, session plumbing, and the `==`/`hashCode` that was only a
prerequisite).

---

## Notes on what NOT to change

- **Maps are correct here.** `_fieldMap`, `_directives`, `_arguments` are keyed
  lookups with cached `.values.toList()` for iteration — the right pattern. Wins
  are in *lazy allocation*, not Map→List.
- **IR objects can't be `const`** — they carry parse-time `TokenInfo` (line/col)
  and mutable caches. The realistic "const" win is returning `const {}` / `const
  []` sentinels for empty cases instead of fresh allocations.
