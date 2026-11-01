import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { UserStatus } from '../lib/generated/enums/user-status.js';
import type { CreateUserInput } from '../lib/generated/inputs/create-user-input.js';
import { MockWsAdapter } from '../../typescript_client_tests/test/mock-adapter.ts';
import { ApqServer } from './apq-server.ts';

export const newClient = (server: ApqServer) =>
  new GraphLinkClient(server.call, server.get, new MockWsAdapter() as never);

export const hashOf = (request: Record<string, unknown>) =>
  (request.extensions as { persistedQuery: Record<string, unknown> }).persistedQuery;

export const createUserInput: CreateUserInput = {
  name: 'Alice',
  email: 'a@test.com',
  status: UserStatus.Active,
  address: { street: 's', city: 'c', country: 'x' },
};
