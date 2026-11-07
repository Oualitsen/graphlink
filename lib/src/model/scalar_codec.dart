class GLScalarCodec {
  static const placeholder = '{}';

  final String type;
  final String? fromJson;
  final String? toJson;
  final Set<String> imports;

  const GLScalarCodec({required this.type, this.fromJson, this.toJson, this.imports = const {}});

  bool get canDecode => fromJson != null;

  bool get canEncode => toJson != null;

  bool get isAlias => !canDecode && !canEncode;

  factory GLScalarCodec.fromConfig(String scalar, Object? raw) {
    if (raw is String) return GLScalarCodec(type: raw);
    if (raw is! Map) {
      throw ArgumentError('typeMappings["$scalar"] must be a type name or an object, got $raw.');
    }
    final type = raw['type'];
    if (type is! String || type.isEmpty) {
      throw ArgumentError('typeMappings["$scalar"] needs a non-empty "type".');
    }
    final fromJson = _expression(scalar, 'fromJson', raw['fromJson']);
    final toJson = _expression(scalar, 'toJson', raw['toJson']);
    return GLScalarCodec(type: type, fromJson: fromJson, toJson: toJson, imports: _imports(scalar, raw['import']));
  }

  String decode(String expression) => _apply(fromJson, expression);

  String encode(String expression) => _apply(toJson, expression);

  static String _apply(String? template, String expression) =>
      template == null ? expression : template.replaceAll(placeholder, expression);

  static String? _expression(String scalar, String key, Object? value) {
    if (value == null) return null;
    if (value is! String || !value.contains(placeholder)) {
      throw ArgumentError('typeMappings["$scalar"].$key must be a string containing $placeholder, got $value.');
    }
    return value;
  }

  static Set<String> _imports(String scalar, Object? value) {
    if (value == null) return const {};
    final items = value is List ? value : [value];
    if (items.any((e) => e is! String || e.isEmpty)) {
      throw ArgumentError('typeMappings["$scalar"].import must be a string or a list of strings, got $value.');
    }
    return Set.unmodifiable(items.cast<String>());
  }
}
