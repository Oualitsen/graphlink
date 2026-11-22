const fileUploadType = '''export interface FileUpload {
  filename: string;
  mimetype: string;
  encoding: string;
  createReadStream(): NodeJS.ReadableStream;
}
''';

const graphqlUploadDeclarations = '''declare module 'graphql-upload/GraphQLUpload.mjs' {
  import { GraphQLScalarType } from 'graphql';
  const GraphQLUpload: GraphQLScalarType;
  export default GraphQLUpload;
}

declare module 'graphql-upload/graphqlUploadExpress.mjs' {
  import { RequestHandler } from 'express';
  function graphqlUploadExpress(options?: {
    maxFileSize?: number;
    maxFiles?: number;
  }): RequestHandler;
  export default graphqlUploadExpress;
}
''';

const graphLinkContextInterface =
    'export interface GraphLinkContext extends Record<string, unknown> {}\n';

const expressRequestGuards = r'''const defaultMaxQueryDepth = 32;

function queryDepth(document: DocumentNode, limit: number): number {
   const fragments = new Map<string, SelectionSetNode>();
   for (const definition of document.definitions) {
      if (definition.kind === Kind.FRAGMENT_DEFINITION) {
         fragments.set(definition.name.value, definition.selectionSet);
      }
   }
   const pending: Array<[SelectionSetNode, number, ReadonlySet<string>]> = [];
   for (const definition of document.definitions) {
      if (definition.kind === Kind.OPERATION_DEFINITION) {
         pending.push([definition.selectionSet, 1, new Set()]);
      }
   }
   let deepest = 0;
   while (pending.length > 0 && deepest <= limit) {
      const [selectionSet, depth, visited] = pending.pop()!;
      deepest = Math.max(deepest, depth);
      for (const selection of selectionSet.selections) {
         if (selection.kind === Kind.FIELD) {
            if (selection.selectionSet) pending.push([selection.selectionSet, depth + 1, visited]);
         } else if (selection.kind === Kind.INLINE_FRAGMENT) {
            pending.push([selection.selectionSet, depth, visited]);
         } else if (!visited.has(selection.name.value)) {
            const fragment = fragments.get(selection.name.value);
            if (fragment) pending.push([fragment, depth, new Set(visited).add(selection.name.value)]);
         }
      }
   }
   return deepest;
}

function depthError(maxDepth: number): GraphQLError {
   return new GraphQLError(`Query is too deep: the maximum depth is ${maxDepth}.`, {
      extensions: { code: 'GRAPHQL_VALIDATION_FAILED' },
   });
}

function exceedsMaxDepth(query: unknown, maxDepth: number): boolean {
   if (typeof query !== 'string') return false;
   try {
      return queryDepth(parse(query), maxDepth) > maxDepth;
   } catch {
      return false;
   }
}

function queryDepthGuard(maxDepth: number): RequestHandler {
   return (req, res, next) => {
      const query = req.method === 'GET' ? req.query.query : req.body?.query;
      if (exceedsMaxDepth(query, maxDepth)) {
         res.status(400).json({ errors: [depthError(maxDepth).toJSON()] });
         return;
      }
      next();
   };
}

function graphLinkErrorHandler(error: any, _req: Request, res: Response, next: NextFunction): void {
   if (res.headersSent) {
      next(error);
      return;
   }
   const status = error?.status >= 400 && error?.status < 500 ? error.status : 500;
   const message = status === 413
      ? 'Request body is too large.'
      : status < 500 ? 'Malformed request body.' : 'Internal server error.';
   const code = status < 500 ? 'BAD_REQUEST' : 'INTERNAL_SERVER_ERROR';
   res.status(status).json({ errors: [{ message, extensions: { code } }] });
}
''';

const expressSubscribeGuard = r'''function subscribeErrors(query: unknown, maxDepth: number): GraphQLError[] | undefined {
   if (typeof query !== 'string') return undefined;
   try {
      if (queryDepth(parse(query), maxDepth) > maxDepth) return [depthError(maxDepth)];
   } catch (error) {
      return [error as GraphQLError];
   }
   return undefined;
}
''';

const expressSourceSupport = r'''export const sourceKey = '__glSource__';

type Json = Record<string, unknown>;

// Keeps the object a service returned next to its JSON form, so a schema mapping gets that same instance.
export function attachSource<T>(toJson: (value: T) => Json, value: T | null | undefined): Json | null | undefined {
  if (value == null) return value as null | undefined;
  return { ...toJson(value), [sourceKey]: value };
}

export function sourceOf<T>(json: unknown): T {
  const source = (json as Json | null | undefined)?.[sourceKey];
  return (source ?? json) as T;
}
''';

const tsServerDomainError = r'''
export class GraphLinkDomainError extends Error {
  constructor(message: string = '') {
    super(message);
    Object.setPrototypeOf(this, new.target.prototype);
    this.name = new.target.name;
  }
}

interface GraphLinkErrorWire {
  field: string[];
  restField: string[] | null;
  value: string;
  status: number | null;
}

type DomainJson = { toJson(): Record<string, unknown> };

function wireOf(error: GraphLinkDomainError): GraphLinkErrorWire {
  return (error.constructor as unknown as { wire: GraphLinkErrorWire }).wire;
}

function setPath(target: Record<string, unknown>, path: string[], value: unknown): void {
  let node = target;
  for (const segment of path.slice(0, -1)) {
    const next = node[segment];
    node = next !== null && typeof next === 'object' ? (next as Record<string, unknown>) : (node[segment] = {});
  }
  node[path[path.length - 1]] = value;
}

export function domainErrorEntry(error: GraphLinkDomainError): Record<string, unknown> {
  const wire = wireOf(error);
  const entry: Record<string, unknown> = { extensions: { ...(error as unknown as DomainJson).toJson() } };
  setPath(entry, wire.field, wire.value);
  return entry;
}

export function domainErrorResponse(error: GraphLinkDomainError): { status: number; body: Record<string, unknown> } {
  const wire = wireOf(error);
  const body: Record<string, unknown> = { ...(error as unknown as DomainJson).toJson(), message: error.message };
  if (wire.restField !== null) setPath(body, wire.restField, wire.value);
  return { status: wire.status ?? 400, body };
}
''';

const tsServerFormatError = r'''
export function formatDomainError(formatted: GraphQLFormattedError, error: unknown): GraphQLFormattedError {
  const original = unwrapResolverError(error);
  if (!(original instanceof GraphLinkDomainError)) return formatted;
  const entry = domainErrorEntry(original);
  return { ...formatted, message: original.message, ...entry, extensions: entry.extensions as Record<string, unknown> };
}
''';
