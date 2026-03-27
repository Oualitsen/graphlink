import 'dart:io';

import 'package:graphlink/src/gl_grammar_cache_extension.dart';
import 'package:logger/logger.dart';
import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_repository.dart';
import 'package:graphlink/src/model/gl_scalar_definition.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_schema.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_comment.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_shcema_mapping.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_fragment.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/gl_union.dart';
import 'package:petitparser/petitparser.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/serializers/graphq_serializer.dart';
import 'package:graphlink/src/serializers/language.dart';
import 'package:graphlink/src/ui/flutter/gl_type_view.dart';
import 'package:graphlink/src/utils.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/gl_grammar_extension.dart';
export 'package:graphlink/src/gl_grammar_extension.dart';
import 'package:graphlink/src/gl_validation_extension.dart';
export 'package:graphlink/src/gl_validation_extension.dart';

class GLGrammar extends GrammarDefinition {
  bool annotationsProcessed = false;
  var logger = Logger();
  static const typename = "__typename";
  static final typenameField = GLField(
      name: typename.toToken(),
      type: GLType("String".toToken(), false),
      arguments: [],
      directives: []);

  // used to skip serialization
  final builtInScalars = {"ID", "Boolean", "Int", "Float", "String", "null"};

  final Map<String, GLScalarDefinition> scalars = {
    "ID": GLScalarDefinition(
        token: "ID".toToken(), directives: [], extension: false),
    "Boolean": GLScalarDefinition(
        token: "Boolean".toToken(), directives: [], extension: false),
    "Int": GLScalarDefinition(
        token: "Int".toToken(), directives: [], extension: false),
    "Float": GLScalarDefinition(
        token: "Float".toToken(), directives: [], extension: false),
    "String": GLScalarDefinition(
        token: "String".toToken(), directives: [], extension: false),
    "null": GLScalarDefinition(
        token: "null".toToken(), directives: [], extension: false)
  };
  final Map<String, GLFragmentDefinitionBase> fragments = {};
  final Map<String, GLTypedFragment> typedFragments = {};

  final Map<String, GLSchemaMapping> _schemaMappings = {};

  late final Map<String, String> typeMap;
  late final CodeGenerationMode mode;

  static const directivesToSkip = [glTypeNameDirective, glEqualsHashcode];

  final Map<String, GLDirectiveDefinition> directives = {
    includeDirective: GLDirectiveDefinition(
      includeDirective.toToken(),
      [
        GLArgumentDefinition(
            "if".toToken(), GLType("Boolean".toToken(), false), [])
      ],
      {GLDirectiveScope.FIELD},
      false,
    ),
    skipDirective: GLDirectiveDefinition(
      skipDirective.toToken(),
      [
        GLArgumentDefinition(
            "if".toToken(), GLType("Boolean".toToken(), false), [])
      ],
      {GLDirectiveScope.FIELD},
      false,
    ),
    glTypeNameDirective: GLDirectiveDefinition(
      glTypeNameDirective.toToken(),
      [
        GLArgumentDefinition(glTypeNameDirectiveArgumentName.toToken(),
            GLType("String".toToken(), false), [])
      ],
      {
        GLDirectiveScope.INPUT_OBJECT,
        GLDirectiveScope.FRAGMENT_DEFINITION,
        GLDirectiveScope.QUERY,
        GLDirectiveScope.MUTATION,
        GLDirectiveScope.SUBSCRIPTION,
      },
      false,
    ),
    glEqualsHashcode: GLDirectiveDefinition(
      glEqualsHashcode.toToken(),
      [
        GLArgumentDefinition(glEqualsHashcodeArgumentName.toToken(),
            GLType("[String]".toToken(), false), [])
      ],
      {GLDirectiveScope.OBJECT},
      false,
    ),
  };

  bool _validate = true;

