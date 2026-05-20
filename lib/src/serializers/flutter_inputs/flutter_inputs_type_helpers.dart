import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/dart_serializer.dart';

class FlutterInputsTypeHelpers {
  final GLParser _parser;
  final DartSerializer _dartSerializer;
  final FlutterConfig _config;

  FlutterInputsTypeHelpers(this._parser, this._dartSerializer, this._config);

  // ── Field classification ──────────────────────────────────────────────────────

  bool isListField(GLField f) => f.type.isList;

  bool isEnumListField(GLField f) =>
      f.type.isList && _parser.enums.containsKey(f.type.inlineType.firstType.token);

  bool isScalarListField(GLField f) =>
      f.type.isList &&
      !isEnumListField(f) &&
      _dartSerializer.typeMap.containsKey(f.type.inlineType.firstType.token);

  bool isEnumField(GLField f) =>
      !f.type.isList && _parser.enums.containsKey(f.type.firstType.token);

  bool isInputField(GLField f) =>
      !f.type.isList && _parser.inputs.containsKey(f.type.firstType.token);

  bool isInputListField(GLField f) =>
      f.type.isList && _parser.inputs.containsKey(f.type.inlineType.firstType.token);

  bool isBoolField(GLField f) =>
      !f.type.isList &&
      (_dartSerializer.typeMap[f.type.firstType.token] ?? '') == 'bool';

  bool isTextField(GLField f) =>
      !isListField(f) && !isEnumField(f) && !isBoolField(f) && !isInputField(f);

  bool isTristateField(GLField f) {
    if (!isBoolField(f)) return false;
    if (f.type.nullable) return _config.nullableBooleanWidget == NullableBooleanWidget.tristate;
    return _config.booleanWidget == BooleanWidget.tristate;
  }

  bool needsSwitchBoolHelper(List<GLField> boolFields) =>
      boolFields.any((f) => !f.type.nullable && _config.booleanWidget == BooleanWidget.switchWidget);

  bool needsCheckboxBoolHelper(List<GLField> boolFields) =>
      boolFields.any((f) => f.type.nullable
          ? _config.nullableBooleanWidget == NullableBooleanWidget.checkbox
          : _config.booleanWidget == BooleanWidget.checkbox);

  // ── Type expressions ──────────────────────────────────────────────────────────

  String dartScalarType(GLField f) =>
      _dartSerializer.typeMap[f.type.firstType.token] ?? f.type.firstType.token;

  String listItemType(GLField f) {
    final inner = f.type.inlineType;
    final base = _dartSerializer.typeMap[inner.firstType.token] ?? inner.firstType.token;
    return inner.nullable ? '$base?' : base;
  }

  String listItemTypeNonNull(GLField f) {
    final inner = f.type.inlineType;
    return _dartSerializer.typeMap[inner.firstType.token] ?? inner.firstType.token;
  }

  String listDartType(GLField f) {
    final item = listItemType(f);
    return f.type.nullable ? 'List<$item>?' : 'List<$item>';
  }

  String typedEmptyList(GLField f) => 'const <${listItemTypeNonNull(f)}>[]';

  String defaultsFieldType(GLField f) => '${dartScalarType(f)}?';

  String validatorType(GLField f, List<GLField> enumFields, List<GLField> boolFields, String inputName) {
    final ctx = '${inputName}FormContext';
    if (enumFields.contains(f)) return 'String? Function(${f.type.firstType.token}?, $ctx)?';
    if (boolFields.contains(f)) return 'String? Function(bool?, $ctx)?';
    return 'String? Function(String?, $ctx)?';
  }

  // ── Values / override helpers ────────────────────────────────────────────────

  /// The T in InputFormWidget<T> for a given field — matches the schema data type.
  String valuesFieldType(GLField f) {
    if (isListField(f)) return listDartType(f);
    if (isEnumField(f)) {
      final base = f.type.firstType.token;
      return f.type.nullable ? '$base?' : base;
    }
    if (isBoolField(f)) return f.type.nullable ? 'bool?' : 'bool';
    final base = dartScalarType(f);
    return f.type.nullable ? '$base?' : base;
  }

  // ── FormContext helpers ───────────────────────────────────────────────────────

  String formContextFieldType(GLField f) {
    if (isListField(f)) {
      if (isEnumListField(f) || isScalarListField(f)) return 'List<${listItemTypeNonNull(f)}>';
      return listDartType(f);
    }
    if (isEnumField(f)) return '${f.type.firstType.token}?';
    if (isBoolField(f)) return f.type.nullable ? 'bool?' : 'bool';
    return 'String';
  }

  String formContextFieldInitExpr(GLField f) {
    if (isTextField(f)) return '_${f.name.token}Controller.text';
    return '_${f.name.token}';
  }

  // ── State initialisation expressions ─────────────────────────────────────────

  String initialTextExpr(GLField f) {
    final name = f.name.token;
    final type = dartScalarType(f);
    final nullable = f.type.nullable;
    if (type == 'int') {
      final rawToString = nullable
          ? "_form.initialValues?.$name?.toString() ?? ''"
          : "_form.initialValues?.$name.toString() ?? ''";
      final epochExpr = nullable
          ? 'DateTime.fromMillisecondsSinceEpoch(_form.initialValues!.$name!)'
          : 'DateTime.fromMillisecondsSinceEpoch(_form.initialValues!.$name)';
      return '_form.dateConfig?.$name != null && _form.initialValues?.$name != null '
          '? DateFormat(_form.dateConfig!.$name!.pattern).format($epochExpr) '
          ': $rawToString';
    }
    if (type == 'double') {
      return nullable
          ? "_form.initialValues?.$name?.toString() ?? ''"
          : "_form.initialValues?.$name.toString() ?? ''";
    }
    return "_form.initialValues?.$name ?? ''";
  }

  String initialBoolExpr(GLField f) {
    final name = f.name.token;
    return boolStateType(f) == 'bool?'
        ? '_form.initialValues?.$name'
        : '_form.initialValues?.$name ?? false';
  }

  String boolStateType(GLField f) {
    if (f.type.nullable) return 'bool?';
    return isTristateField(f) ? 'bool?' : 'bool';
  }

  String boolStateInit(GLField f) {
    if (f.type.nullable || isTristateField(f)) return '';
    return ' = false';
  }

  // ── Text field smart defaults ─────────────────────────────────────────────────

  bool isPasswordField(GLField f) {
    final n = f.name.token.toLowerCase();
    return n.contains('password') ||
        n.contains('secret') ||
        n == 'pin' || n.startsWith('pin') || n.endsWith('pin');
  }

  String smartKeyboardTypeExpr(GLField f) {
    final type = dartScalarType(f);
    if (type == 'int' || type == 'double') return 'TextInputType.number';
    final n = f.name.token.toLowerCase();
    if (n.contains('email')) return 'TextInputType.emailAddress';
    if (n.contains('phone')) return 'TextInputType.phone';
    if (n.contains('url') || n.contains('website')) return 'TextInputType.url';
    return 'TextInputType.text';
  }

  bool smartAutocorrect(GLField f) {
    if (isPasswordField(f)) return false;
    final n = f.name.token.toLowerCase();
    return !n.contains('email') && !n.contains('url') && !n.contains('website');
  }

  bool smartEnableSuggestions(GLField f) => smartAutocorrect(f);

  // ── Misc ──────────────────────────────────────────────────────────────────────

  String gapStr() {
    final g = _config.defaultGap;
    return g % 1 == 0 ? g.toInt().toString() : g.toString();
  }

  String humanize(String camelCase) {
    final spaced = camelCase.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m[1]} ${m[2]}',
    );
    return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }
}
