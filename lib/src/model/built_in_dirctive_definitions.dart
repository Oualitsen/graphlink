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
/// Generates lists as array on languages that support arrays.
///
const glArray = "@glArray";

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
