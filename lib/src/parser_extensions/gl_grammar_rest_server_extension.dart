import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_upload_extension.dart';
import 'package:graphlink/src/model/gl_rest_controller.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_validation_extension.dart';

extension GLGrammarRestServerExtension on GLParser {
  void resolveServerRestOperations() {
    resolveRestOperations();
    validateRestOperations();
    validateRestServerSupport();
  }

  bool isRestField(GLField field) => restOperations.values.any((op) => identical(op.field, field));

  List<GLRestOperation> restOperationsOf(GLService service) =>
      restOperations.values.where((op) => service.fields.any((f) => identical(f, op.field))).toList();

  void generateRestControllers() {
    restControllers.clear();
    restOnly = restOperations.isNotEmpty &&
        !services.values.any((service) => service.fields.any((f) => !isRestField(f) && f.getDirectiveByName(glValidate)?.generated != true));
    for (final service in services.values) {
      final operations = restOperationsOf(service);
      if (operations.isEmpty) continue;
      final controller = GLRestController(service: service, operations: operations, parser: this);
      restControllers[controller.token] = controller;
    }
  }

  void validateRestServerSupport() {
    for (final op in restOperations.values) {
      _rejectUnsupportedArguments(op);
    }
  }

  void _rejectUnsupportedArguments(GLRestOperation op) {
    for (final arg in op.arguments) {
      final name = arg.name;
      final type = arg.argument.type;
      if (arg.role == RestArgRole.field) _rejectUnsupportedFormField(op, arg);
      if (arg.role == RestArgRole.part && _isInput(type)) {
        _unsupported(op, 'the multipart argument \'$name\' (an input object as a part; use scalars, enums, lists of them or uploads)');
      }
      if (arg.role == RestArgRole.part && type.isList && type.inlineType.isList) {
        _unsupported(op, 'the multipart argument \'$name\' (a list of lists)');
      }
      if ((arg.role == RestArgRole.query || arg.role == RestArgRole.field) && _isInput(type)) _rejectRecursiveInput(op, arg);
      if (arg.role == RestArgRole.query && type.isList && type.inlineType.isList) {
        _unsupported(op, 'the query argument \'$name\' (a list of lists)');
      }
      if (arg.role == RestArgRole.header && type.isList && type.inlineType.isList) {
        _unsupported(op, 'the header argument \'$name\' (a list of lists)');
      }
    }
  }

  void _rejectUnsupportedFormField(GLRestOperation op, GLRestArgument arg) {
    final type = arg.argument.type;
    final name = arg.name;
    if (type.isList && type.inlineType.isList) _unsupported(op, 'the form argument \'$name\' (a list of lists)');
  }

  /// An input object, a list of them, or any value sent as JSON text, carried by the query string or a form: the server
  /// reads it out of nested keys (`address.city`, `items[0][name]`) or parses the text.
  bool usesStructuredParams(GLRestArgument arg) {
    if (arg.role != RestArgRole.query && arg.role != RestArgRole.field) return false;
    if (arg.encoding == RestEncoding.json) return true;
    final type = arg.argument.type;
    if (!_isInput(type)) return false;
    if (arg.role == RestArgRole.query && arg.encoding == RestEncoding.spread) {
      return inputs[type.firstType.token]!.fields.any((field) => _isInput(field.type));
    }
    return true;
  }

  bool get restUsesStructuredParams => restOperations.values.any((op) => op.arguments.any(usesStructuredParams));

  bool _isInput(GLType type) => inputs.containsKey(type.firstType.token);

  /// True when a GraphQL operation (not a REST one) takes an upload: only then the GraphQL side needs the upload scalar.
  bool get graphQLUsesUpload {
    final roots = {for (final type in GLQueryType.values) schema.getByQueryType(type)};
    return roots.any((root) => (types[root]?.fields ?? const <GLField>[]).any((field) =>
        !isRestField(field) && field.arguments.any((a) => uploadScalarNames.contains(a.type.firstType.token))));
  }

  void _rejectRecursiveInput(GLRestOperation op, GLRestArgument arg) {
    final path = <String>[];
    bool recursive(String name) {
      if (path.contains(name)) return true;
      path.add(name);
      final found = inputs[name]!.fields.where((f) => _isInput(f.type)).any((f) => recursive(f.type.firstType.token));
      path.removeLast();
      return found;
    }

    if (recursive(arg.argument.type.firstType.token)) {
      _unsupported(op, 'the argument \'${arg.name}\' (a recursive input object cannot be flattened into query or form keys)');
    }
  }

  void _unsupported(GLRestOperation op, String what) {
    throw ParseException(
        "The REST operation '${op.name}' uses $what, which the generated server does not support yet",
        info: op.field.name);
  }
}
