import 'package:graphlink/src/constants.dart';
import 'package:graphlink/src/exceptions/parse_exception.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_directives_mixin.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_query_element.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/new_parser/gl_parser.dart';
import 'package:graphlink/src/serializers/code_generation_mode.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/utils.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';

const String allFieldsFragmentsFileName = "allFieldsFragments";

const allFields = '_all_fields';

extension GLGrammarExtension on GLParser {
  GLToken? getTokenByKey(String key) {
    GLToken? token;

    if (isEnum(key)) {
      token = enums[key]!;
    } else if (types.containsKey(key)) {
      token = types[key]!;
    } else if (interfaces.containsKey(key)) {
      token = interfaces[key]!;
    } else if (isScalar(key)) {
      token = scalars[key];
    } else if (projectedTypes.containsKey(key)) {
      token = projectedTypes[key]!;
    } else if (projectedInterfaces.containsKey(key)) {
      token = projectedInterfaces[key]!;
    } else if (inputs.containsKey(key)) {
      token = inputs[key]!;
    } else if (services.containsKey(key)) {
      token = services[key]!;
    } else if (controllers.containsKey(key)) {
      token = controllers[key]!;
    }
    return token;
  }

  List<GLQueryElement> getAllElements() {
    return queries.values.expand((q) => q.elements).toList();
  }

  List<GLTypeDefinition> getTypesImplementing(GLInterfaceDefinition def) {
    var result = <GLTypeDefinition>[];
    types.forEach((k, v) {
      if (v.implements(def.token)) {
        result.add(v);
      }
    });
    return result;
  }

  void handleGLExternal() {
    [
      ...inputs.values,
      ...types.values,
      ...interfaces.values,
      ...scalars.values,
      ...enums.values
    ]
        .map((f) => f as GLDirectivesMixin)
        .where((t) => t.getDirectiveByName(glExternal) != null)
        .forEach((f) {
      f.addDirectiveIfAbsent(GLDirectiveValue.createDirectiveValue(
          directiveName: glSkipOnClient, generated: true));
      f.addDirectiveIfAbsent(GLDirectiveValue.createDirectiveValue(
          directiveName: glSkipOnServer, generated: true));
    });
  }

  List<GLTypeDefinition> getSerializableTypes() {
    return typesWithNoResolvers.where(filterByMode).toList();
  }

  List<GLTypeDefinition> get typesWithNoResolvers {
    final queries =
        GLQueryType.values.map((t) => schema.getByQueryType(t)).toSet();
    return types.values.where((type) => !queries.contains(type.token)).toList();
  }

  List<GLInputDefinition> getSerializableInputs() {
    return inputs.values.where(filterByMode).toList();
  }

  List<GLEnumDefinition> getSerializableEnums() {
    return enums.values.where(filterByMode).toList();
  }

  List<GLInterfaceDefinition> getSerializableInterfaces() {
    return interfaces.values.where(filterByMode).toList();
  }

  bool filterByMode(GLDirectivesMixin mixin) {
    return filterByParserMode(mixin, mode);
  }

  /// True for a def whose `@glSkipOnClient` was declared by the schema author
  /// — as opposed to one synthesized by [handleGLExternal] for a `@glExternal`
  /// def, which must stay resolvable by name (via [getTokenByKey]) so other
  /// fields can still derive its import path even though it never generates
  /// its own class. `@glExternal` defs are therefore never removed here.
  bool _isUserSkipOnClient(GLDirectivesMixin def) =>
      def.getDirectiveByName(glSkipOnClient) != null &&
      def.getDirectiveByName(glExternal) == null;

  /// Every field/argument that isn't itself skipped must not reference a
  /// whole type/interface/input/enum that is — otherwise a serializer would
  /// have to special-case a directive it can no longer see once
  /// [stripSkipOnClientMembers] removes the definition. Mirrors
  /// [GLValidationExtension._validateSkippedInputNotReferenced], which does
  /// the equivalent check for `@glSkipOnServer`.
  void _validateSkipOnClientNotReferenced() {
    final skipped = <String>{
      for (final def in <GLDirectivesMixin>[
        ...types.values,
        ...interfaces.values,
        ...inputs.values,
        ...enums.values,
      ])
        if (_isUserSkipOnClient(def)) (def as GLToken).token,
    };
    if (skipped.isEmpty) return;

    for (final def in [...types.values, ...interfaces.values]) {
      if (skipped.contains(def.token)) continue;
      for (final field in def.fields) {
        if (field.getDirectiveByName(glSkipOnClient) != null) continue;
        final fieldType = field.type.inlineType.token;
        if (skipped.contains(fieldType)) {
          throw ParseException(
            "Field '${def.token}.${field.name.token}' references '$fieldType' which is marked "
            "$glSkipOnClient — add $glSkipOnClient to this field as well",
            info: field.name,
          );
        }
        for (final arg in field.arguments) {
          final argType = arg.type.inlineType.token;
          if (skipped.contains(argType)) {
            throw ParseException(
              "Argument '${arg.token}' of '${def.token}.${field.name.token}' references '$argType' "
              "which is marked $glSkipOnClient — add $glSkipOnClient to field '${field.name.token}' as well",
              info: arg.tokenInfo,
            );
          }
        }
      }
    }

    for (final input in inputs.values) {
      if (skipped.contains(input.token)) continue;
      for (final field in input.fields) {
        final fieldType = field.type.inlineType.token;
        if (skipped.contains(fieldType)) {
          throw ParseException(
            "Input field '${input.token}.${field.name.token}' references '$fieldType' which is marked "
            "$glSkipOnClient — mark input '${input.token}' with $glSkipOnClient as well",
            info: field.name,
          );
        }
      }
    }
  }

