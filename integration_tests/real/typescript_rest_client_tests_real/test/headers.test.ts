import { beforeEach, describe, expect, it } from 'vitest';
import { RestError, type GraphLinkClient } from '../lib/generated/graphlink';
import { header, newClient, resetServer } from './support';

let client: GraphLinkClient;

beforeEach(async () => {
  await resetServer();
  client = newClient();
});

describe('header arguments', () => {
  it('a scalar header uses its declared name; an input spreads one header per field', async () => {
    const e = await client.queries.eHeaders({ tenant: 't-1', trace: { traceId: 'tr', spanId: 'sp' } });
    expect(header(e, 'X-Tenant')).toBe('t-1');
    expect(header(e, 'X-Trace-Id')).toBe('tr');
    expect(header(e, 'X-Span-Id')).toBe('sp');
  });

  it('a null header field and a null header argument are not sent', async () => {
    const e = await client.queries.eHeaders({ tenant: 't', trace: { traceId: 'tr' } });
    expect(header(e, 'X-Span-Id')).toBeUndefined();
    expect(header(e, 'X-Opt')).toBeUndefined();
    expect(header(e, 'X-Roles')).toBeUndefined();
  });

  it('a list header is joined with commas', async () => {
    const e = await client.queries.eHeaders({ tenant: 't', roles: ['admin', 'ops'] });
    expect(header(e, 'X-Roles')).toBe('admin,ops');
  });
});

describe('Accept and Content-Type', () => {
  it('Accept defaults to JSON and can be overridden per operation', async () => {
    expect(header(await client.queries.eAccept(), 'accept')).toBe('application/json');
    expect(header(await client.queries.eAcceptOverride(), 'accept')).toBe('application/vnd.test+json');
  });

  it('a GET sends no Content-Type', async () => {
    const e = await client.queries.eAccept();
    expect(e.contentType).toBeNull();
  });
});

describe('adapter headers', () => {
  it('the headers provider is consulted for every request', async () => {
    let calls = 0;
    const c = newClient({ headers: async () => ({ 'X-Provider': `call-${++calls}` }) });
    expect(header(await c.queries.eAccept(), 'X-Provider')).toBe('call-1');
    expect(header(await c.queries.eAccept(), 'X-Provider')).toBe('call-2');
  });

  it('an argument header wins over the provider', async () => {
    const c = newClient({ headers: async () => ({ 'X-Tenant': 'from-provider', 'X-Other': 'kept' }) });
    const e = await c.queries.eHeaders({ tenant: 'from-arg' });
    expect(header(e, 'X-Tenant')).toBe('from-arg');
    expect(header(e, 'X-Other')).toBe('kept');
  });

  it('auth through the provider reaches a protected route; without it the call is a RestError 401', async () => {
    const failure = await client.queries.authCheck({}).catch((e: unknown) => e);
    expect(failure).toBeInstanceOf(RestError);
    expect((failure as RestError).status).toBe(401);
    expect((failure as RestError).headers['www-authenticate']).toBe('Bearer');
    const c = newClient({ headers: async () => ({ Authorization: 'Bearer secret' }) });
    const who = await c.queries.authCheck({ tenant: 'acme' });
    expect(who.user).toBe('ann');
    expect(who.tenant).toBe('acme');
  });
});
