import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';

const _explicitRoles = {
  glRestPath: RestArgRole.path,
  glRestParam: RestArgRole.query,
  glRestHeader: RestArgRole.header,
  glRestBody: RestArgRole.body,
  glRestField: RestArgRole.field,
  glRestPart: RestArgRole.part,
};

const _roleDirective = {
  RestArgRole.query: glRestParam,
  RestArgRole.header: glRestHeader,
  RestArgRole.field: glRestField,
  RestArgRole.part: glRestPart,
};

const _roleHint = '@glRestParam, @glRestHeader, @glRestBody, @glRestField or @glRestPart';

class _Shape {
  final bool isList;
  final bool isInput;
  final bool isUpload;

  _Shape({required this.isList, required this.isInput, required this.isUpload});
}

extension GLGrammarRestArgumentsExtension on GLParser {
  List<GLRestArgument> resolveRestArguments(GLField field, RestMethod method, List<String> placeholders) {
    final bound = <String>{};
    final result = <GLRestArgument>[];
    for (final arg in field.arguments) {
      final resolved = _resolveRestArgument(field, arg, placeholders);
      if (resolved.role == RestArgRole.path && !bound.add(resolved.wireName!)) {
        throw ParseException("Path placeholder '${resolved.wireName}' of '${field.name.token}' is bound by more than one argument",
            info: arg.tokenInfo);
      }
      result.add(resolved);
    }
    for (final placeholder in placeholders.where((p) => !bound.contains(p))) {
      throw ParseException(
          "Path placeholder '$placeholder' of '${field.name.token}' has no argument: declare an argument named '$placeholder' or bind one with @glRestPath(name: \"$placeholder\")",
          info: field.name);
    }
    return result;
  }

  RestBodyKind resolveRestBodyKind(GLField field, RestMethod method, List<GLRestArgument> arguments) {
    final bodyArguments = arguments.where((a) => _bodyKindOf(a) != null).toList();
    if (bodyArguments.isEmpty) return RestBodyKind.none;
    if (method == RestMethod.get || method == RestMethod.delete) {
      throw ParseException(
          "'${field.name.token}' uses a body role but ${method.wireName} requests have no body",
          info: bodyArguments.first.argument.tokenInfo);
    }
    final kinds = bodyArguments.map(_bodyKindOf).toSet();
    if (kinds.length > 1) {
      throw ParseException("'${field.name.token}' cannot mix body kinds (@glRestBody, @glRestField and @glRestPart are exclusive)",
          info: field.name);
    }
    if (kinds.single == RestBodyKind.json || kinds.single == RestBodyKind.raw) {
      if (bodyArguments.length > 1) {
        throw ParseException("'${field.name.token}' can have at most one @glRestBody argument", info: field.name);
      }
    }
    return kinds.single!;
  }

  bool resolveRestBodyOptional(RestBodyKind kind, List<GLRestArgument> arguments) {
    if (kind == RestBodyKind.none) return false;
    final entries = arguments.where((a) => _bodyKindOf(a) != null);
    return entries.every((a) => a.argument.type.nullable || a.argument.defaultValue != null);
  }

  RestBodyKind? _bodyKindOf(GLRestArgument a) {
    switch (a.role) {
      case RestArgRole.body:
        return _shapeOf(a.argument).isUpload ? RestBodyKind.raw : RestBodyKind.json;
      case RestArgRole.field:
        return RestBodyKind.form;
      case RestArgRole.part:
        return RestBodyKind.multipart;
      default:
        return null;
    }
  }

  GLRestArgument _resolveRestArgument(GLField field, GLArgumentDefinition arg, List<String> placeholders) {
    final declared = _explicitRoles.entries.where((e) => arg.hasDirective(e.key)).toList();
    if (declared.length > 1) {
      throw ParseException("Argument '${arg.bareName}' of '${field.name.token}' has more than one REST role (${declared.map((e) => e.key).join(', ')})",
          info: arg.tokenInfo);
    }
    if (declared.isEmpty) {
      if (!placeholders.contains(arg.bareName)) {
        throw ParseException("Argument '${arg.bareName}' of '${field.name.token}' needs a REST role: $_roleHint",
            info: arg.tokenInfo);
      }
      _injectPathDirective(arg);
      return _pathArgument(field, arg, placeholders);
    }
    final directive = arg.getDirectiveByName(declared.single.key)!;
    final shape = _shapeOf(arg);
    switch (declared.single.value) {
      case RestArgRole.path:
        return _pathArgument(field, arg, placeholders);
      case RestArgRole.query:
        _rejectUpload(arg, shape, 'a query parameter');
        return _namedArgument(arg, RestArgRole.query, directive, shape, spreadsInputs: true);
      case RestArgRole.header:
        return _headerArgument(field, arg, directive, shape);
      case RestArgRole.body:
        return _bodyArgument(arg, shape);
      case RestArgRole.field:
        _rejectUpload(arg, shape, 'a form field');
        return _namedArgument(arg, RestArgRole.field, directive, shape, spreadsInputs: false);
      case RestArgRole.part:
        return _namedArgument(arg, RestArgRole.part, directive, shape, spreadsInputs: false);
    }
  }

  void _injectPathDirective(GLArgumentDefinition arg) {
    arg.addDirectiveIfAbsent(GLDirectiveValue(
        arg.tokenInfo.ofNewName(glRestPath),
        [GLDirectiveScope.ARGUMENT_DEFINITION],
        [GLArgumentValue(arg.tokenInfo.ofNewName(glRestNameArg), arg.bareName)],
        generated: true));
  }

