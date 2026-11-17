import 'package:graphlink/src/config.dart';
import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_source_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_intercept_extension.dart';
import 'package:graphlink/src/model/built_in_dirctive_definitions.dart';
import 'package:graphlink/src/model/gl_argument.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_field.dart';
import 'package:graphlink/src/model/gl_interface_definition.dart';
import 'package:graphlink/src/model/gl_queries.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/model/gl_schema_mapping.dart';
import 'package:graphlink/src/model/gl_type.dart';
import 'package:graphlink/src/serializers/typescript/express_apollo_server_constants.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_response_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_server_extension.dart';
import 'package:graphlink/src/serializers/gl_graphql_serializer.dart';
import 'package:graphlink/src/serializers/typescript/typescript_serializer.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';
import 'package:graphlink/src/serializers/server_serializer.dart';

/// What the Express and NestJS Apollo servers share: the service and guard contracts, loaders, context, type defs and
/// the naming/import helpers. A subclass decides how a contract is declared and how resolvers and the entry point look.
abstract class TypeScriptApolloServerSerializerBase extends ServerSerializer with ServerSerializerUtils {
  final TypeScriptSerializer tsSerializer;
  final TypeScriptApolloServerConfig apolloConfig;
  final _cg = TypeScriptCodeGenUtils();

  TypeScriptApolloServerSerializerBase(super.grammar, this.tsSerializer, this.apolloConfig);

  /// Appends the Apollo-specific `context`/`info` params onto the shared
  /// `runBefore` IR, then serializes normally. The two import lines are
  /// hand-written since `GraphLinkContext`/`GraphQLResolveInfo` aren't schema
  /// tokens the generic import resolver knows about.
  String? serializeInterceptorInterface() {
    if (!hasInterceptor) return null;
    final def = grammar.interfaces[glInterceptorInterfaceName]!;
    addInterceptorTargetArgs(def);

    return GLClassModel(
      imports: [
        "import { GraphLinkContext } from '../context.js';",
        if (apolloConfig.useResolveInfo) "import { GraphQLResolveInfo } from 'graphql';",
      ],
      body: declareInterceptor(tsSerializer.serializeTypeDefinition(def)),
    ).toFileContent();
  }

  /// Turns the serialized `GraphLinkInterceptor` interface into the declaration a subclass wants.
  String declareInterceptor(String serializedInterface) => serializedInterface;

  /// How a service or guard contract is declared: [signatures] are `name(params): Promise<T>;` lines.
  String declareContract(String name, List<String> signatures) =>
      _cg.createInterface(interfaceName: name, fields: signatures);

  // ── uploads ───────────────────────────────────────────────────────────────

  String serializeFileUploadType() => fileUploadType;

  String serializeGraphqlUploadDeclarations() => graphqlUploadDeclarations;

  // ── interfaces/gl-interceptor.ts ─────────────────────────────────────────

  bool get hasInterceptor => grammar.usesInterceptor;

  void addInterceptorTargetArgs(GLInterfaceDefinition def) {
    final runBefore = def.fields.firstWhere((f) => f.name.token == glInterceptorRunBeforeMethod);
    if (runBefore.arguments.any((a) => a.token == 'context')) return;
    runBefore.addArgument(
        GLArgumentDefinition('context'.toToken(), GLType('GraphLinkContext'.toToken(), true), []));
    if (apolloConfig.useResolveInfo) {
      runBefore.addArgument(
          GLArgumentDefinition('info'.toToken(), GLType('GraphQLResolveInfo'.toToken(), true), []));
    }
  }

  // ── context.ts ────────────────────────────────────────────────────────────

  @override
  String serializeContext() {
    final batch = batchMappings();
    if (batch.isEmpty) return graphLinkContextInterface;

    final typeNames = <String>{};
    for (final e in batch) {
      addIfKnown(e.mapping.type.token, typeNames);
      collectType(e.mapping.field.type, typeNames);
    }
    // context.ts sits one level above types/ etc., so rewrite the shared '../'
    // import prefix to './'.
    final typeImports = importLines(typeNames).replaceAll("from '../", "from './");

    final loaderFields = [
      for (final e in batch) '${e.mapping.key}: ${_loaderFieldType(e.mapping)};',
    ];

    final buf = StringBuffer();
    buf.writeln("import DataLoader from 'dataloader';");
    if (typeImports.isNotEmpty) buf.writeln(typeImports);
    buf.writeln();
    buf.writeln(_cg.createInterface(interfaceName: 'GraphLinkLoaders', fields: loaderFields));
    buf.writeln();
    buf.write(graphLinkContextInterface);
    return buf.toString();
  }

