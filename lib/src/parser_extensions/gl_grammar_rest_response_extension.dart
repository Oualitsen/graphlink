import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

const _defaultContentTypes = {
  RestBodyKind.json: 'application/json',
  RestBodyKind.form: 'application/x-www-form-urlencoded',
  RestBodyKind.multipart: 'multipart/form-data',
};

const _defaultAccept = {
  RestResponseKind.json: 'application/json',
  RestResponseKind.text: 'text/plain',
  RestResponseKind.binary: '*/*',
  RestResponseKind.none: '*/*',
};

extension GLGrammarRestResponseExtension on GLParser {
  Set<String> get downloadScalarNames => _scalarsMarkedWith(glDownload);

  Set<String> get voidScalarNames => _scalarsMarkedWith(glVoid);

  Set<String> _scalarsMarkedWith(String directive) =>
      scalars.entries.where((e) => e.value.hasDirective(directive)).map((e) => e.key).toSet();

  GLRestResponse resolveRestResponse(GLField field, GLDirectiveValue? rest) {
    final kind = _responseKind(field, rest);
    final segments = _responsePathSegments(field, rest, kind);
    return GLRestResponse(
      kind: kind,
      pathSegments: segments,
      accept: rest?.getArgValueAsString(glRestAcceptArg) ?? _defaultAccept[kind]!,
      allowsEmptyBody: field.type.nullable || kind == RestResponseKind.none,
    );
  }

  String? resolveRestContentType(GLField field, GLDirectiveValue? rest, RestBodyKind bodyKind) {
    final declared = rest?.getArgValueAsString(glRestContentTypeArg);
    if (declared == null) return _defaultContentTypes[bodyKind];
    if (bodyKind != RestBodyKind.json && bodyKind != RestBodyKind.raw) {
      throw ParseException(
          "contentType on '${field.name.token}' only applies to a JSON or raw body, but its body is ${bodyKind.name}",
          info: field.name);
    }
    return declared;
  }

  void validateMarkerScalars() {
    _validateMarkerScalar(glDownload, downloadScalarNames);
    _validateMarkerScalar(glVoid, voidScalarNames);
  }

  void _validateMarkerScalar(String directive, Set<String> names) {
    final misplaced = <GLToken>[
      ...types.values.where((t) => t.hasDirective(directive)),
      ...inputs.values.where((t) => t.hasDirective(directive)),
      ...interfaces.values.where((t) => t.hasDirective(directive)),
    ];
    for (final token in misplaced) {
      throw ParseException("$directive is only allowed on a scalar, not on '${token.token}'", info: token.tokenInfo);
    }
    if (names.isEmpty) return;
    for (final query in queries.values) {
      for (final arg in query.arguments) {
        if (names.contains(arg.type.firstType.token)) {
          throw ParseException(
              "Scalar '${arg.type.firstType.token}' ($directive) cannot be used in the GraphQL operation '${query.token}': it is only valid as the return type of a REST operation",
              info: arg.tokenInfo);
        }
      }
    }
    final roots = {for (final type in GLQueryType.values) schema.getByQueryType(type): type};
    for (final entry in [...types.entries, ...interfaces.entries, ...inputs.entries]) {
      for (final field in entry.value.fields) {
        for (final arg in field.arguments) {
          if (names.contains(arg.type.firstType.token)) {
            throw ParseException("Scalar '${arg.type.firstType.token}' ($directive) cannot be an argument", info: arg.tokenInfo);
          }
        }
        if (!names.contains(field.type.firstType.token)) continue;
        final operationType = types.containsKey(entry.key) ? roots[entry.key] : null;
        if (operationType == null) {
          throw ParseException(
              "Scalar '${field.type.firstType.token}' ($directive) can only be the return type of a REST operation, not a field of '${entry.key}'",
              info: field.name);
        }
        if (!restOperations.containsKey(GLOperationKey(field.name.token, operationType))) {
          throw ParseException(
              "Scalar '${field.type.firstType.token}' ($directive) cannot be used in a GraphQL operation: '${field.name.token}' must be a REST operation, add $glRest",
              info: field.name);
        }
      }
    }
  }

  RestResponseKind _responseKind(GLField field, GLDirectiveValue? rest) {
    final declared = _declaredKind(field, rest);
    final returned = field.type;
    if (voidScalarNames.contains(returned.firstType.token)) {
      if (returned is GLListType) {
        throw ParseException("Void scalar '${returned.firstType.token}' cannot be returned as a list from '${field.name.token}'",
            info: field.name);
      }
      if (declared != null) {
        throw ParseException("'${field.name.token}' returns Void, which has no response body: remove response: ${declared.name.toUpperCase()}",
            info: field.name);
      }
      return RestResponseKind.none;
    }
    final isDownload = downloadScalarNames.contains(returned.firstType.token);
    if (isDownload) {
      if (returned is GLListType) {
        throw ParseException("Download scalar '${returned.firstType.token}' cannot be returned as a list from '${field.name.token}'",
            info: field.name);
      }
      if (declared != null && declared != RestResponseKind.binary) {
        throw ParseException("'${field.name.token}' returns a download, which is always binary: remove response: ${declared.name.toUpperCase()}",
            info: field.name);
      }
      return RestResponseKind.binary;
    }
    if (declared == RestResponseKind.binary) {
      throw ParseException("response: BINARY on '${field.name.token}' needs a return type marked $glDownload", info: field.name);
    }
    if (declared == RestResponseKind.text && (returned is GLListType || returned.firstType.token != 'String')) {
      throw ParseException("response: TEXT on '${field.name.token}' needs a plain String return type", info: field.name);
    }
    return declared ?? RestResponseKind.json;
  }

  RestResponseKind? _declaredKind(GLField field, GLDirectiveValue? rest) {
    final value = rest?.getArgValueAsString(glRestResponseArg);
    if (value == null) return null;
    for (final kind in RestResponseKind.values) {
      if (kind.name.toUpperCase() == value) return kind;
    }
    throw ParseException("Unknown response kind '$value' on '${field.name.token}', expected JSON, TEXT or BINARY", info: field.name);
  }

  List<String> _responsePathSegments(GLField field, GLDirectiveValue? rest, RestResponseKind kind) {
    final path = rest?.getArgValueAsString(glRestResponsePathArg);
    if (path == null) return const [];
    if (kind != RestResponseKind.json) {
      throw ParseException("responsePath on '${field.name.token}' only applies to a JSON response", info: field.name);
    }
    final segments = path.split('.');
    if (segments.any((s) => s.isEmpty)) {
      throw ParseException("responsePath '$path' on '${field.name.token}' must be dot-separated keys like data.items", info: field.name);
    }
    return segments;
  }
}
