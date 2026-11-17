import 'package:graphlink/src/extensions.dart';
import 'package:graphlink/src/model/gl_class_model.dart';
import 'package:graphlink/src/model/gl_rest_operation.dart';
import 'package:graphlink/src/model/gl_service.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_intercept_extension.dart';
import 'package:graphlink/src/parser_extensions/gl_grammar_rest_server_extension.dart';
import 'package:graphlink/src/serializers/typescript/express_apollo_rest_serializer.dart';
import 'package:graphlink/src/typescript_code_gen_utils.dart';

const nestRestControllersDir = 'rest';
const nestRestFallbackControllerClass = 'RestFallbackController';

const _expressOnlySupport = {'handle', 'methodNotAllowed', 'notFound', 'restErrorHandler'};

/// The REST adapter of a NestJS server: one `@Controller` per service holding `@glRest*` operations, with the
/// service, its guard and the interceptor constructor-injected.
class NestApolloRestSerializer extends ExpressApolloRestSerializer {
  final _cg = TypeScriptCodeGenUtils();

  NestApolloRestSerializer(super.grammar, super.tsSerializer, super.apolloConfig);

  @override
  String serviceAccess(String member) => 'this.$member';

  @override
  String get interceptorAccess => 'this.interceptor';

  @override
  String get contextAccess => 'await restContext(this.options, req, res)';

  @override
  List<String> get supportImportNames => [
        ...super.supportImportNames.where((name) => !_expressOnlySupport.contains(name)),
        'sendError',
        'sendMethodNotAllowed',
      ];

  /// Controller class names in registration order, the fallback last.
  List<String> get controllerClassNames => [
        for (final service in restServices) controllerClassName(service),
        if (hasRest) nestRestFallbackControllerClass,
      ];

  String controllerClassName(GLService service) => '${service.token}Controller';

  String controllerFileName(GLService service) => '${service.token.toKebabCase()}.controller';

  List<GLService> get restServices => [
        for (final service in grammar.services.values)
          if (grammar.restOperationsOf(service).isNotEmpty) service,
      ];

  String serializeShapes() {
    final declaration = shapesDeclaration(routeBindings());
    return "import { S, Shapes } from './support.js';\n\nexport $declaration\n";
  }

  String serializeController(GLService service) {
    final bindings = [for (final binding in routeBindings()) if (binding.service == service) binding];
    final ops = bindings.map((b) => b.op).toList();
    final usesContext = ops.any((op) => injectsContext(op) || isIntercepted(op));
    final intercepted = ops.any(isIntercepted);
    final interceptor = intercepted ? grammar.interfaces[glInterceptorInterfaceName]! : null;
    final tagEnum = intercepted ? grammar.enums[glInterceptorTagEnumName] : null;
    final guarded = ops.any(hasValidation);
    final verbs = {for (final op in ops) _verb(op)}.toList()..sort();

    final imports = [
      "import { Controller, ${[...verbs, 'Inject', 'Req', 'Res'].join(', ')} } from '@nestjs/common';",
      "import type { Request, Response } from 'express';",
      if (usesContext) "import { GRAPHLINK_OPTIONS, GraphLinkModuleOptions, restContext } from '../graphlink.options.js';",
      if (interceptor != null)
        "import { ${interceptor.codeName} } from '../interfaces/${tsSerializer.getFileNameFor(interceptor).replaceAll('.ts', '.js')}';",
      if (tagEnum != null)
        "import { ${tagEnum.codeName} } from '../enums/${tsSerializer.getFileNameFor(tagEnum).replaceAll('.ts', '.js')}';",
      "import { ${supportImportNames.join(', ')} } from './support.js';",
      "import { shapes } from './shapes.js';",
      if (hasDownloads) "import { sendDownload } from './download.js';",
      if (hasUploads) "import { rawUploadArg${hasMultipart ? ', readMultipart, fileArg, fileListArg' : ''} } from './uploads.js';",
      "import { ${service.token} } from '../services/${service.token.toKebabCase()}.js';",
      if (guarded)
        "import { ${guardName(service)} } from '../guards/${guardName(service).toKebabCase()}.js';",
      ...typeImports(bindings),
    ];

    final dependencies = [
      '@Inject(${service.token}) private readonly ${service.token.firstLow}: ${service.token}',
      if (guarded) '@Inject(${guardName(service)}) private readonly ${guardName(service).firstLow}: ${guardName(service)}',
      if (interceptor != null)
        '@Inject(${interceptor.codeName}) private readonly interceptor: ${interceptor.codeName}',
      if (usesContext) '@Inject(GRAPHLINK_OPTIONS) private readonly options: GraphLinkModuleOptions',
    ];

    final methods = [
      for (final binding in bindings)
        '@${_verb(binding.op)}(${expressPath(binding.op).quote()})\n${_cg.createMethod(
          methodName: binding.op.field.codeName,
          arguments: ['@Req() req: Request', '@Res() res: Response'],
          returnType: 'void',
          async: true,
          statements: routeStatements(binding),
        )}',
    ];

    final className = controllerClassName(service);
    final classBody = _cg.createClass(
      className: className,
      statements: [_constructor(dependencies), ...methods],
    );
    return '${GLClassModel(imports: imports, body: '@Controller()\n$classBody').toFileContent()}\n';
  }

  /// 405 for a path served under other methods only, 404 for anything else below the prefix every REST path shares.
  String serializeFallbackController() {
    final bindings = routeBindings();
    final methodsByPath = <String, List<String>>{};
    for (final binding in bindings) {
      methodsByPath.putIfAbsent(expressPath(binding.op), () => []).add(binding.op.method.wireName);
    }
    final methods = <String>[];
    var index = 0;
    for (final entry in methodsByPath.entries) {
      methods.add('@All(${entry.key.quote()})\n${_cg.createMethod(
        methodName: 'methodNotAllowed${index++}',
        arguments: ['@Res() res: Response'],
        returnType: 'void',
        statements: ['sendMethodNotAllowed(res, [${entry.value.map((m) => m.quote()).join(', ')}]);'],
      )}');
    }
    final prefix = _commonPrefix(bindings);
    if (prefix.isNotEmpty) {
      for (final path in [prefix, '$prefix/*splat']) {
        methods.add('@All(${path.quote()})\n${_cg.createMethod(
          methodName: 'notFound${index++}',
          arguments: ['@Res() res: Response'],
          returnType: 'void',
          statements: ['sendError(res, 404);'],
        )}');
      }
    }
    final imports = [
      "import { All, Controller, Res } from '@nestjs/common';",
      "import type { Response } from 'express';",
      "import { sendError, sendMethodNotAllowed } from './support.js';",
    ];
    final classBody = _cg.createClass(className: nestRestFallbackControllerClass, statements: methods);
    return '${GLClassModel(imports: imports, body: '@Controller()\n$classBody').toFileContent()}\n';
  }

  String _commonPrefix(List<RouteBinding> bindings) {
    final prefixes = [
      for (final binding in bindings)
        expressPath(binding.op).split('/').where((s) => s.isNotEmpty).takeWhile((s) => !s.startsWith(':')).toList(),
    ];
    var common = prefixes.first;
    for (final prefix in prefixes.skip(1)) {
      var length = 0;
      while (length < common.length && length < prefix.length && common[length] == prefix[length]) {
        length++;
      }
      common = common.sublist(0, length);
    }
    return common.isEmpty ? '' : '/${common.join('/')}';
  }

  String _constructor(List<String> dependencies) =>
      'constructor(\n${dependencies.join(',\n').ident()}\n) {}';

  String _verb(GLRestOperation op) => op.method.name.firstUp;
}
