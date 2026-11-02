import { createRestFetchAdapter, type GLRestAdapter } from '../lib/generated/graphlink';

export function createAdapter(baseUrl: string, headers?: () => Promise<Record<string, string>>): GLRestAdapter {
  return createRestFetchAdapter(baseUrl, { headers });
}
