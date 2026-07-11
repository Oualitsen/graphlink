import { GraphLinkClient } from '../src/generated/client/graph-link-client.js';
import { DefaultGraphLinkWsAdapter } from '../src/generated/client/graph-link-default-ws-adapter.js';
import { createFetchAdapter } from '../src/generated/client/graph-link-adapters.js';

const port = parseInt(process.env.SERVER_PORT || '9997', 10);
export const httpUrl = `http://localhost:${port}/graphql`;
export const wsUrl = `ws://localhost:${port}/graphql`;

export function newClient(): GraphLinkClient {
  return new GraphLinkClient(
    createFetchAdapter(httpUrl),
    new DefaultGraphLinkWsAdapter(wsUrl),
  );
}
