import { GraphLinkGetNotSupported } from '../lib/generated/client/graph-link-persisted-queries.js';
import { GraphLinkSha256 } from '../lib/generated/client/graph-link-sha256.js';

type Body = Record<string, unknown>;

export class ApqServer {
  private readonly responses = new Map<string, unknown>();
  private readonly registered = new Set<string>();
  readonly requests: Body[] = [];
  readonly methods: string[] = [];

  supported = true;
  notFoundMessage = 'PersistedQueryNotFound';
  getSupported = true;
  failWith: Error | null = null;
  getFailWith: Error | null = null;

  respondTo(operationName: string, data: Record<string, unknown>): void {
    this.responses.set(operationName, { data });
  }

  respondWithErrors(operationName: string, errors: unknown[]): void {
    this.responses.set(operationName, { data: null, errors });
  }

  evict(): void {
    this.registered.clear();
  }

  isHashOnly(body: Body): boolean {
    return 'extensions' in body && !('query' in body);
  }

  readonly call = async (payload: string): Promise<string> => {
    this.methods.push('POST');
    return this.handle(payload, this.failWith);
  };

  readonly get = async (payload: string): Promise<string> => {
    this.methods.push('GET');
    if (!this.getSupported) throw new GraphLinkGetNotSupported('GET is not allowed');
    return this.handle(payload, this.getFailWith);
  };

  private handle(payload: string, failure: Error | null): string {
    const body = JSON.parse(payload) as Body;
    this.requests.push(body);
    if (failure) throw failure;

    const persisted = (body.extensions as { persistedQuery?: { sha256Hash: string } } | undefined)?.persistedQuery;
    if (persisted) {
      if (!this.supported) return error('PersistedQueryNotSupported', 'PERSISTED_QUERY_NOT_SUPPORTED');
      const query = body.query as string | undefined;
      if (query === undefined) {
        if (!this.registered.has(persisted.sha256Hash)) {
          return error(this.notFoundMessage, 'PERSISTED_QUERY_NOT_FOUND');
        }
      } else {
        if (GraphLinkSha256.hex(query) !== persisted.sha256Hash) {
          return error('provided sha does not match query', 'INTERNAL_SERVER_ERROR');
        }
        this.registered.add(persisted.sha256Hash);
      }
    }
    const response = this.responses.get(body.operationName as string);
    if (response === undefined) throw new Error(`No response registered for ${String(body.operationName)}`);
    return JSON.stringify(response);
  }
}

function error(message: string, code: string): string {
  return JSON.stringify({ errors: [{ message, extensions: { code } }] });
}
