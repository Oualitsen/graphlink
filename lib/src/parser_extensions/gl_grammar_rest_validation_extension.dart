import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_response_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';

const _maxListLevels = 2;

extension GLGrammarRestValidationExtension on GLParser {
  void validateRestOperations() {
    validateMarkerScalars();
    final routes = <String, GLRestOperation>{};
    _rejectGraphQLDocumentsSelectingRestFields();
    for (final op in restOperations.values) {
      _checkRoute(op, routes);
      _checkCaptureErrors(op);
      _checkCacheDirectives(op);
      _checkEntryClashes(op);
      for (final arg in op.arguments) {
        _checkUploadDepth(arg);
        _checkListDepth(arg);
      }
    }
  }

  void _rejectGraphQLDocumentsSelectingRestFields() {
    for (final query in queries.values) {
      for (final element in query.elements) {
        if (restOperations.containsKey(GLOperationKey(element.token, query.type))) {
          throw ParseException(
              "'${element.token}' is a REST operation and cannot be selected in the GraphQL operation '${query.token}'",
              info: element.tokenInfo);
        }
      }
    }
  }

  void _checkCacheDirectives(GLRestOperation op) {
    final field = op.field;
    if (field.hasDirective(glCache) && field.hasDirective(glNoCache)) {
      throw ParseException("$glCache and $glNoCache on the same operation '${op.name}'", info: field.name);
    }
    final cached = field.hasDirective(glCache) || field.hasDirective(glNoCache);
    if (cached && op.type != GLQueryType.query) {
      throw ParseException("$glCache and $glNoCache are not allowed on mutation '${op.name}': mutations are never cached",
          info: field.name);
    }
    if (field.hasDirective(glCache) &&
        (op.responseKind == RestResponseKind.binary || op.responseKind == RestResponseKind.none)) {
      throw ParseException("$glCache cannot be used on '${op.name}': a download or a Void response is never cached", info: field.name);
    }
    if (field.hasDirective(glCache) && op.method != RestMethod.get) {
      throw ParseException("$glCache on '${op.name}' needs method GET, found ${op.method.wireName}", info: field.name);
    }
    if (field.hasDirective(glCacheInvalidate) && op.type != GLQueryType.mutation) {
      throw ParseException("$glCacheInvalidate is only allowed on mutations, not on '${op.name}'", info: field.name);
    }
  }

  void _checkRoute(GLRestOperation op, Map<String, GLRestOperation> routes) {
    final route = '${op.method.wireName} ${op.path.replaceAll(restPlaceholder, '{}')}';
    final other = routes[route];
    if (other != null) {
      throw ParseException("'${other.name}' and '${op.name}' have the same route $route", info: op.field.name);
    }
    routes[route] = op;
  }

  void _checkCaptureErrors(GLRestOperation op) {
    if (op.field.hasDirective(glCaptureErrors)) {
      throw ParseException(
          "$glCaptureErrors cannot be used on REST operation '${op.name}': a non-2xx response raises RestError",
          info: op.field.name);
    }
  }

  void _checkEntryClashes(GLRestOperation op) {
    final seen = <RestArgRole, Set<String>>{};
    for (final arg in op.arguments) {
      if (arg.role == RestArgRole.path || arg.role == RestArgRole.body) continue;
      final group = arg.role == RestArgRole.part ? RestArgRole.field : arg.role;
      final keys = seen.putIfAbsent(group, () => {});
      final names = arg.encoding == RestEncoding.spread ? arg.spreadFields.values : [arg.wireName!];
      for (final name in names) {
        final key = group == RestArgRole.header ? name.toLowerCase() : name;
        if (!keys.add(key)) {
          throw ParseException("'${op.name}' sends '$name' more than once (argument '${arg.name}')",
              info: arg.argument.tokenInfo);
        }
      }
    }
  }

  void _checkUploadDepth(GLRestArgument arg) {
    if (uploadScalarNames.contains(arg.argument.type.firstType.token) && _listLevels(arg.argument.type) > 1) {
      throw ParseException(
          "Upload argument '${arg.name}' must be a scalar or a single-level list: nested lists are not supported",
          info: arg.argument.tokenInfo);
    }
  }

  void _checkListDepth(GLRestArgument arg) {
    final type = arg.argument.type;
    if (arg.role == RestArgRole.header) {
      if (_listLevels(type) > 1) {
        throw ParseException("Argument '${arg.name}' is a list of lists and cannot be sent as a header",
            info: arg.argument.tokenInfo);
      }
      return;
    }
    final structured = arg.role == RestArgRole.query || arg.role == RestArgRole.field || arg.role == RestArgRole.part;
    if (!structured || arg.encoding == RestEncoding.json) return;
    final depth = _listLevels(type) + _fieldListLevels(type.firstType.token, {});
    if (depth > _maxListLevels) {
      throw ParseException(
          "Argument '${arg.name}' has $depth list levels, at most $_maxListLevels are supported: use encoding: JSON on this argument",
          info: arg.argument.tokenInfo);
    }
  }

  int _listLevels(GLType type) {
    var levels = 0;
    GLType current = type;
    while (current is GLListType) {
      levels++;
      current = current.type;
    }
    return levels;
  }

  int _fieldListLevels(String inputName, Set<String> visited) {
    final input = inputs[inputName];
    if (input == null || !visited.add(inputName)) return 0;
    var deepest = 0;
    for (final field in input.fields) {
      final depth = _listLevels(field.type) + _fieldListLevels(field.type.firstType.token, visited);
      if (depth > deepest) deepest = depth;
    }
    visited.remove(inputName);
    return deepest;
  }
}
