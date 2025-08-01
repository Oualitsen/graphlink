import 'dart:io';

import 'package:logger/logger.dart';
import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_scalar_definition.dart';
import 'package:retrofit_graphql/src/model/gq_service.dart';
import 'package:retrofit_graphql/src/model/gq_shcema_mapping.dart';
import 'package:retrofit_graphql/src/model/gq_schema.dart';
import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/gq_comment.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/gq_grammar_extension.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_interface.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_input_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_fragment.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_union.dart';
import 'package:petitparser/petitparser.dart';
import 'package:retrofit_graphql/src/serializers/graphq_serializer.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:retrofit_graphql/src/utils.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
export 'package:retrofit_graphql/src/gq_grammar_extension.dart';

class GQGrammar extends GrammarDefinition {
  bool annotationsProcessed = false;
  var logger = Logger();
  static const typename = "__typename";
  static final typenameField =
      GQField(name: typename, type: GQType("String", false, isScalar: true), arguments: [], directives: []);

  // used to skip serialization
  final builtInScalars = {"ID", "Boolean", "Int", "Float", "String", "null"};


  final Map<String, GQScalarDefinition> scalars = {
    "ID": GQScalarDefinition(token: "ID", directives: []),
    "Boolean": GQScalarDefinition(token: "Boolean", directives: []),
    "Int": GQScalarDefinition(token: "Int", directives: []),
    "Float": GQScalarDefinition(token: "Float", directives: []),
    "String": GQScalarDefinition(token: "String", directives: []),
    "null": GQScalarDefinition(token: "null", directives: [])
  };
  final Map<String, GQFragmentDefinitionBase> fragments = {};
  final Map<String, GQTypedFragment> typedFragments = {};

  late final Map<String, String> typeMap;
  late final CodeGenerationMode mode;

  static const directivesToSkip = [gqTypeNameDirective, gqEqualsHashcode];

  final Map<String, GQDirectiveDefinition> directives = {
    includeDirective: GQDirectiveDefinition(
      includeDirective,
      [GQArgumentDefinition("if", GQType("Boolean", false), [])],
      {GQDirectiveScope.FIELD},
    ),
    skipDirective: GQDirectiveDefinition(
      skipDirective,
      [GQArgumentDefinition("if", GQType("Boolean", false), [])],
      {GQDirectiveScope.FIELD},
    ),
    gqTypeNameDirective: GQDirectiveDefinition(
      gqTypeNameDirective,
      [GQArgumentDefinition(gqTypeNameDirectiveArgumentName, GQType("String", false, isScalar: false), [])],
      {
        GQDirectiveScope.INPUT_OBJECT,
        GQDirectiveScope.FRAGMENT_DEFINITION,
        GQDirectiveScope.QUERY,
        GQDirectiveScope.MUTATION,
        GQDirectiveScope.SUBSCRIPTION,
      },
    ),
    gqEqualsHashcode: GQDirectiveDefinition(
      gqEqualsHashcode,
      [GQArgumentDefinition(gqEqualsHashcodeArgumentName, GQType("[String]", false), [])],
      {GQDirectiveScope.OBJECT},
    ),
  };

  bool _validate = true;

  ///
  /// key is the type name
  /// and value gives a fragment that has references of all fields
  ///
  final Map<String, GQUnionDefinition> unions = {};
  final Map<String, GQInputDefinition> inputs = {};
  final Map<String, GQTypeDefinition> types = {};
  final Map<String, GQInterfaceDefinition> interfaces = {};
  final Map<String, GQInterfaceDefinition> repositories = {};
  final Map<String, GQQueryDefinition> queries = {};
  final Map<String, GQEnumDefinition> enums = {};
  final Map<String, GQTypeDefinition> projectedTypes = {};
  final Map<String, GQDirectiveDefinition> directiveDefinitions = {};
  final Map<String, GQSchemaMapping> schemaMappings = {};
  final Map<String, GQService> services = {};

  final List<GQDirectiveValue> directiveValues = [];

  GQSchema schema = GQSchema();
  bool schemaInitialized = false;
  final bool generateAllFieldsFragments;
  final bool nullableFieldsRequired;
  final bool autoGenerateQueries;
  final String? defaultAlias;
  final bool operationNameAsParameter;
  final List<String> identityFields;

  late final GraphqSerializer serializer;

