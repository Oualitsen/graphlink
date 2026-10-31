import 'dart:convert';

// ── Address ──────────────────────────────────────────────────────────────────

const kAddressJson = <String, dynamic>{
  'street': '123 Main St',
  'city': 'Springfield',
  'country': 'US',
  'zip': '12345',
};

const kAddressNoZipJson = <String, dynamic>{
  'street': '456 Oak Ave',
  'city': 'Shelbyville',
  'country': 'US',
  'zip': null,
};

const kBillingAddressJson = <String, dynamic>{
  'street': '789 Pine Rd',
  'city': 'Capital City',
  'country': 'US',
  'zip': '99999',
};

// ── Users ─────────────────────────────────────────────────────────────────────

/// Alice — status ACTIVE, priority HIGH, no billingAddress, has tags and scores.
const kUserAliceJson = <String, dynamic>{
  'id': 'user-1',
  'name': 'Alice Smith',
  'email': 'alice@test.com',
  'status': 'ACTIVE',
  'priority': 'HIGH',
  'address': kAddressJson,
  'billingAddress': null,
  'tags': ['admin', 'beta'],
  'scores': [10, 20, 30],
};

/// Bob — status INACTIVE, priority null, has billingAddress, empty tags, null scores.
const kUserBobJson = <String, dynamic>{
  'id': 'user-2',
  'name': 'Bob Jones',
  'email': 'bob@test.com',
  'status': 'INACTIVE',
  'priority': null,
  'address': kAddressNoZipJson,
  'billingAddress': kBillingAddressJson,
  'tags': <String>[],
  'scores': null,
};

// ── AllScalars ────────────────────────────────────────────────────────────────

/// All nullable fields are null.
const kAllScalarsNullJson = <String, dynamic>{
  'id': 'scalar-1',
  'strVal': 'hello world',
  'intVal': 42,
  'floatVal': 3.14,
  'boolVal': true,
  'nullableStr': null,
  'nullableInt': null,
  'nullableFloat': null,
  'nullableBool': null,
  'nullableId': null,
};

/// All nullable fields have values; also tests negative numbers and false bool.
const kAllScalarsPresentJson = <String, dynamic>{
  'id': 'scalar-2',
  'strVal': 'edge case',
  'intVal': -1,
  'floatVal': -0.5,
  'boolVal': false,
  'nullableStr': 'present',
  'nullableInt': 99,
  'nullableFloat': 2.718,
  'nullableBool': false,
  'nullableId': 'nid-1',
};

// ── Post ──────────────────────────────────────────────────────────────────────

const kPostJson = <String, dynamic>{
  'id': 'post-1',
  'title': 'Hello World',
  'body': 'Post body text.',
  'author': kUserAliceJson,
  'coAuthor': null,
  'viewCount': 128,
};

const kPostWithCoAuthorJson = <String, dynamic>{
  'id': 'post-2',
  'title': 'Collaboration',
  'body': 'Written together.',
  'author': kUserAliceJson,
  'coAuthor': kUserBobJson,
  'viewCount': 42,
};

// ── AuditEntry ────────────────────────────────────────────────────────────────

/// internalNote is intentionally absent — matches what @glSkipOnClient produces.
const kAuditEntryJson = <String, dynamic>{
  'id': 'audit-1',
  'action': 'LOGIN',
  'performedBy': 'user-1',
};

/// Same entry but with an extra field the server might return — client should ignore it.
const kAuditEntryWithExtraJson = <String, dynamic>{
  'id': 'audit-2',
  'action': 'LOGOUT',
  'performedBy': 'user-1',
  'internalNote': 'this should be silently ignored',
};

// ── Cyclic fixtures (User → Post → User) ─────────────────────────────────────

/// A Post whose author is a minimal User (posts: null — cycle broken here).
const kPostWithAuthorCycleJson = <String, dynamic>{
  'id': 'post-10',
  'title': 'Cyclic Post',
  'body': 'Body text.',
  'author': <String, dynamic>{
    'id': 'user-1',
    'name': 'Alice Smith',
    'email': 'alice@test.com',
    'status': 'ACTIVE',
    'priority': 'HIGH',
    'address': kAddressJson,
    'billingAddress': null,
    'tags': <String>['admin'],
    'scores': null,
    'posts': null, // cycle broken — author does not re-expand posts
  },
  'coAuthor': null,
  'viewCount': 7,
};

/// Alice with two posts; each post's author has posts: null (cycle broken).
const kUserWithPostsJson = <String, dynamic>{
  'id': 'user-1',
  'name': 'Alice Smith',
  'email': 'alice@test.com',
  'status': 'ACTIVE',
  'priority': 'HIGH',
  'address': kAddressJson,
  'billingAddress': null,
  'tags': <String>['admin', 'beta'],
  'scores': <int>[10, 20, 30],
  'posts': <Map<String, dynamic>>[kPostWithAuthorCycleJson],
};

// ── Tags ──────────────────────────────────────────────────────────────────────

const kTagsJson = <Map<String, dynamic>>[
  {'id': 'tag-1', 'label': 'dart', 'color': '#0175C2'},
  {'id': 'tag-2', 'label': 'graphql', 'color': null},
];

// ── Errors ────────────────────────────────────────────────────────────────────

const kGraphQLError = <String, dynamic>{
  'message': 'Not found',
  'locations': [
    {'line': 1, 'column': 1}
  ],
  'path': ['getUser'],
};

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Wraps a data map as a full GraphQL HTTP response JSON string.
String dataResponse(Map<String, dynamic> data) => jsonEncode({'data': data});

/// Builds a GraphQL error response JSON string.
String errorResponse(List<Map<String, dynamic>> errors) =>
    jsonEncode({'data': null, 'errors': errors});
