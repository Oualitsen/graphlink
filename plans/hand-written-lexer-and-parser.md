# Hand-Written Lexer & Parser

## Context

The current parser uses petitparser (combinator-based). When `TokenInfo` was extended to carry file/line/column for better error reporting, generation time doubled. The root cause: petitparser computes line/column by scanning the input string up to each token position — O(n) per token, making the overall parse O(n²).

The goal is to replace petitparser with a hand-written lexer + top-down recursive descent parser that:
- Tracks line/column for free during lexing (one O(n) pass)
- Computes line/column in O(log n) via binary search, only when needed
- Keeps the existing `GLGrammar` architecture, extensions, and models untouched
- Removes the petitparser dependency entirely

---

## Step 1 — Define `GLTokenType` enum

**File:** `lib/src/lexer/gl_token_type.dart` (new file)

```dart
enum GLTokenType {
  // Punctuation
  openBrace, closeBrace, openParen, closeParen,
  openBracket, closeBracket, colon, bang, equals,
  pipe, at, amp, spread, // '...'

  // Keywords (resolved from identifiers via lookup table)
  kwType, kwInput, kwInterface, kwEnum, kwScalar,
  kwUnion, kwDirective, kwFragment, kwQuery,
  kwMutation, kwSubscription, kwExtend, kwSchema,
  kwOn, kwImplements, kwRepeatable, kwTrue, kwFalse, kwNull,

  // Literals
  identifier, string, blockString, int_, float_,

  eof,
}

const Map<String, GLTokenType> keywords = {
  'type': GLTokenType.kwType,
  'input': GLTokenType.kwInput,
  'interface': GLTokenType.kwInterface,
  'enum': GLTokenType.kwEnum,
  'scalar': GLTokenType.kwScalar,
  'union': GLTokenType.kwUnion,
  'directive': GLTokenType.kwDirective,
  'fragment': GLTokenType.kwFragment,
  'query': GLTokenType.kwQuery,
  'mutation': GLTokenType.kwMutation,
  'subscription': GLTokenType.kwSubscription,
  'extend': GLTokenType.kwExtend,
  'schema': GLTokenType.kwSchema,
  'on': GLTokenType.kwOn,
  'implements': GLTokenType.kwImplements,
  'repeatable': GLTokenType.kwRepeatable,
  'true': GLTokenType.kwTrue,
  'false': GLTokenType.kwFalse,
  'null': GLTokenType.kwNull,
};
```

---

## Step 2 — Define `GLLexerToken`

**File:** `lib/src/lexer/gl_lexer_token.dart` (new file)

```dart
class GLLexerToken {
  final GLTokenType type;
  final String value;
  final int offset; // character offset in source string, for line/column lookup
  const GLLexerToken(this.type, this.value, this.offset);
}
```

No line/column stored — only offset. Line/column is derived on demand via binary search.

---

## Step 3 — Build `GLLexer`

**File:** `lib/src/lexer/gl_lexer.dart` (new file)

Single O(n) pass over the source string.

```dart
class GLLexer {
  final String source;
  final String? fileName;
  int _pos = 0;
  final List<int> _lineOffsets = [0]; // offset of the start of each line
  final List<GLLexerToken> tokens = [];

  GLLexer(this.source, {this.fileName});

  List<GLLexerToken> tokenize() {
    while (_pos < source.length) {
      _skipWhitespaceAndComments();
      if (_pos >= source.length) break;
      _scanToken();
    }
    tokens.add(GLLexerToken(GLTokenType.eof, '', _pos));
    return tokens;
  }
}
```

**`_skipWhitespaceAndComments`:** advances past spaces, tabs, commas (GraphQL treats commas as whitespace), `\r`, and `\n`. On `\n`, push `_pos + 1` into `_lineOffsets` — this builds the line table for free. On `#`, skip to end of line.

**`_scanToken` dispatch table:**

