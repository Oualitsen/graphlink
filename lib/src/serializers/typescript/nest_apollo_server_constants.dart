import 'package:graphlink/src/serializers/typescript/express_apollo_rest_constants.dart';
import 'package:graphlink/src/serializers/typescript/express_apollo_server_constants.dart';

const nestRestSupportFileName = expressRestSupportFileName;

const _expressSupportImport = "import { NextFunction, Request, RequestHandler, Response } from 'express';";

const _nestSupportTail = r'''export function sendError(res: Response, status: number): void {
   res.status(status).json({ status, error: reasons[status] ?? 'Error' });
}

export function sendMethodNotAllowed(res: Response, methods: string[]): void {
   res.set('Allow', methods.join(', '));
   sendError(res, 405);
}

function formText(req: Request): string {
   if (typeof req.body === 'string') return req.body;
   const raw = (req as Request & { rawBody?: Buffer }).rawBody;
   if (raw) return raw.toString('utf8');
   throw new Error('Form bodies need NestFactory.create(AppModule, { rawBody: true }).');
}
''';

/// The REST runtime shared with Express (argument reading, validation, responses), minus the Express router glue.
final nestRestSupport = () {
  final core = expressRestSupport.substring(0, expressRestSupport.indexOf('function sendError'));
  return core
      .replaceFirst(_expressSupportImport, "import type { Request, Response } from 'express';")
      .replaceFirst("typeof req.body === 'string' ? req.body : ''", 'formText(req)')
      .replaceFirst('parseScalar(req.params[name], shape)', 'parseScalar(String(req.params[name]), shape)') +
      _nestSupportTail;
}();

const nestRequestGuardsFileName = 'graphlink-request-guards.ts';

final nestRequestGuards = () {
  final queryGuards = expressRequestGuards
      .substring(0, expressRequestGuards.indexOf('function graphLinkErrorHandler'))
      .replaceFirst('const defaultMaxQueryDepth', 'export const defaultMaxQueryDepth')
      .replaceFirst('function queryDepthGuard', 'export function queryDepthGuard');
  final subscribeGuard = expressSubscribeGuard.replaceFirst('function subscribeErrors', 'export function subscribeErrors');
  return '''import { DocumentNode, GraphQLError, Kind, parse, SelectionSetNode } from 'graphql';
import type { RequestHandler } from 'express';

$queryGuards$subscribeGuard''';
}();

const nestExceptionFilterFileName = 'graphlink-exception.filter.ts';

const nestGraphqlErrorBody = r'''function graphqlErrorBody(error: any): { status: number; body: unknown } {
   const status = error?.status >= 400 && error?.status < 500 ? error.status : 500;
   const message = status === 413
      ? 'Request body is too large.'
      : status < 500 ? 'Malformed request body.' : 'Internal server error.';
   const code = status < 500 ? 'BAD_REQUEST' : 'INTERNAL_SERVER_ERROR';
   return { status, body: { errors: [{ message, extensions: { code } }] } };
}
''';

const nestRestErrorStatus = r'''function restErrorStatus(error: any): number {
   if (error instanceof RestError) return error.status;
   if (error?.status >= 400 && error?.status < 500) return error.status;
   console.error(error);
   return 500;
}
''';