  List<MappingEntry> batchMappings() => [
        for (final service in grammar.services.values)
          for (final m in service.mappings.where((m) => m.isBatch))
            MappingEntry(mapping: m, service: service),
      ];

  /// [mapping]'s real declared arguments, excluding the synthetic parent
  /// (`value`) argument every mapping carries.
  List<GLArgumentDefinition> realMappingArgs(GLSchemaMapping mapping) =>
      mapping.field.arguments.where((a) => !a.skipOnGraphqlSerialization).toList();

  /// The `GraphLinkLoaders` field type for a batch [mapping] — a plain
  /// `DataLoader` when zero-arg, or a memoized-loader-getter function when
  /// the field carries real arguments (see `_loaderFactory`).
  String _loaderFieldType(GLSchemaMapping mapping) {
    final dataLoaderType =
        'DataLoader<${tsSerializer.resolveCodeName(mapping.type.token)}, ${tsSerializer.serializeType(mapping.field.type)}>';
    final realArgs = realMappingArgs(mapping);
    if (realArgs.isEmpty) return dataLoaderType;
    final params = realArgs.map((a) => '${a.codeName}: ${tsSerializer.serializeType(a.type)}').join(', ');
    return '($params) => $dataLoaderType';
  }

  // ── impl/my-context.ts stub (written once) ────────────────────────────────

  String serializeContextStub(String generatedDir) {
    final dirName = generatedDir.split('/').last;
    final contextInterface = _cg.createInterface(
      interfaceName: 'GraphLinkContext',
      fields: [
        '// add your typed context fields here, for example:',
        '// userId?: string;',
        '// roles?: string[];',
      ],
      exported: false,
    );
    return "declare module '../$dirName/context.js' ${_cg.block([contextInterface])}\n";
  }

  // ── typeDefs.ts ───────────────────────────────────────────────────────────

  @override
  String serializeTypeDefs() {
    final schema = GLGraphqlSerializer(grammar).generateSchema();
    final escaped = schema.replaceAll('`', r'\`');
    return 'export const typeDefs = `\n$escaped`;\n';
  }

  /// Whether [field]'s resolver/service method receives the request `context`
  /// parameter — either globally (`injectContext`) or per-field via
  /// `@glInjectContext`.
  bool injectsContext(GLField field) =>
      apolloConfig.injectContext || field.hasDirective(glInjectContext);

  @override
  String serializeService(GLService service) {
    final importedTypes = <String>{};
    final methods = <String>[];
    var hasUpload = false;
    var hasDownload = false;

    // A batch mapping resolves many parents in one call, so it has no single
    // GraphQLResolveInfo — exclude `info` from its signature (as subscriptions do).
    final batchKeys =
        service.mappings.where((m) => m.isBatch).map((m) => m.key).toSet();

    for (final field in service.fields) {
      if (field.getDirectiveByName(glValidate)?.generated == true) continue;
      final argList = field.arguments.map((arg) {
        if (isUploadScalar(arg.type)) {
          hasUpload = true;
          return '${arg.codeName}: ${tsUploadType(arg.type)}';
        }
        collectType(arg.type, importedTypes);
        return '${arg.codeName}: ${tsSerializer.serializeType(arg.type)}';
      }).toList();
      final isDownload = grammar.downloadScalarNames.contains(field.type.firstType.token);
      if (isDownload) hasDownload = true;
      final returnTs = grammar.voidScalarNames.contains(field.type.firstType.token)
          ? 'void'
          : isDownload
              ? 'GraphLinkDownload${field.type.nullable ? ' | null' : ''}'
              : tsSerializer.serializeType(field.type);
      collectType(field.type, importedTypes);
      final isSubscription = service.getTypeByFieldName(field.name.token) == GLQueryType.subscription;
      final isBatch = batchKeys.contains(field.name.token);
      final needsInfo = apolloConfig.useResolveInfo && !isSubscription && !isBatch && !grammar.isRestField(field);
      final params = [
        ...argList,
        if (injectsContext(field)) 'context: GraphLinkContext',
        if (needsInfo) 'info: GraphQLResolveInfo',
      ];
      final returnDecl = isSubscription ? 'AsyncIterable<$returnTs>' : 'Promise<$returnTs>';
      methods.add('${field.name}(${params.join(', ')}): $returnDecl;');
    }

    final needsResolveInfoImport = apolloConfig.useResolveInfo &&
        service.fields.any((f) =>
            f.getDirectiveByName(glValidate)?.generated != true &&
            service.getTypeByFieldName(f.name.token) != GLQueryType.subscription &&
            !grammar.isRestField(f) &&
            !batchKeys.contains(f.name.token));
    final needsContextImport = service.fields.any(injectsContext);

    final imp = importLines(importedTypes);
    final lines = [
      if (needsContextImport) "import { GraphLinkContext } from '../context.js';",
      if (needsResolveInfoImport) "import { GraphQLResolveInfo } from 'graphql';",
      if (hasUpload) "import type { FileUpload } from '../file-upload.js';",
      if (hasDownload) "import type { GraphLinkDownload } from '../rest/download.js';",
      if (imp.isNotEmpty) imp,
    ];
    return '${lines.join('\n')}\n\n${declareContract(service.token, methods)}';
  }

