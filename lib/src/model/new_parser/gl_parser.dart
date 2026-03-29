import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_directive.dart';
import 'package:graphlink/src/model/gl_fragment.dart';
import 'package:graphlink/src/model/gl_schema.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_enum_definition.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_input_definition.dart';
import 'package:graphlink/src/model/gl_scalar_definition.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_shcema_mapping.dart';
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_union.dart';
import 'package:graphlink/src/model/new_parser/gl_lexer.dart';
import 'package:graphlink/src/model/new_parser/gl_lexter_token.dart';
import 'package:graphlink/src/model/gl_logical_file.dart';
import 'package:graphlink/src/model/new_parser/gl_token_type.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/serializers/language.dart';
import 'package:graphlink/src/utils.dart';
import 'package:logger/logger.dart';

import 'package:graphlink/src/gl_grammar_cache_extension.dart';
import 'package:graphlink/src/gl_grammar_extension.dart';
import 'package:graphlink/src/gl_validation_extension.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_controller.dart';
import 'package:graphlink/src/model/gl_repository.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_token.dart';
import 'package:graphlink/src/serializers/graphq_serializer.dart';
import 'package:graphlink/src/ui/flutter/gl_type_view.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
export 'package:graphlink/src/gl_grammar_extension.dart';
export 'package:graphlink/src/gl_validation_extension.dart';

class GLParser {
  late GLLexer _lexer;
  int _pos = 0;

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

  final bool _validate = true;

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