  /// Removes every `@glSkipOnClient` field/enum-value and whole
  /// type/interface/input/enum definition from the schema so the client
  /// pipeline (fragments, projections, query validation, serializers) never
  /// sees them — mirrors [skipFieldOfSkipOnServerTypes] but for the client
  /// side, and lets serializers stay dumb (no per-definition directive
  /// checks).
  void stripSkipOnClientMembers() {
    _validateSkipOnClientNotReferenced();

    for (final def in [...types.values, ...interfaces.values, ...inputs.values]) {
      for (final field in def.getSkipOnClientFields()) {
        def.removeField(field.name.token);
      }
    }
    for (final def in enums.values) {
      for (final value in def.values
          .where((v) => v.getDirectiveByName(glSkipOnClient) != null)
          .toList()) {
        def.removeValue(value.value.token);
      }
    }

    enums.removeWhere((_, def) => _isUserSkipOnClient(def));
    inputs.removeWhere((_, def) => _isUserSkipOnClient(def));

    final skippedInterfaces =
        interfaces.values.where(_isUserSkipOnClient).toList();
    for (final iface in skippedInterfaces) {
      for (final impl in [...iface.implementations]) {
        impl.unlinkInterface(iface);
      }
      interfaces.remove(iface.token);
    }

    final skippedTypes = types.values.where(_isUserSkipOnClient).toList();
    for (final type in skippedTypes) {
      for (final iface in [...type.interfaces]) {
        iface.removeImplementation(type.token);
      }
      types.remove(type.token);
    }
  }

  void skipFieldOfSkipOnServerTypes() {
    types.values
        .where((t) => t.getDirectiveByName(glSkipOnServer) != null)
        .forEach((t) {
      var argValues = t
          .getDirectiveByName(glSkipOnServer)!
          .getArguments()
          .where((e) => e.token != glMapTo)
          .toList();
      for (var f in t.fields) {
        f.addDirectiveIfAbsent(GLDirectiveValue.createDirectiveValue(
            directiveName: glSkipOnServer, generated: true, args: argValues));
      }
    });
  }

  void mergeTokens() {
    List<GLExtensibleToken> tokens = [
      ...scalars.values,
      ...enums.values,
      ...inputs.values,
      ...types.values,
      ...interfaces.values,
      ...unions.values
    ];
    for (var token in tokens) {
      var list = extensibleTokens[token.token];
      if (list != null) {
        list.data.where((e) => e != token).forEach((e) {
          token.merge(e);
        });
      }
    }
  }

  void convertUnionsToInterfaces() {
    //
    unions.forEach((k, union) {
      var interfaceDef = GLInterfaceDefinition(
        name: union.tokenInfo,
        nameDeclared: false,
        fields: getUnionFields(union),
        directives: [],
        interfaceNames: {},
        fromUnion: true,
        extension: true,
      );
      addInterfaceDefinition(interfaceDef);

      for (var typeName in union.typeNames) {
        var type = getType(typeName);
        type.addInterfaceName(union.tokenInfo);
      }
    });
  }

  static String allFieldsFragmentName(String token) {
    return "${allFields}_$token";
  }

  static List<String> extractDecorators(
      {required List<GLDirectiveValue> directives,
      required CodeGenerationMode mode}) {
    // find the list
    var decorators = directives
        .where((d) => d.token == glDecorators)
        .where((d) {
          switch (mode) {
            case CodeGenerationMode.client:
              return d
                  .getArguments()
                  .where((arg) => arg.token == glApplyOnClient)
                  .first
                  .value as bool;
            case CodeGenerationMode.server:
              return d
                  .getArguments()
                  .where((arg) => arg.token == glApplyOnServer)
                  .first
                  .value as bool;
          }
        })
        .map((d) {
          return d.getArguments().where((arg) => arg.token == "value").first;
        })
        .map((d) {
          var decoratorValues = (d.value as List)
              .map((e) => e as String)
              .map((str) => str.removeQuotes())
              .toList();
          return decoratorValues;
        })
        .expand((inner) => inner)
        .toList();
    return decorators;
  }
}
