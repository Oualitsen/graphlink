import 'package:graphlink/src/serializers/java/java_imports.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/java_code_gen_utils.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_rest_discriminator.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/serializers/java/java_serializer.dart';

class JavaInterfaceSerializer {
  final JavaSerializer _owner;
  const JavaInterfaceSerializer(this._owner);

  String serializeGetterDeclaration(GLField field,
      {bool skipModifier = false, bool asProperty = false, GLInterfaceDefinition? owner}) {
    var returnType = _owner.serializeType(field.type);
    final type = field.type;
    if (type is GLListType) {
      // Java generics are invariant: List<Alpha> is not a subtype of
      // List<Node> even when Alpha implements Node. A covariant override
      // only type-checks if the interface declares `List<? extends Node>`.
      // Only emit the wildcard when some implementer actually narrows this
      // field — otherwise keep the plain `List<Node>` return type, which is
      // the ergonomic default for callers.
      final needsWildcard = owner != null && _isFieldNarrowedInImplementers(owner, field);
      returnType = needsWildcard ? _owner.wildcardListReturnType(type) : JavaCodeGenUtils.listOf(_owner.grammar, _owner.serializeType(type.inlineType));
    }
    var result = returnType;
    if (asProperty) {
      result = "$result ${field.codeName}";
    } else {
      final name = owner != null
          ? _owner.getterName(owner, field.name.token)
          : (returnType == "boolean" ? "is${field.codeName.firstUp}" : "get${field.codeName.firstUp}");
      result = "$result $name";
    }
    result = "$result()";
    if (skipModifier) {
      return result;
    }
    return "public $result";
  }

  /// Whether some serializable implementer of [owner] narrows [field]
  /// (a list field) to a different element type than [owner] declares —
  /// e.g. `interface Base { nodeList: [Node!]! }` with
  /// `type Dog implements Base { nodeList: [Alpha!]! }`. Java generics are
  /// invariant, so such an override only compiles if the interface getter
  /// returns `List<? extends Node>` instead of `List<Node>`.
  bool _isFieldNarrowedInImplementers(GLInterfaceDefinition owner, GLField field) {
    if (!field.type.isList) return false;
    final declaredToken = field.type.inlineType.firstType.token;
    for (final impl in owner.getSerializableImplementations(_owner.mode)) {
      final implField = impl.getFieldByName(field.name.token);
      if (implField == null || !implField.type.isList) continue;
      if (implField.type.inlineType.firstType.token != declaredToken) return true;
    }
    return false;
  }

  String _serializeInterfaceField(GLField f, bool getters, GLInterfaceDefinition owner, {bool forceClassGetters = false}) {
    var buffer = StringBuffer();
    if (getters) {
      var fieldDecorators = _owner.serializeDecorators(f.getDirectives(), joiner: "\n");
      if (fieldDecorators.isNotEmpty) {
        buffer.writeln(fieldDecorators.trim().ident());
      }
      if (_owner.typesAsRecords && !forceClassGetters) {
        buffer.write(serializeGetterDeclaration(f, skipModifier: true, asProperty: true, owner: owner).ident());
      } else {
        buffer.write(serializeGetterDeclaration(f, skipModifier: true, owner: owner).ident());
      }
    } else {
      // _owner.serializeMethod already emits the field's decorators.
      buffer.write(_owner.serializeMethod(f).ident());
    }
    buffer.write(";");
    return buffer.toString();
  }

