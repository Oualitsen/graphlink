import 'package:graphlink/src/excpetions/parse_exception.dart';
import 'package:graphlink/src/gl_grammar.dart';
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
import 'package:graphlink/src/model/gl_type_definition.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/model/gl_union.dart';
import 'package:graphlink/src/model/new_parser/gl_lexer.dart';
import 'package:graphlink/src/model/new_parser/gl_lexter_token.dart';
import 'package:graphlink/src/model/gl_logical_file.dart';
import 'package:graphlink/src/model/new_parser/gl_token_type.dart';
import 'package:graphlink/src/model/token_info.dart';
import 'package:graphlink/src/utils.dart';

class GLParser {
  final List<GLLexerToken> _tokens;
  final GLLexer _lexer;
  final GLGrammar grammar;
  int _pos = 0;

  GLParser(this._tokens, this._lexer, this.grammar);

  GLLexerToken peek() => _tokens[_pos];

  GLLexerToken peekNext() => _tokens[_pos + 1];

  GLLexerToken consume() => _tokens[_pos++];

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

  bool check(GLTokenType type) => peek().type == type;

  bool checkAny(List<GLTokenType> types) => types.contains(peek().type);

  GLLexerToken? tryConsume(GLTokenType type) => check(type) ? consume() : null;

  TokenInfo tokenInfoOf(GLLexerToken token) => TokenInfo.ofLexer(token, _lexer);

  static void parse(GLGrammar grammar, String text, {bool validate = true}) {
    final lexer = GLLexer(text);
    final tokens = lexer.tokenize();
    GLParser(tokens, lexer, grammar).doParse(validate: validate);
  }

  static void parseAndValidate(GLGrammar grammar, String text) {
    parse(grammar, text, validate: true);
  }

  static void parseFile(GLGrammar grammar, GLLogicalFile file,
      {bool validate = true}) {
    grammar.lastParsedFile = file.path;
    final lexer = GLLexer(file.data, fileName: file.path);
    final tokens = lexer.tokenize();
    GLParser(tokens, lexer, grammar).doParse(validate: validate);
  }

  static void parseFiles(GLGrammar grammar, List<GLLogicalFile> files,
      {String? extraGql}) {
    for (var i = 0; i < files.length; i++) {
      final isLast = i == files.length - 1;
      parseFile(grammar, files[i], validate: extraGql == null && isLast);
    }
    if (extraGql != null) {
      parseAndValidate(grammar, extraGql);
    }
  }

