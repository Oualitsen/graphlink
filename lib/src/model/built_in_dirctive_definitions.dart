///
/// Adds a code such as annotations as a prefix to the generated code
///
const glDecorators = "@glDecorators";

///
/// Skips generating on server
///
const glSkipOnServer = "@glSkipOnServer";
const glMapTo = "mapTo";

///
/// Argument to generate a batch mapping, defaults to true
///
const glBatch = "batch";

///
/// Skips generating on client
///
const glSkipOnClient = "@glSkipOnClient";


///
/// Adds methods to a Service with a given name.
/// By default, a service name is generated based the return type of the query/mutation/subscription
///
const glServiceName = "@glServiceName";
const glServiceNameArg = "name";

///
/// Applied only on client.
/// Generates a class with the given name if possible.
///
const glTypeNameDirective = "@glTypeName";

///
/// Generates equals and hashcode
///
const glEqualsHashcode = "@glEqualsHashcode";

const includeDirective = "@include";

const skipDirective = "@skip";

///
/// Generates a spring data jpa.
///
const glRepository = "@glRepository";
const glType = "glType";
const glIdType = "glIdType";
const glExternal = "@glExternal";
const glInterfaceFieldAsProperties = "@glInterfaceFieldAsProperties";

///
/// Used for internally generated objects
/// Any object with this decorator will be sikpped in all fields fragment generation, ui generation
/// and other stuff in the future
///
const glInternal = "@glInternal";

///
/// When a method (from query/mutation/subscription) is decorated with this directive,
/// the controller will call a validation method named validateXXX before calling the service method.
///

const glValidate = "@glValidate";
const glValidateMethodPrefix = "validate";

const glExternalArg = glClass;
const glClass = "glClass";
const glImport = "glImport";

const glTypeNameDirectiveArgumentName = "name";
const glEqualsHashcodeArgumentName = "fields";
const glDecoratorsArgumentName = "value";

const glAnnotation = "glAnnotation";
const glApplyOnFields = "glApplyOnFields";
const glOnClient = "glOnClient";
const glOnServer = "glOnServer";

///
/// cache annotations
///
const glCache = "@glCache";
const glCacheTTL = "ttl";
const glNoCache = "@glNoCache";
const glCacheInvalidate = "@glCacheInvalidate";
const glCacheTagList = "tags";
const glCacheArgAll = "all";
const glCacheArgStaleIfOffline = "staleIfOffline";

/// Maps an input type to a target type or input, generating a toXxx() method.
const glMapsTo = "@glMapsTo";
const glMapsToType = "type";

/// Aliases an input field to a differently-named field on the mapping target.
const glMapField = "@glMapField";
const glMapFieldTo = "to";

/// Marks a scalar as a file upload type.
/// The generator will produce GLUpload (Dart) / GLUpload (Java) as the type,
/// and multipart/form-data transport for any mutation that uses it.
const glUpload = "@glUpload";

/// Controls inline expansion depth for cyclic types in all-fields fragment generation.
/// When a cycle is detected, the generator inlines the cyclic type's fields up to
/// [glExpandDepth] levels instead of emitting a fragment spread (which would be invalid).
/// Default depth is 1 (one level of inline expansion).
const glExpand = "@glExpand";
const glExpandDepth = "depth";

/// When applied to a query or mutation, errors are returned inline inside the response
/// object instead of being thrown. The method never throws for GraphQL-level errors.
/// The caller checks response.hasErrors instead of using try/catch.
const glCaptureErrors = "@glCaptureErrors";

///
/// Per-type opt-out from the default strict (real schema nullability) server generation.
/// A type marked @glServerLenient has its fields forced all-nullable on the server, exactly as
/// every type did before @glStrict (see plans/glstrict-consolidated.md). It still gets a
/// generated GL<Type>Projection interface and `implements` it — only its own field
/// nullability reverts to all-nullable.
const glServerLenient = "@glServerLenient";

///
/// Per-operation opt-in for selection-driven partial fetches (see
/// plans/glstrict-consolidated.md §2/§9). Applied to a query/mutation/subscription field
/// or a @glSkipOnServer relation field, it makes that one service method return
/// GL<Type>Projection (all-nullable) instead of the strict concrete <Type> — the only
/// shape that can represent "not every field was fetched". It also auto-injects
/// DataFetchingEnvironment into that method regardless of the global injectDataFetching
/// setting, so the resolver can inspect the selection set.
const glReturnsProjection = "@glReturnsProjection";


var jspecifyNullable = '@Nullable';
var jspecifyNonNull = '@NonNull';