  GQGrammar({
    this.typeMap = const {
      "ID": "String",
      "String": "String",
      "Float": "double",
      "Int": "int",
      "Boolean": "bool",
      "Null": "null",
      "Long": "int"
    },
    this.generateAllFieldsFragments = false,
    this.nullableFieldsRequired = false,
    this.autoGenerateQueries = false,
    this.operationNameAsParameter = false,
    this.identityFields = const [],
    this.defaultAlias,
    this.mode = CodeGenerationMode.client,
  }) : assert(
          !autoGenerateQueries || generateAllFieldsFragments,
          'autoGenerateQueries can only be true if generateAllFieldsFragments is also true',
        ){
          serializer = GraphqSerializer(this);
        }

  bool get hasSubscriptions => hasQueryType(GQQueryType.subscription);
  bool get hasQueries => hasQueryType(GQQueryType.query);
  bool get hasMutations => hasQueryType(GQQueryType.mutation);

  bool hasQueryType(GQQueryType type) => queries.values.where((query) => query.type == type).isNotEmpty;

  @override
  Parser start() {
    return ref0(fullGrammar).end();
  }


  Result parse(String text) {
     var parser = buildFrom(fullGrammar().end());
     return parser.parse(text);
  }

  Future<Result> parseFile(String path, {bool validate = true}) async {
    var text = await File(path).readAsString();
    _validate = validate;
    return parse(text);
  }

  Future<List<Result>> parseFiles(List<String> paths) async {
    var result = <Result>[];

    for(var path in paths) {
      var parseResult = await parseFile(path, validate: path == paths.last);
      result.add(parseResult);
    }
    return result;
  }

  Parser fullGrammar() => (documentation().optional() &
              [
                schemaDefinition(),
                scalarDefinition(),
                directiveDefinition(),
                inputDefinition(),
                typeDefinition(),
                interfaceDefinition(),
                fragmentDefinition(),
                enumDefinition(),
                unionDefinition(),
                queryDefinition(GQQueryType.query),
                queryDefinition(GQQueryType.mutation),
                queryDefinition(GQQueryType.subscription),
              ].toChoiceParser())
          .star()
          .map((value) {
        _validateSemantics();
        return value;
      });

  void _validateSemantics() {
    if(!_validate) {
      return;
    }
    validateInputReferences();
    validateTypeReferences();
    convertUnionsToInterfaces();
    setDirectivesDefaulValues();
    updateInterfaceParents();
    handleDirectiveInheritance();
    skipFieldOfSkipOnServerTypes();
    handleGqExternal();
    if (mode == CodeGenerationMode.client) {
      handleRepositories(false);
      if (generateAllFieldsFragments) {
        createAllFieldsFragments();
        if (autoGenerateQueries) {
          generateQueryDefinitions();
        }
      }
      checkFragmentRefs();
      fillQueryElementsReturnType();
      fillTypedFragments();
      validateProjections();
      updateFragmentDependencies();
      createProjectedTypes();
      generateImplementedInterfaces();
      updateFragmentAllTypesDependencies();
    } else {
      handleRepositories(true);
      generateSchemaMappings();
      generateServices();
    }
  }

  void updateInterfaceParents() {
    interfaces.forEach((key, value) {
      if (value.parentNames.isNotEmpty) {
        for (var interfaceName in value.parentNames) {
          var interface = interfaces[interfaceName];
          if (interface == null) {
            throw ParseException("interface $interfaceName is not defined");
          } else {
            value.parents.add(interface);
          }
        }
      }
    });
  }

  Parser token(Object input) {
    if (input is Parser) {
      return input.trim(
        ref0(hiddenStuffWhitespace),
        ref0(hiddenStuffWhitespace),
      );
    } else if (input is String) {
      return token(input.toParser());
    }
    throw ArgumentError(input, "Invalid Token parser");
  }

  Parser<List<GQArgumentDefinition>> arguments({bool parametrized = false}) {
    return seq3(openParen(), oneArgumentDefinition(parametrized: parametrized).star(), closeParen())
        .map3((p0, argsDefinition, p2) => argsDefinition);
  }

  Parser<List<GQArgumentValue>> argumentValues() {
    return seq3(openParen(), oneArgumentValue().star(), closeParen()).map3((p0, argValues, p2) => argValues);
  }

  Parser<GQArgumentValue> oneArgumentValue() =>
      (identifier() & colon() & ref1(token, initialValue())).map((value) {
        return GQArgumentValue(value.first, value.last);
      });

