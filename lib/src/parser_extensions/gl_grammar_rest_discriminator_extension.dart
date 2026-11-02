import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_rest_discriminator.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

extension GLGrammarRestDiscriminatorExtension on GLParser {
  void resolveRestDiscriminators() {
    restDiscriminators.clear();
    _rejectMisplacedDiscriminators();
    for (final union in unions.values) {
      final directive = union.getDirectiveByName(glRestDiscriminator);
      if (directive != null) {
        _register(union, directive, union.typeNames.map((t) => t.token).toList());
      }
    }
    for (final iface in interfaces.values.where((i) => !i.fromUnion)) {
      final directive = iface.getDirectiveByName(glRestDiscriminator);
      if (directive != null) {
        _register(iface, directive, getTypesImplementing(iface).map((t) => t.token).toList());
      }
    }
  }

  void _rejectMisplacedDiscriminators() {
    final misplaced = <GLToken>[
      ...types.values.where((t) => t.hasDirective(glRestDiscriminator)),
      ...inputs.values.where((t) => t.hasDirective(glRestDiscriminator)),
    ];
    for (final token in misplaced) {
      throw ParseException("$glRestDiscriminator is only allowed on an interface or union, not on '${token.token}'",
          info: token.tokenInfo);
    }
  }

  void _register(GLToken parent, GLDirectiveValue directive, List<String> members) {
    final field = directive.getArgValueAsString(glRestDiscriminatorFieldArg);
    if (field == null) {
      throw ParseException("$glRestDiscriminator on '${parent.token}' needs a field argument", info: parent.tokenInfo);
    }
    final declared = _declaredValues(directive);
    for (final type in declared.keys.where((t) => !members.contains(t))) {
      throw ParseException("$glRestDiscriminator on '${parent.token}' names '$type', which is not one of its members",
          info: parent.tokenInfo);
    }
    final valueByType = {for (final m in members) m: declared[m] ?? m};
    final owners = <String, String>{};
    for (final entry in valueByType.entries) {
      final other = owners[entry.value];
      if (other != null) {
        throw ParseException(
            "Members '$other' and '${entry.key}' of '${parent.token}' share the discriminator value '${entry.value}'",
            info: parent.tokenInfo);
      }
      owners[entry.value] = entry.key;
    }
    restDiscriminators[parent.token] =
        GLRestDiscriminator(parent: parent.token, field: field, valueByType: valueByType);
  }

  Map<String, String> _declaredValues(GLDirectiveValue directive) {
    final values = directive.getArgValue(glRestDiscriminatorValuesArg);
    if (values is! Map) return {};
    return {for (final e in values.entries) '${e.key}': '${e.value}'.removeQuotes()};
  }
}
