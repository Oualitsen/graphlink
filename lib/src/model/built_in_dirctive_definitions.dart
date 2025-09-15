///
/// Adds a code such as annotations as a prefix to the generated code
///
const gqDecorators = "@gqDecorators";

///
/// Skips generating on server
///
const gqSkipOnServer = "@gqSkipOnServer";
const gqMapTo = "mapTo";

///
/// Skips generating on client
///
const gqSkipOnClient = "@gqSkipOnClient";

///
/// Generates lists as array on languages that support arrays.
///
const gqArray = "@gqArray";

///
/// Adds methods to a Service with a given name.
/// By default, a service name is generated based the return type of the query/mutation/subscription
///
const gqServiceName = "@gqServiceName";
const gqServiceNameArg = "name";

///
/// Applied only on client.
/// Generates a class with the given name if possible.
///
const gqTypeNameDirective = "@gqTypeName";

///
/// Generates equals and hashcode
///
const gqEqualsHashcode = "@gqEqualsHashcode";

const includeDirective = "@include";

const skipDirective = "@skip";

///
/// Generates a spring data jpa.
///
const gqRepository = "@gqRepository";
const gqType = "gqType";
const gqIdType = "gqIdType";
const gqExternal = "@gqExternal";
const gqExternalArg = gqClass;
const gqClass = "gqClass";
const gqImport = "gqImport";

const gqTypeNameDirectiveArgumentName = "name";
const gqEqualsHashcodeArgumentName = "fields";
const gqDecoratorsArgumentName = "value";

const gqAnnotation = "gqAnnotation";
const gqOnClient = "gqOnClient";
const gqOnServer = "gqOnServer";
