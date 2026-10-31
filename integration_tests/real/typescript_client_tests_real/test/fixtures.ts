// ── Address ───────────────────────────────────────────────────────────────────

export const kAddressJson = {
  street: '123 Main St',
  city: 'Springfield',
  country: 'US',
  zip: '12345',
};

export const kAddressNoZipJson = {
  street: '456 Oak Ave',
  city: 'Shelbyville',
  country: 'US',
  zip: null,
};

export const kBillingAddressJson = {
  street: '789 Pine Rd',
  city: 'Capital City',
  country: 'US',
  zip: '99999',
};

// ── Users ─────────────────────────────────────────────────────────────────────

/** Alice — status ACTIVE, priority HIGH, no billingAddress, has tags and scores. */
export const kUserAliceJson = {
  id: 'user-1',
  name: 'Alice Smith',
  email: 'alice@test.com',
  status: 'ACTIVE',
  priority: 'HIGH',
  address: kAddressJson,
  billingAddress: null,
  tags: ['admin', 'beta'],
  scores: [10, 20, 30],
  posts: null,
};

/** Bob — status INACTIVE, priority null, has billingAddress, empty tags, null scores. */
export const kUserBobJson = {
  id: 'user-2',
  name: 'Bob Jones',
  email: 'bob@test.com',
  status: 'INACTIVE',
  priority: null,
  address: kAddressNoZipJson,
  billingAddress: kBillingAddressJson,
  tags: [] as string[],
  scores: null,
  posts: null,
};

// ── AllScalars ────────────────────────────────────────────────────────────────

/** All nullable fields are null. */
export const kAllScalarsNullJson = {
  id: 'scalar-1',
  strVal: 'hello world',
  intVal: 42,
  floatVal: 3.14,
  boolVal: true,
  nullableStr: null,
  nullableInt: null,
  nullableFloat: null,
  nullableBool: null,
  nullableId: null,
};

/** All nullable fields have values; also tests negative numbers and false bool. */
export const kAllScalarsPresentJson = {
  id: 'scalar-2',
  strVal: 'edge case',
  intVal: -1,
  floatVal: -0.5,
  boolVal: false,
  nullableStr: 'present',
  nullableInt: 99,
  nullableFloat: 2.718,
  nullableBool: false,
  nullableId: 'nid-1',
};

// ── Post ──────────────────────────────────────────────────────────────────────

export const kPostJson = {
  id: 'post-1',
  title: 'Hello World',
  body: 'Post body text.',
  author: kUserAliceJson,
  coAuthor: null,
  viewCount: 128,
};

export const kPostWithCoAuthorJson = {
  id: 'post-2',
  title: 'Collaboration',
  body: 'Written together.',
  author: kUserAliceJson,
  coAuthor: kUserBobJson,
  viewCount: 42,
};

// ── AuditEntry ────────────────────────────────────────────────────────────────

/** internalNote is absent — matches what @glSkipOnClient produces. */
export const kAuditEntryJson = {
  id: 'audit-1',
  action: 'LOGIN',
  performedBy: 'user-1',
};

/** Same entry but with an extra field the server might return — client should ignore it. */
export const kAuditEntryWithExtraJson = {
  id: 'audit-2',
  action: 'LOGOUT',
  performedBy: 'user-1',
  internalNote: 'this should be silently ignored',
};

// ── Cyclic fixtures (User → Post → User) ─────────────────────────────────────

/** A Post whose author is a minimal User (posts: null — cycle broken here). */
export const kPostWithAuthorCycleJson = {
  id: 'post-10',
  title: 'Cyclic Post',
  body: 'Body text.',
  author: {
    id: 'user-1',
    name: 'Alice Smith',
    email: 'alice@test.com',
    status: 'ACTIVE',
    priority: 'HIGH',
    address: kAddressJson,
    billingAddress: null,
    tags: ['admin'],
    scores: null,
    posts: null,
  },
  coAuthor: null,
  viewCount: 7,
};

/** Alice with one post; post's author has posts: null (cycle broken). */
export const kUserWithPostsJson = {
  id: 'user-1',
  name: 'Alice Smith',
  email: 'alice@test.com',
  status: 'ACTIVE',
  priority: 'HIGH',
  address: kAddressJson,
  billingAddress: null,
  tags: ['admin', 'beta'],
  scores: [10, 20, 30],
  posts: [kPostWithAuthorCycleJson],
};

// ── Tags ──────────────────────────────────────────────────────────────────────

export const kTagsJson = [
  { id: 'tag-1', label: 'dart', color: '#0175C2' },
  { id: 'tag-2', label: 'graphql', color: null },
];

// ── Errors ────────────────────────────────────────────────────────────────────

export const kGraphQLError = {
  message: 'Not found',
  locations: [{ line: 1, column: 1 }],
  path: ['getUser'],
};

// ── Helpers ───────────────────────────────────────────────────────────────────

export function dataResponse(data: Record<string, unknown>): string {
  return JSON.stringify({ data });
}

export function errorResponse(errors: unknown[]): string {
  return JSON.stringify({ data: null, errors });
}