  Parser openParen() => ref1(token, char("("));

  Parser closeParen() => ref1(token, char(")"));

  Parser openBrace() => ref1(token, char("{"));

  Parser closeBrace() => ref1(token, char("}"));

  Parser openSquareBracket() => ref1(token, char("["));

  Parser closeSquareBracket() => ref1(token, char("]"));

  Parser colon() => ref1(token, char(":"));
  Parser at() => ref1(token, char("@"));

  Parser<GQTypeDefinition> typeDefinition() {
    return seq4(
        seq2(ref1(token, "type"), ref0(identifier)).map2((_, identifier) => identifier),
        implementsToken().optional(),
        directiveValueList(),
        seq3(
          ref0(openBrace),
          fieldList(
            required: true,
            canBeInitialized: true,
            acceptsArguments: true,
          ),
          ref0(closeBrace),
        ).map3((p0, fields, p2) => fields)).map4((name, interfaceNames, directives, fields) {
      final type = GQTypeDefinition(
        name: name,
        nameDeclared: false,
        fields: fields,
        interfaceNames: interfaceNames ?? {},
        directives: directives,
        derivedFromType: null,
      );
      addTypeDefinition(type);
      return type;
    });
  }

  Parser<GQInputDefinition> inputDefinition() {
    return seq4(
        ref1(token, "input"),
        ref0(identifier),
        directiveValueList(),
        seq3(
                ref0(openBrace),
                fieldList(
                  required: true,
                  canBeInitialized: true,
                  acceptsArguments: false,
                ),
                ref0(closeBrace))
            .map3((p0, fieldList, p2) => fieldList)).map4((_, name, directives, fields) {
      var inputName = getNameValueFromDirectives(directives) ?? name;
      final input = GQInputDefinition(name: inputName, fields: fields, directives: directives);
      addInputDefinition(input);
      return input;
    });
  }

  Parser<GQField> field({required bool canBeInitialized, required acceptsArguments}) {
    return ([
      ref0(documentation).optional(),
      identifier(),
      if (acceptsArguments) arguments().optional(),
      colon(),
      typeTokenDefinition(),
      if (canBeInitialized) initialization().optional(),
      directiveValueList()
    ].toSequenceParser())
        .map((value) {
      String name = value[1] as String;

      String? fieldDocumentation = value[0] as String?;
      List<GQArgumentDefinition>? fieldArguments;
      Object? initialValue;

      if (acceptsArguments) {
        fieldArguments = value[2] as List<GQArgumentDefinition>?;
      } else {
        fieldArguments = null;
      }

      if (canBeInitialized) {
        initialValue = value[acceptsArguments ? 4 : 5];
      }

      GQType type = value[acceptsArguments ? 4 : 3] as GQType;
      List<GQDirectiveValue>? directives = value.last as List<GQDirectiveValue>?;
      return GQField(
        name: name,
        type: type,
        documentation: fieldDocumentation,
        arguments: fieldArguments ?? [],
        initialValue: initialValue,
        directives: directives ?? [],
      );
    });
  }

  Parser<List<GQField>> fieldList({
    required bool required,
    required bool canBeInitialized,
    required bool acceptsArguments,
  }) {
    var p = field(
      canBeInitialized: canBeInitialized,
      acceptsArguments: acceptsArguments,
    );
    if (required) {
      return p.plus();
    } else {
      return p.star();
    }
  }

  Parser<GQInterfaceDefinition> interfaceDefinition() {
    return seq4(
        seq2(ref1(token, "interface"), ref0(identifier)).map2((p0, interfaceName) => interfaceName),
        implementsToken().optional(),
        directiveValueList(),
        seq3(
                ref0(openBrace),
                fieldList(
                  required: true,
                  canBeInitialized: false,
                  acceptsArguments: true,
                ),
                ref0(closeBrace))
            .map3((p0, fieldList, p2) => fieldList)).map4((name, parentNames, directives, fieldList) {
      var interface = GQInterfaceDefinition(
        name: name,
        nameDeclared: false,
        fields: fieldList,
        parentNames: parentNames ?? {},
        directives: directives,
        interfaceNames: {},
      );
      addInterfaceDefinition(interface);
      return interface;
    });
  }