  String serializeInterface(GLInterfaceDefinition interface,
      {required bool getters, bool forceClassGetters = false, bool skipJsonConversionMethods = false}) {
    final codeName = interface.codeName;
    final interfaces = interface.interfaces;
    final fields = interface.getSerializableFields(_owner.grammar.mode);
    var decorators = _owner.serializeDecorators(interface.getDirectives());
    var buffer = StringBuffer();
    if (decorators.isNotEmpty) {
      buffer.writeln(decorators.trim());
    }
    bool generateJsonConverstionMethods = !skipJsonConversionMethods && interface.getDirectiveByName(glInterfaceFieldAsProperties) == null;
    if (generateJsonConverstionMethods) {
      interface.addImport(JavaImports.map);
    }
    buffer.writeln(_owner.codeGenUtils
        .createInterface(interfaceName: codeName, interfaceNames: interfaces.map((e) => _owner.resolveCodeName(e.tokenInfo.token)).toList(), statements: [
      ...fields.map((f) => _serializeInterfaceField(f, getters, interface, forceClassGetters: forceClassGetters)),
      if (generateJsonConverstionMethods && interface.getSerializableImplementations(_owner.mode).isNotEmpty) ...[
        "",
        "Map<String, Object> toJson();",
        interface.syntheticImplementation != null
            ? _owner.serializeSyntheticInterfaceFromJson(interface)
            : _serializeFromJsonForInterface(codeName, interface.getSerializableImplementations(_owner.mode))
      ]
    ]));
    return buffer.toString();
  }

  String _discriminatedFromJson(String token, Set<GLTypeDefinition> subTypes, GLRestDiscriminator discriminator) {
    String typeName(GLTypeDefinition t) => t.derivedFromType?.tokenInfo.token ?? t.tokenInfo.token;
    final byTypename = _owner.codeGenUtils.switchStatement(
      expression: 'typename',
      cases: [
        for (final t in subTypes)
          JavaCaseStatement(caseValue: '"${typeName(t)}"', statement: 'return ${t.codeName}.fromJson(json);'),
      ],
      defaultStatements: ['break;'],
    );
    final byValue = _owner.codeGenUtils.switchStatement(
      expression: 'value',
      cases: [
        for (final t in subTypes)
          JavaCaseStatement(
              caseValue: '"${discriminator.valueByType[typeName(t)] ?? typeName(t)}"',
              statement: 'return ${t.codeName}.fromJson(json);'),
      ],
      defaultStatements: [
        'throw new IllegalArgumentException("Cannot decode $token: unknown \\"${discriminator.field}\\" value (" + value + ")");',
      ],
    );
    return _owner.codeGenUtils.createMethod(
      returnType: 'static $token',
      methodName: 'fromJson',
      arguments: ['${mapOf("String", "Object")} json'],
      statements: [
        'String typename = (String)json.get("__typename");',
        _owner.codeGenUtils.ifStatement(condition: 'typename != null', ifBlockStatements: [byTypename]),
        'Object discriminator = json.get("${discriminator.field}");',
        _owner.codeGenUtils.ifStatement(
          condition: 'discriminator == null',
          ifBlockStatements: ['throw new IllegalArgumentException("Cannot decode $token: missing \\"${discriminator.field}\\" value");'],
        ),
        'String value = discriminator.toString();',
        byValue,
      ],
    );
  }

  String _serializeFromJsonForInterface(String token, Set<GLTypeDefinition> subTypes) {
    if (subTypes.isEmpty) {
      return "";
    }
    final discriminator = _owner.grammar.restDiscriminators[token];
    if (discriminator != null) return _discriminatedFromJson(token, subTypes, discriminator);
    return _owner.codeGenUtils.createMethod(
      returnType: "static $token",
      methodName: "fromJson",
      arguments: ["${mapOf("String", "Object")} json"],
      statements: [
        'String typename = (String)json.get("__typename");',
        _owner.codeGenUtils.switchStatement(
          expression: "typename",
          cases: [
            for (var st in subTypes)
              JavaCaseStatement(
                caseValue: '"${st.derivedFromType?.tokenInfo.token ?? st.tokenInfo.token}"',
                statement: "return ${st.codeName}.fromJson(json);",
              ),
          ],
          defaultStatements: [
            'throw new RuntimeException(String.format("Invalid type %s. %s does not implement $token or not defined", typename, typename));',
          ],
        ),
      ],
    );
  }
}
