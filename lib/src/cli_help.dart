/// Builds the `--help` output for the `glink` CLI, given the flag usage text
/// produced by [ArgParser.usage].
String buildHelpText(String parserUsage) {
  return '''
Usage: glink [-c <config>] [options]

Options:
$parserUsage

If -c is omitted, glink searches for glink.json, glink.yaml, or glink.yml
starting from the current directory and walking up to the filesystem root.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 config reference  (JSON, YAML, and YML are all accepted)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Top-level
  schemaPaths      string[]  Glob patterns for schema files
                             e.g. ["schema/*.gql"]
  mode             string    "client" or "server"
  outputDir        string    Directory where files are generated
  typeMappings     object    Scalar → language type mappings
                             e.g. { "ID": "String", "Float": "Double" }
  unknownScalarType string   Target type for custom scalars not in typeMappings
                             e.g. "String" (Dart), "string" (TS), "Object" (Java)
  identityFields   string[]  Fields used for equals/hashCode  e.g. ["id"]

━━ mode: client ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

clientConfig.dart
  packageName                     string   Dart package name used in imports
  generateAllFieldsFragments      bool     Generate _all_fields fragments          [false]
  nullableFieldsRequired          bool     Nullable fields required in ctors       [false]
  autoGenerateQueries             bool     Auto-generate queries from schema        [false]
  autoGenerateQueriesDefaultAlias string   Default alias for auto-generated queries
  autoGenerateQueriesArgumentLimit integer Max hoisted args per auto-query         [200]
  maxFragmentBodySize             integer  Skip fragments (and their queries) whose
                                           serialized body exceeds this many chars.
                                           null disables the cap.                  [8192]
  operationNameAsParameter        bool     Pass operation name as a parameter      [false]
  flutter.generateTypes           bool     Generate Flutter UI type widgets        [true]
  flutter.generateInputs          bool     Generate Flutter UI input widgets       [false]
  flutter.typesToSkip             list     Type names to exclude from UI gen       []
  flutter.defaultGap              number   Default spacing between field rows      [16]
  immutableInputFields            bool     Generate input fields as final          [true]
  immutableTypeFields             bool     Generate type fields as final           [true]

clientConfig.java
  packageName                     string   Java package name (required)
  generateAllFieldsFragments      bool     Generate _all_fields fragments          [false]
  nullableFieldsRequired          bool     Nullable fields required                [false]
  autoGenerateQueries             bool     Auto-generate queries from schema        [false]
  autoGenerateQueriesArgumentLimit integer Max hoisted args per auto-query         [200]
  maxFragmentBodySize             integer  Skip fragments (and their queries) whose
                                           serialized body exceeds this many chars.
                                           null disables the cap.                  [8192]
  operationNameAsParameter        bool     Pass operation name as a parameter      [false]
  immutableInputFields            bool     Generate input fields as final          [true]
  immutableTypeFields             bool     Generate type fields as final           [true]
  inputAsRecord                   bool     Generate inputs as Java records         [false]
  typeAsRecord                    bool     Generate types as Java records          [false]

clientConfig.kotlin
  packageName                     string   Kotlin package name (required)
  generateAllFieldsFragments      bool     Generate _all_fields fragments          [true]
  nullableFieldsRequired          bool     Nullable fields required in ctors       [false]
  autoGenerateQueries             bool     Auto-generate queries from schema        [true]
  autoGenerateQueriesArgumentLimit integer Max hoisted args per auto-query         [200]
  maxFragmentBodySize             integer  Skip fragments (and their queries) whose
                                           serialized body exceeds this many chars.
                                           null disables the cap.                  [8192]
  operationNameAsParameter        bool     Pass operation name as a parameter      [false]
  captureErrors                   bool     Return full response including errors   [false]
  inputAsDataClass                bool     Generate inputs as data class           [true]
  typeAsDataClass                 bool     Generate types as data class            [true]
  wsAdapter                       string   WS adapter: "okhttp" | "none"          [okhttp]

clientConfig.typescript
  generateAllFieldsFragments      bool     Generate _all_fields fragments          [false]
  autoGenerateQueries             bool     Auto-generate queries from schema        [false]
  autoGenerateQueriesDefaultAlias string   Default alias for auto-generated queries
  autoGenerateQueriesArgumentLimit integer Max hoisted args per auto-query         [200]
  maxFragmentBodySize             integer  Skip fragments (and their queries) whose
                                           serialized body exceeds this many chars.
                                           null disables the cap.                  [8192]
  operationNameAsParameter        bool     Pass operation name as a parameter      [false]
  immutableTypeFields             bool     Generate type fields as final           [true]
  optionalNullableInputFields     bool     Nullable input fields are optional      [true]
  generateDefaultWsAdapter        bool     Generate default WebSocket adapter      [true]
  observables                     bool     Use RxJS observables instead of promises [false]
  httpAdapter                     string   HTTP adapter: "fetch" | "axios" | "none" [fetch]

━━ mode: server ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

serverConfig.spring
  basePackage           string  Java base package name (required)
  generateControllers   bool    Generate Spring controllers                       [true]
  generateRepositories  bool    Generate repository interfaces                    [false]
  inputAsRecord         bool    Generate inputs as Java records                   [false]
  typeAsRecord          bool    Generate types as Java records                    [false]
  generateSchema        bool    Copy schema file to outputDir                     [false]
  schemaTargetPath      string  Target path for schema (required if generateSchema)
  injectDataFetching    bool    Inject @SchemaMapping data-fetching annotations   [false]
  immutableInputFields  bool    Generate input fields as final                    [true]
  immutableTypeFields   bool    Generate type fields as final                     [false]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''';
}