  Parser<GQEnumDefinition> enumDefinition() => seq3(
          seq2(ref1(token, "enum"), ref0(identifier)).map2((p0, id) => id),
          directiveValueList(),
          seq3(
                  ref0(openBrace),
                  seq3(ref1(token, documentation().optional()), ref1(token, identifier()),
                          directiveValueList())
                      .map3((comment, value, directives) =>
                          GQEnumValue(value: value, comment: comment, directives: directives))
                      .plus(),
                  ref0(closeBrace))
              .map3((p0, list, p2) => list)).map3((identifier, directives, enumValues) {
        var enumDef = GQEnumDefinition(token: identifier, values: enumValues, directives: directives);
        addEnumDefinition(enumDef);
        return enumDef;
      });

  Parser<List<GQDirectiveValue>> directiveValueList() => directiveValue().star();

  Parser<GQDirectiveValue> directiveValue() => seq2(directiveValueName(), argumentValues().optional())
          .map2((name, args) => GQDirectiveValue(name.trim(), [], args ?? [], generated: false))
          .map((directiveValue) {
        addDiectiveValue(directiveValue);
        return directiveValue;
      });

  Parser<String> directiveValueName() => ref1(token, (ref0(at) & identifier()))
      .map((list) => "${list.first}${list.last}");

  Parser<GQDirectiveDefinition> directiveDefinition() => seq3(
              seq2(
                ref1(token, "directive"),
                directiveValueName(),
              ).map2((_, name) => name),
              arguments().optional(),
              seq2(ref1(token, "on"), ref1(token, directiveScopes())).map2((_, scopes) => scopes))
          .map3((name, args, scopes) => GQDirectiveDefinition(name, args ?? [], scopes))
          .map((definition) {
        addDirectiveDefinition(definition);
        return definition;
      });

  Parser<GQDirectiveScope> directiveScope() {
    return GQDirectiveScope.values
        .map((e) => e.name)
        .map((name) =>
            ref1(token, name.toParser()).map((value) => GQDirectiveScope.values.asNameMap()[value]!))
        .toList()
        .toChoiceParser();
  }

  Parser<Set<GQDirectiveScope>> directiveScopes() =>
      seq2(directiveScope(), seq2(ref1(token, "|"), directiveScope()).map2((_, scope) => scope).star())
          .map2((scope, scopeList) => {scope, ...scopeList});

  Parser<GQArgumentDefinition> oneArgumentDefinition({bool parametrized = false}) => seq5(
          ref0(parametrized ? parametrizedArgument : identifier),
          colon(),
          typeTokenDefinition(),
          initialization().optional(),
          directiveValueList())
      .map5((name, _, type, initialization, directives) =>
          GQArgumentDefinition(name, type, directives, initialValue: initialization));

  Parser<String> parametrizedArgument() =>
      ref1(token, (char("\$") & identifier())).map((value) => value.join());

  Parser<String> refValue() => ref1(token, (char("\$") & identifier())).map((value) => value.join());

  Parser<GQArgumentValue> onArgumentValue() => (ref0(identifier) & colon() & initialValue()).map((value) {
        return GQArgumentValue(value.first, value.last);
      });

  Parser<Object> initialization() =>
      (ref1(token, "=") & ref1(token, initialValue())).map((value) => value.last);

  Parser<Object> initialValue() => ref1(
          token,
          [
            doubleParser(),
            stringToken(),
            boolean(),
            ref0(objectValue),
            ref0(arrayValue),
            ref1(token, refValue()),
            nullParser()
          ].toChoiceParser())
      .map((value) => value);

  Parser nullParser() => "null".toParser();

  Parser objectValue() =>
      openBrace() & ref1(token, identifier() & colon() & initialValue()).star() & closeBrace();

  Parser arrayValue() => openSquareBracket() & ref0(initialValue).star() & closeSquareBracket();

  Parser<GQType> typeTokenDefinition() =>
      (ref0(simpleTypeTokenDefinition) | ref0(listTypeDefinition)).cast<GQType>();

  Parser<GQType> simpleTypeTokenDefinition() {
    return seq2(ref1(token, identifier()), ref1(token, char("!")).optional().map((value) => value == null))
        .map2((name, nullable) {
      return GQType(name, nullable, isScalar: false);
    });
  }

  Parser<GQType> listTypeDefinition() {
    return seq2(
            seq3(
              openSquareBracket(),
              ref0(typeTokenDefinition),
              closeSquareBracket(),
            ).map3((a, b, c) => b),
            ref1(token, char("!")).optional().map((value) => value == null))
        .map2((type, nullable) => GQListType(type, nullable));
  }

