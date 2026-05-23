# Watch Mode: Skip Unchanged File Writes

## Goal

In watch mode, avoid writing generated files whose content hasn't changed since the last generation pass. This prevents Flutter's file watcher (and other downstream tools) from reacting to no-op regenerations.

## Approach

Maintain an in-memory `Map<String, String>` of `outputPath → contentHash` that persists across watch iterations (the process stays alive, so this is free).

On each regeneration pass, instead of writing directly to disk:
1. Generate the file content string in memory (as today).
2. Compute a cheap hash (e.g. `content.hashCode` or a short SHA).
3. Compare to the cached hash for that path.
4. **Skip the write** if the hash matches; otherwise write and update the cache.

No disk read is needed — the hash serves as a proxy for "did we already write this exact content?"

## Changes Required

- Add a `Map<String, int> _outputHashCache` (or similar) in `main.dart`, scoped to `watchAndGenerate`.
- Pass it (or a write-guard callback) down into each generator's file-write path.
- The write utility (`writeToFile` in `io_utils.dart`) gains an optional cache parameter; if provided it checks before writing.

## Scope

- Watch mode only (`-w` flag). Single-run mode is unaffected.
- No change to parsing or grammar logic.

## Out of Scope

- Incremental parsing (only re-parsing changed schema files). Cross-file type dependencies make this non-trivial and it is deferred.
