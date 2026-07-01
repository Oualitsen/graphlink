/// Adds the wire-name / code-name split to any model node that participates
/// in code generation.
///
/// The *wire name* is the original GraphQL token (used in query strings, JSON
/// keys, and `toJson`/`fromJson`).  The *code name* is the target-language
/// identifier that may differ after keyword-safe sanitization or naming-
/// convention normalization.  Implementors expose the wire name via [wireName];
/// this mixin stores the override and provides [codeName] with a fallback.
mixin CodeNameMixin {
  /// The original GraphQL token used on the wire.  Implemented by the mixing-in
  /// class — for most [GLToken] subclasses this is simply `token`; for
  /// [GLField] it is `name.token`; for [GLArgumentDefinition] it is `bareName`.
  String get wireName;

  String? _codeName;

  /// Target-language-safe identifier. Defaults to [wireName] and is overridden
  /// by the code-name pass when the raw name clashes with a reserved keyword or
  /// requires normalization (e.g. `MyField` → `myField`).
  /// Only use this in *identifier* positions; JSON keys and GraphQL query text
  /// must keep [wireName].
  String get codeName => _codeName ?? wireName;

  set codeName(String v) => _codeName = v;
}