  void doParse({bool validate = true}) {
    while (!check(GLTokenType.eof)) {
      _parseDefinition();
    }
    if (validate) grammar.validateSemantics();
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
    final name = expect(GLTokenType.identifier);
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
    grammar.addTypeDefinition(GLTypeDefinition(
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
    names.add(TokenInfo.ofLexer(expect(GLTokenType.identifier), _lexer));
    while (tryConsume(GLTokenType.amp) != null) {
      names.add(TokenInfo.ofLexer(expect(GLTokenType.identifier), _lexer));
    }
    return names;
  }

  void _parseInputDefinition(
      {required bool isExtension, String? documentation}) {
    expect(GLTokenType.kwInput);
    final name = expect(GLTokenType.identifier);
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
    grammar.addInputDefinition(GLInputDefinition(
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
    final name = expect(GLTokenType.identifier);
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
      final name = expect(GLTokenType.identifier);
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
    final name = expect(GLTokenType.identifier);
    final nullable = tryConsume(GLTokenType.bang) == null;
    return GLType(TokenInfo.ofLexer(name, _lexer), nullable);
  }

  void _parseInterfaceDefinition(
      {required bool isExtension, String? documentation}) {
    expect(GLTokenType.kwInterface);
    final name = expect(GLTokenType.identifier);
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
    grammar.addInterfaceDefinition(GLInterfaceDefinition(
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
    var name = expect(GLTokenType.identifier);
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
    grammar.addEnumDefinition(enumDefinition);
  }

  GLEnumValue _parseEnumValue() {
    final doc = _parseDocumentation();
    final value = expect(GLTokenType.identifier);
    final directives = _parseDirectiveValueList(GLDirectiveScope.ENUM_VALUE);
    return GLEnumValue(
        value: TokenInfo.ofLexer(value, _lexer),
        documentation: doc,
        directives: directives);
  }

  void _parseScalarDefinition(
      {required bool isExtension, String? documentation}) {
    expect(GLTokenType.kwScalar);
    var name = expect(GLTokenType.identifier);
    var directives = _parseDirectiveValueList(GLDirectiveScope.SCALAR);
    var scalarDef = GLScalarDefinition(
        token: TokenInfo.ofLexer(name, _lexer),
        directives: directives,
        extension: isExtension,
        documentation: documentation);
    grammar.addScalarDefinition(scalarDef);
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
    var identifier = expect(GLTokenType.identifier);
    var arguments = _parseDirectiveArguments();
    final value = GLDirectiveValue(
        TokenInfo.ofLexer(identifier, _lexer), [scope], arguments,
        generated: false);
    grammar.addDirectiveValue(value);
    return value;
  }

  List<GLArgumentValue> _parseDirectiveArguments() {
    if (!check(GLTokenType.openParen)) {
      return [];
    }
    var list = <GLArgumentValue>[];
    expect(GLTokenType.openParen);
    while (tryConsume(GLTokenType.closeParen) == null) {
      var token = expect(GLTokenType.identifier);
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
        throw _lexer.errorAt(nextToken.offset, "Unexpected input");
    }
  }

  Map<String, Object?> _parseMap() {
    expect(GLTokenType.openBrace);
    var result = <String, Object?>{};
    while (tryConsume(GLTokenType.closeBrace) == null) {
      var key = expect(GLTokenType.identifier);
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
    final name = expect(GLTokenType.identifier);
    final directives = _parseDirectiveValueList(GLDirectiveScope.UNION);
    final typeNames = <TokenInfo>[];
    if (tryConsume(GLTokenType.equals) != null) {
      typeNames.add(TokenInfo.ofLexer(expect(GLTokenType.identifier), _lexer));
      while (tryConsume(GLTokenType.pipe) != null) {
        typeNames
            .add(TokenInfo.ofLexer(expect(GLTokenType.identifier), _lexer));
      }
    }
    grammar.addUnionDefinition(GLUnionDefinition(
        TokenInfo.ofLexer(name, _lexer), isExtension, typeNames, directives,
        documentation: documentation));
  }

  void _parseDirectiveDefinition({String? documentation}) {
    expect(GLTokenType.kwDirective);
    expect(GLTokenType.at);
    final name = expect(GLTokenType.identifier);
    final args = _parseArgumentDefinitions();
    final repeatable = tryConsume(GLTokenType.kwRepeatable) != null;
    expect(GLTokenType.kwOn);
    final scopes = _parseDirectiveScopes();
    grammar.addDirectiveDefinition(GLDirectiveDefinition(
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
    final token = expect(GLTokenType.identifier);
    final scope = GLDirectiveScope.values.asNameMap()[token.value];
    if (scope == null) {
      throw _lexer.errorAt(
          token.offset, "Unknown directive scope '${token.value}'");
    }
    return scope;
  }

  void _parseFragmentDefinition({String? documentation}) {
    expect(GLTokenType.kwFragment);
    final name = expect(GLTokenType.identifier);
    expect(GLTokenType.kwOn);
    final typeName = expect(GLTokenType.identifier);
    final directives =
        _parseDirectiveValueList(GLDirectiveScope.FRAGMENT_DEFINITION);
    final block = _parseFragmentBlock();
    grammar.addFragmentDefinition(GLFragmentDefinition(
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
        final typeName = expect(GLTokenType.identifier);
        final directives =
            _parseDirectiveValueList(GLDirectiveScope.INLINE_FRAGMENT);
        final block = _parseFragmentBlock();
        final def = GLInlineFragmentDefinition(
            TokenInfo.ofLexer(typeName, _lexer), block, directives);
        grammar.addFragmentDefinition(def);
        inlineFragments.add(def);
      }
      return GLInlineFragmentsProjection(inlineFragments: inlineFragments);
    }
    // Fragment spread: ...FragmentName @directives*
    expect(GLTokenType.spread);
    final name = expect(GLTokenType.identifier);
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
    if (peek().type == GLTokenType.identifier &&
        peekNext().type == GLTokenType.colon) {
      alias = TokenInfo.ofLexer(consume(), _lexer);
      consume(); // consume colon
    }
    final name = expect(GLTokenType.identifier);
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
    final name = expect(GLTokenType.identifier);
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
    grammar.addQueryDefinition(GLQueryDefinition(
      TokenInfo.ofLexer(name, _lexer),
      directives,
      args,
      elements,
      type,
    ));
  }

  GLQueryElement _parseQueryElement() {
    TokenInfo? alias;
    if (peek().type == GLTokenType.identifier &&
        peekNext().type == GLTokenType.colon) {
      alias = TokenInfo.ofLexer(consume(), _lexer);
      consume(); // consume colon
    }
    final name = expect(GLTokenType.identifier);
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
      final name = expect(GLTokenType.identifier);
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
    grammar.defineSchema(GLSchema(
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
    final name = expect(GLTokenType.identifier);
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