| Input | Action |
|-------|--------|
| `{` `}` `(` `)` `[` `]` `:` `!` `=` `\|` `@` `&` | Emit single-char punctuation token |
| `.` | Expect `...`, emit `spread` |
| `"` followed by `""` | Scan block string |
| `"` | Scan single-line string (with escape handling) |
| `-` or `0-9` | Scan number (int or float) |
| `_`, `a-z`, `A-Z` | Scan identifier, then keyword-lookup |
| anything else | Throw `ParseException` with location |

**String scanning:**
- Single-line: scan until closing `"`, handle `\"`, `\\`, `\n`, `\r`, `\t` escapes
- Block string (`"""`): scan until closing `"""`, no escape handling needed

**Number scanning:** scan optional `-`, digits, optional `.` + digits (float), optional `e`/`E` exponent. Emit `float_` if `.` or exponent present, otherwise `int_`.

**Identifier scanning:** scan `[a-zA-Z_][a-zA-Z0-9_]*`, then look up in `keywords` map — emit keyword type if found, else `identifier`.

---

## Step 4 — Line/column lookup

**File:** `lib/src/lexer/gl_lexer.dart`

```dart
({int line, int column}) locationOf(int offset) {
  int lo = 0, hi = _lineOffsets.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (_lineOffsets[mid] <= offset) lo = mid; else hi = mid - 1;
  }
  return (line: lo + 1, column: offset - _lineOffsets[lo] + 1); // 1-based
}
```

Called only when constructing a `TokenInfo` from a `GLLexerToken`. During a successful parse (common case), this is never called for punctuation — only for named tokens (identifiers, type names, argument names) that participate in validation.

---

## Step 5 — Update `TokenInfo` to remove petitparser dependency

**File:** `lib/src/model/token_info.dart`

Remove `import 'package:petitparser/petitparser.dart'` and the `TokenInfo.of(Token token, String? fileName)` factory. Add:

```dart
static TokenInfo ofLexer(GLLexerToken token, GLLexer lexer) {
  final loc = lexer.locationOf(token.offset);
  return TokenInfo(
    token: token.value,
    line: loc.line,
    column: loc.column,
    fileName: lexer.fileName,
  );
}
```

`TokenInfo.ofString()` stays as-is — used for synthetic tokens in code generation.

---

## Step 6 — Build `GLParser`

**File:** `lib/src/parser/gl_parser.dart` (new file)

Replaces `GrammarDefinition`. Holds the token list and a cursor, exposes helper methods, and populates `GLGrammar` directly.

```dart
class GLParser {
  final List<GLLexerToken> _tokens;
  final GLLexer _lexer;
  final GLParser grammar;
  int _pos = 0;

  GLParser(this._tokens, this._lexer, this.grammar);

  // Core helpers replacing petitparser combinators
  GLLexerToken peek() => _tokens[_pos];
  GLLexerToken consume() => _tokens[_pos++];

  GLLexerToken expect(GLTokenType type) {
    final t = peek();
    if (t.type != type) {
      final loc = _lexer.locationOf(t.offset);
      throw ParseException(
        "Expected $type but got '${t.value}'",
        info: TokenInfo(token: t.value, line: loc.line, column: loc.column, fileName: _lexer.fileName),
      );
    }
    return consume();
  }

  bool check(GLTokenType type) => peek().type == type;
  bool checkAny(List<GLTokenType> types) => types.contains(peek().type);

  TokenInfo consumeIdentifier() => TokenInfo.ofLexer(expect(GLTokenType.identifier), _lexer);
  TokenInfo consumeNamedToken() => TokenInfo.ofLexer(consume(), _lexer); // for keywords used as names

  // Optional: returns null if type doesn't match
  GLLexerToken? tryConsume(GLTokenType type) => check(type) ? consume() : null;

  void parse() {
    while (!check(GLTokenType.eof)) {
      _parseDefinition();
    }
    grammar.validateSemantics();
  }
}
```