  GLRestArgument _pathArgument(GLField field, GLArgumentDefinition arg, List<String> placeholders) {
    final directive = arg.getDirectiveByName(glRestPath)!;
    final name = directive.getArgValueAsString(glRestNameArg) ?? arg.bareName;
    final shape = _shapeOf(arg);
    if (!placeholders.contains(name)) {
      throw ParseException("@glRestPath(name: \"$name\") on '${arg.bareName}' matches no placeholder of the path of '${field.name.token}'",
          info: arg.tokenInfo);
    }
    if (arg.type.nullable) {
      throw ParseException("Path variable '${arg.bareName}' of '${field.name.token}' must be non-null", info: arg.tokenInfo);
    }
    if (shape.isList || shape.isInput || shape.isUpload) {
      throw ParseException("Path variable '${arg.bareName}' of '${field.name.token}' must be a scalar or an enum", info: arg.tokenInfo);
    }
    return GLRestArgument(argument: arg, role: RestArgRole.path, wireName: name);
  }

  GLRestArgument _headerArgument(GLField field, GLArgumentDefinition arg, GLDirectiveValue directive, _Shape shape) {
    _rejectUpload(arg, shape, 'a header');
    final name = directive.getArgValueAsString(glRestNameArg);
    if (shape.isInput && !shape.isList) {
      return GLRestArgument(
          argument: arg,
          role: RestArgRole.header,
          wireName: null,
          encoding: RestEncoding.spread,
          spreadFields: _spreadFields(arg, RestArgRole.header));
    }
    if (shape.isInput) {
      throw ParseException("Argument '${arg.bareName}' of '${field.name.token}' is a list of input objects and cannot be a header group",
          info: arg.tokenInfo);
    }
    if (name == null) {
      throw ParseException("@glRestHeader on '${arg.bareName}' of '${field.name.token}' needs a name", info: arg.tokenInfo);
    }
    return GLRestArgument(argument: arg, role: RestArgRole.header, wireName: name);
  }

  GLRestArgument _bodyArgument(GLArgumentDefinition arg, _Shape shape) {
    if (shape.isUpload) {
      if (shape.isList) {
        throw ParseException("Argument '${arg.bareName}' is a list of uploads and cannot be a raw body: use @glRestPart", info: arg.tokenInfo);
      }
    } else if (!shape.isInput) {
      throw ParseException("@glRestBody on '${arg.bareName}' needs an input object, a list of input objects or an upload", info: arg.tokenInfo);
    }
    return GLRestArgument(argument: arg, role: RestArgRole.body, wireName: null);
  }

  GLRestArgument _namedArgument(GLArgumentDefinition arg, RestArgRole role, GLDirectiveValue directive, _Shape shape,
      {required bool spreadsInputs}) {
    final name = directive.getArgValueAsString(glRestNameArg) ?? arg.bareName;
    final declared = _declaredEncoding(arg, directive);
    final structured = shape.isInput || shape.isList;
    if (declared != null && !structured) {
      throw ParseException("encoding on '${arg.bareName}' only applies to input objects and lists", info: arg.tokenInfo);
    }
    if (declared == RestEncoding.spread && shape.isList) {
      throw ParseException("encoding SPREAD on '${arg.bareName}' is not possible for a list: use FLAT or JSON", info: arg.tokenInfo);
    }
    RestEncoding? encoding = declared;
    if (encoding == null && structured && !shape.isUpload) {
      encoding = spreadsInputs && shape.isInput && !shape.isList ? RestEncoding.spread : RestEncoding.flat;
    }
    return GLRestArgument(
        argument: arg,
        role: role,
        wireName: name,
        encoding: shape.isUpload ? null : encoding,
        spreadFields: encoding == RestEncoding.spread ? _spreadFields(arg, role) : const {});
  }

  Map<String, String> _spreadFields(GLArgumentDefinition arg, RestArgRole role) {
    final directiveName = _roleDirective[role]!;
    final result = <String, String>{};
    for (final inputField in inputs[arg.type.firstType.token]!.fields) {
      if (role == RestArgRole.header && inputs.containsKey(inputField.type.firstType.token)) {
        throw ParseException(
            "Field '${inputField.name.token}' of input '${arg.type.firstType.token}' is an object and cannot be sent as a header",
            info: inputField.name);
      }
      result[inputField.name.token] =
          inputField.getDirectiveByName(directiveName)?.getArgValueAsString(glRestNameArg) ?? inputField.name.token;
    }
    return result;
  }

  RestEncoding? _declaredEncoding(GLArgumentDefinition arg, GLDirectiveValue directive) {
    final value = directive.getArgValueAsString(glRestEncodingArg);
    if (value == null) return null;
    for (final encoding in RestEncoding.values) {
      if (encoding.name.toUpperCase() == value) return encoding;
    }
    throw ParseException("Unknown encoding '$value' on '${arg.bareName}', expected FLAT, JSON or SPREAD", info: arg.tokenInfo);
  }

  void _rejectUpload(GLArgumentDefinition arg, _Shape shape, String as) {
    if (shape.isUpload) {
      throw ParseException("Upload argument '${arg.bareName}' cannot be $as: use @glRestPart or @glRestBody", info: arg.tokenInfo);
    }
  }

  _Shape _shapeOf(GLArgumentDefinition arg) {
    final inner = arg.type.firstType.token;
    return _Shape(
      isList: arg.type is GLListType,
      isInput: inputs.containsKey(inner),
      isUpload: uploadScalarNames.contains(inner),
    );
  }
}
