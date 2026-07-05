import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/extensions.dart';

class GLSchemaMapping {
  final GLTypeDefinition type;
  GLField field;
  final GLSchemaMapping? serviceMapping;

  ///
  /// when true, the generator should generate a @BatchMapping instead of @SchemaMapping (when false)
  ///
  final bool? batch;

  bool get isBatch => batch ?? false;

  ///
  /// when true, a @SchemaMapping should be generated to forbid access to field.
  ///
  final bool forbid;

  ///
  /// if true, no need to implement Type field(Type t) or Map<Type, Type> field(List<Type>)
  ///
  final bool identity;

  ///
  /// when true, the field exists on the mapTo server type with the same name/type/nullability.
  /// The controller forwards the call directly to the server type's getter — no service method needed.
  ///
  final bool forwarded;

  final String _key;

  GLSchemaMapping({
    required this.type,
    required this.field,
    this.batch,
    this.forbid = false,
    this.identity = false,
    this.forwarded = false,
    this.serviceMapping,
    String? key
  }): _key = key ??  "${type.token.firstLow}${field.name.token.firstUp}" {
    final glType = GLType(type.tokenInfo, false);
    if(!forbid) {
      field.addArgument(GLArgumentDefinition("value".toToken(), (batch ?? false) ? GLListType(glType, false) : glType, []));
    }
  }

  String get key => _key;

  /// Replaces [field]'s type with [newType], keeping the field's name,
  /// arguments, directives and nullability.
  void replaceFieldType(String newType) {
    field = field.ofType(field.type.ofNewName(TokenInfo.ofString(newType)));
  }

  

  /// Returns a copy of this mapping with [type] renamed to [newTypeName] and
  /// [field]'s type renamed to [newFieldTypeName].
  GLSchemaMapping ofNewTypes(GLSchemaMapping serviceMapping, String newTypeName, String newFieldTypeName, String key) {
    return GLSchemaMapping(
      serviceMapping: serviceMapping,
      type: GLTypeDefinition(
        name: type.tokenInfo.ofNewName(newTypeName),
        nameDeclared: type.nameDeclared,
        fields: type.fields,
        interfaceNames: type.interfaceNames,
        directives: type.getDirectives(),
        derivedFromType: type.derivedFromType,
        extension: type.extension,
        isResponseType: type.isResponseType,
        documentation: type.documentation,
      ),
      field: field.ofType(field.type.ofNewName(TokenInfo.ofString(newFieldTypeName))),
      batch: batch,
      forbid: forbid,
      identity: identity,
      forwarded: forwarded,
      key: key,
    );
  }

  GLTypeDefinition getMappedToType(GLParser parser) {
    final mappedToTypeName = type.getDirectiveByName(glSkipOnServer)?.getArgValueAsString(glMapTo);
    if(mappedToTypeName == null) {
      return type;
    }
    return parser.types[mappedToTypeName]!;
  }
}