  // ── guards/XxxGuard.ts ────────────────────────────────────────────────────

  @override
  String? serializeGuard(GLService service) {
    final importedTypes = <String>{};
    final methods = <String>[];

    for (final field in service.fields) {
      if (!fieldHasValidation(field)) continue;
      final argList = field.arguments.map((arg) {
        collectType(arg.type, importedTypes);
        return '${arg.codeName}: ${tsSerializer.serializeType(arg.type)}';
      }).toList();
      final guardParams = [...argList, if (injectsContext(field)) 'context: GraphLinkContext', if (apolloConfig.useResolveInfo && !grammar.isRestField(field)) 'info: GraphQLResolveInfo'];
      methods.add('${validationMethodName(field.name.token)}(${guardParams.join(', ')}): Promise<void>;');
    }

    if (methods.isEmpty) return null;

    final imp = importLines(importedTypes);
    final resolveInfoImport = apolloConfig.useResolveInfo && service.fields.where(fieldHasValidation).any((f) => !grammar.isRestField(f))
        ? "import { GraphQLResolveInfo } from 'graphql';"
        : '';
    final needsContextImport = service.fields.where(fieldHasValidation).any(injectsContext);
    final lines = [
      if (needsContextImport) "import { GraphLinkContext } from '../context.js';",
      if (resolveInfoImport.isNotEmpty) resolveInfoImport,
      if (imp.isNotEmpty) imp,
    ];
    return '${lines.join('\n')}\n\n${declareContract(guardName(service), methods)}';
  }

  // ── loaders/XxxLoaders.ts ─────────────────────────────────────────────────

