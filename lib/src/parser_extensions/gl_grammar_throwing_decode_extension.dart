import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';

final _throwingCache = Expando<Set<String>>();

extension GLGrammarThrowingDecodeExtension on GLParser {
  /// Whether decoding a value of [typeToken] from JSON can fail on the wire data: the token is
  /// an interface or union that dispatches on `__typename` / a discriminator, or an object
  /// that holds such a value, directly or through other objects.
  bool decodesWithThrows(String typeToken) => (_throwingCache[this] ??= _computeThrowing()).contains(typeToken);

  Set<String> _computeThrowing() {
    final interfaces = {...this.interfaces, ...projectedInterfaces};
    final objects = <String, GLTypeDefinition>{...types, ...projectedTypes};
    final throwing = <String>{
      for (final entry in interfaces.entries)
        if (_hasDispatch(entry.value)) entry.key,
    };

    bool holdsThrowing(GLTypeDefinition type) => type
        .getSerializableFields(mode)
        .any((field) => throwing.contains(field.type.firstType.token));

    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in interfaces.entries) {
        final synthetic = entry.value.syntheticImplementation;
        if (synthetic != null && !throwing.contains(entry.key) && throwing.contains(synthetic.token)) {
          throwing.add(entry.key);
          changed = true;
        }
      }
      for (final entry in objects.entries) {
        if (throwing.contains(entry.key) || entry.value is GLInterfaceDefinition) continue;
        if (holdsThrowing(entry.value)) {
          throwing.add(entry.key);
          changed = true;
        }
      }
    }
    return throwing;
  }

  bool _hasDispatch(GLInterfaceDefinition def) =>
      !def.skipJsonMethods && def.syntheticImplementation == null && def.getSerializableImplementations(mode).isNotEmpty;
}
