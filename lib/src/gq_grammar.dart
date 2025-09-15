import 'dart:io';

import 'package:logger/logger.dart';
import 'package:retrofit_graphql/src/excpetions/parse_exception.dart';
import 'package:retrofit_graphql/src/extensions.dart';
import 'package:retrofit_graphql/src/model/gq_controller.dart';
import 'package:retrofit_graphql/src/model/gq_enum_definition.dart';
import 'package:retrofit_graphql/src/model/gq_repository.dart';
import 'package:retrofit_graphql/src/model/gq_scalar_definition.dart';
import 'package:retrofit_graphql/src/model/gq_service.dart';
import 'package:retrofit_graphql/src/model/gq_schema.dart';
import 'package:retrofit_graphql/src/model/gq_argument.dart';
import 'package:retrofit_graphql/src/model/gq_comment.dart';
import 'package:retrofit_graphql/src/model/gq_directive.dart';
import 'package:retrofit_graphql/src/model/gq_field.dart';
import 'package:retrofit_graphql/src/model/gq_interface_definition.dart';
import 'package:retrofit_graphql/src/model/gq_type.dart';
import 'package:retrofit_graphql/src/model/gq_input_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_fragment.dart';
import 'package:retrofit_graphql/src/model/gq_queries.dart';
import 'package:retrofit_graphql/src/model/gq_type_definition.dart';
import 'package:retrofit_graphql/src/model/gq_union.dart';
import 'package:petitparser/petitparser.dart';
import 'package:retrofit_graphql/src/model/token_info.dart';
import 'package:retrofit_graphql/src/serializers/graphq_serializer.dart';
import 'package:retrofit_graphql/src/serializers/language.dart';
import 'package:retrofit_graphql/src/utils.dart';
import 'package:retrofit_graphql/src/model/built_in_dirctive_definitions.dart';
import 'package:retrofit_graphql/src/gq_grammar_extension.dart';
export 'package:retrofit_graphql/src/gq_grammar_extension.dart';
import 'package:retrofit_graphql/src/gq_validation_extension.dart';
export 'package:retrofit_graphql/src/gq_validation_extension.dart';

class GQGrammar extends GrammarDefinition {
  bool annotationsProcessed = false;
  var logger = Logger();
  static const typename = "__typename";
  static final typenameField = GQField(
      name: typename.toToken(), type: GQType("String".toToken(), false, isScalar: true), arguments: [], directives: []);

  // used to skip serialization
  final builtInScalars = {"ID", "Boolean", "Int", "Float", "String", "null"};

  final Map<String, GQScalarDefinition> scalars = {
    "ID": GQScalarDefinition(token: "ID".toToken(), directives: []),
    "Boolean": GQScalarDefinition(token: "Boolean".toToken(), directives: []),
    "Int": GQScalarDefinition(token: "Int".toToken(), directives: []),
    "Float": GQScalarDefinition(token: "Float".toToken(), directives: []),
    "String": GQScalarDefinition(token: "String".toToken(), directives: []),
    "null": GQScalarDefinition(token: "null".toToken(), directives: [])
  };
  final Map<String, GQFragmentDefinitionBase> fragments = {};
  final Map<String, GQTypedFragment> typedFragments = {};

  late final Map<String, String> typeMap;
  late final CodeGenerationMode mode;

  static const directivesToSkip = [gqTypeNameDirective, gqEqualsHashcode];

