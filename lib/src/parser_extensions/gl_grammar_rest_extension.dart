import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_arguments_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_response_extension.dart';

extension GLGrammarRestExtension on GLParser {
  /// Extension blocks are merged by type name, which loses which block a field came from.
  /// The prefix therefore moves onto the fields of its own block and leaves the type.
  List<GLDirectiveValue> pushRestPrefixToFields(
      List<GLDirectiveValue> typeDirectives, List<GLField> fields) {
    final matching = typeDirectives.where((d) => d.token == glRestPrefix);
    if (matching.isEmpty) return typeDirectives;
    final prefix = matching.first;
    for (final field in fields) {
      field.addDirective(GLDirectiveValue(
          prefix.tokenInfo, [GLDirectiveScope.FIELD_DEFINITION], prefix.getArguments(),
          generated: false));
    }
    return typeDirectives.where((d) => d.token != glRestPrefix).toList();
  }

  void resolveRestOperations() {
    restOperations.clear();
    final rootNames = {
      for (final type in GLQueryType.values) schema.getByQueryType(type): type,
    };
    for (final entry in types.entries) {
      final operationType = rootNames[entry.key];
      for (final field in entry.value.fields) {
        final isRest = field.hasDirective(glRest) || field.hasDirective(glRestPrefix);
        if (!isRest) continue;
        if (operationType == null) {
          throw ParseException(
              "${field.hasDirective(glRest) ? glRest : glRestPrefix} is only allowed on fields of the Query or Mutation type",
              info: field.name);
        }
        if (operationType == GLQueryType.subscription) {
          throw ParseException(
              "$glRest cannot be used on subscription '${field.name.token}': subscriptions are always GraphQL",
              info: field.name);
        }
        final operation = _resolveRestOperation(field, operationType);
        restOperations[operation.key] = operation;
      }
    }
  }

  GLRestOperation _resolveRestOperation(GLField field, GLQueryType type) {
    final rest = field.getDirectiveByName(glRest);
    final prefix = field.getDirectiveByName(glRestPrefix);
    final method = _resolveMethod(field, rest, prefix, type);
    final path = _joinRestPath(field, prefix, rest);
    final placeholders = restPlaceholder.allMatches(path).map((m) => m.group(1)!).toList();
    final arguments = resolveRestArguments(field, method, placeholders);
    final bodyKind = resolveRestBodyKind(field, method, arguments);
    return GLRestOperation(
      field: field,
      type: type,
      method: method,
      path: path,
      placeholders: placeholders,
      arguments: arguments,
      bodyKind: bodyKind,
      bodyIsOptional: resolveRestBodyOptional(bodyKind, arguments),
      response: resolveRestResponse(field, rest),
      contentType: resolveRestContentType(field, rest, bodyKind),
    );
  }

  RestMethod _resolveMethod(
      GLField field, GLDirectiveValue? rest, GLDirectiveValue? prefix, GLQueryType type) {
    final declared = rest?.getArgValueAsString(glRestMethodArg) ?? prefix?.getArgValueAsString(glRestMethodArg);
    if (declared == null) {
      return type == GLQueryType.query ? RestMethod.get : RestMethod.post;
    }
    final method = RestMethod.parse(declared);
    if (method == null) {
      throw ParseException(
          "Unknown REST method '$declared' on '${field.name.token}', expected one of ${RestMethod.values.map((m) => m.wireName).join(', ')}",
          info: field.name);
    }
    return method;
  }

  String _joinRestPath(GLField field, GLDirectiveValue? prefix, GLDirectiveValue? rest) {
    final prefixPath = prefix?.getArgValueAsString(glRestPathArg);
    final fieldPath = rest?.getArgValueAsString(glRestPathArg);
    if (prefixPath == null && fieldPath == null) {
      throw ParseException("$glRest on '${field.name.token}' needs a path", info: field.name);
    }
    final segments = [prefixPath, fieldPath]
        .whereType<String>()
        .expand((p) => p.split('/'))
        .where((s) => s.isNotEmpty);
    return '/${segments.join('/')}';
  }

  void registerRestResponseTypes() {
    final roots = restOperations.values
        .map((op) => _declaredTypeNamed(op.field.type.firstType.token))
        .whereType<GLTypeDefinition>();
    for (final root in roots) {
      registerDeclaredTypeAsProjected(root);
    }
    _requireDiscriminators(roots);
  }

  GLTypeDefinition? _declaredTypeNamed(String name) => interfaces[name] ?? types[name];

  void _requireDiscriminators(Iterable<GLTypeDefinition> roots) {
    final visited = <String>{};
    final pending = [...roots];
    while (pending.isNotEmpty) {
      final type = pending.removeLast();
      if (!visited.add(type.token)) continue;
      if (type is GLInterfaceDefinition) {
        if (!restDiscriminators.containsKey(type.token)) {
          throw ParseException(
              "'${type.token}' is returned by a REST operation but has no discriminator: add $glRestDiscriminator(field: \"...\") to it",
              info: type.tokenInfo);
        }
        pending.addAll(getTypesImplementing(type));
      }
      for (final field in type.fields) {
        final next = _declaredTypeNamed(field.type.firstType.token);
        if (next != null) pending.add(next);
      }
    }
  }
}
