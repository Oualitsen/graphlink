import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/scalar_codec.dart';

enum _Side { encode, decode }

class _Usage {
  final _Side side;
  final String what;
  final String where;
  const _Usage(this.side, this.what, this.where);
}

extension GLGrammarScalarCodecExtension on GLParser {
  GLScalarCodec? scalarCodecOf(String scalarToken) => scalarCodecs[scalarToken];

  Set<String> scalarImportsOfOperation(GLQueryDefinition operation) => {
        for (final arg in operation.arguments) ...?scalarCodecOf(arg.type.token)?.imports,
      };

  Set<String> scalarImportsOfFields(GLTokenWithFields token) => {
        for (final field in token.fields) ...?scalarCodecOf(field.type.token)?.imports,
      };

  Set<String> scalarImportsOfOperations(Iterable<GLQueryDefinition> operations) => {
        for (final op in operations) ...scalarImportsOfOperation(op),
      };

  Set<String> scalarImportsOfRestOperation(GLRestOperation operation) => {
        for (final arg in operation.arguments) ...?scalarCodecOf(arg.argument.type.token)?.imports,
      };

  Set<String> scalarImportsOfOperationType(GLQueryType type) => {
        ...scalarImportsOfOperations(queries.values.where((q) => q.type == type)),
        for (final op in restOperations.values.where((o) => o.type == type)) ...scalarImportsOfRestOperation(op),
      };

  void validateScalarCodecs() {
    for (final entry in scalarCodecs.entries) {
      final codec = entry.value;
      if (codec.isAlias && codec.imports.isEmpty) continue;
      if (!scalars.containsKey(entry.key)) {
        throw ParseException('typeMappings["${entry.key}"] has a codec or imports but the schema declares no scalar ${entry.key}.');
      }
    }
    final codecs = {for (final e in scalarCodecs.entries) if (!e.value.isAlias) e.key: e.value};
    if (codecs.isEmpty) return;
    _rejectDefaults(codecs);
    for (final usage in _scalarUsages(codecs.keys.toSet()).entries) {
      final codec = codecs[usage.key]!;
      for (final u in usage.value) {
        final missing = u.side == _Side.encode ? !codec.canEncode : !codec.canDecode;
        if (!missing) continue;
        final key = u.side == _Side.encode ? 'toJson' : 'fromJson';
        throw ParseException(
          'typeMappings["${usage.key}"] has no $key but ${usage.key} is used as ${u.what} (${u.where}). '
          'Declare "$key", or write "$key": "{}" to pass the value through.',
        );
      }
    }
  }

  void _rejectDefaults(Map<String, GLScalarCodec> codecs) {
    void check(GLType type, Object? initialValue, String where) {
      if (initialValue == null || !codecs.containsKey(type.token)) return;
      throw ParseException(
        'A default value on ${type.token} ($where) is not supported: typeMappings["${type.token}"] converts it, '
        'and the default is a wire value. Remove the default or map ${type.token} to a plain type.',
      );
    }

    for (final def in [...types.values, ...interfaces.values]) {
      for (final field in def.fields) {
        for (final arg in field.arguments) {
          check(arg.type, arg.defaultValue, '${def.token}.${field.name.token}(${arg.token})');
        }
      }
    }
    for (final input in inputs.values) {
      for (final field in input.fields) {
        check(field.type, field.initialValue, '${input.token}.${field.name.token}');
      }
    }
    for (final op in queries.values) {
      for (final arg in op.arguments) {
        check(arg.type, arg.defaultValue, '${op.token}(${arg.token})');
      }
    }
  }

  Map<String, List<_Usage>> _scalarUsages(Set<String> wanted) {
    final result = <String, List<_Usage>>{};
    void add(GLType type, _Usage usage) {
      if (wanted.contains(type.token)) result.putIfAbsent(type.token, () => []).add(usage);
    }

    for (final def in [...types.values, ...interfaces.values]) {
      for (final field in def.fields) {
        final where = '${def.token}.${field.name.token}';
        add(field.type, _Usage(_Side.decode, 'a response field', where));
        for (final arg in field.arguments) {
          add(arg.type, _Usage(_Side.encode, 'an argument', '$where(${arg.token})'));
        }
      }
    }
    for (final input in inputs.values) {
      for (final field in input.fields) {
        add(field.type, _Usage(_Side.encode, 'an input field', '${input.token}.${field.name.token}'));
      }
    }
    for (final op in queries.values) {
      for (final arg in op.arguments) {
        add(arg.type, _Usage(_Side.encode, 'an operation variable', '${op.token}(${arg.token})'));
      }
    }
    return result;
  }
}