  final Map<String, GQDirectiveDefinition> directives = {
    includeDirective: GQDirectiveDefinition(
      includeDirective.toToken(),
      [GQArgumentDefinition("if".toToken(), GQType("Boolean".toToken(), false), [])],
      {GQDirectiveScope.FIELD},
    ),
    skipDirective: GQDirectiveDefinition(
      skipDirective.toToken(),
      [GQArgumentDefinition("if".toToken(), GQType("Boolean".toToken(), false), [])],
      {GQDirectiveScope.FIELD},
    ),
    gqTypeNameDirective: GQDirectiveDefinition(
      gqTypeNameDirective.toToken(),
      [
        GQArgumentDefinition(
            gqTypeNameDirectiveArgumentName.toToken(), GQType("String".toToken(), false, isScalar: false), [])
      ],
      {
        GQDirectiveScope.INPUT_OBJECT,
        GQDirectiveScope.FRAGMENT_DEFINITION,
        GQDirectiveScope.QUERY,
        GQDirectiveScope.MUTATION,
        GQDirectiveScope.SUBSCRIPTION,
      },
    ),
    gqEqualsHashcode: GQDirectiveDefinition(
      gqEqualsHashcode.toToken(),
      [GQArgumentDefinition(gqEqualsHashcodeArgumentName.toToken(), GQType("[String]".toToken(), false), [])],
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
  final Map<String, GQRepository> repositories = {};
  final Map<String, GQQueryDefinition> queries = {};
  final Map<String, GQEnumDefinition> enums = {};
  final Map<String, GQTypeDefinition> projectedTypes = {};
  final Map<String, GQDirectiveDefinition> directiveDefinitions = {};
  final Map<String, GQService> services = {};
  final Map<String, GQController> controllers = {};

  final List<GQDirectiveValue> directiveValues = [];

  GQSchema schema = GQSchema(TokenInfo.ofString("schema"));
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
        ) {
    serializer = GraphqSerializer(this);
  }

  bool get hasSubscriptions => hasQueryType(GQQueryType.subscription);
  bool get hasQueries => hasQueryType(GQQueryType.query);
  bool get hasMutations => hasQueryType(GQQueryType.mutation);

  bool hasQueryType(GQQueryType type) => queries.values.where((query) => query.type == type).isNotEmpty;

  String? lastParsedFile;

  @override
  Parser start() {
    return ref0(fullGrammar).end();
  }

  Result parseAndValidate(String text) {
    _validate = true;
    return parse(text);
  }

  Result parse(String text) {
    var parser = buildFrom(fullGrammar().end());
    return parser.parse(text);
  }

  Future<Result> parseFile(String path, {bool validate = true}) async {
    lastParsedFile = path;
    var text = await File(path).readAsString();
    _validate = validate;
    var result = parse(text);
    return result;
  }

  Future<List<Result>> parseFiles(List<String> paths, {String? extraGql}) async {
    var result = <Result>[];

    for (var path in paths) {
      var parseResult = await parseFile(path, validate: extraGql == null && path == paths.last);
      result.add(parseResult);
    }
    if (extraGql != null) {
      result.add(parseAndValidate(extraGql));
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
                ignoredStuff(),
              ].toChoiceParser())
          .star()
          .map((value) {
        _validateSemantics();
        return value;
      });

  void _validateSemantics() {
    if (!_validate) {
      return;
    }
    validateInputReferences();
    validateTypeReferences();
    convertUnionsToInterfaces();
    fillInterfaceImplementations();
    setDirectivesDefaulValues();
    updateInterfaceReferences();
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
      updateInterfaceCommonFields();
      updateFragmentAllTypesDependencies();
    } else {
      handleRepositories(true);
      generateServicesAndControllers();
      generateSchemaMappings();
    }
  }

  Parser<T> token<T>(Parser<T> input) {
    return input.trim(
      ref0(hiddenStuffWhitespace),
      ref0(hiddenStuffWhitespace),
    );
  }

  Parser<TokenInfo> capture(Parser parser) {
    return parser.token().map((token) => TokenInfo.of(token, lastParsedFile));
  }

  Parser<List<GQArgumentDefinition>> arguments({bool parametrized = false}) {
    return seq3(openParen(), oneArgumentDefinition(parametrized: parametrized).star(), closeParen())
        .map3((p0, argsDefinition, p2) => argsDefinition);
  }

  Parser<List<GQArgumentValue>> argumentValues() {
    return seq3(openParen(), oneArgumentValue().star(), closeParen()).map3((p0, argValues, p2) => argValues);
  }