**Combinators replaced:**

| petitparser | GLParser equivalent |
|-------------|---------------------|
| `p.optional()` | `check(type) ? consume() : null` |
| `p.star()` | `while (check(...)) { ... }` |
| `p.plus()` | same + assert at least one was parsed |
| `[a, b].toChoiceParser()` | `switch (peek().type) { ... }` |
| `ref0(token, kw)` | `expect(GLTokenType.kwXxx)` |

---

## Step 7 — Implement `_parseDefinition` and each definition parser

**File:** `lib/src/parser/gl_parser.dart`

Top-level dispatch — peek at current token and call the appropriate method:

```dart
void _parseDefinition() {
  final optional documentation
  switch (peek().type) {
    case GLTokenType.kwType:    _parseTypeDefinition(); break;
    case GLTokenType.kwInput:   _parseInputDefinition(); break;
    case GLTokenType.kwInterface: _parseInterfaceDefinition(); break;
    case GLTokenType.kwEnum:    _parseEnumDefinition(); break;
    case GLTokenType.kwScalar:  _parseScalarDefinition(); break;
    case GLTokenType.kwUnion:   _parseUnionDefinition(); break;
    case GLTokenType.kwDirective: _parseDirectiveDefinition(); break;
    case GLTokenType.kwFragment: _parseFragmentDefinition(); break;
    case GLTokenType.kwQuery:
    case GLTokenType.kwMutation:
    case GLTokenType.kwSubscription: _parseQueryDefinition(); break;
    case GLTokenType.kwSchema:  _parseSchemaDefinition(); break;
    case GLTokenType.kwExtend:  _parseExtendDefinition(); break;
    default:
      throw ParseException("Unexpected token '${peek().value}'", ...);
  }
}
```

Each `_parseXxxDefinition()` mirrors the existing petitparser method — same name, same return type, same call to `grammar.addType()` / `grammar.addInput()` etc.

---

## Step 8 — Update `GLGrammar` parse entry point

**File:** `lib/src/gl_grammar.dart`

Replace the petitparser `parse()` call with the new lexer+parser pipeline:

```dart
void parseSource(String source, {String? fileName}) {
  final lexer = GLLexer(source, fileName: fileName);
  final tokens = lexer.tokenize();
  final parser = GLParser(tokens, lexer, this);
  parser.parse();
}
```

Remove `extends GrammarDefinition` and the `start()` / `fullGrammar()` methods. All other grammar state (`types`, `inputs`, `scalars`, `directives`, etc.) stays unchanged.

---

## Step 9 — Migration strategy (incremental)

Do not rewrite everything at once. Follow this order:

1. Write `GLLexer` + `GLTokenType` + `GLLexerToken` with unit tests covering every token type and edge case (escape sequences, block strings, hex ints, floats, keywords)
2. Test `locationOf()` with known source strings and offsets
3. Update `TokenInfo.ofLexer()`, remove petitparser import from `token_info.dart`
4. Write `GLParser` starting with `_parseScalarDefinition()` (simplest) — verify it produces identical output to the petitparser version using existing tests
5. Add one definition type at a time in order of complexity: enum → scalar → input → interface → type → union → directive → fragment → query/mutation/subscription → schema → extend
6. Run the full test suite after each definition type is added
7. Once all definitions pass, remove petitparser from `pubspec.yaml`

The existing integration tests act as a regression suite throughout — no new tests needed until the migration is complete, at which point edge-case lexer tests already written in step 1 cover the new code.

---

## What you gain

| | Before | After |
|--|--------|-------|
| Line/column cost | O(n) per token | O(log n) on error only |
| Overall parse complexity | O(n²) | O(n) |
| petitparser dependency | yes | removed |
| Architecture change | — | none (same GLGrammar, extensions, models) |
| Error message quality | same | same (TokenInfo unchanged externally) |
