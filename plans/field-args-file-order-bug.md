# Bug: generated code depends on schema file order (missing `<Op>FieldArgs`)

Status: root cause **partially verified** (trigger reproduced, mechanism is a hypothesis).
Found while investigating CI failures on `main` at `334596b4` (#496) and `6637a0b3` (#495).

## Symptom

CI fails in:

- every `matrix (<server>, <client>)` job in `server_integration_tests` (35 jobs)
- `swift-vs-java-matrix-client`

Everything passes locally.

Java matrix jobs fail at test compile time:

```
cannot find symbol: class GetArticleFieldArgs
cannot find symbol: class CreateArticleFieldArgs
cannot find symbol: class ListArticlesFieldArgs
cannot find symbol: class ArticleCreatedFieldArgs
cannot find symbol: class ArticleUpdatedFieldArgs
cannot find symbol: class UpdateArticleFieldArgs
```

Swift fails the same way (`cannot find 'ArticleUpdatedFieldArgs' in scope`,
`extra argument 'fieldArgs' in call`). The checked-in tests call e.g.
`client.queries.getArticle("1", new GetArticleFieldArgs(2))`, so the generated
client in CI simply does not contain those classes or that parameter.

## What differs between CI and local

The CI `server-integration-tests-generate` job reports **174** files for
`clients/java_client`. Locally the same config produces **182**. The 8 missing
files are `*FieldArgs.java` inputs.

For the operations that lose their `FieldArgs`, the generated method is also
different. Same schemas, two file orders:

```java
// mapping.gql loaded before core.gql  (macOS / local)
public GetProjectedArticleResponse getProjectedArticle(GetProjectedArticleFieldArgs fieldArgs) {
   Objects.requireNonNull(fieldArgs, "fieldArgs is required");
   Map<String, Object> glVariables__ = new HashMap<>();
   glVariables__.putAll(fieldArgs.toJson());
   String glQuery__ = "query getProjectedArticle($latestArticlesLimit: Int!){getProjectedArticle{..._all_fields_Article}}";
   ...
}

// core.gql loaded before mapping.gql  (CI / Linux)
// no fieldArgs parameter, no $latestArticlesLimit variable, no GetProjectedArticleFieldArgs class
```

Also differing: `GraphLinkClient`, `Queries`, `Mutations`, `Subscriptions`,
`GraphLinkFullResponse` (they reference the missing classes), and the order of
imports.

Affected operations in `server_integration_tests`: `getArticle`, `listArticles`,
`createArticle`, `updateArticle`, `articleCreated`, `articleUpdated`,
`getProjectedArticle`, `getArticleWithCount`. All of them return `Article` (or a
type mapped to it) and therefore reach `Author.latestArticles(limit: Int!)`
through `Article.author`. Operations that start from `Author`
(`getAuthor`, `listAuthors`, `getAuthorAndArticle`) still get theirs.

## Why it only shows up in CI

`lib/src/main.dart:261` expands `schemaPaths` with
`Glob(pattern).listSync()`, which returns files in **filesystem order**, and
`parseFiles` parses them in that order into one `GLParser`.

- macOS (APFS) happens to return an order where `mapping.gql` comes before
  `core.gql`.
- The Linux runner returns a different order, with `core.gql` first.

## Reproduction (verified)

Clean worktree at `334596b4`, `server_integration_tests/clients/java_client`,
`schemaPaths` replaced by an explicit file list in a chosen order, then
`dart run ../../generate.dart`:

| order (abbreviated) | files | FieldArgs |
|---|---|---|
| mapping, directives, defaults, keywords, hoist_args, intercept, core, nesting | 182 | 16 |
| **core**, defaults, **mapping**, intercept, nesting, keywords, directives, hoist_args | **174** | **8** |
| mapping, keywords, core, intercept, ... | 182 | 16 |
| **core**, intercept, defaults, **mapping**, ... | **174** | **8** |
| keywords, intercept, nesting, defaults, hoist_args, directives, mapping, core | 182 | 16 |
| directives, defaults, intercept, **core**, nesting, keywords, **mapping**, hoist_args | **174** | **8** |
| 4 more shuffles with mapping before core | 182 | 16 |

10 random orders: every order with `core.gql` before `mapping.gql` gives 174,
every order with `mapping.gql` before `core.gql` gives 182. Other files do not
matter. A plain reversed order also gave 182, which is why that alone did not
reproduce it.

`mapping.gql` contributes `extend type Query { getProjectedArticle,
getArticleWithCount, getArticleInfo, getMessageReadList }`, so the order of
`queries.values` (insertion order) changes with the file order.

## Mechanism (hypothesis, not yet confirmed)

Pipeline (client mode, `gl_parser.dart` ~line 435):

```
createAllFieldsFragments → generateQueryDefinitions → ...
→ propagateFieldArgumentVariables()   // gl_grammar_projection_extension.dart:754
→ groupHoistedArgsIntoInputs()        // gl_grammar_hoist_args_extension.dart
→ pruneOverloadedAutoQueries() → createProjectedTypes() ...
```

`propagateFieldArgumentVariables()` loops over `queries.values` and, for each
operation, asks `_argSpecsFor(type, projectionMap, cache)` which `$variable`
field-argument specs are reachable. `cache` is **shared across all operations**
and keyed by `(projectionMap identity, type token)`.

`_argSpecsFor` publishes its (still empty) result map into the cache
**before** recursing:

```dart
final result = <String, _GeneratedArgSpec>{};
perType[type.token] = result;   // "publish before recursing" guard
...
_mergeArgSpecs(result, _argSpecsFor(subType, ..., cache));
```

The comment says the all-fields graph is acyclic by construction, so the guard
"only guards". Our schema has a cycle:

```
Article.author -> Author -> Author.latestArticles(limit: Int!) -> Article -> ...
```

If a node on that cycle is re-entered while it is in progress, the caller gets
the half-built map, copies what is in it at that moment via `_mergeArgSpecs`,
and the parent result is then **memoized incomplete**. Which node is in progress
when the cycle closes depends on which operation (entry point) populates the
cache first, i.e. on `queries.values` order, i.e. on file order.

This explains the pattern: operations that enter the cycle at `Article` can
end up cached without `latestArticlesLimit`, so `_addGeneratedArgument` never
adds the propagated argument, `groupHoistedArgsIntoInputs` finds nothing to
group (`extracted.isEmpty`), and no `<Op>FieldArgs` input is created.

What is **not** verified:

- that the cycle really is reached inside `_argSpecsFor` (the all-fields
  fragments may already be cut earlier by `forceCyclicEdgesNullable` /
  `createAllFieldsFragments`, which could also be order dependent)
- which operation is processed first in each order
- whether the cause is the in-progress cache entry or a different order
  dependence earlier in the pipeline

## How to confirm

1. Add a test under `test/` (inline `const` schema) that parses the same
   schema with the declarations split across two "files" in both orders
   (`parser.parseFiles([...])`), with `generateAllFieldsFragments` and
   `autoGenerateQueries` on, and asserts that the set of operation arguments
   (including hoisted `<Op>FieldArgs` inputs) is identical. It should fail for
   one order today.
2. Minimal schema shape to try: `Author { latestArticles(limit: Int!): [Article!]!
   @glSkipOnServer(batch:false) }`, `Article { author: Author!
   @glSkipOnServer(batch:false) }`, plus an `extend type Query` in a second file
   returning `Article`.
3. Log, per operation, the size of the result of `_argSpecsFor` for `Article`
   and `Author` and whether a cache hit returns a map that was still in
   progress.

## Fix options

- **Determinism (cheap, do regardless):** sort the globbed files in
  `handleGeneration` (and `resolveWatchedFiles`). Output stops depending on the
  machine, but this alone would pin the broken order (`core` before `mapping`),
  so it is not a fix for the bug.
- **Real fix:** make the walk independent of entry point. Options: detect the
  cycle and compute specs per strongly connected component, or skip caching any
  result computed while a cycle member was in progress (only memoize results
  that finished without hitting an in-progress entry), or iterate to a fixed
  point.
- Add a regression test in both orders, and a lint-style test that generation
  with shuffled file order yields identical output for
  `server_integration_tests/schema`.

## Other CI failures (unrelated to this bug)

- `java-rest-*-real`: `FlowsTest.concurrentCalls` fails once with
  `HTTP/1.1 header parser received no bytes` / `Connection reset` (1 of 87
  tests). Looks like a flaky connection against `rest_server/server.py`.
  Only the `java-rest-real` log was read in detail.
- `java-upload-reactor-real`: `Could not find artifact
  maven-resources-plugin:jar:3.4.0 in central`. Transient Maven Central fetch
  failure on the runner.
- `matrix (typescript, ts)`: `subscriptions.test.ts` `articleCreated` fails with
  `Cannot read properties of undefined (reading 'id')`. Not investigated; may
  be timing or may depend on this bug.