  Parser<GQArgumentValue> oneArgumentValue() => (identifier() & colon() & ref1(token, initialValue())).map((value) {
        return GQArgumentValue(value.first, value.last);
      });

  Parser<String> openParen() => ref1(token, char("(")).map((_) => "(");

  Parser<String> closeParen() => ref1(token, char(")")).map((_) => ")");

  Parser<String> openBrace() => ref1(token, char("{")).map((_) => "{");

  Parser<String> closeBrace() => ref1(token, char("}")).map((_) => "}");

  Parser<String> openSquareBracket() => ref1(token, char("[")).map((_) => "[");

  Parser<String> closeSquareBracket() => ref1(token, char("]")).map((_) => "]");

  Parser<String> colon() => ref1(token, char(":")).map((_) => ":");
  Parser<String> at() => ref1(token, char("@")).map((_) => "@");

  Parser<String> inputKw() => "input".toParser();
  Parser<String> queryKw() => "query".toParser();
  Parser<String> mutationKw() => "mutation".toParser();
  Parser<String> subscriptionKw() => "subscription".toParser();
  Parser<TokenInfo> schemaKw() => "schema".toParser().token().map((t) => TokenInfo.of(t, lastParsedFile));
  Parser<String> scalarKw() => "scalar".toParser();
  Parser<String> typeKw() => "type".toParser();
  Parser<String> interfaceKw() => "interface".toParser();
  Parser<String> unionKw() => "union".toParser();
  Parser<String> enumKw() => "enum".toParser();
  Parser<String> implementsKw() => "implements".toParser();
  Parser<String> extendsKw() => "extends".toParser(); // optional in some tools
  Parser<String> directiveKw() => "directive".toParser();
  Parser<String> onKw() => "on".toParser();
  Parser<String> trueKw() => "true".toParser();
  Parser<String> falseKw() => "false".toParser();
  Parser<String> nullKw() => "null".toParser();
  Parser<String> fragRefKw() => "...".toParser();
  Parser<String> pipeKw() => "|".toParser();
  Parser<String> assignKw() => "=".toParser();
  Parser<String> fragmentKw() => "fragment".toParser();