  Parser<String> identifier() =>
      ref1(token, (ref0(_myLetter) & (((ref0(_myLetter) | ref0(number)).star()))).flatten()).cast<String>();

  Parser number() => ref0(digit).plus();

  Parser _myLetter() => ref0(letter) | char("_");

  Parser hiddenStuffWhitespace() => (ref0(visibleWhitespace) | ref0(singleLineComment) | ref0(commas));

  Parser<String> visibleWhitespace() => whitespace();

  Parser commas() => char(",");

  Parser doubleQuote() => char('"');

  Parser tripleQuote() => string('"""');

  Parser<GQComment> singleLineComment() =>
      (char('#') & ref0(newlineLexicalToken).neg().star()).flatten().map((value) => GQComment(value));

  Parser singleLineStringLexicalToken() =>
      doubleQuote() & ref0(stringContentDoubleQuotedLexicalToken) & doubleQuote();

  Parser stringContentDoubleQuotedLexicalToken() => doubleQuote().neg().star();

  Parser<String> singleLineStringToken() {
    final quote = char('"');
    final escape = (char('\\') & any()).flatten(); // e.g., \" or \\ or \n
    final normalChar = pattern('^\\\"\n\r');

    final content = (escape | normalChar).star().flatten();

    return (quote & content & quote).map((values) {
      final raw = values[1] as String;

      // Unescape basic sequences
      return raw
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', '\\')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\r', '\r')
          .replaceAll(r'\t', '\t');
    });
  }
  //

  Parser<String> blockStringToken() {
    final tripleQuote = string('"""');

    // Match any character unless it's the start of closing triple-quote
    final contentChar = (string('"""').not() & any()).map((v) => v);

    final content = contentChar.star().flatten();

    return (tripleQuote & content & tripleQuote).map((values) => values[1] as String);
  }
  //  ('"""'.toParser() & pattern('"""').neg().star() & '"""'.toParser()).flatten();

  Parser<String> stringToken() => (blockStringToken() | singleLineStringToken()).flatten();

  Parser<String> documentation() => (blockStringToken() | singleLineStringToken()).flatten();

  Parser newlineLexicalToken() => pattern('\n\r');

  Parser<Set<String>> implementsToken() {
    return seq2(ref1(token, "implements"), interfaceList()).map2((_, set) => set);
  }

  Parser<Set<String>> interfaceList() =>
      (identifier() & (ref1(token, "&") & identifier()).map((value) => value[1]).star()).map((array) {
        Set<String> interfaceList = {array[0]};
        for (var value in array[1]) {
          final added = interfaceList.add(value);
          if (!added) {
            throw ParseException(
              "interface $value has been implemented more than once",
            );
          }
        }
        return interfaceList;
      });

  Parser<bool> boolean() => ("true".toParser() | "false".toParser()).map((value) => value == "true");

  Parser<int> intParser() =>
      ("0x".toParser() & (pattern("0-9A-Fa-f").times(4)) | (char("-").optional() & pattern("0-9").plus()))
          .flatten()
          .map(int.parse);

  Parser<Object> doubleParser() =>
      ((plainIntParser() & (char(".") & plainIntParser()).optional()) | intParser().map((value) => "$value"))
          .flatten()
          .map((val) {
        if (val.contains(".")) {
          return double.parse(val);
        } else {
          return int.parse(val);
        }
      });

  Parser<Object> constantType() => [doubleParser(), stringToken(), boolean()].toChoiceParser();

  Parser<GQScalarDefinition> scalarDefinition() =>
      (ref1(token, "scalar") & ref1(token, identifier()) & directiveValueList()).map((array) {
        final scalarName = array[1];
        var scalar = GQScalarDefinition(token: scalarName, directives: array[2]);
        addScalarDefinition(scalar);
        return scalar;
      });

  Parser<GQSchema> schemaDefinition() {
    return seq4(ref1(token, "schema"), openBrace(), schemaElement().repeat(0, 3).map(GQSchema.fromList),
            closeBrace())
        .map4((p0, p1, schema, p3) {
      defineSchema(schema);
      return schema;
    });
  }

  Parser<String> schemaElement() {
    return seq3(ref1(token, ["query", "mutation", "subscription"].map((e) => e.toParser()).toChoiceParser()),
            colon(), identifier())
        .map3((p0, p1, p2) => "$p0-$p2");
  }

  Parser<GQProjection> fragmentReference() {
    return seq3(ref1(token, "..."), identifier(), directiveValueList()).map3(
      (_, name, directives) =>
          GQProjection(fragmentName: name, token: name, alias: null, block: null, directives: directives),
    );
  }

  Parser<GQProjection> fragmentField() {
    return [fragmentValue(), projectionFieldField()].toChoiceParser();
  }

  Parser<GQProjection> projectionFieldField() {
    return seq4(alias().optional(), identifier(), directiveValueList(), ref0(fragmentBlock).optional())
        .map4((alias, token, directives, block) => GQProjection(
              token: token,
              fragmentName: null,
              alias: alias,
              block: block,
              directives: directives,
            ));
  }

  Parser<GQInlineFragmentDefinition> inlineFragment() {
    return seq4(
      ref1(token, "..."),
      ref1(token, "on"),
      identifier(),
      seq2(directiveValueList(), ref0(fragmentBlock)).map2(
        (directives, block) => GQProjection(
          fragmentName: null,
          token: null,
          alias: null,
          block: block,
          directives: directives,
        ),
      ),
    ).map4((p0, p1, typeName, projection) {
      var def = GQInlineFragmentDefinition(
        typeName,
        projection.block!,
        projection.getDirectives(),
      );
      addFragmentDefinition(def);
      return def;
    });
  }

  Parser<GQProjection> fragmentValue() =>
      (inlineFragment().plus().map((list) => GQInlineFragmentsProjection(inlineFragments: list)) |
              fragmentReference())
          .cast<GQProjection>();

  Parser<GQFragmentDefinition> fragmentDefinition() {
    return seq4(
            seq3(
              ref1(token, "fragment"),
              identifier(),
              ref1(token, "on"),
            ).map3((p0, fragmentName, p2) => fragmentName),
            identifier(),
            directiveValueList(),
            fragmentBlock())
        .map4((name, typeName, directiveValues, block) =>
            GQFragmentDefinition(name, typeName, block, directiveValues))
        .map((f) {
      addFragmentDefinition(f);
      return f;
    });
  }

  Parser<GQUnionDefinition> unionDefinition() {
    return seq3(
            seq3(
              ref1(token, "union"),
              ref0(identifier),
              ref1(token, "="),
            ).map3((_, unionName, eq) => unionName),
            ref0(identifier),
            seq2(ref1(token, "|"), ref0(identifier)).map2((p0, p1) => p1).star())
        .map3((name, type1, types) => GQUnionDefinition(name, [type1, ...types]))
        .map((value) {
      addUnionDefinition(value);
      return value;
    });
  }

  ///
  /// example: {
  ///   firstName lastName
  /// }
  ///

  Parser<GQFragmentBlockDefinition> fragmentBlock() {
    return seq3(openBrace(), fragmentField().plus(), closeBrace())
        .map3((p0, projectionList, p2) => GQFragmentBlockDefinition(projectionList));
  }

  Parser<int> plainIntParser() => pattern("0-9").plus().flatten().map(int.parse);

  Parser<GQQueryDefinition> queryDefinition(GQQueryType type) {
    return seq4(
            seq2(
              ref1(token, type.name),
              identifier(),
            ).map2((p0, identifier) => identifier),
            arguments(parametrized: true).optional(),
            directiveValueList(),
            seq3(
                    openBrace(),
                    (type == GQQueryType.subscription
                        ? queryElement().map((value) => [value])
                        : queryElement().plus()),
                    closeBrace())
                .map3((p0, queryElements, p2) => queryElements))
        .map4(
      (name, args, directives, elements) => GQQueryDefinition(
        name,
        directives,
        args ?? [],
        elements,
        type,
      ),
    )
        .map((value) {
      addQueryDefinition(value);
      return value;
    });
  }

  Parser<GQQueryElement> queryElement() {
    return seq5(alias().optional(), identifier(), argumentValues().optional(), directiveValueList(),
            fragmentBlock().optional())
        .map5((alias, name, args, directiveList, block) => GQQueryElement(
              name,
              directiveList,
              block,
              args ?? [],
              alias,
            ));
  }

  Parser<String> alias() => seq2(identifier(), colon()).map2((id, colon) => id);
}