  String? serializeLoader(GLService service) {
    final batchMappings = service.mappings.where((m) => m.isBatch).toList();
    if (batchMappings.isEmpty) return null;

    final importedTypes = <String>{};
    for (final m in batchMappings) {
      addIfKnown(m.type.token, importedTypes);
      collectType(m.field.type, importedTypes);
    }

    final imp = importLines(importedTypes);
    return '${GLClassModel(
      imports: [
        "import DataLoader from 'dataloader';",
        if (batchMappings.any((m) => injectsContext(m.field))) "import { GraphLinkContext } from '../context.js';",
        if (carriesSource(batchMappings.first.type.token) || batchMappings.any((m) => carriesSource(m.type.token)))
          "import { sourceOf } from '../source.js';",
        "import { ${service.token} } from '../services/${kebabJs(service.token)}';",
        if (imp.isNotEmpty) imp,
      ],
      body: batchMappings.map((m) => _loaderFactory(m, service.token)).join('\n'),
    ).toFileContent()}\n';
  }

  bool carriesSource(String typeName) => grammar.sourceTypeNames.contains(typeName);

  String serializeSourceSupport() => expressSourceSupport;

  String _loaderFactory(GLSchemaMapping mapping, String serviceName) {
    final parentName = tsSerializer.resolveCodeName(mapping.type.token);
    final fieldTs = tsSerializer.serializeType(mapping.field.type);
    final factoryName = 'create${mapping.key.firstUp}Loader';
    final serviceVar = serviceName.firstLow;
    final realArgs = realMappingArgs(mapping);
    final argCodeNames = realArgs.map((a) => a.codeName).toList();

    final String mapCallback;
    final lookup = carriesSource(mapping.type.token) ? 'map.get(sourceOf(v))' : 'map.get(v)';
    if (mapping.field.type.nullable) {
      // A nullable batch field legitimately resolves to null when the service
      // has no entry for a parent.
      mapCallback = 'v => $lookup ?? null';
    } else {
      // A non-nullable field requires a value per key. Returning an Error (not
      // throwing) rejects only this key's promise, not the whole batch. Keep the
      // client-facing message generic and log the full parent object server-side.
      final callbackBody = _cg.block([
        _cg.constDecl('r', lookup),
        _cg.ifStatement(
          condition: 'r == null',
          ifBlockStatements: [
            "console.error('${mapping.key}: no result for', v);",
            "return new Error('${mapping.key} resolution failed');",
          ],
        ),
        'return r;',
      ]);
      mapCallback = 'v => $callbackBody';
    }
    final ctx = injectsContext(mapping.field);
    final sourced = carriesSource(mapping.type.token);
    final serviceCallArgs = [
      ...argCodeNames,
      sourced ? 'items.map((item) => sourceOf<$parentName>(item))' : '[...items]',
      if (ctx) 'context',
    ].join(', ');
    final loaderBody = _cg.block([
      _cg.constDecl('map', 'await $serviceVar.${mapping.key}($serviceCallArgs)'),
      'return items.map($mapCallback);',
    ]);
    final newLoaderExpr = 'new DataLoader<$parentName, $fieldTs>(async (items) => $loaderBody)';
    final factoryArgs = ['$serviceVar: $serviceName', if (ctx) 'context: GraphLinkContext'];

    if (realArgs.isEmpty) {
      return '${_cg.createFunction(
        functionName: factoryName,
        arguments: factoryArgs,
        exported: true,
        statements: ['return $newLoaderExpr;'],
      )}\n';
    }

    // A single DataLoader only batches calls sharing the same argument value,
    // so return a per-arguments memoized getter instead of one instance.
    final params = realArgs.map((a) => '${a.codeName}: ${tsSerializer.serializeType(a.type)}').join(', ');
    return '${_cg.createFunction(
      functionName: factoryName,
      arguments: factoryArgs,
      exported: true,
      statements: [
        'const cache = new Map<string, DataLoader<$parentName, $fieldTs>>();',
        'return ($params) => ${_cg.block([
          'const key = JSON.stringify([${argCodeNames.join(', ')}]);',
          'let loader = cache.get(key);',
          _cg.ifStatement(condition: '!loader', ifBlockStatements: [
            'loader = $newLoaderExpr;',
            'cache.set(key, loader);',
          ]),
          'return loader;',
        ])};',
      ],
    )}\n';
  }

  /// The `tag` call-site argument for `runBefore` — a single-element list, or
  /// empty when no `GlInterceptorTag` enum was generated (no tag param exists
  /// to pass).
  List<String> interceptorTagCallArg(GLField field, [GLQueryType? type]) {
    final tagEnum = grammar.enums[glInterceptorTagEnumName];
    if (tagEnum == null) return const [];
    final tag = grammar.interceptTag(field, type);
    if (tag == null) return const ['null'];
    final member = tagEnum.values.firstWhere((v) => v.token == tag).codeName;
    return ['${tagEnum.codeName}.$member'];
  }

  bool hasGuard(GLService service) => service.fields.any(fieldHasValidation);

  bool get hasBatchLoaders =>
      grammar.services.values.any((s) => s.mappings.any((m) => m.isBatch));

  bool get anyBatchInjectsContext =>
      batchMappings().any((e) => injectsContext(e.mapping.field));

  /// Builds the resolver `args` destructuring pattern. Each entry is plain
  /// shorthand (`{ id }`) when the wire name is a legal identifier, or a rename
  /// (`{ return: return_ }`) when the wire name is a reserved word, so the local
  /// binding is safe while the property key stays the GraphQL wire name.
  String argsDestructurePattern(
      List<String> wireNames, List<String> codeNames, String emptyToken) {
    if (wireNames.isEmpty) return emptyToken;
    final parts = <String>[];
    for (var i = 0; i < wireNames.length; i++) {
      parts.add(wireNames[i] == codeNames[i]
          ? wireNames[i]
          : '${wireNames[i]}: ${codeNames[i]}');
    }
    return '{ ${parts.join(', ')} }';
  }

  /// Fields typed as the `@glSkipOnServer(mapTo:)` source: the service returns the source, so it is the parent
  /// and the field resolves to it.
  Map<String, List<String>> mapToPassThroughFields() {
    final result = <String, List<String>>{};
    for (final type in grammar.types.values) {
      final dir = type.getDirectiveByName(glSkipOnServer);
      final source = dir?.getArgValueAsString(glMapTo);
      if (source == null) continue;
      final mapped = {
        for (final service in grammar.services.values)
          for (final mapping in service.mappings)
            if (mapping.type.token == type.token) mapping.field.name.token,
      };
      for (final field in type.fields) {
        if (field.type is GLListType || field.type.token != source || mapped.contains(field.name.token)) continue;
        result.putIfAbsent(type.token, () => []).add(field.name.token);
      }
    }
    return result;
  }

  String tsUploadType(GLType type) {
    final upload = type is GLListType ? 'FileUpload[]' : 'FileUpload';
    return type.nullable ? '$upload | null' : upload;
  }

  String guardName(GLService service) =>
      '${service.token.replaceFirst('Service', '')}Guard';

  /// kebab-case filename with .js extension (for import statements)
  String kebabJs(String typeName) => '${typeName.toKebabCase()}.js';

  String loaderFileJs(GLService service) =>
      '${service.token.replaceFirst('Service', '').toKebabCase()}-loaders.js';

  /// Resolves each collected wire token to its definition and delegates to the
  /// TypeScript serializer's import logic, which routes interfaces/unions to
  /// `../interfaces/`, types to `../types/`, and follows `@glSkipOnServer(mapTo:)`
  /// to the mapped target (e.g. `ArticleWithCount` → `Article`). Deduplicated so
  /// several mapped-away types collapsing onto one target import once.
  String importLines(Set<String> typeNames) {
    final seen = <String>{};
    final lines = <String>[];
    for (final name in typeNames) {
      final token = grammar.types[name] ??
          grammar.interfaces[name] ??
          grammar.inputs[name] ??
          grammar.enums[name];
      if (token == null) continue;
      final line = tsSerializer.serializeImportToken(token);
      if (line.isEmpty || !seen.add(line)) continue;
      lines.add(line);
    }
    return lines.join('\n');
  }

  void collectType(GLType type, Set<String> out) {
    if (type is GLListType) {
      collectType(type.inlineType, out);
    } else if (type is GLMapType) {
      collectType(type.keyType, out);
      collectType(type.valueType, out);
    } else {
      addIfKnown(type.token, out);
    }
  }

  void addIfKnown(String name, Set<String> out) {
    if (grammar.types.containsKey(name) ||
        grammar.interfaces.containsKey(name) ||
        grammar.inputs.containsKey(name) ||
        grammar.enums.containsKey(name)) {
      out.add(name);
    }
  }
}

class RootEntry {
  final GLService service;
  final GLField field;
  final GLQueryType queryType;
  final String fieldName;

  /// Original GraphQL argument names — the wire/property keys read off the
  /// resolver `args` object (always the schema token).
  final List<String> argNames;

  /// Parameter-safe identifiers parallel to [argNames]; equal to the wire name
  /// unless it collides with a reserved word (`return` → `return_`). Used for
  /// the destructuring target, local bindings, and service-call arguments.
  final List<String> argCodeNames;
  final List<GLType> argTypes;
  final GLType returnType;
  final bool needsInfo;
  final bool contextInjected;

  final bool intercepted;
  RootEntry({
    required this.service,
    required this.field,
    required this.queryType,
    required this.fieldName,
    required this.argNames,
    required this.argCodeNames,
    required this.argTypes,
    required this.returnType,
    required this.needsInfo,
    required this.contextInjected,
    required this.intercepted,
  });
}

class MappingEntry {
  final GLSchemaMapping mapping;
  final GLService service;
  MappingEntry({required this.mapping, required this.service});
}