  Parser<GQTypeDefinition> typeDefinition() {
    return seq4(
        seq2(ref1(token, typeKw()), ref0(identifier)).map2((_, identifier) => identifier),
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
        ref1(token, inputKw()),
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
      String? nameFromDirective = getNameValueFromDirectives(directives);
      TokenInfo inputName = name.ofNewName(nameFromDirective ?? name.token);
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
      final name = value[1] as TokenInfo;

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
        seq2(ref1(token, interfaceKw()), ref0(identifier)).map2((p0, interfaceName) => interfaceName),
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
        directives: directives,
        interfaceNames: parentNames ?? {},
      );
      addInterfaceDefinition(interface);
      return interface;
    });
  }

  Parser<GQEnumDefinition> enumDefinition() => seq3(
          seq2(ref1(token, enumKw()), ref0(identifier)).map2((p0, id) => id),
          directiveValueList(),
          seq3(
                  ref0(openBrace),
                  seq3(ref1(token, documentation().optional()), ref1(token, identifier()), directiveValueList())
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
          .map2((name, args) => GQDirectiveValue(name.ofNewName(name.token.trim()), [], args ?? [], generated: false))
          .map((directiveValue) {
        addDiectiveValue(directiveValue);
        return directiveValue;
      });

  Parser<TokenInfo> directiveValueName() => ref1(token, (ref0(at) & identifier())).map((list) {
        var token = list.last as TokenInfo;
        return token.ofNewName("@${token.token}");
      });

  Parser<GQDirectiveDefinition> directiveDefinition() => seq3(
              seq2(
                ref1(token, directiveKw()),
                directiveValueName(),
              ).map2((_, name) => name),
              arguments().optional(),
              seq2(ref1(token, onKw()), ref1(token, directiveScopes())).map2((_, scopes) => scopes))
          .map3((name, args, scopes) => GQDirectiveDefinition(name, args ?? [], scopes))
          .map((definition) {
        addDirectiveDefinition(definition);
        return definition;
      });

  Parser<GQDirectiveScope> directiveScope() {
    return GQDirectiveScope.values
        .map((e) => e.name)
        .map((name) => ref1(token, name.toParser()).map((value) => GQDirectiveScope.values.asNameMap()[value]!))
        .toList()
        .toChoiceParser();
  }

  Parser<Set<GQDirectiveScope>> directiveScopes() =>
      seq2(directiveScope(), seq2(ref1(token, pipeKw()), directiveScope()).map2((_, scope) => scope).star())
          .map2((scope, scopeList) => {scope, ...scopeList});

  Parser<GQArgumentDefinition> oneArgumentDefinition({bool parametrized = false}) => seq5(
          ref0(parametrized ? parametrizedArgument : identifier),
          colon(),
          typeTokenDefinition(),
          initialization().optional(),
          directiveValueList())
      .map5((name, _, type, initialization, directives) =>
          GQArgumentDefinition(name, type, directives, initialValue: initialization));

  Parser<TokenInfo> parametrizedArgument() => ref1(token, (char("\$") & identifier())).map((value) {
        // @TODO make this type safe
        var dollarSign = value[0] as String;
        var token = value[1] as TokenInfo;
        return token.ofNewName("$dollarSign${token.token}");
      });

  Parser<String> refValue() => ref1(token, (char("\$") & identifier())).map((value) => value.join());

  Parser<GQArgumentValue> onArgumentValue() => (ref0(identifier) & colon() & initialValue()).map((value) {
        return GQArgumentValue(value.first, value.last);
      });

  Parser<Object> initialization() => (ref1(token, assignKw()) & ref1(token, initialValue())).map((value) => value.last);

  Parser<Object> initialValue() => ref1(
          token,
          [
            doubleParser(),
            stringToken(),
            boolean(),
            ref0(objectValue),
            ref0(arrayValue),
            ref1(token, refValue()),
            nullKw()
          ].toChoiceParser())
      .map((value) => value);

  Parser<Map<String, Object?>> objectValue() =>
      seq3(openBrace(), ref1(token, oneObjectField()).cast<MapEntry<String, Object>>().star(), closeBrace())
          .map3((_, entries, __) => Map.fromEntries(entries));

  Parser<MapEntry<String, Object>> oneObjectField() =>
      seq3(identifier(), colon(), initialValue()).map3((id, _, value) => MapEntry(id.token, value));

  Parser<List<Object?>> arrayValue() =>
      seq3(openSquareBracket(), ref0(initialValue).star(), closeSquareBracket()).map3((_, values, __) => values);

  Parser<GQType> typeTokenDefinition() => (ref0(simpleTypeTokenDefinition) | ref0(listTypeDefinition)).cast<GQType>();

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

  Parser<TokenInfo> identifier() => ref1(token, _id()).token().map((t) => TokenInfo.of(t, lastParsedFile));

  Parser<String> _id() => seq2(_myLetter(), [_myLetter(), number()].toChoiceParser().star()).flatten();

  Parser<int> number() => ref0(digit).plus().flatten().map(int.parse);

  Parser<String> _myLetter() => [ref0(letter), char("_")].toChoiceParser();

  Parser hiddenStuffWhitespace() => (ref0(visibleWhitespace) | ref0(singleLineComment) | ref0(commas));
  Parser ignoredStuff() => (ref0(visibleWhitespace) | ref0(singleLineComment) | ref0(documentation));

  Parser<String> visibleWhitespace() => whitespace();

  Parser<String> commas() => char(",");

  Parser<String> doubleQuote() => char('"');

  Parser<String> tripleQuote() => string('"""');

  Parser<GQComment> singleLineComment() =>
      (char('#') & ref0(newlineLexicalToken).neg().star()).flatten().map((value) => GQComment(value));

  Parser<String> singleLineStringLexicalToken() =>
      seq3(doubleQuote(), ref0(stringContentDoubleQuotedLexicalToken), doubleQuote()).flatten();

  Parser<String> stringContentDoubleQuotedLexicalToken() => doubleQuote().neg().star().flatten();

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

  Parser<String> newlineLexicalToken() => pattern('\n\r');

  Parser<Set<TokenInfo>> implementsToken() {
    return seq2(ref1(token, implementsKw()), interfaceList()).map2((_, set) => set);
  }

  Parser<String> andKw() => "&".toParser();

  Parser<Set<TokenInfo>> interfaceList() =>
      (identifier() & (ref1(token, andKw()) & identifier()).map((value) => value[1]).star()).map((array) {
        Set<TokenInfo> interfaceList = {array[0]};
        for (var value in array[1]) {
          //if(interfaceList.where((e) => e.token == ))
          final exists = interfaceList.where((e) => e.token == value.token).isNotEmpty;
          if (exists) {
            throw ParseException("interface $value has been implemented more than once", info: value);
          }
          interfaceList.add(value);
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
      (ref1(token, scalarKw()) & ref1(token, identifier()) & directiveValueList()).map((array) {
        final scalarName = array[1];
        var scalar = GQScalarDefinition(token: scalarName, directives: array[2]);
        addScalarDefinition(scalar);
        return scalar;
      });

  Parser<GQSchema> schemaDefinition() {
    return seq4(ref1(token, schemaKw()), openBrace(), schemaElement().repeat(0, 3), closeBrace())
        .map4((tokenInfo, p1, list, p3) {
      var schema = GQSchema.fromList(tokenInfo, list);
      defineSchema(schema);
      return schema;
    });
  }

  Parser<String> schemaElement() {
    return seq3(ref1(token, [queryKw(), mutationKw(), subscriptionKw()].toChoiceParser()), colon(), identifier())
        .map3((p0, p1, p2) => "$p0-$p2");
  }

  Parser<GQProjection> fragmentReference() {
    return seq3(ref1(token, fragRefKw()), identifier(), directiveValueList()).map3(
      (_, name, directives) =>
          GQProjection(fragmentName: name.token, token: name, alias: null, block: null, directives: directives),
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
      ref1(token, fragRefKw()),
      ref1(token, onKw()),
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

  Parser<GQProjection> fragmentValue() => [
        inlineFragment().plus().map((list) => GQInlineFragmentsProjection(inlineFragments: list)),
        fragmentReference()
      ].toChoiceParser().cast<GQProjection>();

  Parser<GQFragmentDefinition> fragmentDefinition() {
    return seq4(
            seq3(
              ref1(token, fragmentKw()),
              identifier(),
              ref1(token, onKw()),
            ).map3((p0, fragmentName, p2) => fragmentName),
            identifier(),
            directiveValueList(),
            fragmentBlock())
        .map4((name, typeName, directiveValues, block) => GQFragmentDefinition(name, typeName, block, directiveValues))
        .map((f) {
      addFragmentDefinition(f);
      return f;
    });
  }

  Parser<GQUnionDefinition> unionDefinition() {
    return seq3(
            seq3(
              ref1(token, unionKw()),
              ref0(identifier),
              ref1(token, assignKw()),
            ).map3((_, unionName, eq) => unionName),
            ref0(identifier),
            seq2(ref1(token, pipeKw()), ref0(identifier)).map2((_, id) => id).star())
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
              ref1(token, type.name.toParser()),
              identifier(),
            ).map2((p0, identifier) => identifier),
            arguments(parametrized: true).optional(),
            directiveValueList(),
            seq3(
                    openBrace(),
                    (type == GQQueryType.subscription ? queryElement().map((value) => [value]) : queryElement().plus()),
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

  Parser<TokenInfo> alias() => seq2(identifier(), colon()).map2((id, colon) => id);
}
