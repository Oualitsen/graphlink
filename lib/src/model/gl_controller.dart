import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_token_with_fields.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_token.dart';

class GLController extends GLService {
  final String serviceName;
  GLController({
    required this.serviceName,
    required super.name,
    required super.nameDeclared,
    required super.fields,
    required super.interfaceNames,
    required super.directives,
    required super.parser,
  });

  static GLController ofService(GLService service, GLParser parser) {
    var ctrl = GLController(
      serviceName: service.token,
      name: "${service.token}Controller".toToken(),
      nameDeclared: service.nameDeclared,
      fields: [],
      interfaceNames: {},
      directives: [],
      parser: parser,
    );
    for (var f in service.fields) {
      var validationDirective = f.getDirectiveByName(glValidate);
      if (validationDirective == null || !validationDirective.generated) {
        var typeToken = f.type.token;
        GLField targetField;
        if (parser.types.containsKey(typeToken) || parser.interfaces.containsKey(typeToken)) {
          var type = parser.getTokenByKey(f.type.token)! as GLTypeDefinition;
          targetField = GLField(
            name: f.name,
            type: f.type.ofNewName(type.serverProjectionName.toToken()),
            arguments: [...f.arguments.map((arg) => GLArgumentDefinition(arg.tokenInfo, arg.type.copy, []))],
            directives: [...f.getDirectives()],
            initialValue: f.initialValue,
            documentation: f.documentation,
          );
        } else {
          targetField = GLField(
              name: f.name,
              type: f.type.copy,
              arguments: [...f.arguments.map((arg) => GLArgumentDefinition(arg.tokenInfo, arg.type.copy, []))],
              directives: [...f.getDirectives()]);
        }
        ctrl.addField(targetField);
        ctrl.setFieldType(f.name.token, service.getTypeByFieldName(f.name.token)!);
      }
    }
    return ctrl;
  }

  @override
  void addMapping(GLSchemaMapping mapping) {
    String newTypeName = mapping.type.token;
    String newFieldTypeName = mapping.field.type.token;
    if (parser.interfaces.containsKey(newFieldTypeName) || parser.types.containsKey(newFieldTypeName)) {
      newFieldTypeName = GLTypeDefinition.getServerProjectionName(newFieldTypeName);
    }
    final newMapping = mapping.ofNewTypes(mapping, newTypeName, newFieldTypeName, mapping.key);
    if (mapping.isBatch && !mapping.identity) {
      // A (non-identity) batch mapping's real return shape is `Map<Key,
      // Value>` — model it as a GLMapType so the serializer's generic
      // GLMapType handling (and any wrapper later applied, e.g.
      // CompletableFuture/Mono) lands on the whole map instead of on the
      // value type embedded inside it. Identity batch mappings return
      // List<Value>/Flux<Value> directly (the value already is the key), so
      // they keep the bare value type.
      final keyType = GLType(mapping.getMappedToType(parser).tokenInfo, false);
      newMapping.field = newMapping.field.ofType(GLMapType(keyType, newMapping.field.type, false));
    }
    super.addMapping(newMapping);
  }

  @override
  Set<GLToken> getImportDependecies(GLParser g) {
    var result = {...super.getImportDependecies(g)};
    if (g.services.containsKey(serviceName)) {
      result.add(g.services[serviceName]!);
    }
    return result;
  }

  /// [GLTokenWithFields.getImports] only walks regular fields — schema/batch
  /// mapping methods live in [mappings] instead, so their return types,
  /// arguments, and directive-declared imports (e.g. the `Mono`/`Flux`/
  /// `CompletableFuture` wrapper set by the Spring controller serializer, or
  /// `Map<String, Object>` from JVM wire-encoding mappification) would
  /// otherwise never make it into the controller's import block.
  @override
  Set<String> getImports(GLParser g) {
    var result = {...super.getImports(g)};
    for (var mapping in mappings) {
      final field = mapping.field;
      result.addAll(GLTokenWithFields.extractImports(field, g.mode, skipOwnImports: false));
      result.addAll(collectionImportsOf(field.type));

      final token = g.getTokenByKey(field.type.token);
      if (token != null && token is GLDirectivesMixin) {
        result.addAll(GLTokenWithFields.extractImports(token as GLDirectivesMixin, g.mode, skipOwnImports: true));

        for (var arg in field.arguments) {
          result.addAll(GLTokenWithFields.extractImports(arg, g.mode, skipOwnImports: false));
          var argToken = g.getTokenByKey(arg.type.token);
          if (argToken != null && argToken is GLDirectivesMixin) {
            result.addAll(GLTokenWithFields.extractImports(argToken as GLDirectivesMixin, g.mode, skipOwnImports: true));
          }
        }
      }
      for (var arg in field.arguments) {
        result.addAll(arg.getAnnotations().map((e) => e.getArgValueAsString(glImport)).where((imp) => imp != null).map((e) => e!));
        result.addAll(arg.getImports(g));
      }
    }
    return result;
  }