  ///
  /// key is the type name
  /// and value gives a fragment that has references of all fields
  ///
  final Map<String, GLUnionDefinition> unions = {};
  final Map<String, GLInputDefinition> inputs = {};
  final Map<String, GLTypeDefinition> types = {};
  final Map<String, GLInterfaceDefinition> interfaces = {};
  final Map<String, GLRepository> repositories = {};
  final Map<String, GLQueryDefinition> queries = {};
  final Map<String, GLEnumDefinition> enums = {};
  final Map<String, GLTypeDefinition> projectedTypes = {};
  final Map<String, GLInterfaceDefinition> projectedInterfaces = {};
  final Map<String, GLInterfaceDefinition> tempProjectedInterfaces = {};
  final Map<String, GLDirectiveDefinition> directiveDefinitions = {};
  final Map<String, GLService> services = {};
  final Map<String, GLController> controllers = {};
  final Map<String, GLTypeView> views = {};

  final Map<String, GLExtensibleTokenList> extensibleTokens = {};

  final List<GLDirectiveValue> directiveValues = [];

  GLSchema schema = GLSchema(TokenInfo.ofString("schema"), false,
      operationTypes: [], directives: []);
  bool schemaInitialized = false;
  final bool generateAllFieldsFragments;
  final bool nullableFieldsRequired;
  final bool autoGenerateQueries;
  final String? defaultAlias;
  final bool operationNameAsParameter;
  final List<String> identityFields;
  final int? defaultCacheTTL;
  late final GLGraphqSerializer serializer;

  GLGrammar({
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
    this.defaultCacheTTL,
  }) : assert(
          !autoGenerateQueries || generateAllFieldsFragments,
          'autoGenerateQueries can only be true if generateAllFieldsFragments is also true',
        ) {
    serializer = GLGraphqSerializer(this);
  }

  void addSchemaMapping(GLSchemaMapping mapping) {
    var m = _schemaMappings[mapping.key];

    ///
    /// replace existing mapping when
    /// current mapping does not exist
    /// current mapping has batch is null
    /// current mapping has batch is false and new mapping has mapping == true
    ///
    if (m == null || m.batch == null || (m.batch == false && m.batch == true)) {
      _schemaMappings[mapping.key] = mapping;
    }
  }

  GLSchemaMapping? getMappingByName(String name) => _schemaMappings[name];

  List<GLSchemaMapping> getAllMappingsByType(String typeName) =>
      _schemaMappings.values.where((e) => e.type.token == typeName).toList();
  List<GLSchemaMapping> getServiceMappingByType(String typeName) =>
      _schemaMappings.values
          .where((e) => e.type.token == typeName && !e.forbid && !e.identity)
          .toList();

  List<GLSchemaMapping> getSchemaMappings(GLTypeDefinition def) {
    return _schemaMappings.values.where((e) => e.type == def).toList();
  }

  bool get hasSubscriptions => hasQueryType(GLQueryType.subscription);
  bool get hasQueries => hasQueryType(GLQueryType.query);
  bool get hasMutations => hasQueryType(GLQueryType.mutation);

  bool hasQueryType(GLQueryType type) =>
      queries.values.where((query) => query.type == type).isNotEmpty;

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