  GLParser({
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

  GLLexerToken peek() => _lexer.tokens[_pos];

  GLLexerToken peekNext() => _lexer.tokens[_pos + 1];

  GLLexerToken consume() => _lexer.tokens[_pos++];

  GLLexerToken expect(GLTokenType type) {
    final t = peek();
    if (t.type != type) {
      final loc = _lexer.locationOf(t.offset);
      throw ParseException(
        "Expected ${tokenTypeNames[type] ?? type.name} but got '${t.value}'",
        info: TokenInfo(
            token: t.value,
            line: loc.line,
            column: loc.column,
            fileName: _lexer.fileName),
      );
    }
    return consume();
  }

  void validateSemantics() {
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

  void addSchemaMapping(GLSchemaMapping mapping) {
    var m = _schemaMappings[mapping.key];
    if (m == null || m.batch == null) {
      _schemaMappings[mapping.key] = mapping;
      return;
    }
    if (mapping.batch != null && m.batch != mapping.batch) {
      throw ParseException(
        "Conflicting batch settings for mapping '${mapping.key}': "
        "one source requires batch: ${m.batch}, another requires batch: ${mapping.batch}. "
        "Add an explicit @glSkipOnServer(batch: ...) on the '${mapping.field.name}' field of '${mapping.type.token}' to resolve the conflict.",
        info: mapping.field.name,
      );
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

  bool check(GLTokenType type) => peek().type == type;

  bool checkAny(List<GLTokenType> types) => types.contains(peek().type);

  GLLexerToken? tryConsume(GLTokenType type) => check(type) ? consume() : null;

  static final _nameTypes = <GLTokenType>{
    GLTokenType.identifier,
    ...keywords.values,
  };

  /// Returns true for tokens that are valid in name positions (identifiers and
  /// contextual keywords). In GraphQL, keywords are not globally reserved and
  /// may appear as field names, type names, argument names, etc.
  bool _isName(GLTokenType type) => _nameTypes.contains(type);

  GLLexerToken expectName() {
    final t = peek();
    if (_isName(t.type)) return consume();
    final loc = _lexer.locationOf(t.offset);
    throw ParseException(
      "Expected name but got '${t.value}'",
      info: TokenInfo(
          token: t.value,
          line: loc.line,
          column: loc.column,
          fileName: _lexer.fileName),
    );
  }

  TokenInfo tokenInfoOf(GLLexerToken token) => TokenInfo.ofLexer(token, _lexer);

  void parse(String text, {bool validate = true}) {
    _pos = 0;
    _lexer = GLLexer(text);
    _lexer.tokenize();
    doParse(validate: validate);
  }

  void parseAndValidate(String text) {
    parse(text, validate: true);
  }

  void parseFile(GLLogicalFile file, {bool validate = true}) {
    _pos = 0;
    lastParsedFile = file.path;
    _lexer = GLLexer(file.data, fileName: file.path);
    _lexer.tokenize();
    doParse(validate: validate);
  }

  void parseFiles(List<GLLogicalFile> files, {String? extraGql}) {
    for (var i = 0; i < files.length; i++) {
      final isLast = i == files.length - 1;
      parseFile(files[i], validate: extraGql == null && isLast);
    }
    if (extraGql != null) {
      parseAndValidate(extraGql);
    }
  }

  void doParse({bool validate = true}) {
    while (!check(GLTokenType.eof)) {
      _parseDefinition();
    }
    if (validate) validateSemantics();
  }

  void _parseDefinition() {
    final doc = _parseDocumentation();
    switch (peek().type) {
      case GLTokenType.kwType:
        _parseTypeDefinition(isExtension: false, documentation: doc);
        break;
      case GLTokenType.kwInput:
        _parseInputDefinition(isExtension: false, documentation: doc);
        break;
      case GLTokenType.kwInterface:
        _parseInterfaceDefinition(isExtension: false, documentation: doc);
        break;
      case GLTokenType.kwEnum:
        _parseEnumDefinition(isExtension: false, documentation: doc);
        break;
      case GLTokenType.kwScalar:
        _parseScalarDefinition(isExtension: false, documentation: doc);
        break;
      case GLTokenType.kwUnion:
        _parseUnionDefinition(isExtension: false, documentation: doc);
        break;
      case GLTokenType.kwDirective:
        _parseDirectiveDefinition(documentation: doc);
        break;
      case GLTokenType.kwFragment:
        _parseFragmentDefinition(documentation: doc);
        break;
      case GLTokenType.kwQuery:
      case GLTokenType.kwMutation:
      case GLTokenType.kwSubscription:
        _parseOperationDefinition(documentation: doc);
        break;
      case GLTokenType.kwSchema:
        _parseSchemaDefinition(isExtension: false, documentation: doc);
        break;
      case GLTokenType.kwExtend:
        _parseExtendDefinition();
        break;
      default:
        final t = peek();
        final loc = _lexer.locationOf(t.offset);
        throw ParseException(
          "Unexpected token '${t.value}'",
          info: TokenInfo(
              token: t.value,
              line: loc.line,
              column: loc.column,
              fileName: _lexer.fileName),
        );
    }
  }

  String? _parseDocumentation() {
    final t = peek();
    if (t.type == GLTokenType.string || t.type == GLTokenType.blockString) {
      return consume().value;
    }
    return null;
  }

  void _parseTypeDefinition(
      {required bool isExtension, String? documentation}) {
    expect(GLTokenType.kwType);
    final name = expectName();
    final interfaceNames = _parseImplementsClause();
    final directives = _parseDirectiveValueList(GLDirectiveScope.OBJECT);
    expect(GLTokenType.openBrace);
    final fields = <GLField>[];
    while (tryConsume(GLTokenType.closeBrace) == null) {
      fields.add(_parseField(
          canBeInitialized: true,
          acceptsArguments: true,
          fieldScope: GLDirectiveScope.FIELD_DEFINITION));
    }
    addTypeDefinition(GLTypeDefinition(
      name: TokenInfo.ofLexer(name, _lexer),
      nameDeclared: false,
      fields: fields,
      interfaceNames: interfaceNames,
      directives: directives,
      derivedFromType: null,
      extension: isExtension,
      documentation: documentation,
    ));
  }

  Set<TokenInfo> _parseImplementsClause() {
    if (tryConsume(GLTokenType.kwImplements) == null) return {};
    final names = <TokenInfo>{};
    names.add(TokenInfo.ofLexer(expectName(), _lexer));
    while (tryConsume(GLTokenType.amp) != null) {
      final name = TokenInfo.ofLexer(expectName(), _lexer);
      final exists = names.where((e) => e.token == name.token).isNotEmpty;
      if (exists) {
        throw ParseException(
            "interface ${name.token} has been implemented more than once",
            info: name);
      }
      names.add(name);
    }
    return names;
  }

  void _parseInputDefinition(
      {required bool isExtension, String? documentation}) {
    expect(GLTokenType.kwInput);
    final name = expectName();
    final directives = _parseDirectiveValueList(GLDirectiveScope.INPUT_OBJECT);
    expect(GLTokenType.openBrace);
    final fields = <GLField>[];
    while (tryConsume(GLTokenType.closeBrace) == null) {
      fields.add(_parseField(
          canBeInitialized: true,
          acceptsArguments: false,
          fieldScope: GLDirectiveScope.INPUT_FIELD_DEFINITION));
    }
    final nameToken = TokenInfo.ofLexer(name, _lexer);
    final nameFromDirective = getNameValueFromDirectives(directives);
    final inputName = nameFromDirective != null
        ? nameToken.ofNewName(nameFromDirective)
        : nameToken;
    addInputDefinition(GLInputDefinition(
      name: inputName,
      declaredName: name.value,
      fields: fields,
      directives: directives,
      extension: isExtension,
      documentation: documentation,
    ));
  }

  GLField _parseField(
      {required bool canBeInitialized,
      required bool acceptsArguments,
      required GLDirectiveScope fieldScope}) {
    final doc = _parseDocumentation();
    final name = expectName();
    if (acceptsArguments &&
        check(GLTokenType.openParen) &&
        peekNext().type == GLTokenType.closeParen) {
      final t = peekNext();
      final loc = _lexer.locationOf(t.offset);
      throw ParseException(
        "Argument list cannot be empty; remove the parentheses or add at least one argument",
        info: TokenInfo(
            token: t.value,
            line: loc.line,
            column: loc.column,
            fileName: _lexer.fileName),
      );
    }
    final args = acceptsArguments
        ? _parseArgumentDefinitions()
        : <GLArgumentDefinition>[];
    expect(GLTokenType.colon);
    final type = _parseType();
    Object? initialValue;
    if (canBeInitialized && tryConsume(GLTokenType.equals) != null) {
      initialValue = _parseObject();
    }
    final directives = _parseDirectiveValueList(fieldScope);
    return GLField(
      name: TokenInfo.ofLexer(name, _lexer),
      type: type,
      arguments: args,
      initialValue: initialValue,
      documentation: doc,
      directives: directives,
    );
  }

  List<GLArgumentDefinition> _parseArgumentDefinitions() {
    if (!check(GLTokenType.openParen)) return [];
    expect(GLTokenType.openParen);
    final args = <GLArgumentDefinition>[];
    while (tryConsume(GLTokenType.closeParen) == null) {
      final name = expectName();
      expect(GLTokenType.colon);
      final type = _parseType();
      Object? defaultValue;
      if (tryConsume(GLTokenType.equals) != null) {
        defaultValue = _parseObject();
      }
      final directives =
          _parseDirectiveValueList(GLDirectiveScope.ARGUMENT_DEFINITION);
      args.add(GLArgumentDefinition(
          TokenInfo.ofLexer(name, _lexer), type, directives,
          initialValue: defaultValue));
    }
    return args;
  }

  GLType _parseType() {
    if (check(GLTokenType.openBracket)) {
      expect(GLTokenType.openBracket);
      final inner = _parseType();
      expect(GLTokenType.closeBracket);
      final nullable = tryConsume(GLTokenType.bang) == null;
      return GLListType(inner, nullable);
    }
    final name = expectName();
    final nullable = tryConsume(GLTokenType.bang) == null;
    return GLType(TokenInfo.ofLexer(name, _lexer), nullable);
  }

  void _parseInterfaceDefinition(
      {required bool isExtension, String? documentation}) {
    expect(GLTokenType.kwInterface);
    final name = expectName();
    final interfaceNames = _parseImplementsClause();
    final directives = _parseDirectiveValueList(GLDirectiveScope.INTERFACE);
    expect(GLTokenType.openBrace);
    final fields = <GLField>[];
    while (tryConsume(GLTokenType.closeBrace) == null) {
      fields.add(_parseField(
          canBeInitialized: false,
          acceptsArguments: true,
          fieldScope: GLDirectiveScope.FIELD_DEFINITION));
    }
    addInterfaceDefinition(GLInterfaceDefinition(
      name: TokenInfo.ofLexer(name, _lexer),
      nameDeclared: false,
      fields: fields,
      interfaceNames: interfaceNames,
      directives: directives,
      extension: isExtension,
      documentation: documentation,
    ));
  }

  void _parseEnumDefinition(
      {required bool isExtension, String? documentation}) {
    expect(GLTokenType.kwEnum);
    var name = expectName();
    var directiveValues = _parseDirectiveValueList(GLDirectiveScope.ENUM);
    expect(GLTokenType.openBrace);
    var enumDefinition = GLEnumDefinition(
        token: TokenInfo.ofLexer(name, _lexer),
        values: [],
        directives: directiveValues,
        extension: isExtension,
        documentation: documentation);
    while (tryConsume(GLTokenType.closeBrace) == null) {
      final GLEnumValue enumValue = _parseEnumValue();
      enumDefinition.addValue(enumValue);
    }
    addEnumDefinition(enumDefinition);
  }

  GLEnumValue _parseEnumValue() {
    final doc = _parseDocumentation();
    final value = expectName();
    final directives = _parseDirectiveValueList(GLDirectiveScope.ENUM_VALUE);
    return GLEnumValue(
        value: TokenInfo.ofLexer(value, _lexer),
        documentation: doc,
        directives: directives);
  }

  void _parseScalarDefinition(
      {required bool isExtension, String? documentation}) {
    expect(GLTokenType.kwScalar);
    var name = expectName();
    var directives = _parseDirectiveValueList(GLDirectiveScope.SCALAR);
    var scalarDef = GLScalarDefinition(
        token: TokenInfo.ofLexer(name, _lexer),
        directives: directives,
        extension: isExtension,
        documentation: documentation);
    addScalarDefinition(scalarDef);
  }

  List<GLDirectiveValue> _parseDirectiveValueList(GLDirectiveScope scope) {
    final result = <GLDirectiveValue>[];
    while (check(GLTokenType.at)) {
      result.add(_parseDirectiveValue(scope));
    }
    return result;
  }

  GLDirectiveValue _parseDirectiveValue(GLDirectiveScope scope) {
    expect(GLTokenType.at);
    var identifier = expectName();
    var arguments = _parseDirectiveArguments();
    final value = GLDirectiveValue(
        TokenInfo.ofLexer(identifier, _lexer), [scope], arguments,
        generated: false);
    addDirectiveValue(value);
    return value;
  }

  List<GLArgumentValue> _parseDirectiveArguments() {
    if (!check(GLTokenType.openParen)) {
      return [];
    }
    var list = <GLArgumentValue>[];
    expect(GLTokenType.openParen);
    while (tryConsume(GLTokenType.closeParen) == null) {
      var token = expectName();
      expect(GLTokenType.colon);
      var initialValue = _parseInitialValue();
      list.add(GLArgumentValue(TokenInfo.ofLexer(token, _lexer), initialValue));
    }
    return list;
  }

  Object? _parseInitialValue() {
    // parse initial object here
    return _parseObject();
  }

  Object? _parseObject() {
    var nextToken = peek();
    switch (nextToken.type) {
      case GLTokenType.string:
      case GLTokenType.blockString:
      case GLTokenType.identifier:
        return consume().value;

      case GLTokenType.int_:
        return int.parse(consume().value);
      case GLTokenType.float_:
        return double.parse(consume().value);

      case GLTokenType.kwTrue:
        consume();
        return true;
      case GLTokenType.kwFalse:
        consume();
        return false;
      case GLTokenType.kwNull:
        consume();
        return null;
      case GLTokenType.openBrace:
        return _parseMap();
      case GLTokenType.openBracket:
        return _parseList();
      default:
        if (_isName(nextToken.type)) return consume().value;
        throw _lexer.errorAt(nextToken.offset, "Unexpected input");
    }
  }

  Map<String, Object?> _parseMap() {
    expect(GLTokenType.openBrace);
    var result = <String, Object?>{};
    while (tryConsume(GLTokenType.closeBrace) == null) {
      var key = expectName();
      expect(GLTokenType.colon);
      result[key.value] = _parseObject();
    }
    return result;
  }

  List<Object?> _parseList() {
    expect(GLTokenType.openBracket);
    var result = <Object?>[];
    while (tryConsume(GLTokenType.closeBracket) == null) {
      result.add(_parseObject());
    }
    return result;
  }

  void _parseUnionDefinition(
      {required bool isExtension, String? documentation}) {
    expect(GLTokenType.kwUnion);
    final name = expectName();
    final directives = _parseDirectiveValueList(GLDirectiveScope.UNION);
    final typeNames = <TokenInfo>[];
    if (tryConsume(GLTokenType.equals) != null) {
      typeNames.add(TokenInfo.ofLexer(expectName(), _lexer));
      while (tryConsume(GLTokenType.pipe) != null) {
        typeNames.add(TokenInfo.ofLexer(expectName(), _lexer));
      }
    }
    addUnionDefinition(GLUnionDefinition(
        TokenInfo.ofLexer(name, _lexer), isExtension, typeNames, directives,
        documentation: documentation));
  }

  void _parseDirectiveDefinition({String? documentation}) {
    expect(GLTokenType.kwDirective);
    expect(GLTokenType.at);
    final name = expectName();
    final args = _parseArgumentDefinitions();
    final repeatable = tryConsume(GLTokenType.kwRepeatable) != null;
    expect(GLTokenType.kwOn);
    final scopes = _parseDirectiveScopes();
    addDirectiveDefinition(GLDirectiveDefinition(
      TokenInfo.ofLexer(name, _lexer),
      args,
      scopes,
      repeatable,
      documentation: documentation,
    ));
  }

  Set<GLDirectiveScope> _parseDirectiveScopes() {
    final scopes = <GLDirectiveScope>{};
    scopes.add(_parseDirectiveScope());
    while (tryConsume(GLTokenType.pipe) != null) {
      scopes.add(_parseDirectiveScope());
    }
    return scopes;
  }

  GLDirectiveScope _parseDirectiveScope() {
    final token = expectName();
    final scope = GLDirectiveScope.values.asNameMap()[token.value];
    if (scope == null) {
      throw _lexer.errorAt(
          token.offset, "Unknown directive scope '${token.value}'");
    }
    return scope;
  }

  void _parseFragmentDefinition({String? documentation}) {
    expect(GLTokenType.kwFragment);
    final name = expectName();
    expect(GLTokenType.kwOn);
    final typeName = expectName();
    final directives =
        _parseDirectiveValueList(GLDirectiveScope.FRAGMENT_DEFINITION);
    final block = _parseFragmentBlock();
    addFragmentDefinition(GLFragmentDefinition(
      TokenInfo.ofLexer(name, _lexer),
      TokenInfo.ofLexer(typeName, _lexer),
      block,
      directives,
    ));
  }

  GLFragmentBlockDefinition _parseFragmentBlock() {
    expect(GLTokenType.openBrace);
    final projections = <GLProjection>[];
    while (tryConsume(GLTokenType.closeBrace) == null) {
      if (check(GLTokenType.spread)) {
        projections.add(_parseSpreadProjection());
      } else {
        projections.add(_parseFieldProjection());
      }
    }
    return GLFragmentBlockDefinition(projections);
  }

  GLProjection _parseSpreadProjection() {
    if (peekNext().type == GLTokenType.kwOn) {
      // Inline fragment(s): collect consecutive ... on Type { } blocks
      final inlineFragments = <GLInlineFragmentDefinition>[];
      while (check(GLTokenType.spread) && peekNext().type == GLTokenType.kwOn) {
        expect(GLTokenType.spread);
        expect(GLTokenType.kwOn);
        final typeName = expectName();
        final directives =
            _parseDirectiveValueList(GLDirectiveScope.INLINE_FRAGMENT);
        final block = _parseFragmentBlock();
        final def = GLInlineFragmentDefinition(
            TokenInfo.ofLexer(typeName, _lexer), block, directives);
        addFragmentDefinition(def);
        inlineFragments.add(def);
      }
      return GLInlineFragmentsProjection(inlineFragments: inlineFragments);
    }
    // Fragment spread: ...FragmentName @directives*
    expect(GLTokenType.spread);
    final name = expectName();
    final directives =
        _parseDirectiveValueList(GLDirectiveScope.FRAGMENT_SPREAD);
    return GLProjection(
      fragmentName: name.value,
      token: TokenInfo.ofLexer(name, _lexer),
      alias: null,
      block: null,
      directives: directives,
    );
  }

  GLProjection _parseFieldProjection() {
    // Detect alias: identifier followed by colon
    TokenInfo? alias;
    if (_isName(peek().type) && peekNext().type == GLTokenType.colon) {
      alias = TokenInfo.ofLexer(consume(), _lexer);
      consume(); // consume colon
    }
    final name = expectName();
    final directives = _parseDirectiveValueList(GLDirectiveScope.FIELD);
    GLFragmentBlockDefinition? block;
    if (check(GLTokenType.openBrace)) {
      block = _parseFragmentBlock();
    }
    return GLProjection(
      fragmentName: null,
      token: TokenInfo.ofLexer(name, _lexer),
      alias: alias,
      block: block,
      directives: directives,
    );
  }

  void _parseOperationDefinition({String? documentation}) {
    final keywordToken = peek();
    final GLQueryType type;
    final GLDirectiveScope operationScope;
    switch (keywordToken.type) {
      case GLTokenType.kwQuery:
        consume();
        type = GLQueryType.query;
        operationScope = GLDirectiveScope.QUERY;
        break;
      case GLTokenType.kwMutation:
        consume();
        type = GLQueryType.mutation;
        operationScope = GLDirectiveScope.MUTATION;
        break;
      case GLTokenType.kwSubscription:
        consume();
        type = GLQueryType.subscription;
        operationScope = GLDirectiveScope.SUBSCRIPTION;
        break;
      default:
        throw _lexer.errorAt(keywordToken.offset, "Expected operation type");
    }
    final name = expectName();
    final args = _parseArgumentDefinitions();
    final directives = _parseDirectiveValueList(operationScope);
    expect(GLTokenType.openBrace);
    final elements = <GLQueryElement>[];
    while (tryConsume(GLTokenType.closeBrace) == null) {
      elements.add(_parseQueryElement());
    }
    if (elements.isEmpty) {
      throw _lexer.errorAt(
          keywordToken.offset, "Operation must have at least one field");
    }
    if (type == GLQueryType.subscription && elements.length > 1) {
      throw _lexer.errorAt(keywordToken.offset,
          "Subscription operations must have exactly one root field");
    }
    addQueryDefinition(GLQueryDefinition(
      TokenInfo.ofLexer(name, _lexer),
      directives,
      args,
      elements,
      type,
    ));
  }

  GLQueryElement _parseQueryElement() {
    TokenInfo? alias;
    if (_isName(peek().type) && peekNext().type == GLTokenType.colon) {
      alias = TokenInfo.ofLexer(consume(), _lexer);
      consume(); // consume colon
    }
    final name = expectName();
    final args = _parseArgumentValues();
    final directives = _parseDirectiveValueList(GLDirectiveScope.FIELD);
    GLFragmentBlockDefinition? block;
    if (check(GLTokenType.openBrace)) block = _parseFragmentBlock();
    return GLQueryElement(
      TokenInfo.ofLexer(name, _lexer),
      directives,
      block,
      args,
      alias,
    );
  }

  List<GLArgumentValue> _parseArgumentValues() {
    if (!check(GLTokenType.openParen)) return [];
    expect(GLTokenType.openParen);
    final args = <GLArgumentValue>[];
    while (tryConsume(GLTokenType.closeParen) == null) {
      final name = expectName();
      expect(GLTokenType.colon);
      final value = _parseObject();
      args.add(GLArgumentValue(TokenInfo.ofLexer(name, _lexer), value));
    }
    return args;
  }

  void _parseSchemaDefinition(
      {required bool isExtension, String? documentation}) {
    final schemaToken = expect(GLTokenType.kwSchema);
    final directives = _parseDirectiveValueList(GLDirectiveScope.SCHEMA);
    final operationTypes = <SchemaElement>[];
    if (tryConsume(GLTokenType.openBrace) != null) {
      while (tryConsume(GLTokenType.closeBrace) == null) {
        operationTypes.add(_parseSchemaElement());
      }
    }
    defineSchema(GLSchema(
      TokenInfo.ofLexer(schemaToken, _lexer),
      isExtension,
      operationTypes: operationTypes,
      directives: directives,
      documentation: documentation,
    ));
  }

  SchemaElement _parseSchemaElement() {
    final token = peek();
    final GLQueryType type;
    switch (token.type) {
      case GLTokenType.kwQuery:
        consume();
        type = GLQueryType.query;
        break;
      case GLTokenType.kwMutation:
        consume();
        type = GLQueryType.mutation;
        break;
      case GLTokenType.kwSubscription:
        consume();
        type = GLQueryType.subscription;
        break;
      default:
        throw _lexer.errorAt(
            token.offset, "Expected 'query', 'mutation', or 'subscription'");
    }
    expect(GLTokenType.colon);
    final name = expectName();
    return SchemaElement(type, TokenInfo.ofLexer(name, _lexer));
  }

  void _parseExtendDefinition() {
    expect(GLTokenType.kwExtend);
    final next = peek();
    switch (next.type) {
      case GLTokenType.kwScalar:
        _parseScalarDefinition(isExtension: true);
        break;
      case GLTokenType.kwType:
        _parseTypeDefinition(isExtension: true);
        break;
      case GLTokenType.kwInput:
        _parseInputDefinition(isExtension: true);
        break;
      case GLTokenType.kwInterface:
        _parseInterfaceDefinition(isExtension: true);
        break;
      case GLTokenType.kwEnum:
        _parseEnumDefinition(isExtension: true);
        break;
      case GLTokenType.kwUnion:
        _parseUnionDefinition(isExtension: true);
        break;
      case GLTokenType.kwSchema:
        _parseSchemaDefinition(isExtension: true);
        break;
      default:
        throw _lexer.errorAt(
            next.offset, "Unexpected token '${next.value}' after 'extend'");
    }
  }
}