  /// JVM Spring controller wire encoding: retypes [field]'s return type
  /// (enum -> `String`, projectable type -> `Map<String, Object>`) and any of
  /// its arguments carrying an input or projectable-type value the same way.
  /// [GLField.originalType] / [GLArgumentDefinition.originalArg] keep pointing
  /// back to the real type/argument so the serializer can still emit the
  /// `toJson`/`fromJson` conversion. Returns [field] unchanged when nothing
  /// needs mappification. Mutates [field]'s arguments in place.
  GLField mappifyForJvmController(GLField field) {
    final mappedField = _mappifyReturnType(field);
    _mappifyArguments(mappedField);
    return mappedField;
  }

  GLField _mappifyReturnType(GLField field) {
    final fieldType = field.type;
    if (parser.isEnum(fieldType.firstType.token) || parser.isProjectableType(fieldType.firstType.token)) {
      final mapped = field.ofType(_mappifyType(fieldType));
      // originalType is only ever consulted to build a *single-value*
      // toJson() conversion (e.g. `entry.getValue()`), so for a batch
      // mapping (fieldType wrapping the value in a GLMapType key/value
      // shape) it must point at the value alone, not the whole map.
      mapped.originalType = fieldType is GLMapType ? fieldType.valueType : fieldType;
      return mapped;
    }
    return field;
  }

  void _mappifyArguments(GLField field) {
    for (var arg in field.arguments) {
      if (parser.isInput(arg.type.firstType.token) || parser.types.containsKey(arg.type.firstType.token)) {
        final newArg = GLArgumentDefinition(
            arg.tokenInfo.ofNewName("${arg.token}AsMap"), _mappifyToJsonMapType(arg.type), arg.getDirectives());
        field.addArgument(newArg);
        field.removeArgument(arg.tokenInfo.token);
        newArg.originalArg = arg;
      }
    }
  }

  /// Recurses through [GLListType] nesting, replacing the innermost element
  /// type with `String` (enum) or `Map<String, Object>` (projectable type) —
  /// e.g. `[User!]!` becomes `List<Map<String, Object>>`, not a flattened
  /// `Map<String, Object>`. Preserves [GLType.wrapper]/[GLType.wrapperImport]
  /// (e.g. the `Flux` wrapper set on a subscription's return type) at every
  /// level so mappification doesn't drop it.
  GLType _mappifyType(GLType type) {
    if (type is GLMapType) {
      // The key (e.g. a batch mapping's parent identity) is never mappified —
      // only the value shares the enum/projectable -> String/Map<String,Object>
      // treatment.
      return GLMapType(type.keyType, _mappifyType(type.valueType), type.nullable, wrapper: type.wrapper, wrapperImport: type.wrapperImport);
    }
    if (type is GLListType) {
      return GLListType(_mappifyType(type.inlineType), type.nullable, wrapper: type.wrapper, wrapperImport: type.wrapperImport);
    }
    if (parser.isEnum(type.token)) {
      return type.ofNewName('String'.toToken());
    }
    return _jsonMapType(type.nullable, wrapper: type.wrapper, wrapperImport: type.wrapperImport);
  }

  /// Recurses through [GLListType] nesting, unconditionally replacing the
  /// innermost element type with `Map<String, Object>` — used for arguments,
  /// where the caller has already established mappification is needed.
  GLType _mappifyToJsonMapType(GLType type) {
    if (type is GLListType) {
      return GLListType(_mappifyToJsonMapType(type.inlineType), type.nullable, wrapper: type.wrapper, wrapperImport: type.wrapperImport);
    }
    return _jsonMapType(type.nullable, wrapper: type.wrapper, wrapperImport: type.wrapperImport);
  }

  GLMapType _jsonMapType(bool nullable, {String? wrapper, String? wrapperImport}) => GLMapType(
      GLType('String'.toToken(), false), GLType('Object'.toToken(), false), nullable,
      wrapper: wrapper, wrapperImport: wrapperImport);
}