  Future<List<Result>> parseFiles(List<String> paths,
      {String? extraGql}) async {
    var result = <Result>[];

    for (var path in paths) {
      var parseResult = await parseFile(path,
          validate: extraGql == null && path == paths.last);
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
                queryDefinition(GLQueryType.query),
                queryDefinition(GLQueryType.mutation),
                queryDefinition(GLQueryType.subscription),
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
    setDirectivesDefaultValues();
    proparageAnnotationsOnFields();
    mergeTokens();
    updateInterfaceReferences();
    checkInterfaceInheritance();
    skipFieldOfSkipOnServerTypes();
    handleGLExternal();
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
      // cache handling — must run before createProjectedTypes to catch errors early
      fixTagListValues();
      validateTagValues();
      checkCacheAndNoCacheConflict();
      checkCacheOnMutationsAndSubscriptions();
      checkCacheInvalidateOnQueriesAndSubscriptions();
      checkGLCacheDirectives();
      checkGLCacheInvalidateDirectives();
      checkGLCacheTags();
      createProjectedTypes();
      updateInterfaceCommonFields();
      fillProjectedInterfaces();
      cleanProjectedInterfacesImplementations();
      addClientTypesToProjectedTypes();
      updateFragmentAllTypesDependencies();
      generateViews();
      if (defaultCacheTTL != null) {
        applyDefaultCacheToQueries(defaultCacheTTL!);
      }
      propagateCacheTags();
      propagateInvalidateCacheTags();
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

  Parser<List<GLArgumentDefinition>> arguments({bool parametrized = false}) {
    return seq3(
            openParen(),
            oneArgumentDefinition(parametrized: parametrized).star(),
            closeParen())
        .map3((p0, argsDefinition, p2) => argsDefinition);
  }

  Parser<List<GLArgumentValue>> argumentValues() {
    return seq3(openParen(), oneArgumentValue().star(), closeParen())
        .map3((p0, argValues, p2) => argValues);
  }

  Parser<GLArgumentValue> oneArgumentValue() =>
      (identifier() & colon() & ref1(token, initialValue())).map((value) {
        return GLArgumentValue(value.first, value.last);
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
  Parser<GLQueryType> queryKw() =>
      "query".toParser().map((e) => GLQueryType.query);
  Parser<GLQueryType> mutationKw() =>
      "mutation".toParser().map((e) => GLQueryType.mutation);
  Parser<GLQueryType> subscriptionKw() =>
      "subscription".toParser().map((e) => GLQueryType.subscription);
  Parser<TokenInfo> schemaKw() =>
      "schema".toParser().token().map((t) => TokenInfo.of(t, lastParsedFile));
  Parser<String> scalarKw() => "scalar".toParser();
  Parser<String> extendKw() => "extend".toParser();
  Parser<String> typeKw() => "type".toParser();
  Parser<String> interfaceKw() => "interface".toParser();
  Parser<String> unionKw() => "union".toParser();
  Parser<String> enumKw() => "enum".toParser();
  Parser<String> implementsKw() => "implements".toParser();
  Parser<String> extendsKw() => "extends".toParser(); // optional in some tools
  Parser<String> directiveKw() => "directive".toParser();
  Parser<String> repeatableKw() => "repeatable".toParser();
  Parser<String> onKw() => "on".toParser();
  Parser<String> trueKw() => "true".toParser();
  Parser<String> falseKw() => "false".toParser();
  Parser<String> nullKw() => "null".toParser();
  Parser<String> fragRefKw() => "...".toParser();
  Parser<String> pipeKw() => "|".toParser();
  Parser<String> assignKw() => "=".toParser();
  Parser<String> fragmentKw() => "fragment".toParser();

  Parser<GLTypeDefinition> typeDefinition() {
    return seq5(
            ref1(token, extendKw()).optional(),
            seq2(ref1(token, typeKw()), ref0(identifier))
                .map2((_, identifier) => identifier),
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
            ).map3((p0, fields, p2) => fields))
        .map5((ext, name, interfaceNames, directives, fields) {
      final type = GLTypeDefinition(
        name: name,
        nameDeclared: false,
        fields: fields,
        interfaceNames: interfaceNames ?? {},
        directives: directives,
        derivedFromType: null,
        extension: ext != null,
      );
      addTypeDefinition(type);
      return type;
    });
  }

  Parser<GLInputDefinition> inputDefinition() {
    return seq5(
            ref1(token, extendKw()).optional(),
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
                .map3((p0, fieldList, p2) => fieldList))
        .map5((extension, _, name, directives, fields) {
      String? nameFromDirective = getNameValueFromDirectives(directives);
      TokenInfo inputName = name.ofNewName(nameFromDirective ?? name.token);
      final input = GLInputDefinition(
        name: inputName,
        declaredName: name.token,
        fields: fields,
        directives: directives,
        extension: extension != null,
      );
      addInputDefinition(input);
      return input;
    });
  }

  Parser<GLField> field(
      {required bool canBeInitialized, required acceptsArguments}) {
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
      List<GLArgumentDefinition>? fieldArguments;
      Object? initialValue;

      if (acceptsArguments) {
        fieldArguments = value[2] as List<GLArgumentDefinition>?;
      } else {
        fieldArguments = null;
      }

      if (canBeInitialized) {
        initialValue = value[acceptsArguments ? 5 : 4];
      }

      GLType type = value[acceptsArguments ? 4 : 3] as GLType;
      List<GLDirectiveValue>? directives =
          value.last as List<GLDirectiveValue>?;
      return GLField(
        name: name,
        type: type,
        documentation: fieldDocumentation,
        arguments: fieldArguments ?? [],
        initialValue: initialValue,
        directives: directives ?? [],
      );
    });
  }

  Parser<List<GLField>> fieldList({
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

  Parser<GLInterfaceDefinition> interfaceDefinition() {
    return seq5(
            ref1(token, extendKw()).optional(),
            seq2(ref1(token, interfaceKw()), ref0(identifier))
                .map2((p0, interfaceName) => interfaceName),
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
                .map3((p0, fieldList, p2) => fieldList))
        .map5((extension, name, parentNames, directives, fieldList) {
      var interface = GLInterfaceDefinition(
        name: name,
        nameDeclared: false,
        fields: fieldList,
        directives: directives,
        interfaceNames: parentNames ?? {},
        extension: extension != null,
      );
      addInterfaceDefinition(interface);
      return interface;
    });
  }

  Parser<GLEnumDefinition> enumDefinition() => seq4(
          ref1(token, extendKw()).optional(),
          seq2(ref1(token, enumKw()), ref0(identifier)).map2((p0, id) => id),
          directiveValueList(),
          seq3(
                  ref0(openBrace),
                  seq3(ref1(token, documentation().optional()),
                          ref1(token, identifier()), directiveValueList())
                      .map3((comment, value, directives) => GLEnumValue(
                          value: value,
                          comment: comment,
                          directives: directives))
                      .plus(),
                  ref0(closeBrace))
              .map3((p0, list, p2) => list)).map4(
          (extension, identifier, directives, enumValues) {
        var enumDef = GLEnumDefinition(
            token: identifier,
            values: enumValues,
            directives: directives,
            extension: extension != null);
        addEnumDefinition(enumDef);
        return enumDef;
      });

  Parser<List<GLDirectiveValue>> directiveValueList() =>
      directiveValue().star();

  Parser<GLDirectiveValue> directiveValue() =>
      seq2(directiveValueName(), argumentValues().optional())
          .map2((name, args) => GLDirectiveValue(
              name.ofNewName(name.token.trim()), [], args ?? [],
              generated: false))
          .map((directiveValue) {
        addDiectiveValue(directiveValue);
        return directiveValue;
      });

  Parser<TokenInfo> directiveValueName() =>
      ref1(token, (ref0(at) & identifier())).map((list) {
        var token = list.last as TokenInfo;
        return token.ofNewName("@${token.token}");
      });

  Parser<GLDirectiveDefinition> directiveDefinition() => seq4(
              seq2(
                ref1(token, directiveKw()),
                directiveValueName(),
              ).map2((_, name) => name),
              arguments().optional(),
              ref1(token, repeatableKw()).optional(),
              seq2(ref1(token, onKw()), ref1(token, directiveScopes()))
                  .map2((_, scopes) => scopes))
          .map4((name, args, repeatable, scopes) => GLDirectiveDefinition(
              name, args ?? [], scopes, repeatable != null))
          .map((definition) {
        addDirectiveDefinition(definition);
        return definition;
      });

  Parser<GLDirectiveScope> directiveScope() {
    return GLDirectiveScope.values
        .map((e) => e.name)
        .map((name) => ref1(token, name.toParser())
            .map((value) => GLDirectiveScope.values.asNameMap()[value]!))
        .toList()
        .toChoiceParser();
  }

  Parser<Set<GLDirectiveScope>> directiveScopes() => seq2(
          directiveScope(),
          seq2(ref1(token, pipeKw()), directiveScope())
              .map2((_, scope) => scope)
              .star())
      .map2((scope, scopeList) => {scope, ...scopeList});

  Parser<GLArgumentDefinition> oneArgumentDefinition(
          {bool parametrized = false}) =>
      seq5(
              ref0(parametrized ? parametrizedArgument : identifier),
              colon(),
              typeTokenDefinition(),
              initialization().optional(),
              directiveValueList())
          .map5((name, _, type, initialization, directives) =>
              GLArgumentDefinition(name, type, directives,
                  initialValue: initialization));

  Parser<TokenInfo> parametrizedArgument() =>
      ref1(token, (char("\$") & identifier())).map((value) {
        // @TODO make this type safe
        var dollarSign = value[0] as String;
        var token = value[1] as TokenInfo;
        return token.ofNewName("$dollarSign${token.token}");
      });

  Parser<String> refValue() =>
      ref1(token, (char("\$") & identifier())).map((value) => value.join());

  Parser<GLArgumentValue> onArgumentValue() =>
      (ref0(identifier) & colon() & initialValue()).map((value) {
        return GLArgumentValue(value.first, value.last);
      });

  Parser<Object> initialization() =>
      (ref1(token, assignKw()) & ref1(token, initialValue()))
          .map((value) => value.last);

  Parser<Object> initialValue() => ref1(
          token,
          [
            doubleParser(),
            stringToken(),
            boolean(),
            ref0(objectValue),
            ref0(arrayValue),
            ref1(token, refValue()),
            nullKw(),
            identifier(),
          ].toChoiceParser())
      .map((value) => value);

  Parser<Map<String, Object?>> objectValue() => seq3(
          openBrace(),
          ref1(token, oneObjectField()).cast<MapEntry<String, Object>>().star(),
          closeBrace())
      .map3((_, entries, __) => Map.fromEntries(entries));

  Parser<MapEntry<String, Object>> oneObjectField() =>
      seq3(identifier(), colon(), initialValue())
          .map3((id, _, value) => MapEntry(id.token, value));

  Parser<List<Object?>> arrayValue() =>
      seq3(openSquareBracket(), ref0(initialValue).star(), closeSquareBracket())
          .map3((_, values, __) => values);

  Parser<GLType> typeTokenDefinition() =>
      (ref0(simpleTypeTokenDefinition) | ref0(listTypeDefinition))
          .cast<GLType>();

  Parser<GLType> simpleTypeTokenDefinition() {
    return seq2(ref1(token, identifier()),
            ref1(token, char("!")).optional().map((value) => value == null))
        .map2((name, nullable) {
      return GLType(name, nullable);
    });
  }

  Parser<GLType> listTypeDefinition() {
    return seq2(
            seq3(
              openSquareBracket(),
              ref0(typeTokenDefinition),
              closeSquareBracket(),
            ).map3((a, b, c) => b),
            ref1(token, char("!")).optional().map((value) => value == null))
        .map2((type, nullable) => GLListType(type, nullable));
  }

  Parser<TokenInfo> identifier() =>
      ref1(token, _id()).token().map((t) => TokenInfo.of(t, lastParsedFile));

  Parser<String> _id() =>
      seq2(_myLetter(), [_myLetter(), number()].toChoiceParser().star())
          .flatten();

  Parser<int> number() => ref0(digit).plus().flatten().map(int.parse);

  Parser<String> _myLetter() => [ref0(letter), char("_")].toChoiceParser();

  Parser hiddenStuffWhitespace() =>
      (ref0(visibleWhitespace) | ref0(singleLineComment) | ref0(commas));
  Parser ignoredStuff() =>
      (ref0(visibleWhitespace) | ref0(singleLineComment) | ref0(documentation));

  Parser<String> visibleWhitespace() => whitespace();

  Parser<String> commas() => char(",");

  Parser<String> doubleQuote() => char('"');

  Parser<String> tripleQuote() => string('"""');

  Parser<GLComment> singleLineComment() =>
      (char('#') & ref0(newlineLexicalToken).neg().star())
          .flatten()
          .map((value) => GLComment(value));

  Parser<String> singleLineStringLexicalToken() => seq3(doubleQuote(),
          ref0(stringContentDoubleQuotedLexicalToken), doubleQuote())
      .flatten();

  Parser<String> stringContentDoubleQuotedLexicalToken() =>
      doubleQuote().neg().star().flatten();

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

    return (tripleQuote & content & tripleQuote)
        .map((values) => values[1] as String);
  }
  //  ('"""'.toParser() & pattern('"""').neg().star() & '"""'.toParser()).flatten();

  Parser<String> stringToken() =>
      (blockStringToken() | singleLineStringToken()).flatten();

  Parser<String> documentation() =>
      (blockStringToken() | singleLineStringToken()).flatten();

  Parser<String> newlineLexicalToken() => pattern('\n\r');

  Parser<Set<TokenInfo>> implementsToken() {
    return seq2(ref1(token, implementsKw()), interfaceList())
        .map2((_, set) => set);
  }

  Parser<String> andKw() => "&".toParser();

  Parser<Set<TokenInfo>> interfaceList() => (identifier() &
              (ref1(token, andKw()) & identifier())
                  .map((value) => value[1])
                  .star())
          .map((array) {
        Set<TokenInfo> interfaceList = {array[0]};
        for (var value in array[1]) {
          //if(interfaceList.where((e) => e.token == ))
          final exists =
              interfaceList.where((e) => e.token == value.token).isNotEmpty;
          if (exists) {
            throw ParseException(
                "interface $value has been implemented more than once",
                info: value);
          }
          interfaceList.add(value);
        }
        return interfaceList;
      });

  Parser<bool> boolean() =>
      ("true".toParser() | "false".toParser()).map((value) => value == "true");

  Parser<int> intParser() =>
      ("0x".toParser() & (pattern("0-9A-Fa-f").times(4)) |
              (char("-").optional() & pattern("0-9").plus()))
          .flatten()
          .map(int.parse);

  Parser<Object> doubleParser() =>
      ((plainIntParser() & (char(".") & plainIntParser()).optional()) |
              intParser().map((value) => "$value"))
          .flatten()
          .map((val) {
        if (val.contains(".")) {
          return double.parse(val);
        } else {
          return int.parse(val);
        }
      });

  Parser<Object> constantType() =>
      [doubleParser(), stringToken(), boolean()].toChoiceParser();

  Parser<GLScalarDefinition> scalarDefinition() =>
      (ref1(token, extendKw()).optional() &
              ref1(token, scalarKw()) &
              ref1(token, identifier()) &
              directiveValueList())
          .map((array) {
        final scalarName = array[2];
        var extension = array[0] != null;
        var scalar = GLScalarDefinition(
            token: scalarName, directives: array[3], extension: extension);
        addScalarDefinition(scalar);
        return scalar;
      });

  Parser<GLSchema> schemaDefinition() {
    return seq4(
            ref1(token, extendKw()).optional(),
            ref1(token, schemaKw()),
            directiveValueList(),
            seq3(openBrace(), schemaElement().repeat(0, 3), closeBrace())
                .map3((_, list, __) => list)
                .optional())
        .map4((extension, tokenInfo, directives, list) {
      var schema = GLSchema(tokenInfo, extension != null,
          operationTypes: list ?? [], directives: directives);
      defineSchema(schema);
      return schema;
    });
  }

  Parser<SchemaElement> schemaElement() {
    return seq3(
            ref1(token,
                [queryKw(), mutationKw(), subscriptionKw()].toChoiceParser()),
            colon(),
            identifier())
        .map3((p0, p1, p2) => SchemaElement(p0, p2));
  }

  Parser<GLProjection> fragmentReference() {
    return seq3(ref1(token, fragRefKw()), identifier(), directiveValueList())
        .map3(
      (_, name, directives) => GLProjection(
          fragmentName: name.token,
          token: name,
          alias: null,
          block: null,
          directives: directives),
    );
  }

  Parser<GLProjection> fragmentField() {
    return [fragmentValue(), projectionFieldField()].toChoiceParser();
  }

  Parser<GLProjection> projectionFieldField() {
    return seq4(alias().optional(), identifier(), directiveValueList(),
            ref0(fragmentBlock).optional())
        .map4((alias, token, directives, block) => GLProjection(
              token: token,
              fragmentName: null,
              alias: alias,
              block: block,
              directives: directives,
            ));
  }

  Parser<GLInlineFragmentDefinition> inlineFragment() {
    return seq4(
      ref1(token, fragRefKw()),
      ref1(token, onKw()),
      identifier(),
      seq2(directiveValueList(), ref0(fragmentBlock)).map2(
        (directives, block) => GLProjection(
          fragmentName: null,
          token: null,
          alias: null,
          block: block,
          directives: directives,
        ),
      ),
    ).map4((p0, p1, typeName, projection) {
      var def = GLInlineFragmentDefinition(
        typeName,
        projection.block!,
        projection.getDirectives(),
      );
      addFragmentDefinition(def);
      return def;
    });
  }

  Parser<GLProjection> fragmentValue() => [
        inlineFragment()
            .plus()
            .map((list) => GLInlineFragmentsProjection(inlineFragments: list)),
        fragmentReference()
      ].toChoiceParser().cast<GLProjection>();

  Parser<GLFragmentDefinition> fragmentDefinition() {
    return seq4(
            seq3(
              ref1(token, fragmentKw()),
              identifier(),
              ref1(token, onKw()),
            ).map3((p0, fragmentName, p2) => fragmentName),
            identifier(),
            directiveValueList(),
            fragmentBlock())
        .map4((name, typeName, directiveValues, block) =>
            GLFragmentDefinition(name, typeName, block, directiveValues))
        .map((f) {
      addFragmentDefinition(f);
      return f;
    });
  }

  Parser<GLUnionDefinition> unionDefinition() {
    return seq5(
      ref1(token, extendKw()).optional(),
      seq2(
        ref1(token, unionKw()),
        ref0(identifier),
      ).map2((_, unionName) => unionName),
      seq2(ref1(token, assignKw()), ref1(token, identifier()))
          .map2((_, id) => id)
          .optional(),
      seq2(ref1(token, pipeKw()), ref0(identifier)).map2((_, id) => id).star(),
      directiveValueList(),
    )
        .map5((extension, name, type1, types, directives) => GLUnionDefinition(
            name,
            extension != null,
            [if (type1 != null) type1, ...types],
            directives))
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

  Parser<GLFragmentBlockDefinition> fragmentBlock() {
    return seq3(openBrace(), fragmentField().plus(), closeBrace()).map3(
        (p0, projectionList, p2) => GLFragmentBlockDefinition(projectionList));
  }

  Parser<int> plainIntParser() =>
      pattern("0-9").plus().flatten().map(int.parse);

  Parser<GLQueryDefinition> queryDefinition(GLQueryType type) {
    return seq4(
            seq2(
              ref1(token, type.name.toParser()),
              identifier(),
            ).map2((p0, identifier) => identifier),
            arguments(parametrized: true).optional(),
            directiveValueList(),
            seq3(
                    openBrace(),
                    (type == GLQueryType.subscription
                        ? queryElement().map((value) => [value])
                        : queryElement().plus()),
                    closeBrace())
                .map3((p0, queryElements, p2) => queryElements))
        .map4(
      (name, args, directives, elements) => GLQueryDefinition(
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

  Parser<GLQueryElement> queryElement() {
    return seq5(alias().optional(), identifier(), argumentValues().optional(),
            directiveValueList(), fragmentBlock().optional())
        .map5((alias, name, args, directiveList, block) => GLQueryElement(
              name,
              directiveList,
              block,
              args ?? [],
              alias,
            ));
  }

  Parser<TokenInfo> alias() =>
      seq2(identifier(), colon()).map2((id, colon) => id);
}
